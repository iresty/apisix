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
local balancer    = require("ngx.balancer")
local core        = require("apisix.core")
local ipairs      = ipairs
local set_more_tries   = balancer.set_more_tries
local get_last_failure = balancer.get_last_failure
local set_timeouts     = balancer.set_timeouts

local module_name = "balancer"
local pickers = {}

local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})
local lrucache_addr = core.lrucache.new({
    ttl = 300, count = 1024 * 4
})


local _M = {
    version = 0.2,
    name = module_name,
}


local function fetch_health_nodes(upstream, checker)
    local nodes = upstream.nodes
    if not checker then
        local new_nodes = core.table.new(0, #nodes)
        for _, node in ipairs(nodes) do
            -- TODO filter with metadata
            new_nodes[node.host .. ":" .. node.port] = node.weight
        end
        return new_nodes
    end

    local host = upstream.checks and upstream.checks.active and upstream.checks.active.host
    local port = upstream.checks and upstream.checks.active and upstream.checks.active.port
    local up_nodes = core.table.new(0, #nodes)
    for _, node in ipairs(nodes) do
        local ok = checker:get_target_status(node.host, port or node.port, host)
        if ok then
            -- TODO filter with metadata
            up_nodes[node.host .. ":" .. node.port] = node.weight
        end
    end

    if core.table.nkeys(up_nodes) == 0 then
        core.log.warn("all upstream nodes is unhealthy, use default")
        for _, node in ipairs(nodes) do
            up_nodes[node.host .. ":" .. node.port] = node.weight
        end
    end

    return up_nodes
end


local function create_server_picker(upstream, checker)
    local picker = pickers[upstream.type]
    if not picker then
        pickers[upstream.type] = require("apisix.balancer." .. upstream.type)
        picker = pickers[upstream.type]
    end

    if picker then
        local up_nodes = fetch_health_nodes(upstream, checker)
        core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))

        return picker.new(up_nodes, upstream)
    end

    return nil, "invalid balancer type: " .. upstream.type, 0
end


local function parse_addr(addr)
    local host, port, err = core.utils.parse_addr(addr)
    return {host = host, port = port}, err
end


local function pick_server(route, ctx)
    core.log.info("route: ", core.json.delay_encode(route, true))
    core.log.info("ctx: ", core.json.delay_encode(ctx, true))
    local up_conf = ctx.upstream_conf

    if up_conf.timeout then
        local timeout = up_conf.timeout
        local ok, err = set_timeouts(timeout.connect, timeout.send,
                                     timeout.read)
        if not ok then
            core.log.error("could not set upstream timeouts: ", err)
        end
    end

    local nodes_count = #up_conf.nodes
    if nodes_count == 1 then
        local node = up_conf.nodes[1]
        ctx.balancer_ip = node.host
        ctx.balancer_port = node.port
        return node
    end

    local version = ctx.upstream_version
    local key = ctx.upstream_key
    local checker = ctx.up_checker

    ctx.balancer_try_count = (ctx.balancer_try_count or 0) + 1
    if ctx.balancer_try_count > 1 then
        if ctx.server_picker and ctx.server_picker.after_balance then
            ctx.server_picker.after_balance(ctx, true)
        end

        if checker then
            local state, code = get_last_failure()
            local host = up_conf.checks and up_conf.checks.active and up_conf.checks.active.host
            local port = up_conf.checks and up_conf.checks.active and up_conf.checks.active.port
            if state == "failed" then
                if code == 504 then
                    checker:report_timeout(ctx.balancer_ip, port or ctx.balancer_port, host)
                else
                    checker:report_tcp_failure(ctx.balancer_ip, port or ctx.balancer_port, host)
                end
            else
                checker:report_http_status(ctx.balancer_ip, port or ctx.balancer_port, host, code)
            end
        end
    end

    if ctx.balancer_try_count == 1 then
        local retries = up_conf.retries
        if not retries or retries < 0 then
            retries = #up_conf.nodes - 1
        end

        if retries > 0 then
            set_more_tries(retries)
        end
    end

    if checker then
        version = version .. "#" .. checker.status_ver
    end

    local server_picker = lrucache_server_picker(key, version,
                            create_server_picker, up_conf, checker)
    if not server_picker then
        return nil, "failed to fetch server picker"
    end

    local server, err = server_picker.get(ctx)
    if not server then
        err = err or "no valid upstream node"
        return nil, "failed to find valid upstream server, " .. err
    end
    ctx.balancer_server = server

    local res, err = lrucache_addr(server, nil, parse_addr, server)
    ctx.balancer_ip = res.host
    ctx.balancer_port = res.port
    -- core.log.info("cached balancer peer host: ", host, ":", port)
    if err then
        core.log.error("failed to parse server addr: ", server, " err: ", err)
        return core.response.exit(502)
    end
    ctx.server_picker = server_picker
    return res
end


-- for test
_M.pick_server = pick_server


function _M.run(route, ctx)
    local server, err = pick_server(route, ctx)
    if not server then
        core.log.error("failed to pick server: ", err)
        return core.response.exit(502)
    end

    core.log.info("proxy request to ", server.host, ":", server.port)
    local ok, err = balancer.set_current_peer(server.host, server.port)
    if not ok then
        core.log.error("failed to set server peer [", server.host, ":",
                       server.port, "] err: ", err)
        return core.response.exit(502)
    end

    ctx.proxy_passed = true
end


function _M.init_worker()
end

return _M
