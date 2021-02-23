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

local core = require("apisix.core")
local log_util = require("apisix.utils.log-util")
local amqp = require("amqp")
local batch_processor = require("apisix.utils.batch-processor")
local ipairs = ipairs
local tostring = tostring
local plugin_name = "amqp-logger"
local stale_timer_running = false
local timer_at = ngx.timer.at
local ngx = ngx
local buffers = {}

local schema = {
    type = "object",
    properties = {
        amqp_role = {
            type = "string",
            default = "producer",
            enum = { "producer", "consumer" },
        },
        amqp_exchange = { type = "string", default = "apisix.topic" },
        amqp_routing_key = { type = "string", default = "logs" },
        amqp_username = { type = "string", default = "guest" },
        amqp_password = { type = "string", default = "guest" },
        amqp_no_ack = { type = "boolean", default = false },
        amqp_durable = { type = "boolean", default = true },
        amqp_auto_delete = { type = "boolean", default = false },
        amqp_exclusive = { type = "boolean", default = false },
        amqp_host = { type = "string" },
        amqp_port = { type = "integer" },
        timeout = { type = "integer", minimum = 1, default = 3 },
        name = { type = "string", default = "amqp logger" },
        max_retry_count = { type = "integer", minimum = 0, default = 0 },
        retry_delay = { type = "integer", minimum = 0, default = 1 },
        buffer_duration = { type = "integer", minimum = 1, default = 60 },
        inactive_timeout = { type = "integer", minimum = 1, default = 5 },
        batch_max_size = { type = "integer", minimum = 1, default = 1000 },
        include_req_body = { type = "boolean", default = false }
    },
    required = { "amqp_host", "amqp_port", "amqp_exchange" }
}

local _M = {
    version = 0.1,
    priority = 404,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature)
    if premature then
        return
    end

    for key, batch in ipairs(buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.warn("removing batch processor stale object, conf: ",
                    core.json.delay_encode(key))
            buffers[key] = nil
        end
    end

    stale_timer_running = false
end

local function send_amqp_data(conf, log_message)
    local err_msg
    local res = true

    local properties = {
        role = conf.amqp_role,
        exchange = conf.amqp_exchange,
        routing_key = conf.amqp_routing_key,
        user = conf.amqp_username,
        password = conf.amqp_password,
        no_ack = conf.amqp_no_ack,
        durable = conf.amqp_durable,
        auto_delete = conf.amqp_auto_delete,
        exclusive = conf.amqp_exclusive
    }

    local ctx = amqp:new(properties)
    local conn, conn_err = ctx:connect(conf.amqp_host, conf.amqp_port)

    if not conn then
        return false, "failed to connect to amqp broker" .. conn_err
    end

    core.log.info("sending a batch logs to amqp broker listen on ", conf.amqp_host,
            ":", tostring(conf.amqp_port))

    local setup, setup_err = ctx:setup()
    if not setup then
        return false, "failed to setup amqp broker channel " .. setup_err
    end

    local publish, publish_err = ctx:publish(log_message)
    if not publish then
        res = false
        err_msg = "failed to publish data to amqp server: host[" .. conf.amqp_host
                .. "] port[" .. tostring(conf.amqp_port) .. "] err: " .. publish_err
    end

    ctx:teardown()
    local close, close_err = ctx:close()
    if not close then
        core.log.error("failed to close the amqp broker connection, host[",
                conf.amqp_host, "] port[", tostring(conf.amqp_port), "] ", close_err)
    end

    return res, err_msg
end

function _M.log(conf, ctx)
    local entry = log_util.get_full_log(ngx, conf)

    if not stale_timer_running then
        -- run the timer every 30 mins if any log is present
        timer_at(1800, remove_stale_objects)
        stale_timer_running = true
    end

    local log_buffer = buffers[conf]
    if log_buffer then
        log_buffer:push(entry)
        return
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        local data, err
        if batch_max_size == 1 then
            data, err = core.json.encode(entries[1]) -- encode as single {}
        else
            data, err = core.json.encode(entries) -- encode as array [{}]
        end

        if not data then
            core.log.error('error occurred while encoding the data: ', err)
        end

        return send_amqp_data(conf, data)
    end

    local config = {
        name = conf.name,
        retry_delay = conf.retry_delay,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
        route_id = ctx.var.route_id,
        server_addr = ctx.var.server_addr,
    }

    local err
    log_buffer, err = batch_processor:new(func, config)

    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return
    end

    buffers[conf] = log_buffer
    log_buffer:push(entry)
end

return _M
