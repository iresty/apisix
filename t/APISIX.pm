#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
package t::APISIX;

use lib 'lib';
use Cwd qw(cwd);
use Test::Nginx::Socket::Lua::Stream -Base;

repeat_each(1);
log_level('info');
no_long_string();
no_shuffle();
no_root_location(); # avoid generated duplicate 'location /'
worker_connections(128);

my $apisix_home = $ENV{APISIX_HOME} || cwd();

sub read_file($) {
    my $infile = shift;
    open my $in, "$apisix_home/$infile"
        or die "cannot open $infile for reading: $!";
    my $data = do { local $/; <$in> };
    close $in;
    $data;
}

sub local_dns_resolver() {
    open my $in, "/etc/resolv.conf" or die "cannot open /etc/resolv.conf";
    my @lines =  <$in>;
    my @dns_addrs = ();
    foreach my $line (@lines){
        $line =~ m/^nameserver\s+(\d+[.]\d+[.]\d+[.]\d+)\s*$/;
        if ($1) {
            push(@dns_addrs, $1);
        }
    }
    close($in);
    return @dns_addrs
}


my $dns_addrs_str = "";
my $dns_addrs_tbl_str = "";
my $enable_local_dns = $ENV{"ENABLE_LOCAL_DNS"};
if ($enable_local_dns) {
    my @dns_addrs = local_dns_resolver();
    $dns_addrs_tbl_str = "{";
    foreach my $addr (@dns_addrs){
        $dns_addrs_str = "$dns_addrs_str $addr";
        $dns_addrs_tbl_str = "$dns_addrs_tbl_str\"$addr\", ";
    }
    $dns_addrs_tbl_str = "$dns_addrs_tbl_str}";
} else {
    $dns_addrs_str = "8.8.8.8 114.114.114.114";
    $dns_addrs_tbl_str = "{\"8.8.8.8\", \"114.114.114.114\"}";
}


my $default_yaml_config = read_file("conf/config-default.yaml");
# enable example-plugin as some tests require it
$default_yaml_config =~ s/# - example-plugin/- example-plugin/;

my $user_yaml_config = read_file("conf/config.yaml");
my $ssl_crt = read_file("t/certs/apisix.crt");
my $ssl_key = read_file("t/certs/apisix.key");
my $ssl_ecc_crt = read_file("t/certs/apisix_ecc.crt");
my $ssl_ecc_key = read_file("t/certs/apisix_ecc.key");
my $test2_crt = read_file("t/certs/test2.crt");
my $test2_key = read_file("t/certs/test2.key");
$user_yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  stream_proxy:
    tcp:
      - 9100
  admin_key: null
_EOC_

my $etcd_enable_auth = $ENV{"ETCD_ENABLE_AUTH"} || "false";

if ($etcd_enable_auth eq "true") {
    $user_yaml_config .= <<_EOC_;
etcd:
  user: root
  password: 5tHkHhYkjr6cQY
_EOC_
}

my $custom_hmac_auth = $ENV{"CUSTOM_HMAC_AUTH"} || "false";
if ($custom_hmac_auth eq "true") {
    $user_yaml_config .= <<_EOC_;
plugin_attr:
  hmac-auth:
    signature_key: X-APISIX-HMAC-SIGNATURE
    algorithm_key: X-APISIX-HMAC-ALGORITHM
    date_key: X-APISIX-DATE
    access_key: X-APISIX-HMAC-ACCESS-KEY
    signed_headers_key: X-APISIX-HMAC-SIGNED-HEADERS
_EOC_
}


my $profile = $ENV{"APISIX_PROFILE"};


my $apisix_file;
my $debug_file;
my $config_file;
if ($profile) {
    $apisix_file = "apisix-$profile.yaml";
    $debug_file = "debug-$profile.yaml";
    $config_file = "config-$profile.yaml";
} else {
    $apisix_file = "apisix.yaml";
    $debug_file = "debug.yaml";
    $config_file = "config.yaml";
}


