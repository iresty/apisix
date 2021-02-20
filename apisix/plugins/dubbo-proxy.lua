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
local ngx_var = ngx.var


local plugin_name = "dubbo-proxy"

local schema = {
    type = "object",
    properties = {
        service_name = {
            type = "string",
            minLength = 1,
        },
        service_version = {
            type = "string",
            pattern = [[^\d+\.\d+\.\d+]],
        },
        method = {
            type = "string",
            minLength = 1,
        },
    },
    required = { "service_name", "service_version"},
}

local _M = {
    version = 0.1,
    priority = 507,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    ctx.dubbo_proxy_enabled = true

    ngx_var.dubbo_service_name = conf.service_name
    ngx_var.dubbo_service_version = conf.service_version
    if not conf.method then
        -- remove the prefix '/' from $uri
        ngx_var.dubbo_method = core.string.sub(ngx_var.uri, 2)
    else
        ngx_var.dubbo_method = conf.method
    end
end


return _M
