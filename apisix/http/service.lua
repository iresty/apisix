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
local core = require("apisix.core")
local plugin_checker = require("apisix.plugin").plugin_checker
local ipairs = ipairs
local services
local error = error
local pairs = pairs


local _M = {
    version = 0.2,
}


function _M.get(service_id)
    return services:get(service_id)
end


function _M.services()
    if not services then
        return nil, nil
    end

    return services.values, services.conf_version
end


local function filter(service)
    service.has_domain = false
    if not service.value then
        return
    end

    if not service.value.upstream then
        return
    end

    service.value.upstream.parent = service

    if not service.value.upstream.nodes then
        return
    end

    local nodes = service.value.upstream.nodes
    if core.table.isarray(nodes) then
        for _, node in ipairs(nodes) do
            local host = node.host
            if not core.utils.parse_ipv4(host) and
                    not core.utils.parse_ipv6(host) then
                service.has_domain = true
                break
            end
        end
    else
        local new_nodes = core.table.new(core.table.nkeys(nodes), 0)
        for addr, weight in pairs(nodes) do
            local host, port = core.utils.parse_addr(addr)
            if not core.utils.parse_ipv4(host) and
                    not core.utils.parse_ipv6(host) then
                service.has_domain = true
            end
            local node = {
                host = host,
                port = port,
                weight = weight,
            }
            core.table.insert(new_nodes, node)
        end
        service.value.upstream.nodes = new_nodes
    end

    core.log.info("filter service: ", core.json.delay_encode(service, true))
end


function _M.init_worker()
    local err
    services, err = core.config.new("/services", {
        automatic = true,
        item_schema = core.schema.service,
        checker = plugin_checker,
        filter = filter,
    })
    if not services then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
