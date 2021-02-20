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
local file = require("apisix.cli.file")


local _M = {}


local config_data


function _M.clear_cache()
    config_data = nil
end


function _M.local_conf(force)
    if not force and config_data then
        return config_data
    end

    local default_conf, err = file.read_yaml_conf()
    if not default_conf then
        return nil, err
    end

    config_data = default_conf
    return config_data
end


return _M
