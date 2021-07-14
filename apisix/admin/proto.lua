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
local type = type
local ipairs = ipairs
local core = require("apisix.core")
local utils = require("apisix.admin.utils")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local tostring = tostring


local _M = {
    version = 0.1,
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing proto id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong proto id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong proto id"}
    end

    core.log.info("schema: ", core.json.delay_encode(core.schema.proto))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.proto, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return need_id and id or true
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/proto/" .. id

    local ok, err = utils.inject_conf_with_prev_conf("proto", key, conf)
    if not ok then
        return 500, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/proto"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    utils.fix_count(res.body, id)
    return res.status, res.body
end


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/proto"

    utils.inject_timestamp(conf)

    -- core.log.info("key: ", key)
    local res, err = core.etcd.push("/proto", conf)
    if not res then
        core.log.error("failed to post proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end

local function check_proto_used(plugins, deleting, ptype, pid)

    --core.log.info("check_proto_used plugins: ", core.json.delay_encode(plugins, true))
    --core.log.info("check_proto_used deleting: ", deleting)
    --core.log.info("check_proto_used ptype: ", ptype)
    --core.log.info("check_proto_used pid: ", pid)

    if plugins then
        if type(plugins) == "table" and plugins["grpc-transcode"]
           and plugins["grpc-transcode"].proto_id
           and tostring(plugins["grpc-transcode"].proto_id) == deleting then
            return false, {error_msg = "can not delete this proto,"
                                     .. ptype .. " [" .. pid
                                     .. "] is still using it now"}
        end
    end
    return true
end

function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing proto id"}
    end
    core.log.info("proto delete: ", id)

    local routes, routes_ver = get_routes()

    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)

    if routes_ver and routes then
        for _, route in ipairs(routes) do
            core.log.info("proto delete route item: ", core.json.delay_encode(route, true))
            if type(route) == "table" and route.value and route.value.plugins then
                local ret, err = check_proto_used(route.value.plugins, id, "route",route.value.id)
                if not ret then
                    return 400, err
                end
            end
        end
    end
    core.log.info("proto delete route ref check pass: ", id)

    local services, services_ver = get_services()

    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)

    if services_ver and services then
        for _, service in ipairs(services) do
            if type(service) == "table" and service.value and service.value.plugins then
                local ret, err = check_proto_used(service.value.plugins, id,
                                                "service", service.value.id)
                if not ret then
                    return 400, err
                end
            end
        end
    end
    core.log.info("proto delete service ref check pass: ", id)

    local key = "/proto/" .. id
    -- core.log.info("key: ", key)
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete proto[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
