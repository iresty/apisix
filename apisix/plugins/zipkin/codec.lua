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
local to_hex = require "resty.string".to_hex
local new_span_context = require("opentracing.span_context").new
local ngx    = ngx
local string = string
local pairs = pairs
local tonumber = tonumber

local function hex_to_char(c)
    return string.char(tonumber(c, 16))
end

local function from_hex(str)
    if str ~= nil then -- allow nil to pass through
        str = str:gsub("%x%x", hex_to_char)
    end
    return str
end

local function new_extractor()
    return function(headers)
        local had_invalid_id = false

        local trace_id = headers["x-b3-traceid"]
        local parent_span_id = headers["x-b3-parentspanid"]
        local request_span_id = headers["x-b3-spanid"]

        -- Validate trace id
        if trace_id and
            ((#trace_id ~= 16 and #trace_id ~= 32) or trace_id:match("%X")) then
            core.log.warn("x-b3-traceid header invalid; ignoring.")
            had_invalid_id = true
        end

        -- Validate parent_span_id
        if parent_span_id and
            (#parent_span_id ~= 16 or parent_span_id:match("%X")) then
            core.log.warn("x-b3-parentspanid header invalid; ignoring.")
            had_invalid_id = true
        end

        -- Validate request_span_id
        if request_span_id and
            (#request_span_id ~= 16 or request_span_id:match("%X")) then
            core.log.warn("x-b3-spanid header invalid; ignoring.")
            had_invalid_id = true
        end

        if trace_id == nil or had_invalid_id then
            return nil
        end

        -- Process jaegar baggage header
        local baggage = {}
        for k, v in pairs(headers) do
            local baggage_key = k:match("^uberctx%-(.*)$")
            if baggage_key then
                baggage[baggage_key] = ngx.unescape_uri(v)
            end
        end

        trace_id = from_hex(trace_id)
        parent_span_id = from_hex(parent_span_id)
        request_span_id = from_hex(request_span_id)

        return new_span_context(trace_id, request_span_id, parent_span_id,
                                baggage)
    end
end

local function new_injector()
    return function(span_context, headers)
        -- We want to remove headers if already present
        headers["x-b3-traceid"] = to_hex(span_context.trace_id)
        headers["x-b3-parentspanid"] = span_context.parent_id
                                    and to_hex(span_context.parent_id) or nil
        headers["x-b3-spanid"] = to_hex(span_context.span_id)
        -- when we call this function, we already start to sample
        headers["x-b3-sampled"] = "1"
        for key, value in span_context:each_baggage_item() do
            -- XXX: https://github.com/opentracing/specification/issues/117
            headers["uberctx-"..key] = ngx.escape_uri(value)
        end
    end
end

return {
    new_extractor = new_extractor,
    new_injector = new_injector,
}
