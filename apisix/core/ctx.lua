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

local require      = require
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
local rawset       = rawset
local ngx          = ngx
local ngx_var      = ngx.var
local re_gsub      = ngx.re.gsub
local ipairs       = ipairs
local type         = type
local error        = error
local pcall        = pcall


local _M = {version = 0.2}
local GRAPHQL_DEFAULT_MAX_SIZE = 1048576               -- 1MiB


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
        cookie = function () return ck:new() end
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
        upstream_hdr_expires       = true,
        upstream_hdr_cache_control = true,
    }

    local mt = {
        __index = function(t, key)
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
                    if not val then
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

            else
                val = get_var(key, t._request)
            end

            if val ~= nil then
                rawset(t, key, val)
            end

            return val
        end,

        __newindex = function(t, key, val)
            if ngx_var_names[key] then
                ngx_var[key] = val
            end

            -- log.info("key: ", key, " new val: ", val)
            rawset(t, key, val)
        end,
    }

function _M.set_vars_meta(ctx)
    local var = tablepool.fetch("ctx_var", 0, 32)
    var._request = get_request()
    setmetatable(var, mt)
    ctx.var = var
end

function _M.release_vars(ctx)
    if ctx.var == nil then
        return
    end

    tablepool.release("ctx_var", ctx.var)
    ctx.var = nil
end

end -- do


return _M
