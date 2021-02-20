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
local plugin_checker = require("apisix.plugin").stream_plugin_checker
local ipairs    = ipairs
local error     = error
local ngx_exit  = ngx.exit
local tonumber  = tonumber
local user_routes


local _M = {version = 0.1}


local function match_opts(route, api_ctx)
    local vars = api_ctx.var

    -- todo: use resty-ipmatcher to support multiple ip address
    if route.value.remote_addr and
       route.value.remote_addr ~= vars.remote_addr then
        return false
    end

    if route.value.server_addr and
       route.value.server_addr ~= vars.server_addr then
        return false
    end

    -- todo: use resty-ipmatcher to support multiple ip address
    if route.value.server_port and
       route.value.server_port ~= tonumber(vars.server_port) then
        return false
    end

    return true
end


function _M.match(api_ctx)
    local routes = _M.routes()
    if not routes then
        core.log.info("not find any user stream route")
        return ngx_exit(200)
    end
    core.log.info("stream routes: ", core.json.delay_encode(routes))

    for _, route in ipairs(routes) do
        local hit = match_opts(route, api_ctx)
        if hit then
            api_ctx.matched_route = route
            return true
        end
    end

    core.log.info("not hit any route")
    return true
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end


function _M.stream_init_worker(filter)
    local err
    user_routes, err = core.config.new("/stream_routes", {
            automatic = true,
            item_schema = core.schema.stream_route,
            checker = plugin_checker,
            filter = filter,
        })

    if not user_routes then
        error("failed to create etcd instance for fetching /stream_routes : "
              .. err)
    end
end


return _M
