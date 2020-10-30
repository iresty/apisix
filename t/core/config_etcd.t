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
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: wrong etcd port
--- yaml_config
apisix:
  node_listen: 1984
etcd:
  host:
    - "http://127.0.0.1:7777"  -- wrong etcd port
  timeout: 1
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(8)
            ngx.say(body)
        }
    }
--- timeout: 12
--- request
GET /t
--- grep_error_log eval
qr{failed to fetch data from etcd: connection refused,  etcd key: .*routes}
--- grep_error_log_out eval
qr/(failed to fetch data from etcd: connection refused,  etcd key: .*routes\n){1,}/



=== TEST 2: originate TLS connection to etcd cluster without TLS configuration
--- yaml_config
apisix:
  node_listen: 1984
etcd:
  host:
    - "https://127.0.0.1:2379"
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(4)
            ngx.say("ok")
        }
    }
--- timeout: 5
--- request
GET /t
--- grep_error_log chop
failed to fetch data from etcd: handshake failed
--- grep_error_log_out eval
qr/(failed to fetch data from etcd: handshake failed){1,}/



=== TEST 3: originate plain connection to etcd cluster which enables TLS
--- yaml_config
apisix:
  node_listen: 1984
etcd:
  host:
    - "http://127.0.0.1:12379"
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(4)
            ngx.say("ok")
        }
    }
--- timeout: 5
--- request
GET /t
--- grep_error_log chop
failed to fetch data from etcd: closed
--- grep_error_log_out eval
qr/(failed to fetch data from etcd: closed){1,}/



=== TEST 4: originate TLS connection to etcd cluster and verify TLS certificate (default behavior)
--- yaml_config
apisix:
  node_listen: 1984
etcd:
  host:
    - "https://127.0.0.1:12379"
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(4)
            ngx.say("ok")
        }
    }
--- timeout: 5
--- request
GET /t
--- grep_error_log chop
failed to fetch data from etcd: 18: self signed certificate
--- grep_error_log_out eval
qr/(failed to fetch data from etcd: 18: self signed certificate){1,}/



=== TEST 5: originate TLS connection to etcd cluster success
--- yaml_config
apisix:
  node_listen: 1984
etcd:
  host:
    - "https://127.0.0.1:12379"
  tls:
    verify: false
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(4)
            ngx.say("ok")
        }
    }
--- timeout: 5
--- request
GET /t
--- no_error_log
[error]