add_block_preprocessor(sub {
    my ($block) = @_;
    my $wait_etcd_sync = $block->wait_etcd_sync // 0.1;

    my $lua_deps_path = <<_EOC_;
    lua_package_path "$apisix_home/?.lua;$apisix_home/?/init.lua;$apisix_home/deps/share/lua/5.1/?/init.lua;$apisix_home/deps/share/lua/5.1/?.lua;$apisix_home/apisix/?.lua;$apisix_home/t/?.lua;;";
    lua_package_cpath "$apisix_home/?.so;$apisix_home/deps/lib/lua/5.1/?.so;$apisix_home/deps/lib64/lua/5.1/?.so;;";
_EOC_

    my $main_config = $block->main_config // <<_EOC_;
worker_rlimit_core  500M;
env ENABLE_ETCD_AUTH;
env APISIX_PROFILE;
env TEST_NGINX_HTML_DIR;
_EOC_

    # set default `timeout` to 5sec
    my $timeout = $block->timeout // 5;
    $block->set_value("timeout", $timeout);

    $block->set_value("main_config", $main_config);

    my $stream_enable = $block->stream_enable;
    my $stream_config = $block->stream_config // <<_EOC_;
    $lua_deps_path
    lua_socket_log_errors off;

    lua_shared_dict lrucache-lock-stream   10m;
    lua_shared_dict worker-events-stream   10m;
    lua_shared_dict upstream-healthcheck-stream 10m;

    upstream apisix_backend {
        server 127.0.0.1:1900;
        balancer_by_lua_block {
            apisix.stream_balancer_phase()
        }
    }

    init_by_lua_block {
        if os.getenv("APISIX_ENABLE_LUACOV") == "1" then
            require("luacov.runner")("t/apisix.luacov")
            jit.off()
        end

        require "resty.core"

        apisix = require("apisix")
        apisix.stream_init()
    }

    init_worker_by_lua_block {
        apisix.stream_init_worker()
    }


    # fake server, only for test
    server {
        listen 1995;

        content_by_lua_block {
            local sock = ngx.req.socket()
            local data = sock:receive("1")
            ngx.say("hello world")
        }
    }
_EOC_

    if (defined $stream_enable) {
        $block->set_value("stream_config", $stream_config);
    }

    my $stream_server_config = $block->stream_server_config // <<_EOC_;
    preread_by_lua_block {
        -- wait for etcd sync
        ngx.sleep($wait_etcd_sync)
        apisix.stream_preread_phase()
    }

    proxy_pass apisix_backend;

    log_by_lua_block {
        apisix.stream_log_phase()
    }
_EOC_

    if (defined $stream_enable) {
        $block->set_value("stream_server_config", $stream_server_config);
    }

    my $init_by_lua_block = $block->init_by_lua_block // <<_EOC_;
    if os.getenv("APISIX_ENABLE_LUACOV") == "1" then
        require("luacov.runner")("t/apisix.luacov")
        jit.off()
    end

    require "resty.core"

    apisix = require("apisix")
    local args = {
        dns_resolver = $dns_addrs_tbl_str,
    }
    apisix.http_init(args)
_EOC_

    my $http_config = $block->http_config // '';
    $http_config .= <<_EOC_;
    $lua_deps_path

    lua_shared_dict plugin-limit-req     10m;
    lua_shared_dict plugin-limit-count   10m;
    lua_shared_dict plugin-limit-conn    10m;
    lua_shared_dict prometheus-metrics   10m;
    lua_shared_dict internal_status      10m;
    lua_shared_dict upstream-healthcheck 32m;
    lua_shared_dict worker-events        10m;
    lua_shared_dict lrucache-lock        10m;
    lua_shared_dict skywalking-tracing-buffer    100m;
    lua_shared_dict balancer_ewma         1m;
    lua_shared_dict balancer_ewma_locks   1m;
    lua_shared_dict balancer_ewma_last_touched_at  1m;
    lua_shared_dict plugin-limit-count-redis-cluster-slot-lock 1m;
    lua_shared_dict tracing_buffer       10m;    # plugin skywalking
    lua_shared_dict plugin-api-breaker   10m;
    lua_capture_error_log                 1m;    # plugin error-log-logger

    resolver $dns_addrs_str;
    resolver_timeout 5;

    underscores_in_headers on;
    lua_socket_log_errors off;

    upstream apisix_backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            apisix.http_balancer_phase()
        }

        keepalive 32;
    }

    init_by_lua_block {
        $init_by_lua_block
    }

    init_worker_by_lua_block {
        require("apisix").http_init_worker()
    }

    log_format main escape=default '\$remote_addr - \$remote_user [\$time_local] \$http_host "\$request" \$status \$body_bytes_sent \$request_time "\$http_referer" "\$http_user_agent" \$upstream_addr \$upstream_status \$upstream_response_time "\$upstream_scheme://\$upstream_host\$upstream_uri"';

    # fake server, only for test
    server {
        listen 1980;
        listen 1981;
        listen 1982;
        listen 5044;

_EOC_

    my $ipv6_fake_server = "";
    if (defined $block->listen_ipv6) {
        $ipv6_fake_server = "listen \[::1\]:1980;";
    }

    $http_config .= <<_EOC_;
        $ipv6_fake_server
        server_tokens off;

        location / {
            content_by_lua_block {
                require("lib.server").go()
            }

            more_clear_headers Date;
        }

        location = /v3/auth/authenticate {
            content_by_lua_block {
                ngx.log(ngx.WARN, "etcd auth failed!")
            }
        }

        location  = /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.say([[
{"issuer":"https://samples.auth0.com/","authorization_endpoint":"https://samples.auth0.com/authorize","token_endpoint":"https://samples.auth0.com/oauth/token","device_authorization_endpoint":"https://samples.auth0.com/oauth/device/code","userinfo_endpoint":"https://samples.auth0.com/userinfo","mfa_challenge_endpoint":"https://samples.auth0.com/mfa/challenge","jwks_uri":"https://samples.auth0.com/.well-known/jwks.json","registration_endpoint":"https://samples.auth0.com/oidc/register","revocation_endpoint":"https://samples.auth0.com/oauth/revoke","scopes_supported":["openid","profile","offline_access","name","given_name","family_name","nickname","email","email_verified","picture","created_at","identities","phone","address"],"response_types_supported":["code","token","id_token","code token","code id_token","token id_token","code token id_token"],"code_challenge_methods_supported":["S256","plain"],"response_modes_supported":["query","fragment","form_post"],"subject_types_supported":["public"],"id_token_signing_alg_values_supported":["HS256","RS256"],"token_endpoint_auth_methods_supported":["client_secret_basic","client_secret_post"],"claims_supported":["aud","auth_time","created_at","email","email_verified","exp","family_name","given_name","iat","identities","iss","name","nickname","phone_number","picture","sub"],"request_uri_parameter_supported":false}
                ]])
            }
        }
    }

    server {
        listen 1983 ssl;
        ssl_certificate             cert/apisix.crt;
        ssl_certificate_key         cert/apisix.key;
        lua_ssl_trusted_certificate cert/apisix.crt;

        server_tokens off;

        location / {
            content_by_lua_block {
                require("lib.server").go()
            }

            more_clear_headers Date;
        }
    }

