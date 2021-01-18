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
local require       = require
local core          = require("apisix.core")
local config_util   = require("apisix.core.config_util")
local plugin        = require("apisix.plugin")
local script        = require("apisix.script")
local service_fetch = require("apisix.http.service").get
local admin_init    = require("apisix.admin.init")
local get_var       = require("resty.ngxvar").fetch
local router        = require("apisix.router")
local set_upstream  = require("apisix.upstream").set_by_route
local upstream_util = require("apisix.utils.upstream")
local ipmatcher     = require("resty.ipmatcher")
local ngx           = ngx
local get_method    = ngx.req.get_method
local ngx_exit      = ngx.exit
local math          = math
local error         = error
local ipairs        = ipairs
local tostring      = tostring
local ngx_now       = ngx.now
local str_byte      = string.byte
local str_sub       = string.sub
local tonumber      = tonumber
local control_api_router
if ngx.config.subsystem == "http" then
    control_api_router = require("apisix.control.router")
end
local load_balancer
local local_conf
local dns_resolver
local lru_resolved_domain
local ver_header    = "APISIX/" .. core.version.VERSION


local function parse_args(args)
    dns_resolver = args and args["dns_resolver"]
    core.utils.set_resolver(dns_resolver)
    core.log.info("dns resolver", core.json.delay_encode(dns_resolver, true))
end


local _M = {version = 0.4}


function _M.http_init(args)
    require("resty.core")

    if require("ffi").os == "Linux" then
        require("ngx.re").opt("jit_stack_size", 200 * 1024)
    end

    require("jit.opt").start("minstitch=2", "maxtrace=4000",
                             "maxrecord=8000", "sizemcode=64",
                             "maxmcode=4000", "maxirconst=1000")

    parse_args(args)
    core.id.init()

    local process = require("ngx.process")
    local ok, err = process.enable_privileged_agent()
    if not ok then
        core.log.error("failed to enable privileged_agent: ", err)
    end
end


