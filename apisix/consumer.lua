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
local require        = require
local core           = require("apisix.core")
local plugin         = require("apisix.plugin")
local plugin_checker = require("apisix.plugin").plugin_checker
local error          = error
local ipairs         = ipairs
local pairs          = pairs
local type           = type
local consumers


local _M = {
    version = 0.3,
}


local function plugin_consumer()
    local plugins = {}

    if consumers.values == nil then
        return plugins
    end

    for _, consumer in ipairs(consumers.values) do
        if type(consumer) ~= "table" then
            goto CONTINUE
        end

        for name, config in pairs(consumer.value.plugins or {}) do
            local plugin_obj = plugin.get(name)
            if plugin_obj and plugin_obj.type == "auth" then
                if not plugins[name] then
                    plugins[name] = {
                        nodes = {},
                        conf_version = consumers.conf_version
                    }
                end

                local new_consumer = core.table.clone(consumer.value)
                -- Note: the id here is the key of consumer data, which
                -- is 'username' field in admin
                new_consumer.consumer_name = new_consumer.id
                new_consumer.auth_conf = config
                core.log.info("consumer:", core.json.delay_encode(new_consumer))
                core.table.insert(plugins[name].nodes, new_consumer)
            end
        end

        ::CONTINUE::
    end

    return plugins
end


function _M.plugin(plugin_name)
    local plugin_conf = core.lrucache.global("/consumers",
                            consumers.conf_version, plugin_consumer)
    return plugin_conf[plugin_name]
end


-- attach chosen consumer to the ctx, used in auth plugin
function _M.attach_consumer(ctx, consumer, conf)
    ctx.consumer = consumer
    ctx.consumer_name = consumer.consumer_name
    ctx.consumer_ver = conf.conf_version
end


function _M.consumers()
    if not consumers then
        return nil, nil
    end

    return consumers.values, consumers.conf_version
end


local function check_consumer(consumer)
    return plugin_checker(consumer, core.schema.TYPE_CONSUMER)
end


local function filter(consumer)
    if not consumer.value then
        return
    end

    -- We expect the id is the same as username. Fix up it here if it isn't.
    consumer.value.id = consumer.value.username
end


function _M.init_worker()
    local err
    local config = core.config.new()
    local cfg = {
        automatic = true,
        item_schema = core.schema.consumer,
        checker = check_consumer,
    }
    if config.type ~= "etcd" then
        cfg.filter = filter
    end

    consumers, err = core.config.new("/consumers", cfg)
    if not consumers then
        error("failed to create etcd instance for fetching consumers: " .. err)
        return
    end
end


return _M
