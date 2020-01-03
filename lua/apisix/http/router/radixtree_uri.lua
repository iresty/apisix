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
local require = require
local router = require("resty.radixtree")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local loadstring = loadstring
local str_sub = string.sub
local str_find = string.find
local user_routes
local cached_version


local _M = {version = 0.2}


    local uri_routes = {}
    local uri_router
local function create_radixtree_router(routes)
    routes = routes or {}

    local api_routes = plugin.api_routes()
    core.table.clear(uri_routes)

    for _, route in ipairs(api_routes) do
        if type(route) == "table" then
            local paths = route.uris or {route.uri}
            for i, path in ipairs(paths) do
                core.table.insert(uri_routes, {
                    paths = path,
                    methods = route.methods,
                    handler = function(api_ctx, ...)
                        api_ctx.matched_uri = path
                        return route.handler(api_ctx, ...)
                    end,
                })
            end
        end
    end

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            local filter_fun, err
            local route_val= route.value

            if route_val.filter_func then
                filter_fun, err = loadstring(
                                        "return " .. route_val.filter_func,
                                        "router#" .. route_val.id)
                if not filter_fun then
                    core.log.error("failed to load filter function: ", err,
                                   " route id: ", route_val.id)
                    goto CONTINUE
                end

                filter_fun = filter_fun()
            end

            core.log.info("insert uri route: ",
                          core.json.delay_encode(route_val))

            local paths = route_val.uris or {route_val.uri}
            for i, path in ipairs(paths) do
                local matched_uri = path
                if str_find(path, "*", #path, true) then
                    matched_uri = str_sub(path, 1, #path - 1)
                end

                core.table.insert(uri_routes, {
                    paths = path,
                    methods = route_val.methods,
                    priority = route_val.priority,
                    hosts = route_val.hosts or route_val.host,
                    remote_addrs = route_val.remote_addrs
                                   or route_val.remote_addr,
                    vars = route_val.vars,
                    filter_fun = filter_fun,
                    handler = function (api_ctx)
                        api_ctx.matched_uri = matched_uri
                        core.log.debug("matched_uri: [", matched_uri, "]")

                        api_ctx.matched_params = nil
                        api_ctx.matched_route = route
                    end
                })
            end

            ::CONTINUE::
        end
    end

    core.log.info("route items: ", core.json.delay_encode(uri_routes, true))
    uri_router = router.new(uri_routes)
end


    local match_opts = {}
function _M.match(api_ctx)
    if not cached_version or cached_version ~= user_routes.conf_version then
        create_radixtree_router(user_routes.values)
        cached_version = user_routes.conf_version
    end

    if not uri_router then
        core.log.error("failed to fetch valid `uri` router: ")
        return true
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.request_method
    match_opts.host = api_ctx.var.host
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var

    local ok = uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    if not ok then
        core.log.info("not find any matched route")
        return true
    end

    return true
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end


function _M.init_worker(filter)
    local err
    user_routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route,
            filter = filter,
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /routes : " .. err)
    end
end


return _M
