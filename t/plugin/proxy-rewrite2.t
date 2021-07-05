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
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: rewrite scheme but the node doesn't have port
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    upstream_id: 1
    plugins:
        proxy-rewrite:
            scheme: "https"
  -
    id: 2
    uri: /hello_chunked
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1": 1
    type: roundrobin
#END
--- error_code: 503
--- error_log
Can't detect upstream's scheme



=== TEST 2: access $upstream_uri before proxy-rewrite
--- apisix_yaml
global_rules:
  -
    id: 1
    plugins:
      serverless-pre-function:
        phase: rewrite
        functions:
            - "return function() ngx.log(ngx.WARN, 'serverless [', ngx.var.upstream_uri, ']') end"
routes:
  -
    id: 1
    uri: /hello
    plugins:
        proxy-rewrite:
            uri: "/plugin_proxy_rewrite"
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- error_log
serverless []
--- response_body
uri: /plugin_proxy_rewrite
host: localhost
scheme: http



=== TEST 3: default X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- response_headers
X-Forwarded-Proto: http



=== TEST 4: pass X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Proto: https
--- response_headers
X-Forwarded-Proto: https



=== TEST 5: customize X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    plugins:
        proxy-rewrite:
            headers:
                X-Forwarded-Proto: https
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Proto: grpc
--- response_headers
X-Forwarded-Proto: https

=== TEST 6: rewrite HTTP method (GET to PUT)
--- request
GET /hello
--- response_body
uri: /plugin_proxy_rewrite
host: localhost
scheme: http
method: GET
--- error_log eval
qr/changed HTTP method from GET to PUT/