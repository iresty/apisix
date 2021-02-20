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
local base_prometheus = require("prometheus")
local core = require("apisix.core")
local ipairs = ipairs
local ngx = ngx
local ngx_capture = ngx.location.capture
local re_gmatch = ngx.re.gmatch
local select = select
local type = type
local prometheus
local router = require("apisix.router")
local get_routes = router.http_routes
local get_ssls   = router.ssls
local get_services = require("apisix.http.service").services
local get_consumers = require("apisix.consumer").consumers
local get_upstreams = require("apisix.upstream").upstreams
local clear_tab = core.table.clear
local get_stream_routes = router.stream_routes
local get_protos = require("apisix.plugins.grpc-transcode.proto").protos



-- Default set of latency buckets, 1ms to 60s:
local DEFAULT_BUCKETS = { 1, 2, 5, 7, 10, 15, 20, 25, 30, 40, 50, 60, 70,
    80, 90, 100, 200, 300, 400, 500, 1000,
    2000, 5000, 10000, 30000, 60000
}

local metrics = {}

local inner_tab_arr = {}

local function gen_arr(...)
    clear_tab(inner_tab_arr)
    for i = 1, select('#', ...) do
        inner_tab_arr[i] = select(i, ...)
    end

    return inner_tab_arr
end


local _M = {}


function _M.init()
    -- todo: support hot reload, we may need to update the lua-prometheus
    -- library
    if ngx.get_phase() ~= "init" and ngx.get_phase() ~= "init_worker"  then
        return
    end

    clear_tab(metrics)

    -- Newly added metrics should follow the naming best practices described in
    -- https://prometheus.io/docs/practices/naming/#metric-names
    -- For example,
    -- 1. Add unit as the suffix
    -- 2. Add `_total` as the suffix if the metric type is counter
    -- 3. Use base unit
    -- We keep the old metric names for the compatibility.

    -- across all services
    prometheus = base_prometheus.init("prometheus-metrics", "apisix_")
    metrics.connections = prometheus:gauge("nginx_http_current_connections",
            "Number of HTTP connections",
            {"state"})

    metrics.etcd_reachable = prometheus:gauge("etcd_reachable",
            "Config server etcd reachable from APISIX, 0 is unreachable")


    metrics.node_info = prometheus:gauge("node_info",
            "Info of APISIX node",
            {"hostname"})

    metrics.etcd_modify_indexes = prometheus:gauge("etcd_modify_indexes",
            "Etcd modify index for APISIX keys",
            {"key"})

    -- per service

    -- The consumer label indicates the name of consumer corresponds to the
    -- request to the route/service, it will be an empty string if there is
    -- no consumer in request.
    metrics.status = prometheus:counter("http_status",
            "HTTP status codes per service in APISIX",
            {"code", "route", "matched_uri", "matched_host", "service", "consumer", "node"})

    metrics.latency = prometheus:histogram("http_latency",
        "HTTP request latency in milliseconds per service in APISIX",
        {"type", "service", "consumer", "node"}, DEFAULT_BUCKETS)

    metrics.overhead = prometheus:histogram("http_overhead",
        "HTTP request overhead added by APISIX in milliseconds per service " ..
        "in APISIX",
        {"type", "service", "consumer", "node"}, DEFAULT_BUCKETS)

    metrics.bandwidth = prometheus:counter("bandwidth",
            "Total bandwidth in bytes consumed per service in APISIX",
            {"type", "route", "service", "consumer", "node"})

end


function _M.log(conf, ctx)
    local vars = ctx.var

    local route_id = ""
    local balancer_ip = ctx.balancer_ip or ""
    local service_id
    local consumer_name = ctx.consumer_name or ""

    local matched_route = ctx.matched_route and ctx.matched_route.value
    if matched_route then
        service_id = matched_route.service_id or ""
        route_id = matched_route.id
    else
        service_id = vars.host
    end

    local matched_uri = ""
    local matched_host = ""
    if ctx.curr_req_matched then
        matched_uri = ctx.curr_req_matched._path or ""
        matched_host = ctx.curr_req_matched._host or ""
    end

    metrics.status:inc(1,
        gen_arr(vars.status, route_id, matched_uri, matched_host,
                service_id, consumer_name, balancer_ip))

    local latency = (ngx.now() - ngx.req.start_time()) * 1000
    metrics.latency:observe(latency,
        gen_arr("request", service_id, consumer_name, balancer_ip))

    local overhead = latency
    if ctx.var.upstream_response_time then
        overhead =  overhead - ctx.var.upstream_response_time * 1000
    end
    metrics.overhead:observe(overhead,
        gen_arr("request", service_id, consumer_name, balancer_ip))

    metrics.bandwidth:inc(vars.request_length,
        gen_arr("ingress", route_id, service_id, consumer_name, balancer_ip))

    metrics.bandwidth:inc(vars.bytes_sent,
        gen_arr("egress", route_id, service_id, consumer_name, balancer_ip))
