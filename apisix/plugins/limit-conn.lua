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
local limit_conn_new = require("resty.limit.conn").new
local core = require("apisix.core")
local sleep = core.sleep
local plugin_name = "limit-conn"


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        conn = {type = "integer", exclusiveMinimum = 0},
        burst = {type = "integer",  minimum = 0},
        default_conn_delay = {type = "number", exclusiveMinimum = 0},
        key = {type = "string",
            enum = {"remote_addr", "server_addr", "http_x_real_ip",
                    "http_x_forwarded_for", "consumer_name"},
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
    },
    required = {"conn", "burst", "default_conn_delay", "key"}
}


local _M = {
    version = 0.1,
    priority = 1003,
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
    core.log.info("create new limit-conn plugin instance")
    return limit_conn_new("plugin-limit-conn", conf.conn, conf.burst,
                          conf.default_conn_delay)
end


function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)
    local lim, err = lrucache(conf, nil, create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.conn object: ", err)
        return 500
    end

    local key = (ctx.var[conf.key] or "") .. ctx.conf_type .. ctx.conf_version
    core.log.info("limit key: ", key)

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    if lim:is_committed() then
        if not ctx.limit_conn then
            ctx.limit_conn = core.tablepool.fetch("plugin#limit-conn", 0, 6)
        end

        core.table.insert_tail(ctx.limit_conn, lim, key, delay)
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end


function _M.log(conf, ctx)
    local limit_conn = ctx.limit_conn
    if not limit_conn then
        return
    end

    for i = 1, #limit_conn, 3 do
        local lim = limit_conn[i]
        local key = limit_conn[i + 1]
        local delay = limit_conn[i + 2]

        local latency
        if ctx.proxy_passed then
            latency = ctx.var.upstream_response_time
        else
            latency = ctx.var.request_time - delay
        end

        core.log.debug("request latency is ", latency) -- for test

        local conn, err = lim:leaving(key, latency)
        if not conn then
            core.log.error("failed to record the connection leaving request: ",
                           err)
            break
        end
    end

    core.tablepool.release("plugin#limit-conn", limit_conn)
    return
end


return _M
