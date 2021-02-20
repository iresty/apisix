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
local util    = require("apisix.plugins.grpc-transcode.util")
local core    = require("apisix.core")
local pb      = require("pb")
local ngx     = ngx
local string  = string
local table   = table
local ipairs  = ipairs

return function(proto, service, method, pb_option)
    local m = util.find_method(proto, service, method)
    if not m then
        return false, "2.Undefined service method: " .. service .. "/" .. method
                      .. " end."
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]
    local buffered = ngx.ctx.buffered
    if not buffered then
        buffered = {}
        ngx.ctx.buffered = buffered
    end

    if chunk ~= "" then
        core.table.insert(buffered, chunk)
        ngx.arg[1] = nil
    end


    if eof then
        ngx.ctx.buffered = nil
        local buffer = table.concat(buffered)
        if not ngx.req.get_headers()["X-Grpc-Web"] then
            buffer = string.sub(buffer, 6)
        end

        if pb_option then
            for _, opt in ipairs(pb_option) do
                pb.option(opt)
            end
        end

        local decoded = pb.decode(m.output_type, buffer)
        if not decoded then
            ngx.arg[1] = "failed to decode response data by protobuf"
            return "failed to decode response data by protobuf"
        end

        local response, err = core.json.encode(decoded)
        if not response then
            core.log.error("failed to call json_encode data: ", err)
            response = "failed to json_encode response body"
        end

        ngx.arg[1] = response
    end

end
