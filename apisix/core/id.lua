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

local require          = require
local fetch_local_conf = require("apisix.core.config_local").local_conf
local try_read_attr    = require("apisix.core.table").try_read_attr
local log              = require("apisix.core.log")
local uuid             = require('resty.jit-uuid')
local smatch           = string.match
local open             = io.open


local prefix = ngx.config.prefix()
local apisix_uid

local _M = {version = 0.1}


local function rtrim(str)
    return smatch(str, "^(.-)%s*$")
end


local function read_file(path)
    local file = open(path, "rb") -- r read mode and b binary mode
    if not file then
        return nil
    end

    local content = file:read("*a")  -- *a or *all reads the whole file
    file:close()
    return rtrim(content)
end


local function write_file(path, data)
    local file = open(path ,"w+")
    if not file then
        return nil, "failed to open file[" .. path .. "] for writing"
    end

    file:write(data)
    file:close()
    return true
end


_M.gen_uuid_v4 = uuid.generate_v4


function _M.init()
    local uid_file_path = prefix .. "/conf/apisix.uid"
    apisix_uid = read_file(uid_file_path)
    if apisix_uid then
        return
    end

    --allow user to specify a meaningful id as apisix instance id
    local local_conf = fetch_local_conf()
    local id = try_read_attr(local_conf, "apisix", "id")
    if id then
        apisix_uid = local_conf.apisix.id
    else
        uuid.seed()
        apisix_uid = uuid.generate_v4()
        log.notice("not found apisix uid, generate a new one: ", apisix_uid)
    end

    local ok, err = write_file(uid_file_path, apisix_uid)
    if not ok then
        log.error(err)
    end
end


function _M.get()
    return apisix_uid
end


return _M
