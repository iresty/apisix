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

local require       = require
local core          = require("apisix.core")
local plugin_name   = "request-id"
local ngx           = ngx
local uuid          = require("resty.jit-uuid")

local schema = {
    type = "object",
    properties = {
        header_name = {type = "string", default = "X-Request-Id"},
        include_in_response = {type = "boolean", default = true}
    }
}


local _M = {
    version = 0.1,
    priority = 11010,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf, ctx)
    local headers = ngx.req.get_headers()
    local uuid_val = uuid()
    if not headers[conf.header_name] then
        core.request.set_header(ctx, conf.header_name, uuid_val)
    end

    if conf.include_in_response then
        ctx.x_request_id = uuid_val
    end
end


function _M.header_filter(conf, ctx)
    if not conf.include_in_response then
        return
    end

    local headers = ngx.resp.get_headers()
    if not headers[conf.header_name] then
        core.response.set_header(conf.header_name, ctx.x_request_id)
    end
end

return _M
