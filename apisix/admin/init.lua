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

local core = require("apisix.core")
local route = require("resty.radixtree")
local plugin = require("apisix.plugin")
local ngx = ngx
local get_method = ngx.req.get_method
local tonumber = tonumber
local str_lower = string.lower
local require = require
local reload_event = "/apisix/admin/plugins/reload"
local ipairs = ipairs
local events
local unpack_tab
do
    local tab = {} and table
    unpack_tab = tab.unpack -- can not use `table.unpack` directly, luacheck
                            -- will show warning message
end


local viewer_methods = {
    get = true,
}


local resources_http = {
    routes          = require("apisix.admin.routes"),
    services        = require("apisix.admin.services"),
    upstreams       = require("apisix.admin.upstreams"),
    consumers       = require("apisix.admin.consumers"),
    schema          = require("apisix.admin.schema"),
    ssl             = require("apisix.admin.ssl"),
    proto           = require("apisix.admin.proto"),
    global_rules    = require("apisix.admin.global_rules"),
    plugins         = require("apisix.admin.plugins"),
}


local resources_stream = {
    routes = require("apisix.admin.stream.routes"),
}


local _M = {version = 0.4}
local router


local function check_token(ctx)
    local local_conf = core.config.local_conf()
    if not local_conf or not local_conf.apisix
       or not local_conf.apisix.admin_key then
        return true
    end

    local req_token = ctx.var.arg_api_key or ctx.var.http_x_api_key
                      or ctx.var.cookie_x_api_key
    if not req_token then
        return false, "missing apikey"
    end

    local admin
    for i, row in ipairs(local_conf.apisix.admin_key) do
        if req_token == row.key then
            admin = row
            break
        end
    end

    if not admin then
        return false, "wrong apikey"
    end

    if admin.role == "viewer" and
       not viewer_methods[str_lower(get_method())] then
        return false, "invalid method for role viewer"
    end

    return true
end


local function run_http(uri_segs)
    core.log.info("uri: ", core.json.delay_encode(uri_segs))

    -- /apisix/admin/:workspace/http/routes/1
    -- /apisix/admin/:workspace/http/schema/limit-count
    local seg_res, seg_id = uri_segs[6], uri_segs[7]
    local seg_sub_path = core.table.concat(uri_segs, "/", 8)

    local resource = resources_http[seg_res]
    if not resource then
        core.response.exit(404)
    end

    local method = str_lower(get_method())
    if not resource[method] then
        core.response.exit(404)
    end

    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()

    if req_body then
        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(400, {error_msg = "invalid request body",
                                     req_body = req_body})
        end

        req_body = data
    end

    local uri_args = ngx.req.get_uri_args() or {}
    if uri_args.ttl then
        if not tonumber(uri_args.ttl) then
            core.response.exit(400, {error_msg = "invalid argument ttl: "
                                                 .. "should be a number"})
        end
    end

    local code, data = resource[method](seg_id, req_body, seg_sub_path,
                                        uri_args)
    if code then
        core.response.exit(code, data)
    end
end


local function run_stream(uri_segs)
    local local_conf = core.config.local_conf()
    if not local_conf.apisix.stream_proxy then
        core.log.warn("stream mode is disabled, can not to add any stream ",
                      "route")
        core.response.exit(400, {error_msg = "stream mode is disabled"})
    end

    core.log.info("uri: ", core.json.delay_encode(uri_segs))

    -- /apisix/admin/:workspace/stream/routes/1
    -- /apisix/admin/:workspace/stream/schema/limit-count
    local seg_res, seg_id = uri_segs[6], uri_segs[7]
    local seg_sub_path = core.table.concat(uri_segs, "/", 8)

    local resource = resources_stream[seg_res]
    if not resource then
        core.response.exit(404)
    end

    local method = str_lower(get_method())
    if not resource[method] then
        core.response.exit(404)
    end

    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()

    if req_body then
        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(400, {error_msg = "invalid request body",
                                     req_body = req_body})
        end

        req_body = data
    end

    local uri_args = ngx.req.get_uri_args() or {}
    if uri_args.ttl then
        if not tonumber(uri_args.ttl) then
            core.response.exit(400, {error_msg = "invalid argument ttl: "
                                                 .. "should be a number"})
        end
    end

    local code, data = resource[method](seg_id, req_body, seg_sub_path,
                                        uri_args)
    if code then
        core.response.exit(code, data)
    end
end


local function get_plugins_list()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local plugins = resources_http.plugins.get_plugins_list()
    core.response.exit(200, plugins)
end


local function post_reload_plugins()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local success, err = events.post(reload_event, get_method(), ngx.time())
    if not success then
        core.response.exit(500, err)
    end

    core.response.exit(200, success)
end


local function reload_plugins(data, event, source, pid)
    core.log.info("start to hot reload plugins")
    plugin.load()
end


-- /apisix/admin/routes
-- /apisix/admin/routes/1
-- /apisix/admin/http/routes
-- /apisix/admin/http/routes/1
-- /apisix/admin/:workspace/http/routes
-- /apisix/admin/:workspace/http/routes/1
local valid_models = {
    http = true,
    stream = true,
}

local function run()
    local api_ctx = {}
    core.ctx.set_vars_meta(api_ctx)

    local ok, err = check_token(api_ctx)
    if not ok then
        core.log.warn("failed to check token: ", err)
        core.response.exit(401)
    end

    local uri_segs = core.utils.split_uri(ngx.var.uri)
    core.log.info("uri: ", core.json.delay_encode(uri_segs))

    local typ = uri_segs[4]
    if resources_http[typ] then
        -- /apisix/admin/routes
        uri_segs = {"", "apisix", "admin", "", "http", unpack_tab(uri_segs, 4)}

    elseif valid_models[typ] then
        -- /apisix/admin/http/routes
        -- /apisix/admin/stream/routes/1
        uri_segs = {"", "apisix", "admin", "", unpack_tab(uri_segs, 4)}

    else
        -- /apisix/admin/:workspace/http/routes
        -- /apisix/admin/:workspace/stream/routes
        uri_segs = {"", "apisix", "admin", unpack_tab(uri_segs, 4)}
    end

    local model = uri_segs[5] or "http"
    if model == "http" then
        return run_http(uri_segs)
    end

    return run_stream(uri_segs)
end


local uri_route = {
    {
        paths = [[/apisix/admin/*]],
        methods = {"GET", "PUT", "POST", "DELETE", "PATCH"},
        handler = run,
    },
    {
        paths = {
            [[/apisix/admin/plugins]],
            [[/apisix/admin/http/plugins]],
        },
        methods = {"GET"},
        handler = get_plugins_list,
    },
    {
        -- "/apisix/admin/plugins/reload"
        paths = reload_event,
        methods = {"PUT"},
        handler = post_reload_plugins,
    },
}


function _M.init_worker()
    local local_conf = core.config.local_conf()
    if not local_conf.apisix or not local_conf.apisix.enable_admin then
        return
    end

    router = route.new(uri_route)
    events = require("resty.worker.events")

    events.register(reload_plugins, reload_event, "PUT")
end


function _M.get()
    return router
end


return _M
