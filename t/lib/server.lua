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
local json_decode = require("toolkit.json").decode
local json_encode = require("toolkit.json").encode

local _M = {}


local function inject_headers()
    local hdrs = ngx.req.get_headers()
    for k, v in pairs(hdrs) do
        if k:sub(1, 5) == "resp-" then
            ngx.header[k:sub(6)] = v
        end
    end
end


function _M.hello()
    ngx.req.read_body()
    local s = "hello world"
    ngx.header['Content-Length'] = #s + 1
    ngx.say(s)
end


function _M.hello_chunked()
    ngx.print("hell")
    ngx.flush(true)
    ngx.print("o w")
    ngx.flush(true)
    ngx.say("orld")
end


function _M.hello1()
    ngx.say("hello1 world")
end


function _M.hello_()
    ngx.say("hello world")
end


-- Fake endpoint, needed for testing authz-keycloak plugin.
function _M.course_foo()
    ngx.say("course foo")
end


function _M.server_port()
    ngx.print(ngx.var.server_port)
end
_M.server_port_route2 = _M.server_port
_M.server_port_hello = _M.server_port
_M.server_port_aa = _M.server_port


function _M.limit_conn()
    ngx.sleep(0.3)
    ngx.say("hello world")
end


function _M.plugin_proxy_rewrite()
    ngx.say("uri: ", ngx.var.uri)
    ngx.say("host: ", ngx.var.host)
    ngx.say("scheme: ", ngx.var.scheme)
    ngx.say("method: ", ngx.var.request_method)
end


function _M.plugin_proxy_rewrite_args()
    ngx.say("uri: ", ngx.var.uri)
    local args = ngx.req.get_uri_args()

    local keys = {}
    for k, _ in pairs(args) do
        table.insert(keys, k)
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        if type(args[key]) == "table" then
            ngx.say(key, ": ", table.concat(args[key], ','))
        else
            ngx.say(key, ": ", args[key])
        end
    end
end


function _M.specific_status()
    local status = ngx.var.http_x_test_upstream_status
    if status ~= nil then
        ngx.status = status
        ngx.say("upstream status: ", status)
    end
end


function _M.status()
    ngx.say("ok")
end


function _M.sleep1()
    ngx.sleep(1)
    ngx.say("ok")
end


function _M.ewma()
    if ngx.var.server_port == "1981"
       or ngx.var.server_port == "1982" then
        ngx.sleep(0.2)
    else
        ngx.sleep(0.1)
    end
    ngx.print(ngx.var.server_port)
end


local builtin_hdr_ignore_list = {
    ["x-forwarded-for"] = true,
    ["x-forwarded-proto"] = true,
    ["x-forwarded-host"] = true,
    ["x-forwarded-port"] = true,
}

function _M.uri()
    -- ngx.sleep(1)
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()

    local keys = {}
    for k in pairs(headers) do
        if not builtin_hdr_ignore_list[k] then
            table.insert(keys, k)
        end
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        ngx.say(key, ": ", headers[key])
    end
end
_M.uri_plugin_proxy_rewrite = _M.uri
_M.uri_plugin_proxy_rewrite_args = _M.uri


function _M.old_uri()
    -- ngx.sleep(1)
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()

    local keys = {}
    for k in pairs(headers) do
        table.insert(keys, k)
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        ngx.say(key, ": ", headers[key])
    end
end


function _M.opentracing()
    ngx.say("opentracing")
end


function _M.with_header()
    --split into multiple chunk
    ngx.say("hello")
    ngx.say("world")
    ngx.say("!")
end


