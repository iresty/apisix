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

local base64_encode = require("base64").encode
local dkjson = require("dkjson")
local util = require("apisix.cli.util")
local file = require("apisix.cli.file")
local http = require("socket.http")
local ltn12 = require("ltn12")

local type = type
local ipairs = ipairs
local print = print
local tonumber = tonumber
local str_format = string.format
local table_concat = table.concat

local _M = {}

-- Timeout for all I/O operations
http.TIMEOUT = 3

local function parse_semantic_version(ver)
    local errmsg = "invalid semantic version: " .. ver

    local parts = util.split(ver, "-")
    if #parts > 2 then
        return nil, errmsg
    end

    if #parts == 2 then
        ver = parts[1]
    end

    local fields = util.split(ver, ".")
    if #fields ~= 3 then
        return nil, errmsg
    end

    local major = tonumber(fields[1])
    local minor = tonumber(fields[2])
    local patch = tonumber(fields[3])

    if not (major and minor and patch) then
        return nil, errmsg
    end

    return {
        major = major,
        minor = minor,
        patch = patch,
    }
end


local function compare_semantic_version(v1, v2)
    local ver1, err = parse_semantic_version(v1)
    if not ver1 then
        return nil, err
    end

    local ver2, err = parse_semantic_version(v2)
    if not ver2 then
        return nil, err
    end

    if ver1.major ~= ver2.major then
        return ver1.major < ver2.major
    end

    if ver1.minor ~= ver2.minor then
        return ver1.minor < ver2.minor
    end

    return ver1.patch < ver2.patch
end


function _M.init(env)
    -- read_yaml_conf
    local yaml_conf, err = file.read_yaml_conf(env.apisix_home)
    if not yaml_conf then
        util.die("failed to read local yaml config of apisix: ", err)
    end

    if not yaml_conf.apisix then
        util.die("failed to read `apisix` field from yaml file when init etcd")
    end

    if yaml_conf.apisix.config_center ~= "etcd" then
        return true
    end

    if not yaml_conf.etcd then
        util.die("failed to read `etcd` field from yaml file when init etcd")
    end

    local etcd_conf = yaml_conf.etcd

    -- convert old single etcd config to multiple etcd config
    if type(yaml_conf.etcd.host) == "string" then
        yaml_conf.etcd.host = {yaml_conf.etcd.host}
    end

    local host_count = #(yaml_conf.etcd.host)
    local scheme
    for i = 1, host_count do
        local host = yaml_conf.etcd.host[i]
        local fields = util.split(host, "://")
        if not fields then
            util.die("malformed etcd endpoint: ", host, "\n")
        end

        if not scheme then
            scheme = fields[1]
        elseif scheme ~= fields[1] then
            print([[WARNING: mixed protocols among etcd endpoints]])
        end
    end

    -- check the etcd cluster version
    for index, host in ipairs(yaml_conf.etcd.host) do
        local version_url = host .. "/version"
        local errmsg

        local res, err = http.request(version_url)
        -- In case of failure, request returns nil followed by an error message.
        -- Else the first return value is the response body
        -- and followed by the response status code.
        if not res then
            errmsg = str_format("request etcd endpoint \'%s\' error, %s\n", version_url, err)
            util.die(errmsg)
        end

        local body, _, err = dkjson.decode(res)
        if err or (body and not body["etcdcluster"]) then
            errmsg = str_format("got malformed version message: \"%s\" from etcd \"%s\"\n", res,
                                version_url)
            util.die(errmsg)
        end

        local cluster_version = body["etcdcluster"]
        if compare_semantic_version(cluster_version, env.min_etcd_version) then
            util.die("etcd cluster version ", cluster_version,
                     " is less than the required version ",
                     env.min_etcd_version,
                     ", please upgrade your etcd cluster\n")
        end
    end

    local etcd_ok = false
    for index, host in ipairs(yaml_conf.etcd.host) do
        local is_success = true

        local errmsg
        local auth_token
        local user = yaml_conf.etcd.user
        local password = yaml_conf.etcd.password
        if user and password then
            local auth_url = host .. "/v3/auth/authenticate"
            local json_auth = {
                name =  etcd_conf.user,
                password = etcd_conf.password
            }

            local post_json_auth = dkjson.encode(json_auth)
            local response_body = {}
            local res, err = http.request{url = auth_url, method = "POST",
                                        source = ltn12.source.string(post_json_auth),
                                        sink = ltn12.sink.table(response_body),
                                        headers = {["Content-Length"] = #post_json_auth}}
            -- In case of failure, request returns nil followed by an error message.
            -- Else the first return value is just the number 1
            -- and followed by the response status code.
            if not res then
                errmsg = str_format("request etcd endpoint \"%s\" error, %s\n", auth_url, err)
                util.die(errmsg)
            end

            local res_auth = table_concat(response_body)
            local body_auth, _, err_auth = dkjson.decode(res_auth)
            if err_auth or (body_auth and not body_auth["token"]) then
                errmsg = str_format("got malformed auth message: \"%s\" from etcd \"%s\"\n",
                                    res_auth, auth_url)
                util.die(errmsg)
            end

            auth_token = body_auth.token
        end


        for _, dir_name in ipairs({"/routes", "/upstreams", "/services",
                                   "/plugins", "/consumers", "/node_status",
                                   "/ssl", "/global_rules", "/stream_routes",
                                   "/proto", "/plugin_metadata"}) do

            local key =  (etcd_conf.prefix or "") .. dir_name .. "/"

            local put_url = host .. "/v3/kv/put"
            local post_json = '{"value":"' .. base64_encode("init_dir")
                              .. '", "key":"' .. base64_encode(key) .. '"}'
            local response_body = {}
            local headers = {["Content-Length"] = #post_json}
            if auth_token then
                headers["Authorization"] = auth_token
            end

            local res, err = http.request{url = put_url, method = "POST",
                                        source = ltn12.source.string(post_json),
                                        sink = ltn12.sink.table(response_body),
                                        headers = headers}
            if not res then
                errmsg = str_format("request etcd endpoint \"%s\" error, %s\n", put_url, err)
                util.die(errmsg)
            end

            local res_put = table_concat(response_body)
            if res_put:find("404 page not found", 1, true) then
                errmsg = str_format("gRPC gateway is not enabled in etcd cluster \"%s\",",
                                    "which is required by Apache APISIX\n")
                util.die(errmsg)
            end

            if res_put:find("error", 1, true) then
                is_success = false
                if (index == host_count) then
                    errmsg = str_format("got malformed key-put message: \"%s\" from etcd \"%s\"\n",
                                        res_put, put_url)
                    util.die(errmsg)
                end

                break
            end

            if yaml_conf.etcd.debug then
                response_body_str = str_format("etcd response_body request body \"%s\" from etcd response_body: \"%s\" \n",
                                    res_put, res_put)
                print(response_body_str)
            end
        end

        if is_success then
            etcd_ok = true
            break
        end
    end

    if not etcd_ok then
        util.die("none of the configured etcd works well")
    end
end


return _M
