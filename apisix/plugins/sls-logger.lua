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

    if not sock then
        err_msg = "failed to init the socket" .. soc_err
        core.log.error(err_msg)
        return false, err_msg
    end

    sock:settimeout(route_conf.timeout)
    local ok, err = sock:connect(route_conf.host, route_conf.port)
    if not ok then
        err_msg = "failed to connect to TCP server: host[" .. route_conf.host
        .. "] port[" .. tostring(route_conf.port) .. "] err: " .. err
        core.log.error(err_msg)
        return false, err_msg
    end

    ok, err = sock:sslhandshake(true, nil, false)
    if not ok then
        err_msg = "failed to to perform TLS handshake to TCP server: host["
        .. route_conf.host .. "] port[" .. tostring(route_conf.port) .. "] err: " .. err
        core.log.error(err_msg)
        return false, err_msg
    end

    core.log.warn("sls logger send data ", log_message)
    ok, err = sock:send(log_message)
    if not ok then
        res = false
        err_msg = "failed to send data to TCP server: host[" .. route_conf.host
                  .. "] port[" .. tostring(route_conf.port) .. "] err: " .. err
        core.log.error(err_msg)
    end

    ok, err = sock:close()
    if not ok then
        core.log.error("failed to close the TCP connection, host[",
        route_conf.host, "] port[", route_conf.port, "] ", err)
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
    local data
    for _, entry in pairs(entries) do
        if not data then
           data = entry.data
        end

        data = data .. entry.data
        core.log.info(entry.data)
    end

    return data
end

local function handle_log(entries)
    local data = combine_syslog(entries)
    if not data then
        return true
    end

    -- get the config from entries, replace of local value
    return send_tcp_data(entries[1].route_conf, data)
end

-- log phase in APISIX
function _M.log(conf)
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

    local rf5424_data = rf5424.encode("SYSLOG", "INFO", ngx.var.host
    , "apisix", ngx.var.pid, conf.project, conf.logstore
    , conf.access_key_id, conf.access_key_secret
    , json_str)

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
        inactive_timeout = conf.inactive_timeout
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