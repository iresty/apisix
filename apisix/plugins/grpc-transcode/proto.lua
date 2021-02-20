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
local config_util = require("apisix.core.config_util")
local protoc      = require("protoc")
local protos


local lrucache_proto = core.lrucache.new({
    ttl = 300, count = 100
})


local function create_proto_obj(proto_id)
    if protos.values == nil then
        return nil
    end

    local content
    for _, proto in config_util.iterate_values(protos.values) do
        if proto_id == proto.value.id then
            content = proto.value.content
            break
        end
    end

    if not content then
        return nil, "failed to find proto by id: " .. proto_id
    end

    local _p  = protoc.new()
    local res = _p:load(content)

    if not res or not _p.loaded then
        return nil, "failed to load proto content"
    end


    return _p.loaded
end


local _M = {version = 0.1}


function _M.fetch(proto_id)
    return lrucache_proto(proto_id, protos.conf_version,
                          create_proto_obj, proto_id)
end


function _M.protos()
    if not protos then
        return nil, nil
    end

    return protos.values, protos.conf_version
end


function _M.init()
    local err
    protos, err = core.config.new("/proto", {
        automatic = true,
        item_schema = core.schema.proto
    })
    if not protos then
        core.log.error("failed to create etcd instance for fetching protos: ",
                       err)
        return
    end
end


return _M
