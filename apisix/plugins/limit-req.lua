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
local limit_req_new = require("resty.limit.req").new
local core = require("apisix.core")
local plugin_name = "limit-req"
local sleep = core.sleep


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        rate = {type = "number", exclusiveMinimum = 0},
        burst = {type = "number",  minimum = 0},
        key = {type = "string",
            enum = {"remote_addr", "server_addr", "http_x_real_ip",
                    "http_x_forwarded_for", "consumer_name"},
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
    },
    required = {"rate", "burst", "key"}
}


local _M = {
    version = 0.1,
    priority = 1001,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function create_limit_obj(conf)
    core.log.info("create new limit-req plugin instance")
    return limit_req_new("plugin-limit-req", conf.rate, conf.burst)
end


function _M.access(conf, ctx)
    local lim, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                              create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.req object: ", err)
        return 500
    end

    local key
    if conf.key == "consumer_name" then
        if not ctx.consumer_name then
            core.log.error("consumer not found.")
            return 500, { message = "Consumer not found."}
        end
        key = ctx.consumer_name .. ctx.conf_type .. ctx.conf_version

    else
        key = (ctx.var[conf.key] or "") .. ctx.conf_type .. ctx.conf_version
    end
    core.log.info("limit key: ", key)

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end

return _M
