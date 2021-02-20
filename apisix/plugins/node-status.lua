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
local ngx = ngx
local re_gmatch = ngx.re.gmatch
local ngx_capture = ngx.location.capture
local plugin_name = "node-status"
local apisix_id = core.id.get()
local ipairs = ipairs


local schema = {
    type = "object",
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = 1000,
    name = plugin_name,
    schema = schema,
}


local ngx_status = {}
local ngx_statu_items = {
    "active", "accepted", "handled", "total",
    "reading", "writing", "waiting"
}


local function collect()
    local res = ngx_capture("/apisix/nginx_status")
    if res.status ~= 200 then
        return res.status
    end

    -- Active connections: 2
    -- server accepts handled requests
    --   26 26 84
    -- Reading: 0 Writing: 1 Waiting: 1

    local iterator, err = re_gmatch(res.body, [[(\d+)]], "jmo")
    if not iterator then
        return 500, "failed to re.gmatch Nginx status: " .. err
    end

    core.table.clear(ngx_status)
    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        ngx_status[name] = val[0]
    end

    return 200, core.json.encode({id = apisix_id, status = ngx_status})
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/status",
            handler = collect,
        }
    }
end


return _M
