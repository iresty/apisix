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

local require     = require
local core        = require("apisix.core")
local plugin_name = "proxy-rewrite"
local pairs       = pairs
local ipairs      = ipairs
local ngx         = ngx
local type        = type
local re_sub      = ngx.re.sub
local sub_str     = string.sub
local str_find    = core.string.find

local schema = {
    type = "object",
    properties = {
        uri = {
            description = "new uri for upstream",
            type        = "string",
            minLength   = 1,
            maxLength   = 4096,
            pattern     = [[^\/.*]],
        },
        regex_uri = {
            description = "new uri that substitute from client uri " ..
                          "for upstream, lower priority than uri property",
            type        = "array",
            maxItems    = 2,
            minItems    = 2,
            items       = {
                description = "regex uri",
                type = "string",
            }
        },
        host = {
            description = "new host for upstream",
            type        = "string",
            pattern     = [[^[0-9a-zA-Z-.]+(:\d{1,5})?$]],
        },
        scheme = {
            description = "new scheme for upstream",
            type    = "string",
            enum    = {"http", "https"}
        },
        headers = {
            description = "new headers for request",
            type = "object",
            minProperties = 1,
        },
    },
    minProperties = 1,
    additionalProperties = false,
}


local _M = {
    version  = 0.1,
    priority = 1008,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.regex_uri and #conf.regex_uri > 0 then
        local _, _, err = re_sub("/fake_uri", conf.regex_uri[1],
                                   conf.regex_uri[2], "jo")
        if err then
            return false, "invalid regex_uri(" .. conf.regex_uri[1] ..
                            ", " .. conf.regex_uri[2] .. "): " .. err
        end
    end

    -- check headers
    if not conf.headers then
        return true
    end

    for field, value in pairs(conf.headers) do
        if type(field) ~= 'string' then
            return false, 'invalid type as header field'
        end

        if type(value) ~= 'string' and type(value) ~= 'number' then
            return false, 'invalid type as header value'
        end

        if #field == 0 then
            return false, 'invalid field length in header'
        end

        core.log.info("header field: ", field)

        if not core.utils.validate_header_field(field) then
            return false, 'invalid field character in header'
        end

        if not core.utils.validate_header_value(value) then
            return false, 'invalid value character in header'
        end
    end

    return true
end


do
    local upstream_vars = {
        host       = "upstream_host",
        upgrade    = "upstream_upgrade",
        connection = "upstream_connection",
    }
    local upstream_names = {}
    for name, _ in pairs(upstream_vars) do
        core.table.insert(upstream_names, name)
    end

function _M.rewrite(conf, ctx)
    for _, name in ipairs(upstream_names) do
        if conf[name] then
            ctx.var[upstream_vars[name]] = conf[name]
        end
    end
    if conf["scheme"] then
        ctx.upstream_scheme = conf["scheme"]
    end

    local upstream_uri = ctx.var.uri
    if conf.uri ~= nil then
        upstream_uri = core.utils.resolve_var(conf.uri, ctx.var)
    elseif conf.regex_uri ~= nil then
        local uri, _, err = re_sub(ctx.var.uri, conf.regex_uri[1],
                                   conf.regex_uri[2], "jo")
        if uri then
            upstream_uri = uri
        else
            local msg = "failed to substitute the uri " .. ctx.var.uri ..
                        " (" .. conf.regex_uri[1] .. ") with " ..
                        conf.regex_uri[2] .. " : " .. err
            core.log.error(msg)
            return 500, {message = msg}
        end
    end

    local index = str_find(upstream_uri, "?")
    if index then
        upstream_uri = core.utils.uri_safe_encode(sub_str(upstream_uri, 1, index-1)) ..
                       sub_str(upstream_uri, index)
    else
        upstream_uri = core.utils.uri_safe_encode(upstream_uri)
    end

    if ctx.var.is_args == "?" then
        if index then
            ctx.var.upstream_uri = upstream_uri .. "&" .. (ctx.var.args or "")
        else
            ctx.var.upstream_uri = upstream_uri .. "?" .. (ctx.var.args or "")
        end
    else
        ctx.var.upstream_uri = upstream_uri
    end

    if not conf.headers then
        return
    end

    -- reform header from object into array, so can avoid use pairs,
    -- which is NYI
    if not conf.headers_arr then
        conf.headers_arr = {}

        for field, value in pairs(conf.headers) do
            core.table.insert_tail(conf.headers_arr, field, value)
        end
    end

    local field_cnt = #conf.headers_arr
    for i = 1, field_cnt, 2 do
        ngx.req.set_header(conf.headers_arr[i],
                           core.utils.resolve_var(conf.headers_arr[i+1], ctx.var))
    end
end

end  -- do


return _M
