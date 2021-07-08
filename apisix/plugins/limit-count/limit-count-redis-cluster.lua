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

local rediscluster = require("resty.rediscluster")
local core = require("apisix.core")
local setmetatable = setmetatable
local tostring = tostring
local ipairs = ipairs

local _M = {}


local mt = {
    __index = _M
}


local script = [=[
    if redis.call('ttl', KEYS[1]) < 0 then
        redis.call('set', KEYS[1], ARGV[1] - 1, 'EX', ARGV[2])
        return ARGV[1] - 1
    end
    return redis.call('incrby', KEYS[1], -1)
]=]


local function new_redis_cluster(conf)
    local config = {
        -- can set different name for different redis cluster
        name = conf.redis_cluster_name,
        serv_list = {},
        read_timeout = conf.redis_timeout,
        auth = conf.redis_password,
        dict_name = "plugin-limit-count-redis-cluster-slot-lock",
    }

    for i, conf_item in ipairs(conf.redis_cluster_nodes) do
        local host, port, err = core.utils.parse_addr(conf_item)
        if err then
            return nil, "failed to parse address: " .. conf_item
                        .. " err: " .. err
        end

        config.serv_list[i] = {
            ip = host, 
            port = port,
        }
    end

    local red_cli, err = rediscluster:new(config)
    if not red_cli then
        return nil, "failed to new redis cluster: " .. err
    end

    return red_cli
end


function _M.new(plugin_name, limit, window, conf)
    local red_cli, err = new_redis_cluster(conf)
    if not red_cli then
        return nil, err
    end

    local self = {
        limit = limit, 
        window = window, 
        conf = conf,
        plugin_name = plugin_name, 
        red_cli =red_cli,
    }

    return setmetatable(self, mt)
end


function _M.incoming(self, key)
    local red = self.red_cli
    local limit = self.limit
    local window = self.window
    key = self.plugin_name .. tostring(key)

    local remaining, err = red:eval(script, 1, key, limit, window)

    if err then
        return nil, err
    end

    if remaining < 0 then
        return nil, "rejected"
    end
    return 0, remaining
end


return _M
