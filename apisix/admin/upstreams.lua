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
local get_services = require("apisix.http.service").services
local utils = require("apisix.admin.utils")
local tostring = tostring
local ipairs = ipairs
local type = type


local _M = {
    version = 0.2,
}


local function get_chash_key_schema(hash_on)
    if not hash_on then
        return nil, "hash_on is nil"
    end

    if hash_on == "vars" then
        return core.schema.upstream_hash_vars_schema
    end

    if hash_on == "header" or hash_on == "cookie" then
        return core.schema.upstream_hash_header_schema
    end

    if hash_on == "consumer" then
        return nil, nil
    end

    if hash_on == "vars_combinations" then
        return core.schema.upstream_hash_vars_combinations_schema
    end

    return nil, "invalid hash_on type " .. hash_on
end


local function check_upstream_conf(conf)
    local ok, err = core.schema.check(core.schema.upstream, conf)
    if not ok then
        return false, "invalid configuration: " .. err
    end

    if conf.pass_host == "node" and conf.nodes and
        core.table.nkeys(conf.nodes) ~= 1
    then
        return false, "only support single node for `node` mode currently"
    end

    if conf.pass_host == "rewrite" and
        (conf.upstream_host == nil or conf.upstream_host == "")
    then
        return false, "`upstream_host` can't be empty when `pass_host` is `rewrite`"
    end

    if conf.type ~= "chash" then
        return true
    end

    if not conf.hash_on then
        conf.hash_on = "vars"
    end

    if conf.hash_on ~= "consumer" and not conf.key then
        return false, "missing key"
    end

    local key_schema, err = get_chash_key_schema(conf.hash_on)
    if err then
        return false, "type is chash, err: " .. err
    end

    if key_schema then
        local ok, err = core.schema.check(key_schema, conf.key)
        if not ok then
            return false, "invalid configuration: " .. err
        end
    end

    return true
end


local function check_conf(id, conf, need_id)
    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    id = id or conf.id
    if need_id and not id then
        return nil, {error_msg = "missing upstream id"}
    end

    if not need_id and id then
        return nil, {error_msg = "wrong upstream id, do not need it"}
    end

    if need_id and conf.id and tostring(conf.id) ~= tostring(id) then
        return nil, {error_msg = "wrong upstream id"}
    end

    -- let schema check id
    conf.id = id

    core.log.info("schema: ", core.json.delay_encode(core.schema.upstream))
    core.log.info("conf  : ", core.json.delay_encode(conf))

    local ok, err = check_upstream_conf(conf)
    if not ok then
        return nil, {error_msg = err}
    end

    return need_id and id or true
end


function _M.put(id, conf)
    local id, err = check_conf(id, conf, true)
    if not id then
        return 400, err
    end

    local key = "/upstreams/" .. id
    core.log.info("key: ", key)

    local ok, err = utils.inject_conf_with_prev_conf("upstream", key, conf)
    if not ok then
        return 500, {error_msg = err}
    end

    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(id)
    local key = "/upstreams"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(id, conf)
    local id, err = check_conf(id, conf, false)
    if not id then
        return 400, err
    end

    local key = "/upstreams"
    utils.inject_timestamp(conf)
    local res, err = core.etcd.push(key, conf)
    if not res then
        core.log.error("failed to post upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.delete(id)
    if not id then
        return 400, {error_msg = "missing upstream id"}
    end

    local routes, routes_ver = get_routes()
    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)
    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.value
               and route.value.upstream_id
               and tostring(route.value.upstream_id) == id then
                return 400, {error_msg = "can not delete this upstream,"
                                         .. " route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local services, services_ver = get_services()
    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)
    if services_ver and services then
        for _, service in ipairs(services) do
            if type(service) == "table" and service.value
               and service.value.upstream_id
               and tostring(service.value.upstream_id) == id then
                return 400, {error_msg = "can not delete this upstream,"
                                         .. " service [" .. service.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local key = "/upstreams/" .. id
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.patch(id, conf, sub_path)
    if not id then
        return 400, {error_msg = "missing upstream id"}
    end

    if not conf then
        return 400, {error_msg = "missing new configuration"}
    end

    if not sub_path or sub_path == "" then
        if type(conf) ~= "table"  then
            return 400, {error_msg = "invalid configuration"}
        end
    end

    local key = "/upstreams" .. "/" .. id
    local res_old, err = core.etcd.get(key)
    if not res_old then
        core.log.error("failed to get upstream [", key, "]: ", err)
        return 500, {error_msg = err}
    end

    if res_old.status ~= 200 then
        return res_old.status, res_old.body
    end
    core.log.info("key: ", key, " old value: ",
                  core.json.delay_encode(res_old, true))

    local new_value = res_old.body.node.value
    local modified_index = res_old.body.node.modifiedIndex

    if sub_path and sub_path ~= "" then
        local code, err, node_val = core.table.patch(new_value, sub_path, conf)
        new_value = node_val
        if code then
            return code, err
        end
    else
        new_value = core.table.merge(new_value, conf);
    end

    utils.inject_timestamp(new_value, nil, conf)

    core.log.info("new value ", core.json.delay_encode(new_value, true))

    local id, err = check_conf(id, new_value, true)
    if not id then
        return 400, err
    end

    local res, err = core.etcd.atomic_set(key, new_value, nil, modified_index)
    if not res then
        core.log.error("failed to set new upstream[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end

-- for routes and services check upstream conf
_M.check_upstream_conf = check_upstream_conf


return _M
