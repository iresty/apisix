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

master_on();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

run_tests();

__DATA__

=== TEST 1: set route(only passive)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 0,
                            "127.0.0.1:1": 1
                        },
                        "retries": 0,
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 100,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 100,
                                    "http_failures": 2
                                }
                            },]] .. [[
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 3
                                },
                                "unhealthy": {
                                    "http_statuses": [502],
                                    "http_failures": 1,
                                    "tcp_failures": 1
                                }
                            }
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: hit routes (two healthy nodes)
--- config
    location /tt {
        content_by_lua_block {
            ngx.sleep(1) -- wait for sync

            local json_sort = require("toolkit.json")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. 1985 .. "/server_port"

            local ports_count = {}
            for i = 1, 6 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ports_count["502"] = (ports_count["502"] or 0) + 1
                else
                    local status = tostring(res.status)
                    ports_count[status] = (ports_count[status] or 0) + 1
                end
            end

            ngx.say(json_sort.encode(ports_count))
            ngx.exit(200)
        }
    }
--- stream_enable
--- request
GET /tt
--- response_body
{"200":5,"502":1}
--- error_log
(upstream#/apisix/stream_routes/1) unhealthy HTTP increment (1/1)
