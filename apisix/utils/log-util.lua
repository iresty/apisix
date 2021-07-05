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
local ngx  = ngx
local pairs = pairs
local str_byte = string.byte
local req_get_body_data = ngx.req.get_body_data

local lru_log_format = core.lrucache.new({
    ttl = 300, count = 512
})

local open = io.open

local _M = {}
_M.metadata_schema_log_format = {
    type = "object",
    default = {
        ["host"] = "$host",
        ["@timestamp"] = "$time_iso8601",
        ["client_ip"] = "$remote_addr",
    },
}


local function gen_log_format(format)
    local log_format = {}
    for k, var_name in pairs(format) do
        if var_name:byte(1, 1) == str_byte("$") then
            log_format[k] = {true, var_name:sub(2)}
        else
            log_format[k] = {false, var_name}
        end
    end
    core.log.info("log_format: ", core.json.delay_encode(log_format))
    return log_format
end

local function get_custom_format_log(ctx, format)
    local log_format = lru_log_format(format or "", nil, gen_log_format, format)
    local entry = core.table.new(0, core.table.nkeys(log_format))
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
    return entry
end
_M.get_custom_format_log = get_custom_format_log

local function get_full_log(ngx, conf)
    local ctx = ngx.ctx.api_ctx
    local var = ctx.var
    local service_id
    local route_id
    local url = var.scheme .. "://" .. var.host .. ":" .. var.server_port
                .. var.request_uri
    local matched_route = ctx.matched_route and ctx.matched_route.value

    if matched_route then
        service_id = matched_route.service_id or ""
        route_id = matched_route.id
    else
        service_id = var.host
    end

    local log =  {
        request = {
            url = url,
            uri = var.request_uri,
            method = ngx.req.get_method(),
            headers = ngx.req.get_headers(),
            querystring = ngx.req.get_uri_args(),
            size = var.request_length
        },
        response = {
            status = ngx.status,
            headers = ngx.resp.get_headers(),
            size = var.bytes_sent
        },
        server = {
            hostname = core.utils.gethostname(),
            version = core.version.VERSION
        },
        upstream = var.upstream_addr,
        service_id = service_id,
        route_id = route_id,
        consumer = ctx.consumer,
        client_ip = core.request.get_remote_client_ip(ngx.ctx.api_ctx),
        start_time = ngx.req.start_time() * 1000,
        latency = (ngx.now() - ngx.req.start_time()) * 1000
    }

    if conf.include_req_body then
        local body = req_get_body_data()
        if body then
            log.request.body = body
        else
            local body_file = ngx.req.get_body_file()
            if body_file then
                local file = open(body_file, "rb")
                local content = file:read "*a"
                file:close()
                log.request.body_file = content
            end
        end
    end

    return log
end
_M.get_full_log = get_full_log


function _M.get_req_original(ctx, conf)
    local headers = {
        ctx.var.request, "\r\n"
    }
    for k, v in pairs(ngx.req.get_headers()) do
        core.table.insert_tail(headers, k, ": ", v, "\r\n")
    end
    -- core.log.error("headers: ", core.table.concat(headers, ""))
    core.table.insert(headers, "\r\n")

    if conf.include_req_body then
        core.table.insert(headers, ctx.var.request_body)
    end

    return core.table.concat(headers, "")
end


return _M
