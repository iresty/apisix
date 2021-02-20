--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local require   = require
local core      = require("apisix.core")
local http      = require("resty.http")
local plugin    = require("apisix.plugin")
local ngx       = ngx
local ipairs    = ipairs
local pairs     = pairs
local str_find  = core.string.find
local str_lower = string.lower


local plugin_name = "batch-requests"

local schema = {
    type = "object",
    additionalProperties = false,
}

local default_max_body_size = 1024 * 1024 -- 1MiB
local metadata_schema = {
    type = "object",
    properties = {
        max_body_size = {
            description = "max pipeline body size in bytes",
            type = "integer",
            exclusiveMinimum = 0,
            default = default_max_body_size,
        },
    },
    additionalProperties = false,
}

local req_schema = {
    type = "object",
    properties = {
        query = {
            description = "pipeline query string",
            type = "object"
        },
        headers = {
            description = "pipeline header",
            type = "object"
        },
        timeout = {
            description = "pipeline timeout(ms)",
            type = "integer",
            default = 30000,
        },
        pipeline = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    version = {
                        description = "HTTP version",
                        type = "number",
                        enum = {1.0, 1.1},
                        default = 1.1,
                    },
                    method = {
                        description = "HTTP method",
                        type = "string",
                        enum = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                                "OPTIONS", "CONNECT", "TRACE"},
                        default = "GET"
                    },
                    path = {
                        type = "string",
                        minLength = 1,
                    },
                    query = {
                        description = "request header",
                        type = "object",
                    },
                    headers = {
                        description = "request query string",
                        type = "object",
                    },
                    ssl_verify = {
                        type = "boolean",
                        default = false
                    },
                }
            }
        }
    },
    anyOf = {
        {required = {"pipeline"}},
    },
}

local _M = {
    version = 0.1,
    priority = 4010,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end


local function check_input(data)
    local ok, err = core.schema.check(req_schema, data)
    if not ok then
        return 400, {error_msg = "bad request body: " .. err}
    end
end

local function lowercase_key_or_init(obj)
    if not obj then
        return {}
    end

    local lowercase_key_obj = {}
    for k, v in pairs(obj) do
        lowercase_key_obj[str_lower(k)] = v
    end

    return lowercase_key_obj
end

local function ensure_header_lowercase(data)
    data.headers = lowercase_key_or_init(data.headers)

    for i,req in ipairs(data.pipeline) do
        req.headers = lowercase_key_or_init(req.headers)
    end
end


local function set_common_header(data)
    local outer_headers = core.request.headers(nil)
    for i,req in ipairs(data.pipeline) do
        for k, v in pairs(data.headers) do
            if not req.headers[k] then
                req.headers[k] = v
            end
        end

        if outer_headers then
            for k, v in pairs(outer_headers) do
                local is_content_header = str_find(k, "content-") == 1
                -- skip header start with "content-"
                if not req.headers[k] and not is_content_header then
                    req.headers[k] = v
                end
            end
        end
    end
end


local function set_common_query(data)
    if not data.query then
        return
    end

    for i,req in ipairs(data.pipeline) do
        if not req.query then
            req.query = data.query
        else
            for k, v in pairs(data.query) do
                if not req.query[k] then
                    req.query[k] = v
                end
            end
        end
    end
end


local function batch_requests(ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    local max_body_size
    if metadata then
        max_body_size = metadata.value.max_body_size
    else
        max_body_size = default_max_body_size
    end

    local req_body, err = core.request.get_body(max_body_size, ctx)
    if err then
        -- Nginx doesn't support 417: https://trac.nginx.org/nginx/ticket/2062
        -- So always return 413 instead
        return 413, { error_msg = err }
    end
    if not req_body then
        return 400, {
            error_msg = "no request body, you should give at least one pipeline setting"
        }
    end

    local data, err = core.json.decode(req_body)
    if not data then
        return 400, {
            error_msg = "invalid request body: " .. req_body .. ", err: " .. err
        }
    end

    local code, body = check_input(data)
    if code then
        return code, body
    end

    local httpc = http.new()
    httpc:set_timeout(data.timeout)
    local ok, err = httpc:connect("127.0.0.1", ngx.var.server_port)
    if not ok then
        return 500, {error_msg = "connect to apisix failed: " .. err}
    end

    ensure_header_lowercase(data)
    set_common_header(data)
    set_common_query(data)

    local responses, err = httpc:request_pipeline(data.pipeline)
    if not responses then
        return 400, {error_msg = "request failed: " .. err}
    end

    local aggregated_resp = {}
    for _, resp in ipairs(responses) do
        if not resp.status then
            core.table.insert(aggregated_resp, {
                status = 504,
                reason = "upstream timeout"
            })
        end
        local sub_resp = {
            status  = resp.status,
            reason  = resp.reason,
            headers = resp.headers,
        }
        if resp.has_body then
            sub_resp.body = resp:read_body()
        end
        core.table.insert(aggregated_resp, sub_resp)
    end
    return 200, aggregated_resp
end


function _M.api()
    return {
        {
            methods = {"POST"},
            uri = "/apisix/batch-requests",
            handler = batch_requests,
        }
    }
end


return _M