function _M.http_init_worker()
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx_now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)
    -- for testing only
    core.log.info("random test in [1, 10000]: ", math.random(1, 10000))

    local we = require("resty.worker.events")
    local ok, err = we.configure({shm = "worker-events", interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end
    local discovery = require("apisix.discovery.init").discovery
    if discovery and discovery.init_worker then
        discovery.init_worker()
    end
    require("apisix.balancer").init_worker()
    load_balancer = require("apisix.balancer").run
    require("apisix.admin.init").init_worker()

    require("apisix.timers").init_worker()

    router.http_init_worker()
    require("apisix.http.service").init_worker()
    plugin.init_worker()
    require("apisix.consumer").init_worker()

    if core.config == require("apisix.core.config_yaml") then
        core.config.init_worker()
    end

    require("apisix.debug").init_worker()
    require("apisix.upstream").init_worker()

    local_conf = core.config.local_conf()
    local dns_resolver_valid = local_conf and local_conf.apisix and
                        local_conf.apisix.dns_resolver_valid

    lru_resolved_domain = core.lrucache.new({
        ttl = dns_resolver_valid, count = 512, invalid_stale = true,
    })

    if local_conf.apisix and local_conf.apisix.enable_server_tokens == false then
        ver_header = "APISIX"
    end
end


local function run_plugin(phase, plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    plugins = plugins or api_ctx.plugins
    if not plugins or #plugins == 0 then
        return api_ctx
    end

    if phase ~= "log"
        and phase ~= "header_filter"
        and phase ~= "body_filter"
    then
        for i = 1, #plugins, 2 do
            local phase_func = plugins[i][phase]
            if phase_func then
                local code, body = phase_func(plugins[i + 1], api_ctx)
                if code or body then
                    if code >= 400 then
                        core.log.warn(plugins[i].name, " exits with http status code ", code)
                    end

                    core.response.exit(code, body)
                end
            end
        end
        return api_ctx
    end

    for i = 1, #plugins, 2 do
        local phase_func = plugins[i][phase]
        if phase_func then
            phase_func(plugins[i + 1], api_ctx)
        end
    end

    return api_ctx
end


function _M.http_ssl_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if api_ctx == nil then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    local ok, err = router.router_ssl.match_and_set(api_ctx)
    if not ok then
        if err then
            core.log.error("failed to fetch ssl config: ", err)
        end
        ngx_exit(-1)
    end
end


local function parse_domain(host)
    local ip_info, err = core.utils.dns_parse(host)
    if not ip_info then
        core.log.error("failed to parse domain: ", host, ", error: ",err)
        return nil, err
    end

    core.log.info("parse addr: ", core.json.delay_encode(ip_info))
    core.log.info("resolver: ", core.json.delay_encode(dns_resolver))
    core.log.info("host: ", host)
    if ip_info.address then
        core.log.info("dns resolver domain: ", host, " to ", ip_info.address)
        return ip_info.address
    else
        return nil, "failed to parse domain"
    end
end
_M.parse_domain = parse_domain


local function parse_domain_for_nodes(nodes)
    local new_nodes = core.table.new(#nodes, 0)
    for _, node in ipairs(nodes) do
        local host = node.host
        if not ipmatcher.parse_ipv4(host) and
                not ipmatcher.parse_ipv6(host) then
            local ip, err = parse_domain(host)
            if ip then
                local new_node = core.table.clone(node)
                new_node.host = ip
                new_node.domain = host
                core.table.insert(new_nodes, new_node)
            end

            if err then
                return nil, err
            end
        else
            core.table.insert(new_nodes, node)
        end
    end
    return new_nodes
end


local function parse_domain_in_up(up)
    local nodes = up.value.nodes
    local new_nodes, err = parse_domain_for_nodes(nodes)
    if not new_nodes then
        return nil, err
    end

    local old_dns_value = up.dns_value and up.dns_value.nodes
    local ok = upstream_util.compare_upstream_node(old_dns_value, new_nodes)
    if ok then
        return up
    end

    local up_new = core.table.clone(up)
    up_new.modifiedIndex = up.modifiedIndex .. "#" .. ngx_now()
    up_new.dns_value = core.table.clone(up.value)
    up_new.dns_value.nodes = new_nodes
    core.log.info("resolve upstream which contain domain: ",
                  core.json.delay_encode(up_new))
    return up_new
end


local function parse_domain_in_route(route)
    local nodes = route.value.upstream.nodes
    local new_nodes, err = parse_domain_for_nodes(nodes)
    if not new_nodes then
        return nil, err
    end

    local old_dns_value = route.dns_value and route.dns_value.upstream.nodes
    local ok = upstream_util.compare_upstream_node(old_dns_value, new_nodes)
    if ok then
        return route
    end

    local route_new = core.table.clone(route)
    route_new.modifiedIndex = route.modifiedIndex .. "#" .. ngx_now()

    route_new.dns_value = core.table.deepcopy(route.value)
    route_new.dns_value.upstream.nodes = new_nodes
    core.log.info("parse route which contain domain: ",
                  core.json.delay_encode(route))
    return route_new
end


local function set_upstream_host(api_ctx)
    local pass_host = api_ctx.pass_host or "pass"
    if pass_host == "pass" then
        return
    end

    if pass_host == "rewrite" then
        api_ctx.var.upstream_host = api_ctx.upstream_host
        return
    end

    -- only support single node for `node` mode currently
    local host
    local up_conf = api_ctx.upstream_conf
    local nodes_count = up_conf.nodes and #up_conf.nodes or 0
    if nodes_count == 1 then
        local node = up_conf.nodes[1]
        if node.domain and #node.domain > 0 then
            host = node.domain
        else
            host = node.host
        end
    end

    if host then
        api_ctx.var.upstream_host = host
    end
end


function _M.http_access_phase()
    local ngx_ctx = ngx.ctx
    -- always fetch table from the table pool, we don't need a reused api_ctx
    local api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
    ngx_ctx.api_ctx = api_ctx

    core.ctx.set_vars_meta(api_ctx)

    -- load and run global rule
    if router.global_rules and router.global_rules.values
       and #router.global_rules.values > 0 then
        local plugins = core.tablepool.fetch("plugins", 32, 0)
        local values = router.global_rules.values
        for _, global_rule in config_util.iterate_values(values) do
            api_ctx.conf_type = "global_rule"
            api_ctx.conf_version = global_rule.modifiedIndex
            api_ctx.conf_id = global_rule.value.id

            core.table.clear(plugins)
            api_ctx.plugins = plugin.filter(global_rule, plugins)
            run_plugin("rewrite", plugins, api_ctx)
            run_plugin("access", plugins, api_ctx)
        end

        core.tablepool.release("plugins", plugins)
        api_ctx.plugins = nil
        api_ctx.conf_type = nil
        api_ctx.conf_version = nil
        api_ctx.conf_id = nil

        api_ctx.global_rules = router.global_rules
    end

    local uri = api_ctx.var.uri
    if local_conf.apisix and local_conf.apisix.delete_uri_tail_slash then
        if str_byte(uri, #uri) == str_byte("/") then
            api_ctx.var.uri = str_sub(api_ctx.var.uri, 1, #uri - 1)
            core.log.info("remove the end of uri '/', current uri: ",
                          api_ctx.var.uri)
        end
    end

    if router.api.has_route_not_under_apisix() or
        core.string.has_prefix(uri, "/apisix/")
    then
        local matched = router.api.match(api_ctx)
        if matched then
            return
        end
    end

    router.router_http.match(api_ctx)

    local route = api_ctx.matched_route
    if not route then
        core.log.info("not find any matched route")
        return core.response.exit(404,
                    {error_msg = "404 Route Not Found"})
    end

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    if route.value.service_protocol == "grpc" then
        return ngx.exec("@grpc_pass")
    end

    local enable_websocket = route.value.enable_websocket
    if route.value.service_id then
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

        route = plugin.merge_service_route(service, route)
        api_ctx.matched_route = route
        api_ctx.conf_type = "route&service"
        api_ctx.conf_version = route.modifiedIndex .. "&" .. service.modifiedIndex
        api_ctx.conf_id = route.value.id .. "&" .. service.value.id
        api_ctx.service_id = service.value.id
        api_ctx.service_name = service.value.name

        if enable_websocket == nil then
            enable_websocket = service.value.enable_websocket
        end

    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end
    api_ctx.route_id = route.value.id
    api_ctx.route_name = route.value.name

    local up_id = route.value.upstream_id
    if up_id then
        local upstreams = core.config.fetch_created_obj("/upstreams")
        if upstreams then
            local upstream = upstreams:get(tostring(up_id))
            if not upstream then
                core.log.error("failed to find upstream by id: " .. up_id)
                return core.response.exit(502)
            end

            if upstream.has_domain then
                -- try to fetch the resolved domain, if we got `nil`,
                -- it means we need to create the cache by handle.
                -- the `api_ctx.conf_version` is different after we called
                -- `parse_domain_in_up`, need to recreate the cache by new
                -- `api_ctx.conf_version`
                local err
                upstream, err = lru_resolved_domain(upstream,
                                                    upstream.modifiedIndex,
                                                    parse_domain_in_up,
                                                    upstream)
                if err then
                    core.log.error("failed to get resolved upstream: ", err)
                    return core.response.exit(500)
                end
            end

            if upstream.value.enable_websocket then
                core.log.warn("DEPRECATE: enable websocket in upstream will be removed soon. ",
                              "Please enable it in route/service level.")
                enable_websocket = true
            end

            if upstream.value.pass_host then
                api_ctx.pass_host = upstream.value.pass_host
                api_ctx.upstream_host = upstream.value.upstream_host
            end

            core.log.info("parsed upstream: ", core.json.delay_encode(upstream))
            api_ctx.matched_upstream = upstream.dns_value or upstream.value
        end

    else
        if route.has_domain then
            local err
            route, err = lru_resolved_domain(route, api_ctx.conf_version,
                                             parse_domain_in_route, route)
            if err then
                core.log.error("failed to get resolved route: ", err)
                return core.response.exit(500)
            end

            api_ctx.matched_route = route
        end

        local route_val = route.value
        if route_val.upstream and route_val.upstream.enable_websocket then
            enable_websocket = true
        end

        if route_val.upstream and route_val.upstream.pass_host then
            api_ctx.pass_host = route_val.upstream.pass_host
            api_ctx.upstream_host = route_val.upstream.upstream_host
        end

        api_ctx.matched_upstream = (route.dns_value and
                                    route.dns_value.upstream)
                                   or route_val.upstream
    end

    if enable_websocket then
        api_ctx.var.upstream_upgrade    = api_ctx.var.http_upgrade
        api_ctx.var.upstream_connection = api_ctx.var.http_connection
        core.log.info("enabled websocket for route: ", route.value.id)
    end

    if route.value.script then
        script.load(route, api_ctx)
        script.run("access", api_ctx)
    else
        local plugins = plugin.filter(route)
        api_ctx.plugins = plugins

        run_plugin("rewrite", plugins, api_ctx)
        if api_ctx.consumer then
            local changed
            route, changed = plugin.merge_consumer_route(
                route,
                api_ctx.consumer,
                api_ctx
            )

            core.log.info("find consumer ", api_ctx.consumer.username,
                          ", config changed: ", changed)

            if changed then
                core.table.clear(api_ctx.plugins)
                api_ctx.plugins = plugin.filter(route, api_ctx.plugins)
            end
        end
        run_plugin("access", plugins, api_ctx)
    end

    local code, err = set_upstream(route, api_ctx)
    if code then
        core.log.error("failed to set upstream: ", err)
        core.response.exit(code)
    end

    set_upstream_host(api_ctx)
end


function _M.grpc_access_phase()
    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)

    router.router_http.match(api_ctx)

    core.log.info("route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local route = api_ctx.matched_route
    if not route then
        return core.response.exit(404)
    end

    if route.value.service_id then
        -- core.log.info("matched route: ", core.json.delay_encode(route.value))
        local service = service_fetch(route.value.service_id)
        if not service then
            core.log.error("failed to fetch service configuration by ",
                           "id: ", route.value.service_id)
            return core.response.exit(404)
        end

        local changed
        route, changed = plugin.merge_service_route(service, route)
        api_ctx.matched_route = route

        if changed then
            api_ctx.conf_type = "route&service"
            api_ctx.conf_version = route.modifiedIndex .. "&"
                                   .. service.modifiedIndex
            api_ctx.conf_id = route.value.id .. "&"
                              .. service.value.id
        else
            api_ctx.conf_type = "service"
            api_ctx.conf_version = service.modifiedIndex
            api_ctx.conf_id = service.value.id
        end

    else
        api_ctx.conf_type = "route"
        api_ctx.conf_version = route.modifiedIndex
        api_ctx.conf_id = route.value.id
    end

    -- todo: support upstream id

    api_ctx.matched_upstream = (route.dns_value and
                                route.dns_value.upstream)
                               or route.value.upstream

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.filter(route, plugins)

    run_plugin("rewrite", plugins, api_ctx)
    run_plugin("access", plugins, api_ctx)

    set_upstream(route, api_ctx)
end


local function common_phase(phase_name)
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    if api_ctx.global_rules then
        local plugins = core.tablepool.fetch("plugins", 32, 0)
        local values = api_ctx.global_rules.values
        for _, global_rule in config_util.iterate_values(values) do
            core.table.clear(plugins)
            plugins = plugin.filter(global_rule, plugins)
            run_plugin(phase_name, plugins, api_ctx)
        end
        core.tablepool.release("plugins", plugins)
    end

    if api_ctx.script_obj then
        script.run(phase_name, api_ctx)
    else
        run_plugin(phase_name, nil, api_ctx)
    end

    return api_ctx
end


local function set_resp_upstream_status(up_status)
    core.response.set_header("X-APISIX-Upstream-Status", up_status)
    core.log.info("X-APISIX-Upstream-Status: ", up_status)
end


function _M.http_header_filter_phase()
    core.response.set_header("Server", ver_header)

    local up_status = get_var("upstream_status")
    if up_status and #up_status == 3
       and tonumber(up_status) >= 500
       and tonumber(up_status) <= 599
    then
        set_resp_upstream_status(up_status)
    elseif up_status and #up_status > 3 then
        -- the up_status can be "502, 502" or "502, 502 : "
        local last_status
        if str_byte(up_status, -1) == str_byte(" ") then
            last_status = str_sub(up_status, -6, -3)
        else
            last_status = str_sub(up_status, -3)
        end

        if tonumber(last_status) >= 500 and tonumber(last_status) <= 599 then
            set_resp_upstream_status(up_status)
        end
    end

    common_phase("header_filter")
end


function _M.http_body_filter_phase()
    common_phase("body_filter")
end


local function healcheck_passive(api_ctx)
    local checker = api_ctx.up_checker
    if not checker then
        return
    end

    local up_conf = api_ctx.upstream_conf
    local passive = up_conf.checks.passive
    if not passive then
        return
    end

    core.log.info("enabled healthcheck passive")
    local host = up_conf.checks and up_conf.checks.active
                 and up_conf.checks.active.host
    local port = up_conf.checks and up_conf.checks.active
                 and up_conf.checks.active.port

    local resp_status = ngx.status
    local http_statuses = passive and passive.healthy and
                          passive.healthy.http_statuses
    core.log.info("passive.healthy.http_statuses: ",
                  core.json.delay_encode(http_statuses))
    if http_statuses then
        for i, status in ipairs(http_statuses) do
            if resp_status == status then
                checker:report_http_status(api_ctx.balancer_ip,
                                           port or api_ctx.balancer_port,
                                           host,
                                           resp_status)
            end
        end
    end

    http_statuses = passive and passive.unhealthy and
                    passive.unhealthy.http_statuses
    core.log.info("passive.unhealthy.http_statuses: ",
                  core.json.delay_encode(http_statuses))
    if not http_statuses then
        return
    end

    for i, status in ipairs(http_statuses) do
        for i, status in ipairs(http_statuses) do
            if resp_status == status then
                checker:report_http_status(api_ctx.balancer_ip,
                                           port or api_ctx.balancer_port,
                                           host,
                                           resp_status)
            end
        end
    end
end


function _M.http_log_phase()
    local api_ctx = common_phase("log")
    healcheck_passive(api_ctx)

    if api_ctx.server_picker and api_ctx.server_picker.after_balance then
        api_ctx.server_picker.after_balance(api_ctx, false)
    end

    if api_ctx.uri_parse_param then
        core.tablepool.release("uri_parse_param", api_ctx.uri_parse_param)
    end

    core.ctx.release_vars(api_ctx)
    if api_ctx.plugins and api_ctx.plugins ~= core.empty_tab then
        core.tablepool.release("plugins", api_ctx.plugins)
    end

    if api_ctx.curr_req_matched then
        core.tablepool.release("matched_route_record", api_ctx.curr_req_matched)
    end

    core.tablepool.release("api_ctx", api_ctx)
end


function _M.http_balancer_phase()
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return core.response.exit(500)
    end

    load_balancer(api_ctx.matched_route, api_ctx)
end


local function cors_admin()
    local_conf = core.config.local_conf()
    if local_conf.apisix and not local_conf.apisix.enable_admin_cors then
        return
    end

    local method = get_method()
    if method == "OPTIONS" then
        core.response.set_header("Access-Control-Allow-Origin", "*",
            "Access-Control-Allow-Methods",
            "POST, GET, PUT, OPTIONS, DELETE, PATCH",
            "Access-Control-Max-Age", "3600",
            "Access-Control-Allow-Headers", "*",
            "Access-Control-Allow-Credentials", "true",
            "Content-Length", "0",
            "Content-Type", "text/plain")
        ngx_exit(200)
    end

    core.response.set_header("Access-Control-Allow-Origin", "*",
                            "Access-Control-Allow-Credentials", "true",
                            "Access-Control-Expose-Headers", "*",
                            "Access-Control-Max-Age", "3600")
end

local function add_content_type()
    core.response.set_header("Content-Type", "application/json")
end

do
    local router

function _M.http_admin()
    if not router then
        router = admin_init.get()
    end

    -- add cors rsp header
    cors_admin()

    -- add content type to rsp header
    add_content_type()

    -- core.log.info("uri: ", get_var("uri"), " method: ", get_method())
    local ok = router:dispatch(get_var("uri"), {method = get_method()})
    if not ok then
        ngx_exit(404)
    end
end

end -- do


function _M.http_control()
    local ok = control_api_router.match(get_var("uri"))
    if not ok then
        ngx_exit(404)
    end
end


function _M.stream_init()
    core.log.info("enter stream_init")
end


function _M.stream_init_worker()
    core.log.info("enter stream_init_worker")
    local seed, err = core.utils.get_seed_from_urandom()
    if not seed then
        core.log.warn('failed to get seed from urandom: ', err)
        seed = ngx_now() * 1000 + ngx.worker.pid()
    end
    math.randomseed(seed)
    -- for testing only
    core.log.info("random stream test in [1, 10000]: ", math.random(1, 10000))

    local we = require("resty.worker.events")
    local ok, err = we.configure({shm = "worker-events-stream", interval = 0.1})
    if not ok then
        error("failed to init worker event: " .. err)
    end

    router.stream_init_worker()
    plugin.init_worker()

    if core.config == require("apisix.core.config_yaml") then
        core.config.init_worker()
    end

    load_balancer = require("apisix.balancer").run

    local_conf = core.config.local_conf()
    local dns_resolver_valid = local_conf and local_conf.apisix and
                        local_conf.apisix.dns_resolver_valid

    lru_resolved_domain = core.lrucache.new({
        ttl = dns_resolver_valid, count = 512, invalid_stale = true,
    })
end


function _M.stream_preread_phase()
    core.log.info("enter stream_preread_phase")

    local ngx_ctx = ngx.ctx
    local api_ctx = ngx_ctx.api_ctx

    if not api_ctx then
        api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
        ngx_ctx.api_ctx = api_ctx
    end

    core.ctx.set_vars_meta(api_ctx)

    router.router_stream.match(api_ctx)

    core.log.info("matched route: ",
                  core.json.delay_encode(api_ctx.matched_route, true))

    local matched_route = api_ctx.matched_route
    if not matched_route then
        return ngx_exit(1)
    end

    local plugins = core.tablepool.fetch("plugins", 32, 0)
    api_ctx.plugins = plugin.stream_filter(matched_route, plugins)
    -- core.log.info("valid plugins: ", core.json.delay_encode(plugins, true))

    api_ctx.matched_upstream = matched_route.value.upstream
    api_ctx.conf_type = "stream/route"
    api_ctx.conf_version = matched_route.modifiedIndex
    api_ctx.conf_id = matched_route.value.id

    run_plugin("preread", plugins, api_ctx)

    local code, err = set_upstream(matched_route, api_ctx)
    if code then
        core.log.error("failed to set upstream: ", err)
        return ngx_exit(1)
    end
end


function _M.stream_balancer_phase()
    core.log.info("enter stream_balancer_phase")
    local api_ctx = ngx.ctx.api_ctx
    if not api_ctx then
        core.log.error("invalid api_ctx")
        return ngx_exit(1)
    end

    load_balancer(api_ctx.matched_route, api_ctx)
end


function _M.stream_log_phase()
    core.log.info("enter stream_log_phase")
    -- core.ctx.release_vars(api_ctx)
    local api_ctx = run_plugin("log")
    if api_ctx then
        healcheck_passive(api_ctx)
    end
end


return _M
