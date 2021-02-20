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
local ipairs = ipairs
local type = type


local _M = {}


local function sort_by_key_host(a, b)
    return a.host < b.host
end


function _M.compare_upstream_node(old_t, new_t)
    if type(old_t) ~= "table" then
        return false
    end

    if #new_t ~= #old_t then
        return false
    end

    core.table.sort(old_t, sort_by_key_host)
    core.table.sort(new_t, sort_by_key_host)

    for i = 1, #new_t do
        local new_node = new_t[i]
        local old_node = old_t[i]
        for _, name in ipairs({"host", "port", "weight"}) do
            if new_node[name] ~= old_node[name] then
                return false
            end
        end
    end

    return true
end


return _M
