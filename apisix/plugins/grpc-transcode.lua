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
local ngx         = ngx
local core        = require("apisix.core")
local schema_def  = require("apisix.schema_def")
local proto       = require("apisix.plugins.grpc-transcode.proto")
local request     = require("apisix.plugins.grpc-transcode.request")
local response    = require("apisix.plugins.grpc-transcode.response")


local plugin_name = "grpc-transcode"

local pb_option_def = {
    {   description = "enum as result",
        type = "string",
        enum = {"int64_as_number", "int64_as_string", "int64_as_hexstring"},
    },
    {   description = "int64 as result",
        type = "string",
        enum = {"enum_as_name", "enum_as_value"},
    },
    {   description ="default values option",
        type = "string",
        enum = {"auto_default_values", "no_default_values",
                "use_default_values", "use_default_metatable"},
    },
    {   description = "hooks option",
        type = "string",
        enum = {"enable_hooks", "disable_hooks" },
    },
}

local schema = {
    type = "object",
    properties = {
        proto_id  = schema_def.id_schema,
        service = {
            description = "the grpc service name",
            type        = "string"
        },
        method = {
            description = "the method name in the grpc service.",
            type    = "string"
        },
        deadline = {
            description = "deadline for grpc, millisecond",
            type        = "number",
            default     = 0
        },
        pb_option = {
            type = "array",
            items = { type="string", anyOf = pb_option_def },
            minItems = 1,
        },
    },
    additionalProperties = true,
    required = { "proto_id", "service", "method" },
}

local status_rel = {
    ["3"] = 400,
    ["4"] = 504,
    ["5"] = 404,
    ["7"] = 403,
    ["11"] = 416,
    ["12"] = 501,
    ["13"] = 500,
    ["14"] = 503,
}

local _M = {
    version = 0.1,
    priority = 506,
    name = plugin_name,
    schema = schema,
}


function _M.init()
    proto.init()
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("conf: ", core.json.delay_encode(conf))

    local proto_id = conf.proto_id
    if not proto_id then
        core.log.error("proto id miss: ", proto_id)
        return
    end

    local proto_obj, err = proto.fetch(proto_id)
    if err then
        core.log.error("proto load error: ", err)
        return
    end

    local ok, err = request(proto_obj, conf.service,
                            conf.method, conf.pb_option, conf.deadline)
    if not ok then
        core.log.error("transform request error: ", err)
        return
    end

    ctx.proto_obj = proto_obj
end


function _M.header_filter(conf, ctx)
    if ngx.status >= 300 then
        return
    end

    ngx.header["Content-Type"] = "application/json"
    ngx.header["Trailer"] = {"grpc-status", "grpc-message"}

    local headers = ngx.resp.get_headers()
    if headers["grpc-status"] ~= nil and headers["grpc-status"] ~= "0" then
        local http_status = status_rel[headers["grpc-status"]]
        if http_status ~= nil then
            ngx.status = http_status
        else
            ngx.status = 599
        end
        return
    end

end


function _M.body_filter(conf, ctx)
    if ngx.status >= 300 then
        return
    end

    local proto_obj = ctx.proto_obj
    if not proto_obj then
        return
    end

    local err = response(proto_obj, conf.service, conf.method, conf.pb_option)
    if err then
        core.log.error("transform response error: ", err)
        return
    end
end


return _M
