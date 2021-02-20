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
local plugin = require("apisix.plugin")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local upstream_mod = require("apisix.upstream")
local get_upstreams = upstream_mod.upstreams
local ipairs = ipairs
local str_format = string.format
local ngx_var = ngx.var


local _M = {}


function _M.schema()
    local schema = {
        main = {
            consumer = core.schema.consumer,
            global_rule = core.schema.global_rule,
            plugins = core.schema.plugins,
            proto = core.schema.proto,
            route = core.schema.route,
            service = core.schema.service,
            ssl = core.schema.ssl,
            stream_route = core.schema.stream_route,
            upstream = core.schema.upstream,
            upstream_hash_header_schema = core.schema.upstream_hash_header_schema,
            upstream_hash_vars_schema = core.schema.upstream_hash_vars_schema,
        },
        plugins = plugin.get_all({
            version = true,
            priority = true,
            schema = true,
            metadata_schema = true,
            consumer_schema = true,
            type = true,
        }),
    }
    return 200, schema
end


local function extra_checker_info(value, src_type)
    local checker = value.checker
    local upstream = value.checker_upstream
    local host = upstream.checks and upstream.checks.active and upstream.checks.active.host
    local port = upstream.checks and upstream.checks.active and upstream.checks.active.port
    local nodes = upstream.nodes
    local healthy_nodes = core.table.new(#nodes, 0)
    for _, node in ipairs(nodes) do
        local ok = checker:get_target_status(node.host, port or node.port, host)
        if ok then
            core.table.insert(healthy_nodes, node)
        end
    end

    local conf = value.value
    return {
        name = upstream_mod.get_healthchecker_name(value),
        src_id = conf.id,
        src_type = src_type,
        nodes = nodes,
        healthy_nodes = healthy_nodes,
    }
end


local function iter_and_add_healthcheck_info(infos, values, src_type)
    if not values then
        return
    end

    for _, value in core.config_util.iterate_values(values) do
        if value.checker then
            core.table.insert(infos, extra_checker_info(value, src_type))
        end
    end
end


function _M.get_health_checkers()
    local infos = {}
    local routes = get_routes()
    iter_and_add_healthcheck_info(infos, routes, "routes")
    local services = get_services()
    iter_and_add_healthcheck_info(infos, services, "services")
    local upstreams = get_upstreams()
    iter_and_add_healthcheck_info(infos, upstreams, "upstreams")
    return 200, infos
end


local function iter_and_find_healthcheck_info(values, src_type, src_id)
    if not values then
        return nil, str_format("%s[%s] not found", src_type, src_id)
    end

    for _, value in core.config_util.iterate_values(values) do
        if value.value.id == src_id then
            if not value.checker then
                return nil, str_format("no checker for %s[%s]", src_type, src_id)
            end

            return extra_checker_info(value, src_type)
        end
    end

    return nil, str_format("%s[%s] not found", src_type, src_id)
end


function _M.get_health_checker()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    core.log.info("healthcheck uri: ", core.json.delay_encode(uri_segs))

    local src_type, src_id = uri_segs[4], uri_segs[5]
    if not src_id then
        return 404, {error_msg = str_format("missing src id for src type %s", src_type)}
    end

    local values
    if src_type == "routes" then
        values = get_routes()
    elseif src_type == "services" then
        values = get_services()
    elseif src_type == "upstreams" then
        values = get_upstreams()
    else
        return 400, {error_msg = str_format("invalid src type %s", src_type)}
    end

    local info, err = iter_and_find_healthcheck_info(values, src_type, src_id)
    if not info then
        return 404, {error_msg = err}
    end
    return 200, info
end


return {
    -- /v1/schema
    {
        methods = {"GET"},
        uris = {"/schema"},
        handler = _M.schema,
    },
    -- /v1/healthcheck
    {
        methods = {"GET"},
        uris = {"/healthcheck"},
        handler = _M.get_health_checkers,
    },
    -- /v1/healthcheck/{src_type}/{src_id}
    {
        methods = {"GET"},
        uris = {"/healthcheck/*"},
        handler = _M.get_health_checker,
    }
}