end


    local ngx_statu_items = {"active", "accepted", "handled", "total",
                             "reading", "writing", "waiting"}
    local label_values = {}
local function nginx_status()
    local res = ngx_capture("/apisix/nginx_status")
    if not res or res.status ~= 200 then
        core.log.error("failed to fetch Nginx status")
        return
    end

    -- Active connections: 2
    -- server accepts handled requests
    --   26 26 84
    -- Reading: 0 Writing: 1 Waiting: 1

    local iterator, err = re_gmatch(res.body, [[(\d+)]], "jmo")
    if not iterator then
        core.log.error("failed to re.gmatch Nginx status: ", err)
        return
    end

    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        label_values[1] = name
        metrics.connections:set(val[0], label_values)

    end
end


local key_values = {}
local function set_modify_index(key, items, items_ver, global_max_index)
    clear_tab(key_values)
    local max_idx = 0
    if items_ver and items then
        for _, item in ipairs(items) do
            if type(item) == "table" then
                local modify_index = item.modifiedIndex
                if modify_index > max_idx then
                    max_idx = modify_index
                end
            end
        end
    end

    key_values[1] = key
    metrics.etcd_modify_indexes:set(max_idx, key_values)


    global_max_index = max_idx > global_max_index and max_idx or global_max_index

    return global_max_index
end


local function etcd_modify_index()
    clear_tab(key_values)
    local global_max_idx = 0

    -- routes
    local routes, routes_ver = get_routes()
    global_max_idx = set_modify_index("routes", routes, routes_ver, global_max_idx)

    -- services
    local services, services_ver = get_services()
    global_max_idx = set_modify_index("services", services, services_ver, global_max_idx)

    -- ssls
    local ssls, ssls_ver = get_ssls()
    global_max_idx = set_modify_index("ssls", ssls, ssls_ver, global_max_idx)

    -- consumers
    local consumers, consumers_ver = get_consumers()
    global_max_idx = set_modify_index("consumers", consumers, consumers_ver, global_max_idx)

    -- global_rules
    local global_rules = router.global_rules
    if global_rules then
        global_max_idx = set_modify_index("global_rules", global_rules.values,
            global_rules.conf_version, global_max_idx)

        -- prev_index
        key_values[1] = "prev_index"
        metrics.etcd_modify_indexes:set(global_rules.prev_index, key_values)

    else
        global_max_idx = set_modify_index("global_rules", nil, nil, global_max_idx)
    end

    -- upstreams
    local upstreams, upstreams_ver = get_upstreams()
    global_max_idx = set_modify_index("upstreams", upstreams, upstreams_ver, global_max_idx)

    -- stream_routes
    local stream_routes, stream_routes_ver = get_stream_routes()
    global_max_idx = set_modify_index("stream_routes", stream_routes,
        stream_routes_ver, global_max_idx)

    -- proto
    local protos, protos_ver = get_protos()
    global_max_idx = set_modify_index("protos", protos, protos_ver, global_max_idx)

    -- global max
    key_values[1] = "max_modify_index"
    metrics.etcd_modify_indexes:set(global_max_idx, key_values)

end


function _M.collect()
    if not prometheus or not metrics then
        core.log.error("prometheus: plugin is not initialized, please make sure ",
                     " 'prometheus_metrics' shared dict is present in nginx template")
        return 500, {message = "An unexpected error occurred"}
    end

    -- across all services
    nginx_status()

    local config = core.config.new()

    -- config server status
    local vars = ngx.var or {}
    local hostname = vars.hostname or ""

    if config.type == "etcd" then
        -- etcd modify index
        etcd_modify_index()

        local version, err = config:server_version()
        if version then
            metrics.etcd_reachable:set(1)

        else
            metrics.etcd_reachable:set(0)
            core.log.error("prometheus: failed to reach config server while ",
                           "processing metrics endpoint: ", err)
        end

        local res, _ = config:getkey("/routes")
        if res and res.headers then
            clear_tab(key_values)
            -- global max
            key_values[1] = "x_etcd_index"
            metrics.etcd_modify_indexes:set(res.headers["X-Etcd-Index"], key_values)
        end
    end

    metrics.node_info:set(1, gen_arr(hostname))

    core.response.set_header("content_type", "text/plain")
    return 200, core.table.concat(prometheus:metric_data())
end


function _M.metric_data()
    return prometheus:metric_data()
end

function _M.get_prometheus()
    return prometheus
end

return _M
