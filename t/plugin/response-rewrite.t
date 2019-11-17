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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
run_tests;

__DATA__

=== TEST 1:  add plugin
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                body = 'Hello world',
                headers = {
                    ["X-Server-id"] = 3
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2:  add plugin with wrong status_code
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                status_code = 599
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "status_code" validation failed: expected 599 to be smaller than 598
--- no_error_log
[error]



=== TEST 3:  add plugin fail
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                body = 2,
                headers = {
                    ["X-Server-id"] = "3"
                }
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
property "body" validation failed: wrong type: expected string, got number
--- no_error_log
[error]



=== TEST 4: set header(rewrite header and body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers" : {
                                "X-Server-id":"3",                
                                "Access-Control-Allow-Origin": "*",
                                "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
                            },
                            "body": "new body\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 5: check header
--- request
GET /hello
--- response_body
new body
--- response_headers
X-Server-id: 3
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
--- no_error_log
[error]



=== TEST 6: set body only
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "new body2\n"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 7: check body
--- request
GET /hello
--- response_body
new body2
--- no_error_log
[error]



=== TEST 6: set location header with 302 code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "response-rewrite": {
                            "headers": {
                                "Location":"https://www.iresty.com"
                            },
                            "status_code":302
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 7: check 302 redirect
--- request
GET /hello
--- error_code eval
302
--- response_headers
Location: https://www.iresty.com
--- no_error_log
[error]



=== TEST 7:  empty string in header field
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                status_code = 200,
                headers = {
                    [""] = 2
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
invalid field length in header
--- no_error_log
[error]



=== TEST 8: array in header value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.response-rewrite")
            local ok, err = plugin.check_schema({
                status_code = 200,
                headers = {
                    ["X-Name"] = {}
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
invalid type as header value
--- no_error_log
[error]

