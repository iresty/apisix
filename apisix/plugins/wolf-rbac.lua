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

local require  = require
local core     = require("apisix.core")
local consumer = require("apisix.consumer")
local json     = require("apisix.core.json")
local sleep    = core.sleep
local ngx_re = require("ngx.re")
local http     = require("resty.http")
local ipairs   = ipairs
local ngx      = ngx
local tostring = tostring
local rawget   = rawget
local rawset   = rawset
local setmetatable = setmetatable
local type     = type
local string   = string
local req_read_body = ngx.req.read_body
local req_get_post_args = ngx.req.get_post_args
local req_get_body_data = ngx.req.get_body_data

local plugin_name = "wolf-rbac"


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        appid = {
            type = "string",
            default = "unset"
        },
        server = {
            type = "string",
            default = "http://127.0.0.1:10080"
        },
        header_prefix = {
            type = "string",
            default = "X-"
        },
    }
}

local _M = {
    version = 0.1,
    priority = 2555,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}


local create_consume_cache
do
    local consumer_names = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_names)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_names[consumer.auth_conf.appid] = consumer
        end

        return consumer_names
    end

end -- do

local token_version = 'V1'
local function create_rbac_token(appid, wolf_token)
    return token_version .. "#" .. appid .. "#" .. wolf_token
end

local function fail_response(message, init_values)
    local response = init_values or {}
    response.message = message
    return response
end

local function success_response(message, init_values)
    local response = init_values or {}
    response.message = message
    return response
end

local function parse_rbac_token(rbac_token)
    local res, err = ngx_re.split(rbac_token, "#", nil, nil, 3)
    if not res then
        return nil, err
    end

    if #res ~= 3 or res[1] ~= token_version then
        return nil, 'invalid rbac token: version'
    end
    local appid = res[2]
    local wolf_token = res[3]

    return {appid = appid, wolf_token = wolf_token}
end

local function new_headers()
    local t = {}
    local lt = {}
    local _mt = {
        __index = function(t, k)
            return rawget(lt, string.lower(k))
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(lt, string.lower(k), v)
        end,
     }
    return setmetatable(t, _mt)
end

-- timeout in ms
local function http_req(method, uri, body, myheaders, timeout)
    if myheaders == nil then myheaders = new_headers() end

    local httpc = http.new()
    if timeout then
        httpc:set_timeout(timeout)
    end

    local params = {method = method, headers = myheaders, body = body,
                    ssl_verify = false}
    local res, err = httpc:request_uri(uri, params)
    if err then
        core.log.error("FAIL REQUEST [ ",core.json.delay_encode(
            {method = method, uri = uri, body = body, headers = myheaders}),
            " ] failed! res is nil, err:", err)
        return nil, err
    end

    return res
end

local function http_get(uri, myheaders, timeout)
    return http_req("GET", uri, nil, myheaders, timeout)
end


function _M.check_schema(conf)
    core.log.info("input conf: ", core.json.delay_encode(conf))

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function fetch_rbac_token(ctx)
    if ctx.var.arg_rbac_token then
        return ngx.unescape_uri(ctx.var.arg_rbac_token)
    end

    if ctx.var.http_authorization then
        return ctx.var.http_authorization
    end

    if ctx.var.http_x_rbac_token then
        return ctx.var.http_x_rbac_token
    end

    return ctx.var['cookie_x-rbac-token']
end


local function check_url_permission(server, appid, action, resName, client_ip, wolf_token)
    local retry_max = 3
    local errmsg
    local userInfo
    local res
    local err
    local access_check_url = server .. "/wolf/rbac/access_check"
    local headers = new_headers()
    headers["x-rbac-token"] = wolf_token
    headers["Content-Type"] = "application/json; charset=utf-8"
    local args = { appID = appid, resName = resName, action = action, clientIP = client_ip}
    local url = access_check_url .. "?" .. ngx.encode_args(args)
    local timeout = 1000 * 10

    for i = 1, retry_max do
        -- TODO: read apisix info.
        res, err = http_get(url, headers, timeout)
        if err then
            break
        else
            core.log.info("check permission request:", url, ", status:", res.status,
                            ",body:", core.json.delay_encode(res.body))
            if res.status < 500 then
                break
            else
                core.log.info("request [curl -v ", url, "] failed! status:", res.status)
                if i < retry_max then
                    sleep(0.1)
                end
            end
        end
    end

    if err then
        core.log.error("fail request: ", url, ", err:", err)
        return {
            status = 500,
            err = "request to wolf-server failed, err:" .. err
        }
    end

    if res.status ~= 200 and res.status ~= 401 then
        return {
            status = 500,
            err = 'request to wolf-server failed, status:' .. res.status
        }
    end

    local body, err = json.decode(res.body)
    if err then
        errmsg = 'check permission failed! parse response json failed!'
        core.log.error( "json.decode(", res.body, ") failed! err:", err)
        return {status = res.status, err = errmsg}
    else
        if body.data then
            userInfo = body.data.userInfo
        end
        errmsg = body.reason
        return {status = res.status, err = errmsg, userInfo = userInfo}
    end
