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

local require         = require
local batch_processor = require("apisix.utils.batch-processor")
local log_util        = require("apisix.utils.log-util")
local core            = require("apisix.core")
local http            = require("resty.http")
local url             = require("net.url")
local plugin          = require("apisix.plugin")

local ngx      = ngx
local tostring = tostring
local pairs    = pairs
local ipairs   = ipairs
local str_byte = string.byte
local timer_at = ngx.timer.at

local plugin_name = "http-logger"
local stale_timer_running = false
local buffers = {}
local lru_log_format = core.lrucache.new({
    ttl = 300, count = 512
})

local schema = {
    type = "object",
    properties = {
        uri = core.schema.uri_def,
        auth_header = {type = "string", default = ""},
        timeout = {type = "integer", minimum = 1, default = 3},
        name = {type = "string", default = "http logger"},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 5},
        batch_max_size = {type = "integer", minimum = 1, default = 1000},
        include_req_body = {type = "boolean", default = false},
        concat_method = {type = "string", default = "json",
                         enum = {"json", "new_line"}}
    },
    required = {"uri"}
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = {
            type = "object",
            default = {
                ["host"] = "$host",
                ["@timestamp"] = "$time_iso8601",
                ["client_ip"] = "$remote_addr",
            },
        },
    },
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = 410,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function send_http_data(conf, log_message)
    local err_msg
    local res = true
    local url_decoded = url.parse(conf.uri)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending a batch logs to ", conf.uri)

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, false)
        if not ok then
            return nil, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end

    local content_type
    if conf.concat_method == "json" then
        content_type = "application/json"
    else
        content_type = "text/plain"
    end

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = url_decoded.path,
        query = url_decoded.query,
        body = log_message,
        headers = {
            ["Host"] = url_decoded.host,
            ["Content-Type"] = content_type,
            ["Authorization"] = conf.auth_header
        }
    })

    if not httpc_res then
        return false, "error while sending data to [" .. host .. "] port["
            .. tostring(port) .. "] " .. httpc_err
    end

    -- some error occurred in the server
    if httpc_res.status >= 400 then
        res =  false
        err_msg = "server returned status code[" .. httpc_res.status .. "] host["
            .. host .. "] port[" .. tostring(port) .. "] "
            .. "body[" .. httpc_res:read_body() .. "]"
    end

    return res, err_msg
end


local function gen_log_format(metadata)
    local log_format = {}
    if metadata == nil then
        return log_format
    end

    for k, var_name in pairs(metadata.value.log_format) do
        if var_name:byte(1, 1) == str_byte("$") then
            log_format[k] = {true, var_name:sub(2)}
        else
            log_format[k] = {false, var_name}
        end
    end
    core.log.info("log_format: ", core.json.delay_encode(log_format))
    return log_format
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


function _M.log(conf, ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    local entry
    local log_format = lru_log_format(metadata or "", nil, gen_log_format,
                                      metadata)
    if core.table.nkeys(log_format) > 0 then
        entry = core.table.new(0, core.table.nkeys(log_format))
        for k, var_attr in pairs(log_format) do
            if var_attr[1] then
                entry[k] = ctx.var[var_attr[2]]
            else
                entry[k] = var_attr[2]
            end
        end

        local matched_route = ctx.matched_route and ctx.matched_route.value
        if matched_route then
            entry.service_id = matched_route.service_id
            entry.route_id = matched_route.id
        end
    else
        entry = log_util.get_full_log(ngx, conf)
    end

    if not entry.route_id then
        entry.route_id = "no-matched"
    end

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

        if conf.concat_method == "json" then
            if batch_max_size == 1 then
                data, err = core.json.encode(entries[1]) -- encode as single {}
            else
                data, err = core.json.encode(entries) -- encode as array [{}]
            end

        elseif conf.concat_method == "new_line" then
            if batch_max_size == 1 then
                data, err = core.json.encode(entries[1]) -- encode as single {}
            else
                local t = core.table.new(#entries, 0)
                for i, entrie in ipairs(entries) do
                    t[i], err = core.json.encode(entrie)
                    if err then
                        core.log.warn("failed to encode http log: ", err, ", log data: ", entrie)
                        break
                    end
                end
                data = core.table.concat(t, "\n") -- encode as multiple string
            end

        else
            -- defensive programming check
            err = "unknown concat_method " .. (conf.concat_method or "nil")
        end

        if not data then
            return false, 'error occurred while encoding the data: ' .. err
        end

        return send_http_data(conf, data)
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
