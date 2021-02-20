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
local require     = require
local core        = require("apisix.core")
local resty_chash = require("resty.chash")
local str_char    = string.char
local str_gsub    = string.gsub
local pairs = pairs


local _M = {}


local function fetch_chash_hash_key(ctx, upstream)
    local key = upstream.key
    local hash_on = upstream.hash_on or "vars"
    local chash_key

    if hash_on == "consumer" then
        chash_key = ctx.consumer_name
    elseif hash_on == "vars" then
        chash_key = ctx.var[key]
    elseif hash_on == "header" then
        chash_key = ctx.var["http_" .. key]
    elseif hash_on == "cookie" then
        chash_key = ctx.var["cookie_" .. key]
    elseif hash_on == "vars_combinations" then
        local err
        chash_key, err = core.utils.resolve_var(key, ctx.var);
        if err then
            core.log.error("could not resolve vars in ", key, " error: ", err)
        end
    end

    if not chash_key then
        chash_key = ctx.var["remote_addr"]
        core.log.warn("chash_key fetch is nil, use default chash_key ",
                      "remote_addr: ", chash_key)
    end
    core.log.info("upstream key: ", key)
    core.log.info("hash_on: ", hash_on)
    core.log.info("chash_key: ", core.json.delay_encode(chash_key))

    return chash_key
end


function _M.new(up_nodes, upstream)
    local str_null = str_char(0)

    local servers, nodes = {}, {}
    for serv, weight in pairs(up_nodes) do
        local id = str_gsub(serv, ":", str_null)

        servers[id] = serv
        nodes[id] = weight
    end

    local picker = resty_chash:new(nodes)
    return {
        upstream = upstream,
        get = function (ctx)
            local id
            if ctx.balancer_try_count > 1 and ctx.chash_last_server_index then
                id, ctx.chash_last_server_index = picker:next(ctx.chash_last_server_index)
            else
                local chash_key = fetch_chash_hash_key(ctx, upstream)
                id, ctx.chash_last_server_index = picker:find(chash_key)
            end
            -- core.log.warn("chash id: ", id, " val: ", servers[id])
            return servers[id]
        end
    }
end


return _M
