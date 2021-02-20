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
local util   = require("apisix.plugins.grpc-transcode.util")
local core   = require("apisix.core")
local pb     = require("pb")
local bit    = require("bit")
local ngx    = ngx
local string = string
local table  = table
local ipairs = ipairs
local tonumber = tonumber
local req_read_body = ngx.req.read_body

return function (proto, service, method, pb_option, deadline, default_values)
    core.log.info("proto: ", core.json.delay_encode(proto, true))
    local m = util.find_method(proto, service, method)
    if not m then
        return false, "Undefined service method: " .. service .. "/" .. method
                      .. " end"
    end

    req_read_body()

    if pb_option then
        for _, opt in ipairs(pb_option) do
            pb.option(opt)
        end
    end

    local map_message = util.map_message(m.input_type, default_values or {})
    local encoded = pb.encode(m.input_type, map_message)

    if not encoded then
        return false, "failed to encode request data to protobuf"
    end

    local size = #encoded
    local prefix = {
        string.char(0),
        string.char(bit.band(bit.rshift(size, 24), 0xFF)),
        string.char(bit.band(bit.rshift(size, 16), 0xFF)),
        string.char(bit.band(bit.rshift(size, 8), 0xFF)),
        string.char(bit.band(size, 0xFF))
    }

    local message = table.concat(prefix, "") .. encoded

    ngx.req.set_method(ngx.HTTP_POST)
    ngx.req.set_uri("/" .. service .. "/" .. method, false)
    ngx.req.set_uri_args({})
    ngx.req.set_body_data(message)

    local dl = tonumber(deadline)
    if dl~= nil and dl > 0 then
        ngx.req.set_header("grpc-timeout",  dl .. "m")
    end

    return true
end
