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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: empty conf
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ua-restriction")
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/object matches none of the requireds/



=== TEST 2: set allowlist, denylist and user-defined message
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ua-restriction")
            local conf = {
               allowlist = {
                    "my-bot1",
                    "my-bot2"
               },
               denylist = {
                    "my-bot1",
                    "my-bot2"
               },
               message = "User-Agent Forbidden",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body
{"allowlist":["my-bot1","my-bot2"],"denylist":["my-bot1","my-bot2"],"message":"User-Agent Forbidden"}



=== TEST 3: allowlist not array
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ua-restriction")
            local conf = {
                allowlist = "my-bot1",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "allowlist" validation failed: wrong type: expected array, got string
done



=== TEST 4: denylist not array
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ua-restriction")
            local conf = {
                denylist = 100,
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "denylist" validation failed: wrong type: expected array, got number
done



=== TEST 5: message not string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.ua-restriction")
            local conf = {
                message = 100,
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "message" validation failed: wrong type: expected string, got number
done



=== TEST 6: set denylist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ua-restriction": {
                                 "denylist": [
                                     "my-bot1",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
                                 ]
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
--- response_body
passed



=== TEST 7: hit route and user-agent in denylist
--- request
GET /hello
--- more_headers
User-Agent:my-bot1
--- error_code: 403



=== TEST 8: hit route and user-agent in denylist with multiple
--- request
GET /hello
--- more_headers
User-Agent:my-bot1
User-Agent:my-bot2
--- error_code: 403



=== TEST 9: hit route and user-agent match denylist regex
--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/3.0
--- error_code: 403



=== TEST 10: hit route and user-agent not in denylist
--- request
GET /hello
--- more_headers
User-Agent:foo/bar
--- error_code: 200



=== TEST 11: set allowlist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ua-restriction": {
                                 "allowlist": [
                                     "my-bot1",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
                                 ]
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
--- response_body
passed



=== TEST 12: hit route and user-agent in allowlist
--- request
GET /hello
--- more_headers
User-Agent:my-bot1
--- error_code: 200



=== TEST 13: hit route and user-agent match allowlist regex
--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/3.0
--- error_code: 200



=== TEST 14: hit route and user-agent not in allowlist
--- request
GET /hello
--- more_headers
User-Agent:foo/bar
--- error_code: 200



=== TEST 15: set config: user-agent in both allowlist and denylist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ua-restriction": {
                                 "allowlist": [
                                     "foo/bar",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
                                 ],
                                 "denylist": [
                                     "foo/bar",
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
                                 ]
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
--- response_body
passed



=== TEST 16: hit route and user-agent in both allowlist and denylist, part 1
--- request
GET /hello
--- more_headers
User-Agent:foo/bar
--- error_code: 200



=== TEST 17: hit route and user-agent in both allowlist and denylist, part 2
--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/1.0
--- error_code: 200



=== TEST 18: message that do not reach the minimum range
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ua-restriction": {
                                 "message": ""
                            }
                        }
                }]]
                )

            ngx.say(body)
        }
    }
--- response_body_like eval
qr/string too short, expected at least 1, got 0/



=== TEST 19: exceeds the maximum limit of message
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            local data = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    }
                },
                plugins = {
                    ["ua-restriction"] = {
                        denylist = {
                           "my-bot1",
                        },
                        message = ("-1Aa#"):rep(205)
                    }
                }
            }

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            ngx.say(body)
        }
    }
--- response_body_like eval
qr/string too long, expected at most 1024, got 1025/



=== TEST 20: set custom message
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ua-restriction": {
                                "denylist": [
                                    "(Baiduspider)/(\\d+)\\.(\\d+)"
                                ],
                                "message": "Do you want to do something bad?"
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

--- response_body
passed



=== TEST 21: test custom message
--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/1.0
--- error_code: 403
--- response_body
{"message":"Do you want to do something bad?"}



=== TEST 22: test remove ua-restriction part 1, enable
--- config
    location /enable {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "ua-restriction": {
                                "denylist": [
                                     "(Baiduspider)/(\\d+)\\.(\\d+)"
                                ]
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
GET /enable
--- error_code: 200



=== TEST 23: test remove ua-restriction part 2
--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/1.0
--- error_code: 403



=== TEST 24: test remove ua-restriction part 3, remove plugin
--- config
    location /disable {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
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
GET /disable
--- error_code: 200



=== TEST 25: test remove ua-restriction part 4, check spider User-Agent
--- request
GET /hello
--- more_headers
User-Agent:Baiduspider/1.0
--- response_body
hello world



=== TEST 26: set disable=true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "ua-restriction": {
                            "denylist": [
                                "foo"
                            ],
                            "disable": true
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
--- response_body
passed
