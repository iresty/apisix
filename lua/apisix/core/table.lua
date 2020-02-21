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
local newproxy     = newproxy
local getmetatable = getmetatable
local setmetatable = setmetatable
local select       = select
local new_tab      = require("table.new")
local nkeys        = require("table.nkeys")
local json         = require("cjson.safe")
local pairs        = pairs
local ipairs        = ipairs
local type         = type
local error        = error


local _M = {
    version = 0.1,
    new     = new_tab,
    clear   = require("table.clear"),
    nkeys   = nkeys,
    insert  = table.insert,
    concat  = table.concat,
    clone   = require("table.clone"),
}


setmetatable(_M, {__index = table})


function _M.insert_tail(tab, ...)
    local idx = #tab
    for i = 1, select('#', ...) do
        idx = idx + 1
        tab[idx] = select(i, ...)
    end

    return idx
end


function _M.set(tab, ...)
    for i = 1, select('#', ...) do
        tab[i] = select(i, ...)
    end
end


-- only work under lua51 or luajit
function _M.setmt__gc(t, mt)
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() mt.__gc(t) end
    t[prox] = true
    return setmetatable(t, mt)
end


local function deepcopy(orig)
    local orig_type = type(orig)
    if orig_type ~= 'table' then
        return orig
    end

    local copy = new_tab(0, nkeys(orig))
    for orig_key, orig_value in pairs(orig) do
        copy[orig_key] = deepcopy(orig_value)
    end

    return copy
end
_M.deepcopy = deepcopy


local function read_only(t)
    if type(t) ~= "table" then
        return t
    end

    local str_v = json.encode(t)
    local proxy = {}

    local mt = {
        __index = t,
        __newindex = function(self, k, v)
            error("attempt to update a read-only table", 2)
        end,
        __tostring = function(self) return str_v end,
        __pairs = function (self) return pairs(t) end,
        __ipairs = function (self) return ipairs(t) end,
        __len = function (self) return #t end,
    }

    for k, v in pairs(t) do
        if type(v) == "table" then
            t[k] = _M.read_only(v)
        end
    end

    proxy = setmetatable(proxy, mt)
    return proxy
end
_M.read_only = read_only


return _M
