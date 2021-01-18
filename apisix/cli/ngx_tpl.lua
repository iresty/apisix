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

return [=[
# Configuration File - Nginx Server Configs
# This is a read-only file, do not try to modify it.

master_process on;

worker_processes {* worker_processes *};
{% if os_name == "Linux" and enable_cpu_affinity == true then %}
worker_cpu_affinity auto;
{% end %}

# main configuration snippet starts
{% if main_configuration_snippet then %}
{* main_configuration_snippet *}
{% end %}
# main configuration snippet ends

error_log {* error_log *} {* error_log_level or "warn" *};
pid logs/nginx.pid;

worker_rlimit_nofile {* worker_rlimit_nofile *};

events {
    accept_mutex off;
    worker_connections {* event.worker_connections *};
}

worker_rlimit_core  {* worker_rlimit_core *};

worker_shutdown_timeout {* worker_shutdown_timeout *};

env APISIX_PROFILE;

{% if envs then %}
{% for _, name in ipairs(envs) do %}
env {*name*};
{% end %}
{% end %}

{% if stream_proxy then %}
stream {
    lua_package_path  "$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;]=]
                      .. [=[{*apisix_lua_home*}/?.lua;{*apisix_lua_home*}/?/init.lua;;{*lua_path*};";
    lua_package_cpath "$prefix/deps/lib64/lua/5.1/?.so;]=]
                      .. [=[$prefix/deps/lib/lua/5.1/?.so;;]=]
                      .. [=[{*lua_cpath*};";
    lua_socket_log_errors off;

    lua_shared_dict lrucache-lock-stream   10m;
    lua_shared_dict worker-events-stream   10m;
    lua_shared_dict upstream-healthcheck-stream 10m;

    resolver {% for _, dns_addr in ipairs(dns_resolver or {}) do %} {*dns_addr*} {% end %} valid={*dns_resolver_valid*};
    resolver_timeout {*resolver_timeout*};

    # stream configuration snippet starts
    {% if stream_configuration_snippet then %}
    {* stream_configuration_snippet *}
    {% end %}
    # stream configuration snippet ends

    upstream apisix_backend {
        server 127.0.0.1:80;
        balancer_by_lua_block {
            apisix.stream_balancer_phase()
        }
    }

    init_by_lua_block {
        require "resty.core"
        apisix = require("apisix")
        apisix.stream_init()
    }

    init_worker_by_lua_block {
        apisix.stream_init_worker()
    }

    server {
        {% for _, port in ipairs(stream_proxy.tcp or {}) do %}
        listen {*port*} {% if enable_reuseport then %} reuseport {% end %} {% if proxy_protocol and proxy_protocol.enable_tcp_pp then %} proxy_protocol {% end %};
        {% end %}
        {% for _, port in ipairs(stream_proxy.udp or {}) do %}
        listen {*port*} udp {% if enable_reuseport then %} reuseport {% end %};
        {% end %}

        {% if proxy_protocol and proxy_protocol.enable_tcp_pp_to_upstream then %}
        proxy_protocol on;
        {% end %}

        preread_by_lua_block {
            apisix.stream_preread_phase()
        }

        proxy_pass apisix_backend;

        log_by_lua_block {
            apisix.stream_log_phase()
        }
    }
}
{% end %}

http {
    lua_package_path  "$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;]=]
                       .. [=[{*apisix_lua_home*}/?.lua;{*apisix_lua_home*}/?/init.lua;;{*lua_path*};";
    lua_package_cpath "$prefix/deps/lib64/lua/5.1/?.so;]=]
                      .. [=[$prefix/deps/lib/lua/5.1/?.so;;]=]
                      .. [=[{*lua_cpath*};";

    lua_shared_dict internal_status      10m;
    lua_shared_dict plugin-limit-req     10m;
    lua_shared_dict plugin-limit-count   10m;
    lua_shared_dict prometheus-metrics   10m;
    lua_shared_dict plugin-limit-conn    10m;
    lua_shared_dict upstream-healthcheck 10m;
    lua_shared_dict worker-events        10m;
    lua_shared_dict lrucache-lock        10m;
    lua_shared_dict skywalking-tracing-buffer    100m;
    lua_shared_dict balancer_ewma        10m;
    lua_shared_dict balancer_ewma_locks  10m;
    lua_shared_dict balancer_ewma_last_touched_at 10m;
    lua_shared_dict plugin-limit-count-redis-cluster-slot-lock 1m;
    lua_shared_dict tracing_buffer       10m; # plugin: skywalking
    lua_shared_dict plugin-api-breaker   10m;

    # for openid-connect and authz-keycloak plugin
    lua_shared_dict discovery             1m; # cache for discovery metadata documents

    # for openid-connect plugin
    lua_shared_dict jwks                  1m; # cache for JWKs
    lua_shared_dict introspection        10m; # cache for JWT verification results

    # for custom shared dict
    {% if http.lua_shared_dicts then %}
    {% for cache_key, cache_size in pairs(http.lua_shared_dicts) do %}
    lua_shared_dict {*cache_key*} {*cache_size*};
    {% end %}
    {% end %}

    {% if enabled_plugins["proxy-cache"] then %}
    # for proxy cache
    {% for _, cache in ipairs(proxy_cache.zones) do %}
    proxy_cache_path {* cache.disk_path *} levels={* cache.cache_levels *} keys_zone={* cache.name *}:{* cache.memory_size *} inactive=1d max_size={* cache.disk_size *} use_temp_path=off;
    {% end %}
    {% end %}

    {% if enabled_plugins["proxy-cache"] then %}
    # for proxy cache
    map $upstream_cache_zone $upstream_cache_zone_info {
    {% for _, cache in ipairs(proxy_cache.zones) do %}
        {* cache.name *} {* cache.disk_path *},{* cache.cache_levels *};
    {% end %}
    }
    {% end %}

    {% if enabled_plugins["error-log-logger"] then %}
        lua_capture_error_log  10m;
    {% end %}

    lua_ssl_verify_depth 5;
    ssl_session_timeout 86400;

    {% if http.underscores_in_headers then %}
    underscores_in_headers {* http.underscores_in_headers *};
    {%end%}

    lua_socket_log_errors off;

    resolver {% for _, dns_addr in ipairs(dns_resolver or {}) do %} {*dns_addr*} {% end %} valid={*dns_resolver_valid*};
    resolver_timeout {*resolver_timeout*};

    lua_http10_buffering off;

    lua_regex_match_limit 100000;
    lua_regex_cache_max_entries 8192;

    {% if http.enable_access_log == false then %}
    access_log off;
    {% else %}
    log_format main escape={* http.access_log_format_escape *} '{* http.access_log_format *}';

    access_log {* http.access_log *} main buffer=16384 flush=3;
    {% end %}
    open_file_cache  max=1000 inactive=60;
    client_max_body_size {* http.client_max_body_size *};
    keepalive_timeout {* http.keepalive_timeout *};
    client_header_timeout {* http.client_header_timeout *};
    client_body_timeout {* http.client_body_timeout *};
    send_timeout {* http.send_timeout *};

    server_tokens off;

    include mime.types;
    charset utf-8;

    {% if real_ip_header then %}
    real_ip_header {* real_ip_header *};
    {% print("\nDeprecated: apisix.real_ip_header has been moved to nginx_config.http.real_ip_header. apisix.real_ip_header will be removed in the future version. Please use nginx_config.http.real_ip_header first.\n\n") %}
    {% elseif http.real_ip_header then %}
    real_ip_header {* http.real_ip_header *};
    {% end %}

    {% if real_ip_from then %}
    {% print("\nDeprecated: apisix.real_ip_from has been moved to nginx_config.http.real_ip_from. apisix.real_ip_from will be removed in the future version. Please use nginx_config.http.real_ip_from first.\n\n") %}
    {% for _, real_ip in ipairs(real_ip_from) do %}
    set_real_ip_from {*real_ip*};
    {% end %}
    {% elseif http.real_ip_from then %}
    {% for _, real_ip in ipairs(http.real_ip_from) do %}
    set_real_ip_from {*real_ip*};
    {% end %}
    {% end %}

    # http configuration snippet starts
    {% if http_configuration_snippet then %}
    {* http_configuration_snippet *}
    {% end %}
    # http configuration snippet ends

    upstream apisix_backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            apisix.http_balancer_phase()
        }

        keepalive 320;
    }

    init_by_lua_block {
        require "resty.core"
        apisix = require("apisix")

        local dns_resolver = { {% for _, dns_addr in ipairs(dns_resolver or {}) do %} "{*dns_addr*}", {% end %} }
        local args = {
            dns_resolver = dns_resolver,
        }
        apisix.http_init(args)
    }

    init_worker_by_lua_block {
        apisix.http_init_worker()
    }

    {% if enable_control then %}
    server {
        listen {* control_server_addr *};

        access_log off;

        location / {
            content_by_lua_block {
                apisix.http_control()
            }
        }
    }
    {% end %}

    {% if enable_admin and port_admin then %}
    server {
        {%if https_admin then%}
        listen {* port_admin *} ssl;

        ssl_certificate      {* admin_api_mtls.admin_ssl_cert *};
        ssl_certificate_key  {* admin_api_mtls.admin_ssl_cert_key *};
        {%if admin_api_mtls.admin_ssl_ca_cert and admin_api_mtls.admin_ssl_ca_cert ~= "" then%}
        ssl_verify_client on;
        ssl_client_certificate {* admin_api_mtls.admin_ssl_ca_cert *};
        {% end %}

        ssl_session_cache    shared:SSL:20m;
        ssl_protocols {* ssl.ssl_protocols *};
        ssl_ciphers {* ssl.ssl_ciphers *};
        ssl_prefer_server_ciphers on;
        {% if ssl.ssl_session_tickets then %}
        ssl_session_tickets on;
        {% else %}
        ssl_session_tickets off;
        {% end %}

        {% else %}
        listen {* port_admin *};
        {%end%}
        log_not_found off;

        # admin configuration snippet starts
        {% if http_admin_configuration_snippet then %}
        {* http_admin_configuration_snippet *}
        {% end %}
        # admin configuration snippet ends

        set $upstream_scheme             'http';
        set $upstream_host               $host;
        set $upstream_uri                '';

        location /apisix/admin {
            {%if allow_admin then%}
                {% for _, allow_ip in ipairs(allow_admin) do %}
                allow {*allow_ip*};
                {% end %}
                deny all;
            {%else%}
                allow all;
            {%end%}

            content_by_lua_block {
                apisix.http_admin()
            }
        }

        location /apisix/dashboard {
            {%if allow_admin then%}
                {% for _, allow_ip in ipairs(allow_admin) do %}
                allow {*allow_ip*};
                {% end %}
                deny all;
            {%else%}
                allow all;
            {%end%}

            alias dashboard/;

            try_files $uri $uri/index.html /index.html =404;
        }

        location =/robots.txt {
            return 200 'User-agent: *\nDisallow: /';
        }
    }
    {% end %}

    server {
        {% for _, port in ipairs(node_listen) do %}
        listen {* port *} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}
        {% if ssl.enable then %}
        {% for _, port in ipairs(ssl.listen_port) do %}
        listen {* port *} ssl {% if ssl.enable_http2 then %} http2 {% end %} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}
        {% end %}
        {% if proxy_protocol and proxy_protocol.listen_http_port then %}
        listen {* proxy_protocol.listen_http_port *} proxy_protocol;
        {% end %}
        {% if proxy_protocol and proxy_protocol.listen_https_port then %}
        listen {* proxy_protocol.listen_https_port *} ssl {% if ssl.enable_http2 then %} http2 {% end %} proxy_protocol;
        {% end %}

        {% if enable_ipv6 then %}
        {% for _, port in ipairs(node_listen) do %}
        listen [::]:{* port *} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}
        {% if ssl.enable then %}
        {% for _, port in ipairs(ssl.listen_port) do %}
        listen [::]:{* port *} ssl {% if ssl.enable_http2 then %} http2 {% end %} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}
        {% end %}
        {% end %} {% -- if enable_ipv6 %}

        {% if ssl.enable then %}
        ssl_certificate      {* ssl.ssl_cert *};
        ssl_certificate_key  {* ssl.ssl_cert_key *};
        ssl_session_cache    shared:SSL:20m;
        ssl_session_timeout 10m;

        {% if ssl.ssl_trusted_certificate ~= nil then %}
        lua_ssl_trusted_certificate {* ssl.ssl_trusted_certificate *};
        {% end %}

        ssl_protocols {* ssl.ssl_protocols *};
        ssl_ciphers {* ssl.ssl_ciphers *};
        ssl_prefer_server_ciphers on;
        {% if ssl.ssl_session_tickets then %}
        ssl_session_tickets on;
        {% else %}
        ssl_session_tickets off;
        {% end %}
        {% end %}

        # http server configuration snippet starts
        {% if http_server_configuration_snippet then %}
        {* http_server_configuration_snippet *}
        {% end %}
        # http server configuration snippet ends

        set $upstream_scheme             'http';
        set $upstream_host               $host;
        set $upstream_uri                '';

        {% if with_module_status then %}
        location = /apisix/nginx_status {
            allow 127.0.0.0/24;
            deny all;
            access_log off;
            stub_status;
        }
        {% end %}

        {% if enable_admin and not port_admin then %}
        location /apisix/admin {
            {%if allow_admin then%}
                {% for _, allow_ip in ipairs(allow_admin) do %}
                allow {*allow_ip*};
                {% end %}
                deny all;
            {%else%}
                allow all;
            {%end%}

            content_by_lua_block {
                apisix.http_admin()
            }
        }

        location /apisix/dashboard {
            {%if allow_admin then%}
                {% for _, allow_ip in ipairs(allow_admin) do %}
                allow {*allow_ip*};
                {% end %}
                deny all;
            {%else%}
                allow all;
            {%end%}

            alias dashboard/;

            try_files $uri $uri/index.html /index.html =404;
        }
        {% end %}

        {% if ssl.enable then %}
        ssl_certificate_by_lua_block {
            apisix.http_ssl_phase()
        }
        {% end %}

        location / {
            set $upstream_mirror_host        '';
            set $upstream_upgrade            '';
            set $upstream_connection         '';

            access_by_lua_block {
                apisix.http_access_phase()
            }

            proxy_http_version 1.1;
            proxy_set_header   Host              $upstream_host;
            proxy_set_header   Upgrade           $upstream_upgrade;
            proxy_set_header   Connection        $upstream_connection;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_pass_header  Date;

            ### the following x-forwarded-* headers is to send to upstream server

            set $var_x_forwarded_for        $remote_addr;
            set $var_x_forwarded_proto      $scheme;
            set $var_x_forwarded_host       $host;
            set $var_x_forwarded_port       $server_port;

            if ($http_x_forwarded_for != "") {
                set $var_x_forwarded_for "${http_x_forwarded_for}, ${realip_remote_addr}";
            }
            if ($http_x_forwarded_proto != "") {
                set $var_x_forwarded_proto $http_x_forwarded_proto;
            }
            if ($http_x_forwarded_host != "") {
                set $var_x_forwarded_host $http_x_forwarded_host;
            }
            if ($http_x_forwarded_port != "") {
                set $var_x_forwarded_port $http_x_forwarded_port;
            }

            proxy_set_header   X-Forwarded-For      $var_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto    $var_x_forwarded_proto;
            proxy_set_header   X-Forwarded-Host     $var_x_forwarded_host;
            proxy_set_header   X-Forwarded-Port     $var_x_forwarded_port;

            {% if enabled_plugins["proxy-cache"] then %}
            ###  the following configuration is to cache response content from upstream server

            set $upstream_cache_zone            off;
            set $upstream_cache_key             '';
            set $upstream_cache_bypass          '';
            set $upstream_no_cache              '';
            set $upstream_hdr_expires           '';
            set $upstream_hdr_cache_control     '';

            proxy_cache                         $upstream_cache_zone;
            proxy_cache_valid                   any {% if proxy_cache.cache_ttl then %} {* proxy_cache.cache_ttl *} {% else %} 10s {% end %};
            proxy_cache_min_uses                1;
            proxy_cache_methods                 GET HEAD;
            proxy_cache_lock_timeout            5s;
            proxy_cache_use_stale               off;
            proxy_cache_key                     $upstream_cache_key;
            proxy_no_cache                      $upstream_no_cache;
            proxy_cache_bypass                  $upstream_cache_bypass;

            proxy_hide_header                   Cache-Control;
            proxy_hide_header                   Expires;
            add_header      Cache-Control       $upstream_hdr_cache_control;
            add_header      Expires             $upstream_hdr_expires;
            add_header      Apisix-Cache-Status $upstream_cache_status always;
            {% end %}

            proxy_pass      $upstream_scheme://apisix_backend$upstream_uri;

            {% if enabled_plugins["proxy-mirror"] then %}
            mirror          /proxy_mirror;
            {% end %}

            header_filter_by_lua_block {
                apisix.http_header_filter_phase()
            }

            body_filter_by_lua_block {
                apisix.http_body_filter_phase()
            }

            log_by_lua_block {
                apisix.http_log_phase()
            }
        }

        location @grpc_pass {

            access_by_lua_block {
                apisix.grpc_access_phase()
            }

            grpc_set_header   Content-Type application/grpc;
            grpc_socket_keepalive on;
            grpc_pass         grpc://apisix_backend;

            header_filter_by_lua_block {
                apisix.http_header_filter_phase()
            }

            body_filter_by_lua_block {
                apisix.http_body_filter_phase()
            }

            log_by_lua_block {
                apisix.http_log_phase()
            }
        }

        {% if enabled_plugins["proxy-mirror"] then %}
        location = /proxy_mirror {
            internal;

            if ($upstream_mirror_host = "") {
                return 200;
            }

            proxy_http_version 1.1;
            proxy_set_header Host $upstream_host;
            proxy_pass $upstream_mirror_host$request_uri;
        }
        {% end %}
    }
    # http end configuration snippet starts
    {% if http_end_configuration_snippet then %}
    {* http_end_configuration_snippet *}
    {% end %}
    # http end configuration snippet ends
}
]=]