_EOC_

    $block->set_value("http_config", $http_config);

    my $TEST_NGINX_HTML_DIR = $ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
    my $ipv6_listen_conf = '';
    if (defined $block->listen_ipv6) {
        $ipv6_listen_conf = "listen \[::1\]:12345;"
    }

    my $config = $block->config // '';
    $config .= <<_EOC_;
        $ipv6_listen_conf

        ssl_certificate             cert/apisix.crt;
        ssl_certificate_key         cert/apisix.key;
        lua_ssl_trusted_certificate cert/apisix.crt;

        ssl_certificate_by_lua_block {
            apisix.http_ssl_phase()
        }

        set \$upstream_scheme             'http';
        set \$upstream_host               \$host;
        set \$upstream_uri                '';

        location = /apisix/nginx_status {
            allow 127.0.0.0/24;
            access_log off;
            stub_status;
        }

        location /apisix/admin {
            content_by_lua_block {
                apisix.http_admin()
            }
        }

        location /v1/ {
            content_by_lua_block {
                apisix.http_control()
            }
        }

        location / {
            set \$upstream_mirror_host        '';
            set \$upstream_upgrade            '';
            set \$upstream_connection         '';

            set \$upstream_cache_zone            off;
            set \$upstream_cache_key             '';
            set \$upstream_cache_bypass          '';
            set \$upstream_no_cache              '';
            set \$upstream_hdr_expires           '';
            set \$upstream_hdr_cache_control     '';

            proxy_cache                         \$upstream_cache_zone;
            proxy_cache_valid                   any 10s;
            proxy_cache_min_uses                1;
            proxy_cache_methods                 GET HEAD;
            proxy_cache_lock_timeout            5s;
            proxy_cache_use_stale               off;
            proxy_cache_key                     \$upstream_cache_key;
            proxy_no_cache                      \$upstream_no_cache;
            proxy_cache_bypass                  \$upstream_cache_bypass;

            proxy_hide_header                   Cache-Control;
            proxy_hide_header                   Expires;
            add_header      Cache-Control       \$upstream_hdr_cache_control;
            add_header      Expires             \$upstream_hdr_expires;
            add_header      Apisix-Cache-Status \$upstream_cache_status always;

            access_by_lua_block {
                -- wait for etcd sync
                ngx.sleep($wait_etcd_sync)
                apisix.http_access_phase()
            }

            proxy_http_version 1.1;
            proxy_set_header   Host              \$upstream_host;
            proxy_set_header   Upgrade           \$upstream_upgrade;
            proxy_set_header   Connection        \$upstream_connection;
            proxy_set_header   X-Real-IP         \$remote_addr;
            proxy_pass_header  Date;
            proxy_pass         \$upstream_scheme://apisix_backend\$upstream_uri;
            mirror             /proxy_mirror;

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

        location \@grpc_pass {
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

        location = /proxy_mirror {
            internal;

            if (\$upstream_mirror_host = "") {
                return 200;
            }

            proxy_http_version 1.1;
            proxy_set_header Host \$upstream_host;
            proxy_pass \$upstream_mirror_host\$request_uri;
        }
_EOC_

    $block->set_value("config", $config);

    my $user_apisix_yaml = $block->apisix_yaml // "";
    if ($user_apisix_yaml) {
        $user_apisix_yaml = <<_EOC_;
>>> ../conf/$apisix_file
$user_apisix_yaml
_EOC_
    }

    my $yaml_config = $block->yaml_config // $user_yaml_config;

    if ($block->extra_yaml_config) {
        $yaml_config .= $block->extra_yaml_config;
    }

    my $user_debug_config = $block->debug_config // "";

    my $user_files = $block->user_files;
    $user_files .= <<_EOC_;
>>> ../conf/$debug_file
$user_debug_config
>>> ../conf/config-default.yaml
$default_yaml_config
>>> ../conf/$config_file
$yaml_config
>>> ../conf/cert/apisix.crt
$ssl_crt
>>> ../conf/cert/apisix.key
$ssl_key
>>> ../conf/cert/apisix_ecc.crt
$ssl_ecc_crt
>>> ../conf/cert/apisix_ecc.key
$ssl_ecc_key
>>> ../conf/cert/test2.crt
$test2_crt
>>> ../conf/cert/test2.key
$test2_key
$user_apisix_yaml
_EOC_

    $block->set_value("user_files", $user_files);

    $block;
});

1;
