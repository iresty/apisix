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
local fetch_local_conf = require("apisix.core.config_local").local_conf
local http = require("resty.http")


local _M = {
    version = 0.1,
}


function _M.request_self(uri, opts)
    local local_conf = fetch_local_conf()
    if not local_conf or not local_conf.apisix
       or not local_conf.apisix.node_listen then
        return nil, nil -- invalid local yaml config
    end

    local httpc = http.new()
    local full_uri = "http://127.0.0.1:" .. local_conf.apisix.node_listen
                     .. uri
    return httpc:request_uri(full_uri, opts)
end


return _M
