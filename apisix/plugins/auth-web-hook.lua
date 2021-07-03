local http = require("resty.http")
local core = require("apisix.core")
local http_regex = "^http://"
local https_regex = "^https://"
local string = string
local ngx = ngx
local plugin_name = "auth-web-hook"
local util = require("apisix.plugins.limit-count.util")
local schema = {
    type = "object",
    properties = {
        auth_uri = {type = "string"},
        keep_alive = {type = "boolean" , default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5},
        timeout = {type = "integer", minimum = 1000, default = 2000},
        is_cache = {type = "boolean", default = true},
        headers = {type = "string"},
        url_params = {type = "string"},
        include_body = {type = "boolean", default = false}
    },
    required = {"auth_uri", "timeout", "headers"}
}

local lrucache = core.lrucache.new({
    ttl = 60, count = 512
})

local _M = {
    version = 0.1,
    schema = schema,
    priority = 41,
    name = plugin_name
}

function _M.check_schema(conf)
    core.log.info("input conf: ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    ok = string.match(conf.auth_uri, http_regex)
    if not ok then
        ok = string.match(conf.auth_uri, https_regex)
        if not ok then
            return false, "auth uri is not correct"
        end
    end

    return true
end

local function get_values(keys,data)
    local obj = {}
    if (not keys) or (not data) then
        return obj
    end

    for _, value in pairs(keys) do
        local data_value = data[value]
        if data_value then
            obj[value] = data_value
        end
    end

    return obj
end

local function combine_url(url, params)
   local start,_ = string.find(url,"?")
   if not start then
       url = url .. "?"
   end

   local url_params = ""
   for key, value in pairs(params) do
    url_params = url_params .. key .. "=" .. value .. "&"
   end

   return url .. url_params
end

local auth = function (conf, ctx)
    local  header_keys, url_param_keys
    if conf.headers then
       header_keys = util.split(conf.headers, ",")
    end

    if conf.url_params then
        url_param_keys = util.split(conf.url_params, ",")
    end

    local req_headers = get_values(header_keys, ctx.var)
    local req_params = get_values(url_param_keys, ngx.req.get_uri_args())
    req_headers["Content-Type"] = "application/json"
    req_headers["Authorization"] = ctx.authorization
    conf.auth_uri = combine_url(conf.auth_uri, req_params)
    local httpc = http.new()
    local params = {
        method = "POST",
        headers = req_headers
    }

    if conf.include_body then
       local body = ngx.req.get_body_data()
       if body then
            params.body = body
       end
    end

    httpc:set_timeout(conf.timeout)
    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    params.keepalive = conf.keepalive
    local res, err = httpc:request_uri(conf.auth_uri, params)

    local err_msg
    if  not res then
        err_msg = "auth web hook error, request:" .. core.json.encode(params) .. ", error:" .. err
        .. ", request url:" .. conf.auth_uri
        return nil ,err_msg
    end

    if res.status ~= 200 then
        err_msg = "auth web hook response error code, response code:" ..
        res.status .. "request:" .. core.json.encode(params) .. ", request uri" ..
        conf.auth_uri
        return nil, err_msg
    end

    local response_str
    response_str = res.body
    if not response_str then
        err_msg = "get reponse from auth serve fail, request url:" .. conf.auth_uri
        return nil, err_msg
    end

    local resp_body
    resp_body, err =  core.json.decode(response_str)
    core.log.info("auth hook response data:", response_str)
    if not resp_body then
        return nil, "decode resp body error:" .. err ..
        "response:" .. response_str .. ", request url:" .. conf.auth_uri
    end

    return resp_body, nil
end

function _M.rewrite(conf, ctx)
    local token = core.request.header(ctx, "Authorization")
    if not token then
        return 401, {message = "missing auth web hook token key"}
    end

    ctx.authorization = token
    local auth_info, err
    if conf.is_cache then
       auth_info, err = lrucache(plugin_name .. "#" .. token, conf.version, auth, conf, ctx)
    else
        auth_info, err = auth(conf, ctx)
    end

    if not auth_info then
        core.log.error(err)
        return 500, {message = "auth  web hook fail, please confirm"}
    end

    if not auth_info.success then
        if auth_info.status then
            return auth_info.status, {message = auth_info.message}
        end

        return 401, {message = auth_info.message}
    end

    core.log.info("current auth info:" .. core.json.encode(auth_info))
    ctx.auth_info = auth_info.body
end

return _M
