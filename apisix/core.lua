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
local log = require("apisix.core.log")
local utils = require("apisix.core.utils")
local local_conf, err = require("apisix.core.config_local").local_conf()
if not local_conf then
    error("failed to parse yaml config: " .. err)
end

local config_center = local_conf.apisix and local_conf.apisix.config_center
                      or "etcd"
log.info("use config_center: ", config_center)
local config = require("apisix.core.config_" .. config_center)
config.type = config_center


return {
    version     = require("apisix.core.version"),
    log         = log,
    config      = config,
    config_util = require("apisix.core.config_util"),
    sleep       = utils.sleep,
    json        = require("apisix.core.json"),
    table       = require("apisix.core.table"),
    request     = require("apisix.core.request"),
    response    = require("apisix.core.response"),
    lrucache    = require("apisix.core.lrucache"),
    schema      = require("apisix.schema_def"),
    string      = require("apisix.core.string"),
    ctx         = require("apisix.core.ctx"),
    timer       = require("apisix.core.timer"),
    id          = require("apisix.core.id"),
    utils       = utils,
    etcd        = require("apisix.core.etcd"),
    http        = require("apisix.core.http"),
    tablepool   = require("tablepool"),
    empty_tab   = {},
}
