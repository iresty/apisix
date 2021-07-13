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
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1:1053"
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
routes:
  -
    id: 1
    uris:
        - /hello
    upstream_id: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: default port to 53
--- log_level: debug
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1"
--- apisix_yaml
upstreams:
    - service_name: sd.test.local
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_code: 503
--- error_log
connect to 127.0.0.1:53



=== TEST 2: A
--- apisix_yaml
upstreams:
    - service_name: "sd.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":1,"127.0.0.2:1980":1|"127.0.0.2:1980":1,"127.0.0.1:1980":1)\}/
--- response_body
hello world



=== TEST 3: AAAA
--- listen_ipv6
--- apisix_yaml
upstreams:
    - service_name: "ipv6.sd.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- response_body
hello world



=== TEST 4: prefer A to AAAA
--- listen_ipv6
--- apisix_yaml
upstreams:
    - service_name: "mix.sd.test.local:1980"
      discovery_type: dns
      type: roundrobin
      id: 1
--- response_body
hello world



=== TEST 5: no /etc/hosts
--- apisix_yaml
upstreams:
    - service_name: test.com
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
failed to query the DNS server
--- error_code: 503



=== TEST 6: no /etc/resolv.conf
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    enable_resolv_search_option: false
discovery:                        # service discovery center
    dns:
        servers:
            - "127.0.0.1:1053"
--- apisix_yaml
upstreams:
    - service_name: apisix
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
failed to query the DNS server
--- error_code: 503



=== TEST 7: bad discovery configuration
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    enable_resolv_search_option: false
discovery:                        # service discovery center
    dns:
        servers: "127.0.0.1:1053"
--- apisix_yaml
upstreams:
    - service_name: apisix
      discovery_type: dns
      type: roundrobin
      id: 1
--- error_log
invalid dns discovery configuration
--- error_code: 500



=== TEST 8: SRV
--- apisix_yaml
upstreams:
    - service_name: "srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":20|"127.0.0.2:1980":20,"127.0.0.1:1980":60)\}/
--- response_body
hello world



=== TEST 9: SRV (RFC 2782 style)
--- apisix_yaml
upstreams:
    - service_name: "_sip._tcp.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":20|"127.0.0.2:1980":20,"127.0.0.1:1980":60)\}/
--- response_body
hello world



=== TEST 10: SRV (different port)
--- apisix_yaml
upstreams:
    - service_name: "port.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1981":20|"127.0.0.2:1981":20,"127.0.0.1:1980":60)\}/
--- response_body
hello world



=== TEST 11: SRV (zero weight)
--- apisix_yaml
upstreams:
    - service_name: "zero-weight.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{("127.0.0.1:1980":60,"127.0.0.2:1980":1|"127.0.0.2:1980":1,"127.0.0.1:1980":60)\}/
--- response_body
hello world



=== TEST 12: SRV (split weight)
--- apisix_yaml
upstreams:
    - service_name: "split-weight.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- grep_error_log eval
qr/upstream nodes: \{[^}]+\}/
--- grep_error_log_out eval
qr/upstream nodes: \{(,?"127.0.0.(1:1980":200|3:1980":1|4:1980":1)){3}\}/
--- response_body
hello world



=== TEST 13: SRV (priority)
--- apisix_yaml
upstreams:
    - service_name: "priority.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- response_body
hello world
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1980



=== TEST 14: Stream Discovery
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    enable_resolv_search_option: false
    stream_proxy:
        tcp:
         - addr: 1985
discovery:
    dns:
        servers:
         - "127.0.0.1:1053"
--- apisix_yaml
stream_routes:
    - id: 1
      server_port: 1985
      upstream_id: 1
upstreams:
    - service_name: "zero-weight.srv.test.local"
      discovery_type: dns
      type: roundrobin
      id: 1
--- stream_enable
--- stream_request eval
"\47\45\54\20\2f\68\65\6c\6c\6f\20\48\54\54\50\2f\31\2e\31\0d\0a\48\6f\73\74\3a\20\31\32\37\2e\30\2e\30\2e\31\3a\31\39\38\35\0d\0a\0d\0a"
--- stream_response
hello world
--- no_error_log
[error]
