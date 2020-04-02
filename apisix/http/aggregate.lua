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
local core   = require("apisix.core")
local http   = require("resty.http")
local ngx    = ngx
local ipairs = ipairs
local pairs  = pairs
local type   = type

local _M = {
    version = 0.1,
}

local function check_input(data)
    if not data.pipeline then
        return 400, {message = "missing 'pipeline' in input"}
    end
    local type_timeout = type(data.timeout)
    if type_timeout ~= "number" and type_timeout ~= "nil" then
        return 400, {message = "'timeout' should be number"}
    end
    if not data.timeout or data.timeout == 0 then
        data.timeout = 30000
    end
end

local function set_base_header(data)
    if not data.headers then
        return
    end

    for i,req in ipairs(data.pipeline) do
        if not req.headers then
            req.headers = data.headers
        else
            for k, v in pairs(data.headers) do
                req.headers[k] = v
            end
        end
    end
end

local function set_base_query(data)
    if not data.query then
        return
    end

    for i,req in ipairs(data.pipeline) do
        if not req.query then
            req.query = data.query
        else
            for k, v in pairs(data.query) do
                req.query[k] = v
            end
        end
    end
end

function _M.aggregate(service_id)
    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()
    local data, err = core.json.decode(req_body)
    local code, body = check_input(data)
    if not data then
        core.log.error("invalid request body: ", req_body, " err: ", err)
        return 400, {message = "invalid request body", req_body = req_body}
    end

    if code then
        return code, body
    end

    local httpc = http.new()
    core.log.info(data.timeout)
    httpc:set_timeout(data.timeout)
    httpc:connect("127.0.0.1", ngx.var.server_port)
    set_base_header(data)
    set_base_query(data)
    local responses, err = httpc:request_pipeline(data.pipeline)
    if not responses then
        return 400, {message = "request failed", err = err}
    end

    local aggregated_resp = {}
    for i,r in ipairs(responses) do
        if not r.status then
            core.table.insert(aggregated_resp, {
                status = 504,
                reason = "target timeout"
            })
        end
        local sub_resp = {
            status  = r.status,
            reason  = r.reason,
            headers = r.headers,
        }
        if r.has_body then
            sub_resp.body = r:read_body()
        end
        core.table.insert(aggregated_resp, sub_resp)
    end
    return 200, aggregated_resp
end

return _M
