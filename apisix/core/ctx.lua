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
local core_str     = require("apisix.core.string")
local core_tab     = require("apisix.core.table")
local request      = require("apisix.core.request")
local log          = require("apisix.core.log")
local config_local = require("apisix.core.config_local")
local tablepool    = require("tablepool")
local get_var      = require("resty.ngxvar").fetch
local get_request  = require("resty.ngxvar").request
local ck           = require "resty.cookie"
local gq_parse     = require("graphql").parse
local setmetatable = setmetatable
local sub_str      = string.sub
local ngx          = ngx
local ngx_var      = ngx.var
local re_gsub      = ngx.re.gsub
local ipairs       = ipairs
local type         = type
local error        = error
local pcall        = pcall
local req_method   = ngx.var.request_method
local headers      = ngx.req.get_headers()
local core         = require("apisix.core")


local _M = {version = 0.2}
local GRAPHQL_DEFAULT_MAX_SIZE = 1048576               -- 1MiB



local function explode (_str, seperator)
    local pos, arr = 0, {}
    for st, sp in function()
        return string.find(_str, seperator, pos, true)
    end do
        table.insert(arr, string.sub(_str, pos, st - 1))
        pos = sp + 1
    end
    table.insert(arr, string.sub(_str, pos))
    return arr
end


local function get_request_parameter(ctx)
    if  ctx.request_parameter then
        return ctx.request_parameter
    end

    local request_parameter = {};
    local in_parameter = "app_id";

    local req_body,err = core.request.get_body(max_body_siz,ctx)

    local args = nil;
    if "POST" == req_method then

        local content_type = headers["content-type"]
        content_type = string.gsub(content_type, "\r\n", "");

        if string.sub(content_type, 1, 19) == "multipart/form-data" then

            local body =req_body;
            local boundary = "--" .. string.sub(headers["content-type"], 31)
            local dataTable = explode(boundary, tostring(body))

            for i, v in ipairs(dataTable) do
                local t = explode("\r\n", v)
                if table.getn(t) == 5 then
                    local start_pos,end_pos,param_name = string.find(t[2], 'Content%-Disposition: form%-data; name="(.*)"')
                    if param_name == in_parameter then
                        request_parameter[param_name] = t[4]
                    end
                end
            end


        elseif string.sub(content_type, 1, 34) == "application/x-www-form-urlencoded" then
            args = req_body;
            for key, value in pairs(args) do
                if tostring(key) == in_parameter then
                    request_parameter[param_name] = tostring(value)
                end
            end

        elseif string.sub(content_type, 1, 16) == "application/json" then
            local json = req_body;
            if json ~= nil then
                args = core.json.decode(json)

                for key, value in pairs(args) do
                    if tostring(key) == in_parameter then
                        request_parameter[param_name] = tostring(value)
                    end
                end

            end

        end
    end


    return ctx.request_parameter

end


local function parse_graphql(ctx)
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, "failed to get local conf: " .. err
    end

    local max_size = GRAPHQL_DEFAULT_MAX_SIZE
    local size = core_tab.try_read_attr(local_conf, "graphql", "max_size")
    if size then
        max_size = size
    end

    local body, err = request.get_body(max_size, ctx)
    if not body then
        return nil, "failed to read graphql body: " .. err
    end

    local ok, res = pcall(gq_parse, body)
    if not ok then
        return nil, "failed to parse graphql: " .. res .. " body: " .. body
    end

    if #res.definitions == 0 then
        return nil, "empty graphql: " .. body
    end

    return res
end


local function get_parsed_graphql(ctx)
    if ctx._graphql then
        return ctx._graphql
    end

    local res, err = parse_graphql(ctx)
    if not res then
        log.error(err)
        ctx._graphql = {}
        return ctx._graphql
    end

    if #res.definitions > 1 then
        log.warn("Multiple operations are not supported.",
                    "Only the first one is handled")
    end

    local def = res.definitions[1]
    local fields = def.selectionSet.selections
    local root_fields = core_tab.new(#fields, 0)
    for i, f in ipairs(fields) do
        root_fields[i] = f.name.value
    end

    local name = ""
    if def.name and def.name.value then
        name = def.name.value
    end

    ctx._graphql = {
        name = name,
        operation = def.operation,
        root_fields = root_fields,
    }

    return ctx._graphql
end


do
    local var_methods = {
        method = ngx.req.get_method,
        cookie = function ()
            if ngx.var.http_cookie then
                return ck:new()
            end
        end
    }

    local ngx_var_names = {
        upstream_scheme            = true,
        upstream_host              = true,
        upstream_upgrade           = true,
        upstream_connection        = true,
        upstream_uri               = true,

        upstream_mirror_host       = true,

        upstream_cache_zone        = true,
        upstream_cache_zone_info   = true,
        upstream_no_cache          = true,
        upstream_cache_key         = true,
        upstream_cache_bypass      = true,

        var_x_forwarded_proto = true,
    }

    local mt = {
        __index = function(t, key)
            local cached = t._cache[key]
            if cached ~= nil then
                return cached
            end

            if type(key) ~= "string" then
                error("invalid argument, expect string value", 2)
            end

            local val
            local method = var_methods[key]
            if method then
                val = method()

            elseif core_str.has_prefix(key, "cookie_") then
                local cookie = t.cookie
                if cookie then
                    local err
                    val, err = cookie:get(sub_str(key, 8))
                    if err then
                        log.warn("failed to fetch cookie value by key: ",
                                 key, " error: ", err)
                    end
                end

            elseif core_str.has_prefix(key, "http_") then
                key = key:lower()
                key = re_gsub(key, "-", "_", "jo")
                val = get_var(key, t._request)

            elseif core_str.has_prefix(key, "graphql_") then
                -- trim the "graphql_" prefix
                key = sub_str(key, 9)
                val = get_parsed_graphql(t)[key]

            elseif key == "route_id" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.route_id

            elseif key == "service_id" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.service_id

            elseif key == "consumer_name" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.consumer_name

            elseif key == "route_name" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.route_name

            elseif key == "service_name" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.service_name

            elseif key == "balancer_ip" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.balancer_ip

            elseif key == "balancer_port" then
                val = ngx.ctx.api_ctx and ngx.ctx.api_ctx.balancer_port

            elseif core_str.has_prefix(key, "req_body_data") then
                val = get_request_parameter(t)
            else
                val = get_var(key, t._request)
            end

            if val ~= nil then
                t._cache[key] = val
            end

            return val
        end,

        __newindex = function(t, key, val)
            if ngx_var_names[key] then
                ngx_var[key] = val
            end

            -- log.info("key: ", key, " new val: ", val)
            t._cache[key] = val
        end,
    }

function _M.set_vars_meta(ctx)
    local var = tablepool.fetch("ctx_var", 0, 32)
    if not var._cache then
        var._cache = {}
    end

    var._request = get_request()
    setmetatable(var, mt)
    ctx.var = var
end

function _M.release_vars(ctx)
    if ctx.var == nil then
        return
    end

    core_tab.clear(ctx.var._cache)
    tablepool.release("ctx_var", ctx.var, true)
    ctx.var = nil
end

end -- do


return _M
