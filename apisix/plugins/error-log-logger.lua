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
local errlog = require("ngx.errlog")
local batch_processor = require("apisix.utils.batch-processor")
local plugin = require("apisix.plugin")
local timers = require("apisix.timers")
local plugin_name = "error-log-logger"
local table = core.table
local schema_def = core.schema
local ngx = ngx
local tcp = ngx.socket.tcp
local string = string
local tostring = tostring
local ipairs  = ipairs
local lrucache = core.lrucache.new({
    ttl = 300, count = 32
})


local metadata_schema = {
    type = "object",
    properties = {
        host = schema_def.host_def,
        port = {type = "integer", minimum = 0},
        tls = {type = "boolean", default = false},
        tls_server_name = {type = "string"},
        timeout = {type = "integer", minimum = 1, default = 3},
        keepalive = {type = "integer", minimum = 1, default = 30},
        name = {type = "string", default = plugin_name},
        level = {type = "string", default = "WARN", enum = {"STDERR", "EMERG", "ALERT", "CRIT",
                "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"}},
        batch_max_size = {type = "integer", minimum = 0, default = 1000},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 3},
    },
    required = {"host", "port"}
}
local schema = {
    type = "object",
}


local log_level = {
    STDERR =    ngx.STDERR,
    EMERG  =    ngx.EMERG,
    ALERT  =    ngx.ALERT,
    CRIT   =    ngx.CRIT,
    ERR    =    ngx.ERR,
    ERROR  =    ngx.ERR,
    WARN   =    ngx.WARN,
    NOTICE =    ngx.NOTICE,
    INFO   =    ngx.INFO,
    DEBUG  =    ngx.DEBUG
}


local config = {}
local buffers = {}


local _M = {
    version = 0.1,
    priority = 1091,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


local function send_to_server(data)
    local sock, soc_err = tcp()

    if not sock then
        return false, "failed to init the socket " .. soc_err
    end

    sock:settimeout(config.timeout * 1000)

    local ok, err = sock:connect(config.host, config.port)
    if not ok then
        return false, "failed to connect the TCP server: host[" .. config.host
            .. "] port[" .. tostring(config.port) .. "] err: " .. err
    end

    if config.tls then
        ok, err = sock:sslhandshake(false, config.tls_server_name, false)
        if not ok then
            sock:close()
            return false, "failed to perform TLS handshake to TCP server: host["
                .. config.host .. "] port[" .. tostring(config.port) .. "] err: " .. err
        end
    end

    local bytes, err = sock:send(data)
    if not bytes then
        sock:close()
        return false, "failed to send data to TCP server: host[" .. config.host
            .. "] port[" .. tostring(config.port) .. "] err: " .. err
    end

    sock:setkeepalive(config.keepalive * 1000)
    return true
end


local function update_filter(value)
    local level = log_level[string.upper(value.level)]
    local status, err = errlog.set_filter_level(level)
    if not status then
        return nil, "failed to set filter level by ngx.errlog, the error is :" .. err
    else
        core.log.debug("set the filter_level to ", config.level)
    end

    return value
end


local function process()
    local metadata = plugin.plugin_metadata(plugin_name)
    if not (metadata and metadata.value and metadata.modifiedIndex) then
        core.log.info("please set the correct plugin_metadata for ", plugin_name)
        return
    else
        local err
        config, err = lrucache(plugin_name, metadata.modifiedIndex, update_filter, metadata.value)
        if not config then
            core.log.warn("set log filter failed for ", err)
            return
        end

    end

    local id = ngx.worker.id()
    local entries = {}
    local logs = errlog.get_logs(9)
    while ( logs and #logs>0 ) do
        for i = 1, #logs, 3 do
            table.insert(entries, logs[i + 2])
            table.insert(entries, "\n")
        end
        logs = errlog.get_logs(9)
    end

    if #entries == 0 then
        return
    end

    local log_buffer = buffers[id]
    if log_buffer then
        for _, v in ipairs(entries) do
            log_buffer:push(v)
        end
        return
    end

    local config_bat = {
        name = config.name,
        retry_delay = config.retry_delay,
        batch_max_size = config.batch_max_size,
        max_retry_count = config.max_retry_count,
        buffer_duration = config.buffer_duration,
        inactive_timeout = config.inactive_timeout,
    }

    local err
    log_buffer, err = batch_processor:new(send_to_server, config_bat)

    if not log_buffer then
        core.log.warn("error when creating the batch processor: ", err)
        return
    end

    buffers[id] = log_buffer
    for _, v in ipairs(entries) do
        log_buffer:push(v)
    end

end


function _M.init()
    timers.register_timer("plugin#error-log-logger", process, true)
end


function _M.destory()
    timers.unregister_timer("plugin#error-log-logger", true)
end


return _M
