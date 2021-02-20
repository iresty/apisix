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
local resty_http = require "resty.http"
local to_hex = require "resty.string".to_hex
local cjson = require "cjson.safe".new()
cjson.encode_number_precision(16)
local assert = assert
local type = type
local setmetatable = setmetatable
local math = math
local tostring = tostring
local batch_processor = require("apisix.utils.batch-processor")
local core = require("apisix.core")

local _M = {}
local mt = { __index = _M }


local span_kind_map = {
    client = "CLIENT",
    server = "SERVER",
    producer = "PRODUCER",
    consumer = "CONSUMER",
}


function _M.new(conf)
    local endpoint = conf.endpoint
    local service_name = conf.service_name
    local server_port = conf.server_port
    local server_addr = conf.server_addr
    assert(type(endpoint) == "string", "invalid http endpoint")
    return setmetatable({
        endpoint = endpoint,
        service_name = service_name,
        server_addr = server_addr,
        server_port = server_port,
        pending_spans_n = 0,
        route_id = conf.route_id
    }, mt)
end


function _M.report(self, span)
    local span_context = span:context()

    local zipkin_tags = {}
    for k, v in span:each_tag() do
        -- Zipkin tag values should be strings
        zipkin_tags[k] = tostring(v)
    end

    local span_kind = zipkin_tags["span.kind"]
    zipkin_tags["span.kind"] = nil

    local localEndpoint = {
        serviceName = self.service_name,
        ipv4 = self.server_addr,
        port = self.server_port,
        -- TODO: ip/port from ngx.var.server_name/ngx.var.server_port?
    }

    local remoteEndpoint do
        local peer_port = span:get_tag "peer.port" -- get as number
        if peer_port then
            zipkin_tags["peer.port"] = nil
            remoteEndpoint = {
                ipv4 = zipkin_tags["peer.ipv4"],
                -- ipv6 = zipkin_tags["peer.ipv6"],
                port = peer_port, -- port is *not* optional
            }
            zipkin_tags["peer.ipv4"] = nil
            zipkin_tags["peer.ipv6"] = nil
        else
            remoteEndpoint = cjson.null
        end
    end

    local zipkin_span = {
        traceId = to_hex(span_context.trace_id),
        name = span.name,
        parentId = span_context.parent_id and
                    to_hex(span_context.parent_id) or nil,
        id = to_hex(span_context.span_id),
        kind = span_kind_map[span_kind],
        timestamp = span.timestamp * 1000000,
        duration = math.floor(span.duration * 1000000), -- zipkin wants integer
        -- TODO: debug?
        localEndpoint = localEndpoint,
        remoteEndpoint = remoteEndpoint,
        tags = zipkin_tags,
        annotations = span.logs
    }

    self.pending_spans_n = self.pending_spans_n + 1
    if self.processor then
        self.processor:push(zipkin_span)
    end
end


local function send_span(pending_spans, report)
    local httpc = resty_http.new()
    local res, err = httpc:request_uri(report.endpoint, {
        method = "POST",
        headers = {
            ["content-type"] = "application/json",
        },
        body = pending_spans,
        keepalive = 5000,
        keepalive_pool = 5
    })

    if not res then
        -- for zipkin test
        core.log.error("report zipkin span failed")
        return nil, "failed: " .. err .. ", url: " .. report.endpoint
    elseif res.status < 200 or res.status >= 300 then
        return nil, "failed: " .. report.endpoint .. " "
               .. res.status .. " " .. res.reason
    end

    return true
end


function _M.init_processor(self)
    local process_conf = {
        name = "zipkin_report",
        retry_delay = 1,
        batch_max_size = 1000,
        max_retry_count = 0,
        buffer_duration = 60,
        inactive_timeout = 5,
        route_id = self.route_id,
        server_addr = self.server_addr,
    }

    local flush = function (entries, batch_max_size)
        if not entries then
            return true
        end

        local pending_spans, err
        if batch_max_size == 1 then
            pending_spans, err = cjson.encode(entries[1])
        else
            pending_spans, err = cjson.encode(entries)
        end

        if not pending_spans then
            return false, 'error occurred while encoding the data: ' .. err
        end

        return send_span(pending_spans, self)
    end

    local processor, err = batch_processor:new(flush, process_conf)
    if err then
        return false, "create processor error: " .. err
    end

    self.processor = processor
end


return _M
