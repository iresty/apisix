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
local http      = require "resty.http"
local lrucache  = core.lrucache.new({
    ttl = 300, count = 512
})


local schema = {
    type = "object",
    properties = {
        bypass_missing = {
            type = "boolean",
            default = false,
        },
        whitelist = {
            type = "array",
            items = core.schema.host_def,
            minItems = 1
        },
    },
    required = {"whitelist"},
    additionalProperties = false,
}


local plugin_name = "referer-restriction"


local _M = {
    version = 0.1,
    priority = 2990,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function match_host(matcher, host)
     if matcher.map[host] then
        return true
    end
    for _, h in ipairs(matcher.suffixes) do
        if core.string.has_suffix(host, h) then
            return true
        end
    end
    return false
end


local function create_host_matcher(hosts)
    local hosts_suffix = {}
    local hosts_map = {}

    for _, h in ipairs(hosts) do
        if h:byte(1) == 42 then -- start with '*'
            core.table.insert(hosts_suffix, h:sub(2))
        else
            hosts_map[h] = true
        end
    end

    return {
        suffixes = hosts_suffix,
        map = hosts_map,
    }
end


function _M.access(conf, ctx)
    local block = false
    local referer = ctx.var.http_referer
    if referer then
        -- parse_uri doesn't support IPv6 literal, it is OK since we only
        -- expect hostname in the whitelist.
        -- See https://github.com/ledgetech/lua-resty-http/pull/104
        local uri = http.parse_uri(nil, referer)
        if not uri then
            -- malformed Referer
            referer = nil
        else
            -- take host part only
            referer = uri[2]
        end
    end


    if not referer then
        block = not conf.bypass_missing

    elseif conf.whitelist then
        local matcher = lrucache(conf.whitelist, nil,
                                 create_host_matcher, conf.whitelist)
        block = not match_host(matcher, referer)
    end

    if block then
        return 403, { message = "Your referer host is not allowed" }
    end
end


return _M
