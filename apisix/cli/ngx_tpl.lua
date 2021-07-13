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
{% if user and user ~= '' then %}
user {* user *};
{% end %}
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
env PATH; # for searching external plugin runner's binary

{% if envs then %}
{% for _, name in ipairs(envs) do %}
env {*name*};
{% end %}
{% end %}

{% if stream_proxy then %}
stream {
    lua_package_path  "{*extra_lua_path*}$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;]=]
                      .. [=[{*apisix_lua_home*}/?.lua;{*apisix_lua_home*}/?/init.lua;;{*lua_path*};";
    lua_package_cpath "{*extra_lua_cpath*}$prefix/deps/lib64/lua/5.1/?.so;]=]
                      .. [=[$prefix/deps/lib/lua/5.1/?.so;;]=]
                      .. [=[{*lua_cpath*};";
    lua_socket_log_errors off;

    lua_shared_dict lrucache-lock-stream {* stream.lua_shared_dict["lrucache-lock-stream"] *};

    resolver {% for _, dns_addr in ipairs(dns_resolver or {}) do %} {*dns_addr*} {% end %} {% if dns_resolver_valid then %} valid={*dns_resolver_valid*}{% end %};
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
        local dns_resolver = { {% for _, dns_addr in ipairs(dns_resolver or {}) do %} "{*dns_addr*}", {% end %} }
        local args = {
            dns_resolver = dns_resolver,
        }
        apisix.stream_init(args)
    }

    init_worker_by_lua_block {
        apisix.stream_init_worker()
    }

    server {
        {% for _, item in ipairs(stream_proxy.tcp or {}) do %}
        listen {*item.addr*} {% if item.tls then %} ssl {% end %} {% if enable_reuseport then %} reuseport {% end %} {% if proxy_protocol and proxy_protocol.enable_tcp_pp then %} proxy_protocol {% end %};
        {% end %}
        {% for _, addr in ipairs(stream_proxy.udp or {}) do %}
        listen {*addr*} udp {% if enable_reuseport then %} reuseport {% end %};
        {% end %}

        {% if tcp_enable_ssl then %}
        ssl_certificate      {* ssl.ssl_cert *};
        ssl_certificate_key  {* ssl.ssl_cert_key *};

        ssl_certificate_by_lua_block {
            apisix.stream_ssl_phase()
        }
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
    # put extra_lua_path in front of the builtin path
    # so user can override the source code
    lua_package_path  "{*extra_lua_path*}$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;]=]
                       .. [=[{*apisix_lua_home*}/?.lua;{*apisix_lua_home*}/?/init.lua;;{*lua_path*};";
    lua_package_cpath "{*extra_lua_cpath*}$prefix/deps/lib64/lua/5.1/?.so;]=]
                      .. [=[$prefix/deps/lib/lua/5.1/?.so;;]=]
                      .. [=[{*lua_cpath*};";

    lua_shared_dict internal-status {* http.lua_shared_dict["internal-status"] *};
    lua_shared_dict plugin-limit-req {* http.lua_shared_dict["plugin-limit-req"] *};
    lua_shared_dict plugin-limit-count {* http.lua_shared_dict["plugin-limit-count"] *};
    lua_shared_dict prometheus-metrics {* http.lua_shared_dict["prometheus-metrics"] *};
    lua_shared_dict plugin-limit-conn {* http.lua_shared_dict["plugin-limit-conn"] *};
    lua_shared_dict upstream-healthcheck {* http.lua_shared_dict["upstream-healthcheck"] *};
    lua_shared_dict worker-events {* http.lua_shared_dict["worker-events"] *};
    lua_shared_dict lrucache-lock {* http.lua_shared_dict["lrucache-lock"] *};
    lua_shared_dict balancer-ewma {* http.lua_shared_dict["balancer-ewma"] *};
    lua_shared_dict balancer-ewma-locks {* http.lua_shared_dict["balancer-ewma-locks"] *};
    lua_shared_dict balancer-ewma-last-touched-at {* http.lua_shared_dict["balancer-ewma-last-touched-at"] *};
    lua_shared_dict plugin-limit-count-redis-cluster-slot-lock {* http.lua_shared_dict["plugin-limit-count-redis-cluster-slot-lock"] *};
    lua_shared_dict tracing_buffer {* http.lua_shared_dict.tracing_buffer *}; # plugin: skywalking
    lua_shared_dict plugin-api-breaker {* http.lua_shared_dict["plugin-api-breaker"] *};
    lua_shared_dict etcd-cluster-health-check {* http.lua_shared_dict["etcd-cluster-health-check"] *}; # etcd health check

    # for openid-connect and authz-keycloak plugin
    lua_shared_dict discovery {* http.lua_shared_dict["discovery"] *}; # cache for discovery metadata documents

    # for openid-connect plugin
    lua_shared_dict jwks {* http.lua_shared_dict["jwks"] *}; # cache for JWKs
    lua_shared_dict introspection {* http.lua_shared_dict["introspection"] *}; # cache for JWT verification results

    # for authz-keycloak
    lua_shared_dict access-tokens {* http.lua_shared_dict["access-tokens"] *}; # cache for service account access tokens

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

    resolver {% for _, dns_addr in ipairs(dns_resolver or {}) do %} {*dns_addr*} {% end %} {% if dns_resolver_valid then %} valid={*dns_resolver_valid*}{% end %};
    resolver_timeout {*resolver_timeout*};

    lua_http10_buffering off;

    lua_regex_match_limit 100000;
    lua_regex_cache_max_entries 8192;

    {% if http.enable_access_log == false then %}
    access_log off;
    {% else %}
    uninitialized_variable_warn off;
    {% for _, log_item in ipairs(http.access_log) do %}
    log_format {*log_item.log_format_name*} {% if log_item.log_format_escape then %} escape={* http.access_log_format_escape *}{% else %} escape=default{% end %} '{* log_item.log_format *}';
    {% if log_item.log_type == "local" then %}
    access_log {* log_item.log_path *} {* log_item.log_format_name *} buffer={*log_item.log_buffer*} flush={*log_item.log_flush*};
    {% elseif log_item.log_type == "syslog" then %}
    access_log syslog:server={* log_item.log_server *}:{* log_item.log_port *},{% if log_item.log_nohostname then %}nohostname,{% end %}{% if log_item.log_severity then %}severity={* log_item.log_severity *},{% end %}{% if log_item.log_facility then %}facility={* log_item.log_facility *},{% end %}tag={% if log_item.log_tag then %}{*log_item.log_tag*}{% else %}apisix{% end %} {* log_item.log_format_name *};

    {% end %}

    {% if use_apisix_openresty then %}
    apisix_delay_client_max_body_check on;
    {% end %}

    {% end %}

    open_file_cache  max=1000 inactive=60;
    client_max_body_size {* http.client_max_body_size *};
    keepalive_timeout {* http.keepalive_timeout *};
    client_header_timeout {* http.client_header_timeout *};
    client_body_timeout {* http.client_body_timeout *};
    send_timeout {* http.send_timeout *};
    variables_hash_max_size {* http.variables_hash_max_size *};

    server_tokens off;

    include mime.types;
    charset {* http.charset *};

    # error_page
    error_page 500 @50x.html;

    {% if real_ip_header then %}
    real_ip_header {* real_ip_header *};
    {% print("\nDeprecated: apisix.real_ip_header has been moved to nginx_config.http.real_ip_header. apisix.real_ip_header will be removed in the future version. Please use nginx_config.http.real_ip_header first.\n\n") %}
    {% elseif http.real_ip_header then %}
    real_ip_header {* http.real_ip_header *};
    {% end %}

    {% if http.real_ip_recursive then %}
    real_ip_recursive {* http.real_ip_recursive *};
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

    {% if ssl.ssl_trusted_certificate ~= nil then %}
    lua_ssl_trusted_certificate {* ssl.ssl_trusted_certificate *};
    {% end %}

    # http configuration snippet starts
    {% if http_configuration_snippet then %}
    {* http_configuration_snippet *}
    {% end %}
    # http configuration snippet ends

    upstream apisix_backend {
        server 0.0.0.1;

        {% if use_apisix_openresty then %}
        keepalive {* http.upstream.keepalive *};
        keepalive_requests {* http.upstream.keepalive_requests *};
        keepalive_timeout {* http.upstream.keepalive_timeout *};
        # we put the static configuration above so that we can override it in the Lua code

        balancer_by_lua_block {
            apisix.http_balancer_phase()
        }
        {% else %}
        balancer_by_lua_block {
            apisix.http_balancer_phase()
        }

        keepalive {* http.upstream.keepalive *};
        keepalive_requests {* http.upstream.keepalive_requests *};
        keepalive_timeout {* http.upstream.keepalive_timeout *};
        {% end %}
    }

    {% if enabled_plugins["dubbo-proxy"] then %}
    upstream apisix_dubbo_backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            apisix.http_balancer_phase()
        }

        # dynamical keepalive doesn't work with dubbo as the connection here
        # is managed by ngx_multi_upstream_module
        multi {* dubbo_upstream_multiplex_count *};
        keepalive {* http.upstream.keepalive *};
        keepalive_requests {* http.upstream.keepalive_requests *};
        keepalive_timeout {* http.upstream.keepalive_timeout *};
    }
    {% end %}

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

    {% if not use_openresty_1_17 then %}
    exit_worker_by_lua_block {
        apisix.http_exit_worker()
    }
    {% end %}

    {% if enable_control then %}
    server {
        listen {* control_server_addr *};

        access_log off;

        location / {
            content_by_lua_block {
                apisix.http_control()
            }
        }

        location @50x.html {
            set $from_error_page 'true';
            try_files /50x.html $uri;
        }
    }
    {% end %}

    {% if enabled_plugins["prometheus"] and prometheus_server_addr then %}
    server {
        listen {* prometheus_server_addr *};

        access_log off;

        location / {
            content_by_lua_block {
                local prometheus = require("apisix.plugins.prometheus")
                prometheus.export_metrics()
            }
        }

        {% if with_module_status then %}
        location = /apisix/nginx_status {
            allow 127.0.0.0/24;
            deny all;
            stub_status;
        }
        {% end %}
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
        set $upstream_host               $http_host;
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

        location @50x.html {
            set $from_error_page 'true';
            try_files /50x.html $uri;
        }
    }
    {% end %}

    server {
        {% for _, item in ipairs(node_listen) do %}
        listen {* item.port *} default_server {% if enable_reuseport then %} reuseport {% end %} {% if item.enable_http2 then %} http2 {% end %};
        {% end %}
        {% if ssl.enable then %}
        {% for _, port in ipairs(ssl.listen_port) do %}
        listen {* port *} ssl default_server {% if ssl.enable_http2 then %} http2 {% end %} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}
        {% end %}
        {% if proxy_protocol and proxy_protocol.listen_http_port then %}
        listen {* proxy_protocol.listen_http_port *} default_server proxy_protocol;
        {% end %}
        {% if proxy_protocol and proxy_protocol.listen_https_port then %}
        listen {* proxy_protocol.listen_https_port *} ssl default_server {% if ssl.enable_http2 then %} http2 {% end %} proxy_protocol;
        {% end %}

        {% if enable_ipv6 then %}
        {% for _, item in ipairs(node_listen) do %}
        listen [::]:{* item.port *} default_server {% if enable_reuseport then %} reuseport {% end %} {% if item.enable_http2 then %} http2 {% end %};
        {% end %}
        {% if ssl.enable then %}
        {% for _, port in ipairs(ssl.listen_port) do %}
        listen [::]:{* port *} ssl default_server {% if ssl.enable_http2 then %} http2 {% end %} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}
        {% end %}
        {% end %} {% -- if enable_ipv6 %}

        server_name _;

        {% if ssl.enable then %}
        ssl_certificate      {* ssl.ssl_cert *};
        ssl_certificate_key  {* ssl.ssl_cert_key *};
        ssl_session_cache    shared:SSL:20m;
        ssl_session_timeout 10m;

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
            set $upstream_scheme             'http';
            set $upstream_host               $http_host;
            set $upstream_uri                '';

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
        {% end %}

        {% if ssl.enable then %}
        ssl_certificate_by_lua_block {
            apisix.http_ssl_phase()
        }
        {% end %}

        {% if http.proxy_ssl_server_name then %}
        proxy_ssl_name $upstream_host;
        proxy_ssl_server_name on;
        {% end %}

        location / {
            set $upstream_mirror_host        '';
            set $upstream_upgrade            '';
            set $upstream_connection         '';

            set $upstream_scheme             'http';
            set $upstream_host               $http_host;
            set $upstream_uri                '';
            set $ctx_ref                     '';
            set $from_error_page             '';

            {% if enabled_plugins["dubbo-proxy"] then %}
            set $dubbo_service_name          '';
            set $dubbo_service_version       '';
            set $dubbo_method                '';
            {% end %}

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

            proxy_cache                         $upstream_cache_zone;
            proxy_cache_valid                   any {% if proxy_cache.cache_ttl then %} {* proxy_cache.cache_ttl *} {% else %} 10s {% end %};
            proxy_cache_min_uses                1;
            proxy_cache_methods                 GET HEAD;
            proxy_cache_lock_timeout            5s;
            proxy_cache_use_stale               off;
            proxy_cache_key                     $upstream_cache_key;
            proxy_no_cache                      $upstream_no_cache;
            proxy_cache_bypass                  $upstream_cache_bypass;

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
            grpc_pass         $upstream_scheme://apisix_backend;

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

        {% if enabled_plugins["dubbo-proxy"] then %}
        location @dubbo_pass {
            access_by_lua_block {
                apisix.dubbo_access_phase()
            }

            dubbo_pass_all_headers on;
            dubbo_pass_body on;
            dubbo_pass $dubbo_service_name $dubbo_service_version $dubbo_method apisix_dubbo_backend;

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
        {% end %}

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

        location @50x.html {
            set $from_error_page 'true';
            try_files /50x.html $uri;
            header_filter_by_lua_block {
                apisix.http_header_filter_phase()
            }

            log_by_lua_block {
                apisix.http_log_phase()
            }
        }
    }
    # http end configuration snippet starts
    {% if http_end_configuration_snippet then %}
    {* http_end_configuration_snippet *}
    {% end %}
    # http end configuration snippet ends
}
]=]
