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
local core = require("apisix.core")
local ngx_re = require("ngx.re")
local tab_concat = table.concat
local string = string
local io_open = io.open
local io_close = io.close
local ngx = ngx
local os = os
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber

local plugin_name = "proxy-cache"

local schema = {
    type = "object",
    properties = {
        cache_zone = {
            type = "string",
            minLength = 1,
            maxLength = 100,
            default = "disk_cache_one",
        },
        cache_key = {
            type = "array",
            minItems = 1,
            items = {
                description = "a key for caching",
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]],
            },
            default = {"$host", "$request_uri"}
        },
        cache_http_status = {
            type = "array",
            minItems = 1,
            items = {
                description = "http response status",
                type = "integer",
                minimum = 200,
                maximum = 599,
            },
            uniqueItems = true,
            default = {200, 301, 404},
        },
        cache_method = {
            type = "array",
            minItems = 1,
            items = {
                description = "http method",
                type = "string",
                enum = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                    "OPTIONS", "CONNECT", "TRACE"},
            },
            uniqueItems = true,
            default = {"GET", "HEAD"},
        },
        hide_cache_headers = {
            type = "boolean",
            default = false,
        },
        cache_bypass = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
        },
        no_cache = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
        },
    },
}

local _M = {
    version = 0.1,
    priority = 1009,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for _, key in ipairs(conf.cache_key) do
        if key == "$request_method" then
            return false, "cache_key variable " .. key .. " unsupported"
        end
    end

    local found = false
    local local_conf = core.config.local_conf()
    if local_conf.apisix.proxy_cache then
        for _, cache in ipairs(local_conf.apisix.proxy_cache.zones) do
            if cache.name == conf.cache_zone then
                found = true
            end
        end

        if found == false then
            return false, "cache_zone " .. conf.cache_zone .. " not found"
        end
    end
    return true
end


local tmp = {}
local function generate_complex_value(data, ctx)
    core.table.clear(tmp)

    core.log.info("proxy-cache complex value: ", core.json.delay_encode(data))
    for i, value in ipairs(data) do
        core.log.info("proxy-cache complex value index-", i, ": ", value)

        if string.byte(value, 1, 1) == string.byte('$') then
            tmp[i] = ctx.var[string.sub(value, 2)]
        else
            tmp[i] = value
        end
    end

    return tab_concat(tmp, "")
end


-- check whether the request method and response status
-- match the user defined.
local function match_method_and_status(conf, ctx)
    local match_method, match_status = false, false

    -- Maybe there is no need for optimization here.
    for _, method in ipairs(conf.cache_method) do
        if method == ctx.var.request_method then
            match_method = true
            break
        end
    end

    for _, status in ipairs(conf.cache_http_status) do
        if status == ngx.status then
            match_status = true
            break
        end
    end

    if match_method and match_status then
        return true
    end

    return false
end


local function file_exists(name)
    local f = io_open(name, "r")
    if f ~= nil then
        io_close(f)
        return true
    end
    return false
end


local function generate_cache_filename(cache_path, cache_levels, cache_key)
    local md5sum = ngx.md5(cache_key)
    local levels = ngx_re.split(cache_levels, ":")
    local filename = ""

    local index = string.len(md5sum)
    for k, v in pairs(levels) do
        local length = tonumber(v)
        index = index - length
        filename = filename .. md5sum:sub(index+1, index+length) .. "/"
    end
    if cache_path:sub(-1) ~= "/" then
        cache_path = cache_path .. "/"
    end
    filename = cache_path .. filename .. md5sum
    return filename
end


local function cache_purge(conf, ctx)
    local cache_zone_info = ngx_re.split(ctx.var.upstream_cache_zone_info, ",")

    local filename = generate_cache_filename(cache_zone_info[1], cache_zone_info[2],
                                             ctx.var.upstream_cache_key)
    if file_exists(filename) then
        os.remove(filename)
        return nil
    end

    return "Not found"
end


function _M.rewrite(conf, ctx)
    core.log.info("proxy-cache plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    ctx.var.upstream_cache_zone = conf.cache_zone

    local value = generate_complex_value(conf.cache_key, ctx)
    ctx.var.upstream_cache_key = value
    core.log.info("proxy-cache cache key value:", value)

    if ctx.var.request_method == "PURGE" then
        local err = cache_purge(conf, ctx)
        if err ~= nil then
            return 404
        end

        return 200
    end

    if conf.cache_bypass ~= nil then
        local value = generate_complex_value(conf.cache_bypass, ctx)
        ctx.var.upstream_cache_bypass = value
        core.log.info("proxy-cache cache bypass value:", value)
    end
end


function _M.header_filter(conf, ctx)
    core.log.info("proxy-cache plugin header filter phase, conf: ", core.json.delay_encode(conf))

    local no_cache = "1"

    if match_method_and_status(conf, ctx) then
        no_cache = "0"
    end

    if conf.no_cache ~= nil then
        local value = generate_complex_value(conf.no_cache, ctx)
        core.log.info("proxy-cache no-cache value:", value)

        if value ~= nil and value ~= "" and value ~= "0" then
            no_cache = "1"
        end
    end

    if conf.hide_cache_headers == true then
        ctx.var.upstream_hdr_cache_control = ""
        ctx.var.upstream_hdr_expires = ""
    else
        ctx.var.upstream_hdr_cache_control = ctx.var.upstream_http_cache_control
        ctx.var.upstream_hdr_expires = ctx.var.upstream_http_expires
    end

    ctx.var.upstream_no_cache = no_cache
    core.log.info("proxy-cache no cache:", no_cache)
end


return _M
