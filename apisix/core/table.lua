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

local require      = require
local newproxy     = newproxy
local getmetatable = getmetatable
local setmetatable = setmetatable
local select       = select
local new_tab      = require("table.new")
local nkeys        = require("table.nkeys")
local ipairs       = ipairs
local pairs        = pairs
local type         = type
local ngx_re       = require("ngx.re")


local _M = {
    version = 0.2,
    new     = new_tab,
    clear   = require("table.clear"),
    nkeys   = nkeys,
    insert  = table.insert,
    concat  = table.concat,
    sort    = table.sort,
    clone   = require("table.clone"),
    isarray = require("table.isarray"),
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


function _M.try_read_attr(tab, ...)
    local count = select('#', ...)

    for i = 1, count do
        local attr = select(i, ...)
        if type(tab) ~= "table" then
            return nil
        end

        tab = tab[attr]
    end

    return tab
end


function _M.array_find(array, val)
    for i, v in ipairs(array) do
        if v == val then
            return i
        end
    end

    return nil
end


-- only work under lua51 or luajit
function _M.setmt__gc(t, mt)
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() mt.__gc(t) end
    t[prox] = true
    return setmetatable(t, mt)
end


local deepcopy
do
    local function _deepcopy(orig, copied)
        -- prevent infinite loop when a field refers its parent
        copied[orig] = true
        -- If the array-like table contains nil in the middle,
        -- the len might be smaller than the expected.
        -- But it doesn't affect the correctness.
        local len = #orig
        local copy = new_tab(len, nkeys(orig) - len)
        for orig_key, orig_value in pairs(orig) do
            if type(orig_value) == "table" and not copied[orig_value] then
                copy[orig_key] = _deepcopy(orig_value, copied)
            else
                copy[orig_key] = orig_value
            end
        end

        return copy
    end


    local copied_recorder = {}

    function deepcopy(orig)
        local orig_type = type(orig)
        if orig_type ~= 'table' then
            return orig
        end

        local res = _deepcopy(orig, copied_recorder)
        _M.clear(copied_recorder)
        return res
    end
end
_M.deepcopy = deepcopy


local ngx_null = ngx.null
local function merge(origin, extend)
    for k,v in pairs(extend) do
        if type(v) == "table" then
            if type(origin[k] or false) == "table" then
                if _M.nkeys(origin[k]) ~= #origin[k] then
                    merge(origin[k] or {}, extend[k] or {})
                else
                    origin[k] = v
                end
            else
                origin[k] = v
            end
        elseif v == ngx_null then
            origin[k] = nil
        else
            origin[k] = v
        end
    end

    return origin
end
_M.merge = merge


local function patch(node_value, sub_path, conf)
    local sub_value = node_value
    local sub_paths = ngx_re.split(sub_path, "/")
    for i = 1, #sub_paths - 1 do
        local sub_name = sub_paths[i]
        if sub_value[sub_name] == nil then
            sub_value[sub_name] = {}
        end

        sub_value = sub_value[sub_name]

        if type(sub_value) ~= "table" then
            return 400, "invalid sub-path: /"
                      .. _M.concat(sub_paths, 1, i)
        end
    end

    if type(sub_value) ~= "table" then
        return 400, "invalid sub-path: /" .. sub_path
    end

    local sub_name = sub_paths[#sub_paths]
    if sub_name and sub_name ~= "" then
        sub_value[sub_name] = conf
    else
        node_value = conf
    end

    return nil, nil, node_value
end
_M.patch = patch


-- Compare two tables as if they are sets (only compare the key part)
function _M.set_eq(a, b)
    if nkeys(a) ~= nkeys(b) then
        return false
    end

    for k in pairs(a) do
        if b[k] == nil then
            return false
        end
    end

    return true
end


-- Compare two elements, including their descendants
local function deep_eq(a, b)
    local type_a = type(a)
    local type_b = type(b)

    if type_a ~= 'table' or type_b ~= 'table' then
        return a == b
    end

    local n_a = nkeys(a)
    local n_b = nkeys(b)
    if n_a ~= n_b then
        return false
    end

    for k, v_a in pairs(a) do
        local v_b = b[k]
        local eq = deep_eq(v_a, v_b)
        if not eq then
            return false
        end
    end

    return true
end
_M.deep_eq = deep_eq


-- pick takes the given attributes out of object
function _M.pick(obj, attrs)
    local data = {}
    for k, v in pairs(obj) do
        if attrs[k] ~= nil then
            data[k] = v
        end
    end

    return data
end


return _M