end


function _M.rewrite(conf, ctx)
    local url = ctx.var.uri
    local action = ctx.var.request_method
    local client_ip = ctx.var.http_x_real_ip or core.request.get_ip(ctx)
    local perm_item = {action = action, url = url, clientIP = client_ip}
    core.log.info("hit wolf-rbac rewrite")

    local rbac_token = fetch_rbac_token(ctx)
    if rbac_token == nil then
        core.log.info("no permission to access ",
                      core.json.delay_encode(perm_item), ", need login!")
        return 401, fail_response("Missing rbac token in request")
    end

    local tokenInfo, err = parse_rbac_token(rbac_token)
    core.log.info("token info: ", core.json.delay_encode(tokenInfo),
                  ", err: ", err)
    if err then
        return 401, fail_response('invalid rbac token: parse failed')
    end

    local appid = tokenInfo.appid
    local wolf_token = tokenInfo.wolf_token
    perm_item.appid = appid
    perm_item.wolf_token = wolf_token

    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return 401, fail_response("Missing related consumer")
    end

    local consumers = lrucache("consumers_key", consumer_conf.conf_version,
        create_consume_cache, consumer_conf)

    core.log.info("------ consumers: ", core.json.delay_encode(consumers))
    local consumer = consumers[appid]
    if not consumer then
        core.log.error("consumer [", appid, "] not found")
        return 401, fail_response("Invalid appid in rbac token")
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))
    local server = consumer.auth_conf.server

    local res = check_url_permission(server, appid, action, url,
                    client_ip, wolf_token)
    core.log.info(" check_url_permission(", core.json.delay_encode(perm_item),
                  ") res: ",core.json.delay_encode(res))

    local username = nil
    local nickname = nil
    if type(res.userInfo) == 'table' then
        local userInfo = res.userInfo
        ctx.userInfo = userInfo
        local userId = userInfo.id
        username = userInfo.username
        nickname = userInfo.nickname or userInfo.username
        local prefix = consumer.auth_conf.header_prefix or ''
        core.response.set_header(prefix .. "UserId", userId)
        core.response.set_header(prefix .. "Username", username)
        core.response.set_header(prefix .. "Nickname", ngx.escape_uri(nickname))
        core.request.set_header(ctx, prefix .. "UserId", userId, ctx)
        core.request.set_header(ctx, prefix .. "Username", username)
        core.request.set_header(ctx, prefix .. "Nickname", ngx.escape_uri(nickname))
    end

    if res.status ~= 200 then
        -- no permission.
        core.log.error(" check_url_permission(",
            core.json.delay_encode(perm_item),
            ") failed, res: ",core.json.delay_encode(res))
        return 401, fail_response(res.err,
            { username = username, nickname = nickname }
        )
    end
    core.log.info("wolf-rbac check permission passed")
end

local function get_args()
    local ctx = ngx.ctx.api_ctx
    local args, err
    req_read_body()
    if string.find(ctx.var.http_content_type or "","application/json",
                   1, true) then
        local req_body = req_get_body_data()
        args, err = json.decode(req_body)
        if err then
            core.log.error("json.decode(", req_body, ") failed! ", err)
        end
    else
        args = req_get_post_args()
    end

    return args
end

local function get_consumer(appid)
    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        core.response.exit(500)
    end

    local consumers = lrucache("consumers_key", consumer_conf.conf_version,
        create_consume_cache, consumer_conf)

    core.log.info("------ consumers: ", core.json.delay_encode(consumers))
    local consumer = consumers[appid]
    if not consumer then
        core.log.info("request appid [", appid, "] not found")
        core.response.exit(400,
                fail_response("appid [" .. tostring(appid) .. "] not found")
            )
    end
    return consumer
end

