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
local ngx         = ngx
local plugin_name = "cors"
local str_find    = core.string.find
local re_gmatch   = ngx.re.gmatch


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        allow_origins = {
            description =
                "you can use '*' to allow all origins when no credentials," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple origin use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        allow_methods = {
            description =
                "you can use '*' to allow all methods when no credentials and '**'," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple method use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        allow_headers = {
            description =
                "you can use '*' to allow all header when no credentials," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple header use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        expose_headers = {
            description =
                "you can use '*' to expose all header when no credentials," ..
                "multiple header use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        max_age = {
            description =
                "maximum number of seconds the results can be cached." ..
                "-1 mean no cached,the max value is depend on browser," ..
                "more detail plz check MDN. default: 5.",
            type = "integer",
            default = 5
        },
        allow_credential = {
            description =
                "allow client append credential. according to CORS specification," ..
                "if you set this option to 'true', you can not use '*' for other options.",
            type = "boolean",
            default = false
        }
    }
}

local _M = {
    version = 0.1,
    priority = 4000,
    name = plugin_name,
    schema = schema,
}


local function create_multiple_origin_cache(conf)
    if not str_find(conf.allow_origins, ",") then
        return nil
    end
    local origin_cache = {}
    local iterator, err = re_gmatch(conf.allow_origins, "([^,]+)", "jiox")
    if not iterator then
        core.log.error("match origins failed: ", err)
        return nil
    end
    while true do
        local origin, err = iterator()
        if err then
            core.log.error("iterate origins failed: ", err)
            return nil
        end
        if not origin then
            break
        end
        origin_cache[origin[0]] = true
    end
    return origin_cache
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.allow_credential then
        if conf.allow_origins == "*" or conf.allow_methods == "*" or
            conf.allow_headers == "*" or conf.expose_headers == "*" then
            return false, "you can not set '*' for other option when 'allow_credential' is true"
        end
    end

    return true
end


local function set_cors_headers(conf, ctx)
    local allow_methods = conf.allow_methods
    if allow_methods == "**" then
        allow_methods = "GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE"
    end

    core.response.set_header("Access-Control-Allow-Origin", ctx.cors_allow_origins)
    if ctx.cors_allow_origins ~= "*" then
        core.response.add_header("Vary", "Origin")
    end

    core.response.set_header("Access-Control-Allow-Methods", allow_methods)
    core.response.set_header("Access-Control-Max-Age", conf.max_age)
    core.response.set_header("Access-Control-Expose-Headers", conf.expose_headers)
    if conf.allow_headers == "**" then
        core.response.set_header("Access-Control-Allow-Headers",
            core.request.header(ctx, "Access-Control-Request-Headers"))
    else
        core.response.set_header("Access-Control-Allow-Headers", conf.allow_headers)
    end
    if conf.allow_credential then
        core.response.set_header("Access-Control-Allow-Credentials", true)
    end
end


function _M.rewrite(conf, ctx)
    if ctx.var.request_method == "OPTIONS" then
        return 200
    end
end


function _M.header_filter(conf, ctx)
    local allow_origins = conf.allow_origins
    local req_origin = core.request.header(ctx, "Origin")
    if allow_origins == "**" then
        allow_origins = req_origin or '*'
    end
    local multiple_origin, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                                create_multiple_origin_cache, conf)
    if err then
        return 500, {message = "get multiple origin cache failed: " .. err}
    end

    if multiple_origin then
        if multiple_origin[req_origin] then
            allow_origins = req_origin
        else
            return
        end
    end

    ctx.cors_allow_origins = allow_origins
    set_cors_headers(conf, ctx)
end

return _M
