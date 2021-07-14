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
local ipairs = ipairs
local core = require("apisix.core")
local stringx = require('pl.stringx')
local type = type
local str_strip = stringx.strip
local re_find = ngx.re.find

local MATCH_NONE = 0
local MATCH_ALLOW = 1
local MATCH_DENY = 2

local lrucache_useragent = core.lrucache.new({ ttl = 300, count = 4096 })

local schema = {
    type = "object",
    properties = {
        message = {
            type = "string",
            minLength = 1,
            maxLength = 1024,
            default = "Not allowed"
        },
        allowlist = {
            type = "array",
            minItems = 1
        },
        denylist = {
            type = "array",
            minItems = 1
        },
    },
    anyOf = {
        {required = {"allowlist"}},
        {required = {"denylist"}},
    },
    minProperties = 1,
    additionalProperties = false,
}

local plugin_name = "ua-restriction"

local _M = {
    version = 0.1,
    priority = 2999,
    name = plugin_name,
    schema = schema,
}

local function match_user_agent(user_agent, conf)
    user_agent = str_strip(user_agent)
    if conf.allowlist then
        for _, rule in ipairs(conf.allowlist) do
            if re_find(user_agent, rule, "jo") then
                return MATCH_ALLOW
            end
        end
    end

    if conf.denylist then
        for _, rule in ipairs(conf.denylist) do
            if re_find(user_agent, rule, "jo") then
                return MATCH_DENY
            end
        end
    end

    return MATCH_NONE
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end

function _M.access(conf, ctx)
    local user_agent = core.request.header(ctx, "User-Agent")

    if not user_agent then
        return
    end
    local match = MATCH_NONE
    if type(user_agent) == "table" then
        for _, v in ipairs(user_agent) do
            if type(v) == "string" then
                match = lrucache_useragent(v, conf, match_user_agent, v, conf)
                if match > MATCH_ALLOW then
                    break
                end
            end
        end
    else
        match = lrucache_useragent(user_agent, conf, match_user_agent, user_agent, conf)
    end

    if match > MATCH_ALLOW then
        return 403, { message = conf.message }
    end
end

return _M