function _M.mock_zipkin()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    ngx.log(ngx.NOTICE, data)

    local spans = json_decode(data)
    local ver = ngx.req.get_uri_args()['span_version']
    if ver == "1" then
        if #spans ~= 5 then
            ngx.log(ngx.ERR, "wrong number of spans: ", #spans)
            ngx.exit(400)
        end
    else
        if #spans ~= 3 then
            -- request/proxy/response
            ngx.log(ngx.ERR, "wrong number of spans: ", #spans)
            ngx.exit(400)
        end
    end

    for _, span in pairs(spans) do
        local prefix = string.sub(span.name, 1, 6)
        if prefix ~= 'apisix' then
            ngx.log(ngx.ERR, "wrong prefix of name", prefix)
            ngx.exit(400)
        end
        if not span.traceId then
            ngx.log(ngx.ERR, "missing trace id")
            ngx.exit(400)
        end

        if not span.localEndpoint then
            ngx.log(ngx.ERR, "missing local endpoint")
            ngx.exit(400)
        end

        if span.localEndpoint.serviceName ~= 'APISIX'
          and span.localEndpoint.serviceName ~= 'apisix' then
            ngx.log(ngx.ERR, "wrong serviceName: ", span.localEndpoint.serviceName)
            ngx.exit(400)
        end

        if span.localEndpoint.port ~= 1984 then
            ngx.log(ngx.ERR, "wrong port: ", span.localEndpoint.port)
            ngx.exit(400)
        end

        local server_addr = ngx.req.get_uri_args()['server_addr']
        if server_addr then
            if span.localEndpoint.ipv4 ~= server_addr then
                ngx.log(ngx.ERR, "server_addr mismatched")
                ngx.exit(400)
            end
        end

    end
end


function _M.wolf_rbac_login_rest()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local args = json_decode(data)
    if not args.username then
        ngx.say(json_encode({ok=false, reason="ERR_USERNAME_MISSING"}))
        ngx.exit(0)
    end
    if not args.password then
        ngx.say(json_encode({ok=false, reason="ERR_PASSWORD_MISSING"}))
        ngx.exit(0)
    end
    if args.username ~= "admin" then
        ngx.say(json_encode({ok=false, reason="ERR_USER_NOT_FOUND"}))
        ngx.exit(0)
    end
    if args.password ~= "123456" then
        ngx.say(json_encode({ok=false, reason="ERR_PASSWORD_ERROR"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true, data={token="wolf-rbac-token",
        userInfo={nickname="administrator",username="admin", id="100"}}}))
end


function _M.wolf_rbac_access_check()
    local headers = ngx.req.get_headers()
    local token = headers['x-rbac-token']
    if token ~= 'wolf-rbac-token' then
        ngx.say(json_encode({ok=false, reason="ERR_TOKEN_INVALID"}))
        ngx.exit(0)
    end

    local args = ngx.req.get_uri_args()
    local resName = args.resName
    if resName == '/hello' or resName == '/wolf/rbac/custom/headers' then
        ngx.say(json_encode({ok=true,
                            data={ userInfo={nickname="administrator",
                                username="admin", id="100"} }}))
    else
        ngx.status = 401
        ngx.say(json_encode({ok=false, reason="no permission to access"}))
    end
end


function _M.wolf_rbac_user_info()
    local headers = ngx.req.get_headers()
    local token = headers['x-rbac-token']
    if token ~= 'wolf-rbac-token' then
        ngx.say(json_encode({ok=false, reason="ERR_TOKEN_INVALID"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true,
                        data={ userInfo={nickname="administrator", username="admin", id="100"} }}))
end


function _M.wolf_rbac_change_pwd()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local args = json_decode(data)
    if args.oldPassword ~= "123456" then
        ngx.say(json_encode({ok=false, reason="ERR_OLD_PASSWORD_INCORRECT"}))
        ngx.exit(0)
    end

    ngx.say(json_encode({ok=true, data={ }}))
end


function _M.wolf_rbac_custom_headers()
    local headers = ngx.req.get_headers()
    ngx.say('id:' .. headers['X-UserId'] .. ',username:' .. headers['X-Username']
            .. ',nickname:' .. headers['X-Nickname'])
end


function _M.websocket_handshake()
    local websocket = require "resty.websocket.server"
    local wb, err = websocket:new()
    if not wb then
        ngx.log(ngx.ERR, "failed to new websocket: ", err)
        return ngx.exit(400)
    end

    local bytes, err = wb:send_text("hello")
    if not bytes then
        ngx.log(ngx.ERR, "failed to send text: ", err)
        return ngx.exit(444)
    end
end
_M.websocket_handshake_route = _M.websocket_handshake


function _M.api_breaker()
    ngx.exit(tonumber(ngx.var.arg_code))
end


function _M.mysleep()
    ngx.sleep(tonumber(ngx.var.arg_seconds))
    ngx.say(ngx.var.arg_seconds)
end


local function print_uri()
    ngx.say(ngx.var.uri)
end
for i = 1, 100 do
    _M["print_uri_" .. i] = print_uri
end


function _M.go()
    local action = string.sub(ngx.var.uri, 2)
    action = string.gsub(action, "[/\\.]", "_")
    if not action or not _M[action] then
        return ngx.exit(404)
    end

    inject_headers()
    return _M[action]()
end


function _M.headers()
    local args = ngx.req.get_uri_args()
    for name, val in pairs(args) do
        ngx.header[name] = nil
        ngx.header[name] = val
    end

    ngx.say("/headers")
end


function _M.echo()
    ngx.req.read_body()
    local hdrs = ngx.req.get_headers()
    for k, v in pairs(hdrs) do
        ngx.header[k] = v
    end
    ngx.say(ngx.req.get_body_data() or "")
end


function _M.log()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local ct = ngx.var.content_type
    if ct ~= "text/plain" then
        body = json_decode(body)
        body = json_encode(body)
    end
    ngx.log(ngx.WARN, "request log: ", body or "nil")
end


function _M.server_error()
    error("500 Internal Server Error")
end


return _M
