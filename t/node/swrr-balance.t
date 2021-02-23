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
log_level('info');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set route(two upstream node)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
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
--- no_error_log
[error]



=== TEST 2: hit routes
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":6,"port":"1981"},{"count":6,"port":"1980"}]
--- no_error_log
[error]



=== TEST 3: set route(three upstream node)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1,
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 4: hit routes
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":4,"port":"1982"},{"count":4,"port":"1981"},{"count":4,"port":"1980"}]
--- no_error_log
[error]



=== TEST 5: set route(three upstream node and different weight)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1980": 3,
                            "127.0.0.1:1981": 2,
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 6: hit routes
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":2,"port":"1982"},{"count":4,"port":"1981"},{"count":6,"port":"1980"}]
--- no_error_log
[error]



=== TEST 7: set route(weight is 0)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1980": 3,
                            "127.0.0.1:1981": 0,
                            "127.0.0.1:1982": 1
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
--- no_error_log
[error]



=== TEST 8: hit routes
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"count":3,"port":"1982"},{"count":9,"port":"1980"}]
--- no_error_log
[error]



=== TEST 9: set route(GCD is 1， total weigh much larger)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1980": 6001,
                            "127.0.0.1:1981": 2999,
                            "127.0.0.1:1982": 1000
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
--- no_error_log
[error]



=== TEST 10: hit smooth , test 10 times
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            local test_count = 10
            for i = 1, test_count do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, hit_rate = string.format("%.1f",count/test_count)})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"hit_rate":"0.1","port":"1982"},{"hit_rate":"0.3","port":"1981"},{"hit_rate":"0.6","port":"1980"}]
--- no_error_log
[error]



=== TEST 11: hit smooth , test 50 times
--- timeout: 6
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            local test_count = 50
            for i = 1, test_count do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, hit_rate = string.format("%.1f",count/test_count)})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"hit_rate":"0.1","port":"1982"},{"hit_rate":"0.3","port":"1981"},{"hit_rate":"0.6","port":"1980"}]
--- no_error_log
[error]



=== TEST 12: hit smooth , test 100 times
--- timeout: 12
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local ports_count = {}
            local test_count = 100
            for i = 1, test_count do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, hit_rate = string.format("%.1f",count/test_count)})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
[{"hit_rate":"0.1","port":"1982"},{"hit_rate":"0.3","port":"1981"},{"hit_rate":"0.6","port":"1980"}]
--- no_error_log
[error]



=== TEST 13: set retry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1999": 2,
                            "127.0.0.1:1980": 1
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
--- no_error_log
[error]



=== TEST 14: hit retry
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.body)
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
1980
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1999 while connecting to upstream
proxy request to 127.0.0.1:1980 while connecting to upstream



=== TEST 15: set retry all nodes, failed
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "nodes": {
                            "127.0.0.1:1999": 2,
                            "127.0.0.1:2999": 1
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
--- no_error_log
[error]



=== TEST 16: hit retry all nodes, failed
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.status)
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
502
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1999 while connecting to upstream
proxy request to 127.0.0.1:2999 while connecting to upstream



=== TEST 17: set retry 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "swrr",
                        "retries": 2,
                        "nodes": {
                            "127.0.0.1:1999": 2,
                            "127.0.0.1:2999": 1
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
--- no_error_log
[error]



=== TEST 18: hit all upstream servers tried
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end

            ngx.say(res.status)
            ngx.exit(200)
        }
    }
--- request
GET /t
--- response_body
502
--- error_log
connect() failed
--- grep_error_log eval
qr/failed to find valid upstream server/
--- grep_error_log_out
failed to find valid upstream server
