-- Copyright (C) Yuansheng Wang

local require = require
local core = require("apisix.core")
local router = require("apisix.route").get
local plugin_module = require("apisix.plugin")
local new_tab = require("table.new")
local load_balancer = require("apisix.balancer") .run
local ngx = ngx


local _M = {version = 0.1}


function _M.init()
    require("resty.core")
    require("ngx.re").opt("jit_stack_size", 200 * 1024)
    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")
end


function _M.init_worker()
    require("apisix.route").init_worker()
    require("apisix.balancer").init_worker()

    core.lrucache.global("/local_plugins", nil, plugin_module.load)
end


function _M.rewrite_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        -- todo: reuse this table
        api_ctx = new_tab(0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    local method = core.request.var(api_ctx, "method")
    local uri = core.request.var(api_ctx, "uri")
    -- local host = core.request.var(api_ctx, "host") -- todo: support host

    local ok = router():dispatch(method, uri, api_ctx)
    if not ok then
        core.log.warn("not find any matched route")
        return core.response.say(404)
    end

    local local_plugins = core.lrucache.global("/local_plugins", nil,
                                               plugin_module.load)

    if api_ctx.matched_route.service_id then
        error("todo: suppport to use service fetch user config")
    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = api_ctx.matched_route.modifiedIndex
        api_ctx.conf_id = api_ctx.matched_route.value.id
    end

    local filter_plugins = plugin_module.filter_plugin(
        api_ctx.matched_route, local_plugins)

    api_ctx.filter_plugins = filter_plugins
    -- todo: fetch the upstream node status, it may be stored in
    -- different places.

    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.rewrite then
            plugin.rewrite(filter_plugins[i + 1], api_ctx)
        end
    end
end

function _M.access_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    local filter_plugins = api_ctx.filter_plugins
    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.access then
            local code, body = plugin.access(filter_plugins[i + 1], api_ctx)
            if code then
                core.response.exit(code, body)
            end
        end
    end
end

function _M.header_filter_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    local filter_plugins = api_ctx.filter_plugins
    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.header_filter then
            plugin.header_filter(filter_plugins[i + 1], api_ctx)
        end
    end
end

function _M.log_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    local filter_plugins = api_ctx.filter_plugins
    for i = 1, #filter_plugins, 2 do
        local plugin = filter_plugins[i]
        if plugin.log then
            plugin.log(filter_plugins[i + 1], api_ctx)
        end
    end
end

function _M.balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx.filter_plugins then
        return
    end

    -- TODO: fetch the upstream by upstream_id
    load_balancer(api_ctx.matched_route, api_ctx.conf_version)
end

return _M
