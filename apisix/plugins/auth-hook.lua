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

local core = require("apisix.core")
local http = require("resty.http")
local ck = require("resty.cookie")
local ngx = ngx
local ipairs = ipairs
local type = type
local rawget = rawget
local rawset = rawset
local setmetatable = setmetatable
local string = string

local plugin_name = "auth-hook"
local hook_lrucache = core.lrucache.new({
    ttl = 60, count = 1024
})

local schema = {
    type = "object",
    properties = {
        auth_hook_id = {
            type = "string",
            minLength = 1,
            maxLength = 100,
            default = "unset"
        },
        auth_hook_uri = {
            type = "string",
            minLength = 1,
            maxLength = 4096
        },
        auth_hook_method = {
            type = "string",
            default = "GET",
            enum = { "GET", "POST" },
        },
        hook_headers = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 100
            },
            uniqueItems = true
        },
        hook_args = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 100
            },
            uniqueItems = true
        },
        hook_res_to_headers = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 100
            },
            uniqueItems = true
        },
        hook_keepalive = {
            type = "boolean",
            default = true
        },
        hook_keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000
        },
        hook_keepalive_pool = {
            type = "integer",
            minimum = 1,
            default = 5
        },
        hook_res_to_header_prefix = {
            type = "string",
            default = "X-",
            minLength = 1,
            maxLength = 100
        },
        hook_cache = {
            type = "boolean",
            default = false
        },
        check_termination = {
            type = "boolean",
            default = true
        },
    },
    required = { "auth_hook_uri" },
}

local _M = {
    version = 0.1,
    priority = 1007,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)

    return core.schema.check(schema, conf)

end

local function get_auth_token(ctx)

    local token = ctx.var.http_x_auth_token
    if token then
        return token
    end

    token = ctx.var.http_authorization
    if token then
        return token
    end

    token = ctx.var.arg_auth_token
    if token then
        return token
    end

    local cookie, err = ck:new()
    if not cookie or err then
        return nil
    end

    local val, error = cookie:get("auth-token")
    if error then
        return nil
    end
    return val

end

local function fail_response(message, init_values)

    local response = init_values or {}
    response.message = message
    return response

end

local function new_table()
    local t = {}
    local lt = {}
    local _mt = {
        __index = function(t, k)
            return rawget(lt, string.lower(k))
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(lt, string.lower(k), v)
        end,
    }
    return setmetatable(t, _mt)
end

--proxy headers
local function request_headers(config, ctx)

    local req_headers = new_table()
    local headers = core.request.headers(ctx)
    local hook_headers = config.hook_headers
    if not hook_headers then
        return req_headers
    end
    for i, field in ipairs(hook_headers) do
        local v = headers[field]
        if v then
            req_headers[field] = v
        end
    end
    return req_headers

end


--init headers
local function res_init_headers(config, ctx)

    local prefix = config.hook_res_to_header_prefix or ''
    local hook_res_to_headers = config.hook_res_to_headers

    if type(hook_res_to_headers) ~= "table" then
        return
    end

    core.request.set_header(ctx, prefix .. "auth-data", nil)
    for i, val in ipairs(hook_res_to_headers) do
        local f = string.gsub(val, '_', '-')
        core.request.set_header(ctx, prefix .. f, nil)
        core.response.set_header(prefix .. f, nil)

    end
    return
end

--res headers
local function res_to_headers(config, data, ctx)

    local prefix = config.hook_res_to_header_prefix or ''
    local hook_res_to_headers = config.hook_res_to_headers
    if type(hook_res_to_headers) ~= "table" or type(data) ~= "table" then
        return
    end
    core.request.set_header(ctx, prefix .. "auth-data", core.json.encode(data))
    for i, val in ipairs(hook_res_to_headers) do
        local v = data[val]
        if v then
            if type(v) == "table" then
                v = core.json.encode(v)
            end
            local f = string.gsub(val, '_', '-')
            core.request.set_header(ctx, prefix .. f, v)
            core.response.set_header(prefix .. f, v)

        end
    end
    return

