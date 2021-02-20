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
local get_routes = require("apisix.router").http_routes
local schema_plugin = require("apisix.admin.plugins").check_schema
local upstreams = require("apisix.admin.upstreams")
local utils = require("apisix.admin.utils")
local tostring = tostring
local ipairs = ipairs
local type = type
local loadstring = loadstring


local _M = {
    version = 0.3,
}


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing service id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong service id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong service id"}
    end

    conf.id = id

    core.log.info("schema: ", core.json.delay_encode(core.schema.service))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(core.schema.service, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if need_id and not id then
        return nil, {error_msg = "wrong type of service id"}
    end

    local upstream_conf = conf.upstream
    if upstream_conf then
        local ok, err = upstreams.check_upstream_conf(upstream_conf)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    local upstream_id = conf.upstream_id
    if upstream_id then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    if conf.plugins then
        local ok, err = schema_plugin(conf.plugins)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    if conf.script then
        local obj, err = loadstring(conf.script)
        if not obj then
            return nil, {error_msg = "failed to load 'script' string: "
                                     .. err}
        end

        if type(obj()) ~= "table" then
            return nil, {error_msg = "'script' should be a Lua object"}
        end
    end

    return need_id and id or true
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/services/" .. id
    core.log.info("key: ", key)

    local ok, err = utils.inject_conf_with_prev_conf("service", key, conf)
    if not ok then
        return 500, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/services"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/services"
    utils.inject_timestamp(conf)
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing service id"}
    end

    local routes, routes_ver = get_routes()
    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)
    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.value
               and route.value.service_id
               and tostring(route.value.service_id) == id then
                return 400, {error_msg = "can not delete this service directly,"
                                         .. " route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local key = "/services/" .. id
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(id, conf, sub_path)
    if not id then
        return 400, {error_msg = "missing service id"}
    end

    if not conf then
        return 400, {error_msg = "missing new configuration"}
    end

    if not sub_path or sub_path == "" then
        if type(conf) ~= "table"  then
            return 400, {error_msg = "invalid configuration"}
        end
    end

    local key = "/services" .. "/" .. id
    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ",
                  core.json.delay_encode(res_old, true))

    local node_value = res_old.body.node.value
    local modified_index = res_old.body.node.modifiedIndex

    if sub_path and sub_path ~= "" then
        local code, err, node_val = core.table.patch(node_value, sub_path, conf)
        node_value = node_val
        if code then
            return code, err
        end
    else
        node_value = core.table.merge(node_value, conf);
    end

    utils.inject_timestamp(node_value, nil, conf)

    core.log.info("new value ", core.json.delay_encode(node_value, true))

    local id, err = check_conf(id, node_value, true)
    if not id then
        return 400, err
    end

    local res, err = core.etcd.atomic_set(key, node_value, nil, modified_index)
    if not res then
        core.log.error("failed to set new service[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
