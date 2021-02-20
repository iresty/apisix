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
local json_encode = require("cjson.safe").encode
local clear_tab = require("table.clear")
local ngx = ngx
local tostring = tostring
local type = type
local pairs = pairs
local cached_tab = {}


local _M = {
    version = 0.1,
    decode = require("cjson.safe").decode,
}


local function serialise_obj(data)
    if type(data) == "function" or type(data) == "userdata"
       or type(data) == "cdata"
       or type(data) == "table" then
        return tostring(data)
    end

    return data
end


local function tab_clone_with_serialise(data)
    if type(data) ~= "table" then
        return serialise_obj(data)
    end

    local t = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            if cached_tab[v] then
                t[serialise_obj(k)] = tostring(v)
            else
                cached_tab[v] = true
                t[serialise_obj(k)] = tab_clone_with_serialise(v)
            end

        else
            t[serialise_obj(k)] = serialise_obj(v)
        end
    end

    return t
end


local function encode(data, force)
    if force then
        clear_tab(cached_tab)
        data = tab_clone_with_serialise(data)
    end

    return json_encode(data)
end
_M.encode = encode


local delay_tab = setmetatable({data = "", force = false}, {
    __tostring = function(self)
        local res, err = encode(self.data, self.force)
        if not res then
            ngx.log(ngx.WARN, "failed to encode: ", err,
                    " force: ", self.force)
        end

        return res
    end
})


-- this is a non-thread safe implementation
-- it works well with log, eg: log.info(..., json.delay_encode({...}))
function _M.delay_encode(data, force)
    delay_tab.data = data
    delay_tab.force = force
    return delay_tab
end


return _M
