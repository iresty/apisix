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
local log_util = require("apisix.utils.log-util")
local batch_processor = require("apisix.utils.batch-processor")
local plugin_name = "sls-logger"
local ngx = ngx
local rf5424 = require("apisix.plugins.slslog.rfc5424")
local stale_timer_running = false;
local timer_at = ngx.timer.at
local tcp = ngx.socket.tcp
local buffers = {}
local tostring = tostring
local ipairs = ipairs
local table = table
local schema = {
    type = "object",
    properties = {
        include_req_body = {type = "boolean", default = false},
        name = {type = "string", default = "sls-logger"},
        timeout = {type = "integer", minimum = 1, default= 5000},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 5},
        batch_max_size = {type = "integer", minimum = 1, default = 1000},
        host = {type = "string"},
        port = {type = "integer"},
        project = {type = "string"},
        logstore = {type = "string"},
        access_key_id = {type = "string"},
        access_key_secret = {type ="string"}
    },
    required = {"host", "port", "project", "logstore", "access_key_id", "access_key_secret"}
}

local _M = {
    version = 0.1,
    priority = 406,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
   return core.schema.check(schema, conf)
end

local function send_tcp_data(route_conf, log_message)
    local err_msg
    local res = true
    local sock, soc_err = tcp()
    local can_close

    if not sock then
        return false, "failed to init the socket" .. soc_err
    end

    sock:settimeout(route_conf.timeout)
    local ok, err = sock:connect(route_conf.host, route_conf.port)
    if not ok then
        return false, "failed to connect to TCP server: host[" .. route_conf.host
                      .. "] port[" .. tostring(route_conf.port) .. "] err: " .. err
    end

    ok, err = sock:sslhandshake(true, nil, false)
    if not ok then
        return false, "failed to perform TLS handshake to TCP server: host["
                      .. route_conf.host .. "] port[" .. tostring(route_conf.port)
                      .. "] err: " .. err
    end

    core.log.debug("sls logger send data ", log_message)
    ok, err = sock:send(log_message)
    if not ok then
        res = false
        can_close = true
        err_msg = "failed to send data to TCP server: host[" .. route_conf.host
                  .. "] port[" .. tostring(route_conf.port) .. "] err: " .. err
    else
        ok, err = sock:setkeepalive(120 * 1000, 20)
        if not ok then
            can_close = true
            core.log.warn("failed to set socket keepalive: host[", route_conf.host,
                          "] port[", tostring(route_conf.port), "] err: ", err)
        end
    end

    if  can_close then
        ok, err = sock:close()
        if not ok then
            core.log.warn("failed to close the TCP connection, host[",
                          route_conf.host, "] port[", route_conf.port, "] ", err)
        end
    end

    return res, err_msg
end

-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature)
    if premature then
        return
    end

    for key, batch in ipairs(buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.warn("removing batch processor stale object, route id:", tostring(key))
            buffers[key] = nil
        end
    end

    stale_timer_running = false
end

local function combine_syslog(entries)
    local items = {}
    for _, entry in ipairs(entries) do
        table.insert(items, entry.data)
        core.log.info("buffered logs:", entry.data)
    end

    return table.concat(items)
end

_M.combine_syslog = combine_syslog

local function handle_log(entries)
    local data = combine_syslog(entries)
    if not data then
        return true
    end

    return send_tcp_data(entries[1].route_conf, data)
end

-- log phase in APISIX
function _M.log(conf, ctx)
    local entry = log_util.get_full_log(ngx, conf)
    if not entry.route_id then
        core.log.error("failed to obtain the route id for sys logger")
        return
    end

    local json_str, err = core.json.encode(entry)
    if not json_str then
        core.log.error('error occurred while encoding the data: ', err)
        return
    end

    local rf5424_data = rf5424.encode("SYSLOG", "INFO", ctx.var.host,"apisix",
                                      ctx.var.pid, conf.project, conf.logstore,
                                      conf.access_key_id, conf.access_key_secret, json_str)

    local process_context = {
        data = rf5424_data,
        route_conf = conf
    }

    local log_buffer = buffers[entry.route_id]
    if not stale_timer_running then
        -- run the timer every 15 mins if any log is present
        timer_at(900, remove_stale_objects)
        stale_timer_running = true
    end

    if log_buffer then
        log_buffer:push(process_context)
        return
    end

    local process_conf = {
        name = conf.name,
        retry_delay = conf.retry_delay,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
        route_id = ctx.var.route_id,
        server_addr = ctx.var.server_addr,
    }

    log_buffer, err = batch_processor:new(handle_log, process_conf)
    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return
    end

    buffers[entry.route_id] = log_buffer
    log_buffer:push(process_context)
end


return _M