end


--proxy args
local function get_hook_args(hook_args)

    local req_args = new_table()
    if not hook_args then
        return req_args
    end
    local args = ngx.req.get_uri_args()
    for i, field in ipairs(hook_args) do
        local v = args[field]
        if v then
            req_args[field] = v
        end
    end
    return req_args

end

-- Configure request parameters.
local function hook_configure_params(args, config, hook_headers)

    hook_headers["Content-Type"] = "application/json; charset=utf-8"
    local auth_hook_params = {
        ssl_verify = false,
        method = config.auth_hook_method,
        headers = hook_headers,
    }
    if config.hook_keepalive then
        auth_hook_params.keepalive_timeout = config.hook_keepalive_timeout
        auth_hook_params.keepalive_pool = config.hook_keepalive_pool
    else
        auth_hook_params.keepalive = config.hook_keepalive
    end
    local url = config.auth_hook_uri .. "?" .. ngx.encode_args(args)
    return auth_hook_params, url

end

-- timeout in ms
local function http_req(url, auth_hook_params)

    local httpc = http.new()
    httpc:set_timeout(1000 * 10)
    local res, err = httpc:request_uri(url, auth_hook_params)
    if err then
        core.log.error("FAIL REQUEST [ ", core.json.encode(auth_hook_params),
                " ] failed! res is nil, err:", err)
        return nil, err
    end
    return res

end

local function get_auth_info(config, ctx, action, path, client_ip, auth_token)

    local hook_headers = request_headers(config, ctx)
    hook_headers["X-Client-Ip"] = client_ip
    hook_headers["Authorization"] = auth_token
    hook_headers["Auth-Hook-Id"] = config.auth_hook_id
    local args = get_hook_args(config.hook_args)
    args['hook_path'] = path
    args['hook_action'] = action
    args['hook_client_ip'] = client_ip
    core.response.set_header("APISIX-Hook-Cache", 'no-cache')
    local auth_hook_params, url = hook_configure_params(args, config, hook_headers)
    local res, err = http_req(url, auth_hook_params)
    return { res = res, err = err }

end

function _M.rewrite(conf, ctx)

    local url = ctx.var.uri
    local action = ctx.var.request_method
    local client_ip = ctx.var.http_x_real_ip or core.request.get_ip(ctx)
    local config = conf
    local auth_token = get_auth_token(ctx)

    res_init_headers(config, ctx)

    if auth_token then
        local res, hook_data
        if config.hook_cache then
            core.response.set_header("APISIX-Hook-Cache", 'cache')
            res = hook_lrucache(plugin_name .. "#" .. auth_token, config.version,
                    get_auth_info, config, ctx, action, url, client_ip, auth_token)
        else
            res = get_auth_info(config, ctx, action, url, client_ip, auth_token)
        end

        local hook_res = res.res
        if res.err then
            core.response.set_header("Content-Type", "application/json; charset=utf-8")
            return 500, fail_response(res.err, { status_code = 500 })
        end

        if hook_res.status ~= 200 and config.check_termination then
            core.response.set_header("Content-Type", "application/json; charset=utf-8")
            return hook_res.status, fail_response('auth-hook check permission failed',
                    { status_code = hook_res.status })
        end

        local hook_body, err = core.json.decode(hook_res.body)
        if not hook_body and config.check_termination then
            core.response.set_header("Content-Type", "application/json; charset=utf-8")
            return 500, fail_response("JSON decoding failed: " .. err,
                    { status_code = 500 })
        end

        hook_data = hook_body.data
        if type(hook_data) == "table" then
            res_to_headers(config, hook_data, ctx)
        end

    elseif config.check_termination then
        core.response.set_header("Content-Type", "application/json; charset=utf-8")
        return 401, fail_response("Missing auth token in request",
                { status_code = 401 })
    end
    core.log.info("auth-hook check permission passed")

end

return _M
