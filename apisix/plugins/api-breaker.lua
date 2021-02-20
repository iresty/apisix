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
local plugin_name = "api-breaker"
local ngx = ngx
local math = math
local error = error

local shared_buffer = ngx.shared['plugin-'.. plugin_name]
if not shared_buffer then
    error("failed to get ngx.shared dict when load plugin " .. plugin_name)
end


local schema = {
    type = "object",
    properties = {
        break_response_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
        },
        max_breaker_sec = {
            type = "integer",
            minimum = 3,
            default = 300,
        },
        unhealthy = {
            type = "object",
            properties = {
                http_statuses = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "integer",
                        minimum = 500,
                        maximum = 599,
                    },
                    uniqueItems = true,
                    default = {500}
                },
                failures = {
                    type = "integer",
                    minimum = 1,
                    default = 3,
                }
            },
            default = {http_statuses = {500}, failures = 3}
        },
        healthy = {
            type = "object",
            properties = {
                http_statuses = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "integer",
                        minimum = 200,
                        maximum = 499,
                    },
                    uniqueItems = true,
                    default = {200}
                },
                successes = {
                    type = "integer",
                    minimum = 1,
                    default = 3,
                }
            },
            default = {http_statuses = {200}, successes = 3}
        }
    },
    required = {"break_response_code"},
}


local function gen_healthy_key(ctx)
    return "healthy-" .. core.request.get_host(ctx) .. ctx.var.uri
end


local function gen_unhealthy_key(ctx)
    return "unhealthy-" .. core.request.get_host(ctx) .. ctx.var.uri
end


local function gen_lasttime_key(ctx)
    return "unhealthy-lastime" .. core.request.get_host(ctx) .. ctx.var.uri
end


local _M = {
    version = 0.1,
    name = plugin_name,
    priority = 1005,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    local unhealthy_key = gen_unhealthy_key(ctx)
    -- unhealthy counts
    local unhealthy_count, err = shared_buffer:get(unhealthy_key)
    if err then
        core.log.warn("failed to get unhealthy_key: ",
                      unhealthy_key, " err: ", err)
        return
    end

    if not unhealthy_count then
        return
    end

    -- timestamp of the last time a unhealthy state was triggered
    local lasttime_key = gen_lasttime_key(ctx)
    local lasttime, err = shared_buffer:get(lasttime_key)
    if err then
        core.log.warn("failed to get lasttime_key: ",
                      lasttime_key, " err: ", err)
        return
    end

    if not lasttime then
        return
    end

    local failure_times = math.ceil(unhealthy_count / conf.unhealthy.failures)
    if failure_times < 1 then
        failure_times = 1
    end

    -- cannot exceed the maximum value of the user configuration
    local breaker_time = 2 ^ failure_times
    if breaker_time > conf.max_breaker_sec then
        breaker_time = conf.max_breaker_sec
    end
    core.log.info("breaker_time: ", breaker_time)

    -- breaker
    if lasttime + breaker_time >= ngx.time() then
        return conf.break_response_code
    end

    return
end


function _M.log(conf, ctx)
    local unhealthy_key = gen_unhealthy_key(ctx)
    local healthy_key = gen_healthy_key(ctx)
    local upstream_status = core.response.get_upstream_status(ctx)

    if not upstream_status then
        return
    end

    -- unhealth process
    if core.table.array_find(conf.unhealthy.http_statuses,
                             upstream_status)
    then
        local unhealthy_count, err = shared_buffer:incr(unhealthy_key, 1, 0)
        if err then
            core.log.warn("failed to incr unhealthy_key: ", unhealthy_key,
                          " err: ", err)
        end
        core.log.info("unhealthy_key: ", unhealthy_key, " count: ",
                      unhealthy_count)

        shared_buffer:delete(healthy_key)

        -- whether the user-configured number of failures has been reached,
        -- and if so, the timestamp for entering the unhealthy state.
        if unhealthy_count % conf.unhealthy.failures == 0 then
            shared_buffer:set(gen_lasttime_key(ctx), ngx.time(),
                              conf.max_breaker_sec)
            core.log.info("update unhealthy_key: ", unhealthy_key, " to ",
                          unhealthy_count)
        end

        return
    end

    -- health process
    if not core.table.array_find(conf.healthy.http_statuses, upstream_status) then
        return
    end

    local unhealthy_count, err = shared_buffer:get(unhealthy_key)
    if err then
        core.log.warn("failed to `get` unhealthy_key: ", unhealthy_key,
                      " err: ", err)
    end

    if not unhealthy_count then
        return
    end

    local healthy_count, err = shared_buffer:incr(healthy_key, 1, 0)
    if err then
        core.log.warn("failed to `incr` healthy_key: ", healthy_key,
                      " err: ", err)
    end

    -- clear related status
    if healthy_count >= conf.healthy.successes then
        -- stat change to normal
        core.log.info("change to normal, ", healthy_key, " ", healthy_count)
        shared_buffer:delete(gen_lasttime_key(ctx))
        shared_buffer:delete(unhealthy_key)
        shared_buffer:delete(healthy_key)
    end

    return
end


return _M
