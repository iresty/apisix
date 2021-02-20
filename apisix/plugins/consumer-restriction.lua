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

local require   = require
local ipairs    = ipairs
local core      = require("apisix.core")

local schema = {
    type = "object",
    oneOf = {
        {
            title = "blacklist",
            properties = {
                type = {
                    type = "string",
                    enum = {"consumer_name", "service_id"},
                    default = "consumer_name"
                },
                blacklist = {
                    type = "array",
                    minItems = 1,
                    items = {type = "string"}
                },
                rejected_code = {type = "integer", minimum = 200, default = 403}
            },
            required = {"blacklist"},
        },
        {
            title = "whitelist",
            properties = {
                type = {
                    type = "string",
                    enum = {"consumer_name", "service_id"},
                    default = "consumer_name"
                },
                whitelist = {
                    type = "array",
                    minItems = 1,
                    items = {type = "string"}
                },
                rejected_code = {type = "integer", minimum = 200, default = 403}
            },
            required = {"whitelist"},
        }
    }
}

local plugin_name = "consumer-restriction"

local _M = {
    version = 0.1,
    priority = 2400,
    name = plugin_name,
    schema = schema,
}

local fetch_val_funcs = {
    ["service_id"] = function(ctx)
        return ctx.service_id
    end,
    ["consumer_name"] = function(ctx)
        return ctx.consumer_name
    end
}

local function is_include(value, tab)
    for k,v in ipairs(tab) do
        if v == value then
            return true
        end
    end
    return false
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    local value = fetch_val_funcs[conf.type](ctx)
    if not value then
        return 401, { message = "Missing authentication or identity verification."}
    end
    core.log.info("value: ", value)

    local block = false
    if conf.blacklist and #conf.blacklist > 0 then
        if is_include(value, conf.blacklist) then
            block = true
        end
    end

    if conf.whitelist and #conf.whitelist > 0 then
        if not is_include(value, conf.whitelist) then
            block = true
        end
    end

    if block then
        return conf.rejected_code, { message = "The " .. conf.type .. " is forbidden." }
    end
end


return _M