local function request_to_wolf_server(method, uri, headers, body)
    headers["Content-Type"] = "application/json; charset=utf-8"
    local timeout = 1000 * 5
    local request_debug = core.json.delay_encode(
        {
            method = method, uri = uri, body = body,
            headers = headers,timeout = timeout
        }
    )

    core.log.info("request [", request_debug, "] ....")
    local res, err = http_req(method, uri, core.json.encode(body), headers, timeout)
    if err or not res then
        core.log.error("request [", request_debug, "] failed! err: ", err)
        return core.response.exit(500,
            fail_response("request to wolf-server failed! " .. tostring(err))
        )
    end
    core.log.info("request [", request_debug, "] status: ", res.status,
                  ", body: ", res.body)

    if res.status ~= 200 then
        core.log.error("request [", request_debug, "] failed! status: ",
                        res.status)
        return core.response.exit(500,
        fail_response("request to wolf-server failed! status:"
                          .. tostring(res.status))
        )
    end
    local body, err = json.decode(res.body)
    if err or not body then
        core.log.error("request [", request_debug, "] failed! err:", err)
        return core.response.exit(500, fail_response("request to wolf-server failed!"))
    end
    if not body.ok then
        core.log.error("request [", request_debug, "] failed! response body:",
                       core.json.delay_encode(body))
        return core.response.exit(200, fail_response(body.reason))
    end

    core.log.info("request [", request_debug, "] success! response body:",
                  core.json.delay_encode(body))
    return body
end

local function wolf_rbac_login()
    local args = get_args()
    if not args then
        return core.response.exit(400, fail_response("invalid request"))
    end
    if not args.appid then
        return core.response.exit(400, fail_response("appid is missing"))
    end

    local appid = args.appid
    local consumer = get_consumer(appid)
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local uri = consumer.auth_conf.server .. '/wolf/rbac/login.rest'
    local headers = new_headers()
    local body = request_to_wolf_server('POST', uri, headers, args)

    local userInfo = body.data.userInfo
    local wolf_token = body.data.token

    local rbac_token = create_rbac_token(appid, wolf_token)
    core.response.exit(200, success_response(nil, {rbac_token = rbac_token, user_info = userInfo}))
end

local function get_wolf_token(ctx)
    core.log.info("hit wolf-rbac change_password api")
    local rbac_token = fetch_rbac_token(ctx)
    if rbac_token == nil then
        local url = ctx.var.uri
        local action = ctx.var.request_method
        local client_ip = core.request.get_ip(ctx)
        local perm_item = {action = action, url = url, clientIP = client_ip}
        core.log.info("no permission to access ",
                      core.json.delay_encode(perm_item), ", need login!")
        return core.response.exit(401, fail_response("Missing rbac token in request"))
    end

    local tokenInfo, err = parse_rbac_token(rbac_token)
    core.log.info("token info: ", core.json.delay_encode(tokenInfo),
                  ", err: ", err)
    if err then
        return core.response.exit(401, fail_response('invalid rbac token: parse failed'))
    end
    return tokenInfo
end

local function wolf_rbac_change_pwd()
    local args = get_args()

    local ctx = ngx.ctx.api_ctx
    local tokenInfo = get_wolf_token(ctx)
    local appid = tokenInfo.appid
    local wolf_token = tokenInfo.wolf_token
    local consumer = get_consumer(appid)
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local uri = consumer.auth_conf.server .. '/wolf/rbac/change_pwd'
    local headers = new_headers()
    headers['x-rbac-token'] = wolf_token
    request_to_wolf_server('POST', uri, headers, args)
    core.response.exit(200, success_response('success to change password', { }))
end

local function wolf_rbac_user_info()
    local ctx = ngx.ctx.api_ctx
    local tokenInfo = get_wolf_token(ctx)
    local appid = tokenInfo.appid
    local wolf_token = tokenInfo.wolf_token
    local consumer = get_consumer(appid)
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    local uri = consumer.auth_conf.server .. '/wolf/rbac/user_info'
    local headers = new_headers()
    headers['x-rbac-token'] = wolf_token
    local body = request_to_wolf_server('GET', uri, headers, {})
    local userInfo = body.data.userInfo
    core.response.exit(200, success_response(nil, {user_info = userInfo}))
end

function _M.api()
    return {
        {
            methods = {"POST"},
            uri = "/apisix/plugin/wolf-rbac/login",
            handler = wolf_rbac_login,
        },
        {
            methods = {"PUT"},
            uri = "/apisix/plugin/wolf-rbac/change_pwd",
            handler = wolf_rbac_change_pwd,
        },
        {
            methods = {"GET"},
            uri = "/apisix/plugin/wolf-rbac/user_info",
            handler = wolf_rbac_user_info,
        },
    }
end

return _M
