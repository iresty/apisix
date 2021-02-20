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
local consumer_mod = require("apisix.consumer")
local plugin_name = "key-auth"
local ipairs = ipairs


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    additionalProperties = false,
    properties = {},
}

local consumer_schema = {
    type = "object",
    additionalProperties = false,
    properties = {
        key = {type = "string"},
    },
    required = {"key"},
}


local _M = {
    version = 0.1,
    priority = 2500,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema,
}


local create_consume_cache
do
    local consumer_names = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_names)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_names[consumer.auth_conf.key] = consumer
        end

        return consumer_names
    end

end -- do


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end


function _M.rewrite(conf, ctx)
    local key = core.request.header(ctx, "apikey")
    if not key then
        return 401, {message = "Missing API key found in request"}
    end

    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return 401, {message = "Missing related consumer"}
    end

    local consumers = lrucache("consumers_key", consumer_conf.conf_version,
        create_consume_cache, consumer_conf)

    local consumer = consumers[key]
    if not consumer then
        return 401, {message = "Invalid API key in request"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
    core.log.info("hit key-auth rewrite")
end


return _M
