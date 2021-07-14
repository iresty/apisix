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

log_level('debug');
worker_connections(1024);
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({})
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



=== TEST 2: wrong type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({include_in_response = "bad_type"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "include_in_response" validation failed: wrong type: expected boolean, got string
done
--- no_error_log
[error]



=== TEST 3: add plugin with include_in_response true (default true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                            "request-id": {
                            }
                        },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 4: check for request id in response header (default header name)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["X-Request-Id"] then
                ngx.say("request header present")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
request header present
--- no_error_log
[error]



=== TEST 5: check for unique id
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = {}
            local ids = {}
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end

                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end

                    if ids[id] == true then
                        ngx.say("ids not unique")
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            ngx.say("true")
        }
    }
--- request
GET /t
--- wait: 5
--- response_body
true
--- no_error_log
[error]



=== TEST 6: add plugin with custom header name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "header_name": "Custom-Header-Name"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                            "request-id": {
                                "header_name": "Custom-Header-Name",
                                "include_in_response": true
                            }
                        },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 7: check for request id in response header (custom header name)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["Custom-Header-Name"] then
                ngx.say("request header present")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
request header present
--- no_error_log
[error]



=== TEST 8: add plugin with include_in_response false (default true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "include_in_response": false
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                            "request-id": {
                                "include_in_response": false
                            }
                        },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 9: check for request id is not present in the response header
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if not res.headers["X-Request-Id"] then
                ngx.say("request header not present")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
request header not present
--- no_error_log
[error]



=== TEST 10: add plugin with custom header name in global rule and add plugin with default header name in specific route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                     [[{
                        "plugins": {
                            "request-id": {
                                "header_name":"Custom-Header-Name"
                            }
                        }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                    [[{
                        "plugins": {
                            "request-id": {
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return
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



=== TEST 11: check for multiple request-ids in the response header are different
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

            if res.headers["X-Request-Id"] ~= res.headers["Custom-Header-Name"] then
                ngx.say("X-Request-Id and Custom-Header-Name are different")
            else
                ngx.say("failed")
            end
        }
    }
--- request
GET /t
--- response_body
X-Request-Id and Custom-Header-Name are different
--- no_error_log
[error]



=== TEST 12: check for snowflake id
--- yaml_config
plugins:
    - request-id
plugin_attr:
    request-id:
        snowflake:
            enable: true
            snowflake_epoc: 1609459200000
            data_machine_bits: 10
            sequence_bits: 10
            data_machine_ttl: 30
            data_machine_interval: 10
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(3)
        local core = require("apisix.core")
        local key = "/plugins/request-id/snowflake/1"
        local res, err = core.etcd.get(key)
        if err ~= nil then
            ngx.status = 500
            ngx.say(err)
            return
        end
        if res.body.node.key ~= "/apisix/plugins/request-id/snowflake/1" then
            ngx.say(core.json.encode(res.body.node))
        end
        ngx.say("ok")
    }
}
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 13: wrong type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.request-id")
            local ok, err = plugin.check_schema({algorithm = "bad_algorithm"})
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "algorithm" validation failed: matches none of the enum values
done
--- no_error_log
[error]



=== TEST 14: add plugin with algorithm snowflake (default uuid)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "request-id": {
                                "algorithm": "snowflake"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                            "request-id": {
                                "algorithm": "snowflake"
                            }
                        },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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



=== TEST 15: check for snowflake id
--- yaml_config
plugins:
    - request-id
plugin_attr:
    request-id:
        snowflake:
            enable: true
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = {}
            local ids = {}
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end
                    if ids[id] == true then
                        ngx.say("ids not unique")
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
            ngx.say("true")
        }
    }
--- request
GET /t
--- wait: 5
--- response_body
true
--- no_error_log
[error]



=== TEST 16: check for delta_offset 1000 milliseconds
--- yaml_config
plugins:
    - request-id
plugin_attr:
    request-id:
        snowflake:
            enable: true
            snowflake_epoc: 1609459200000
            data_machine_bits: 12
            sequence_bits: 10
            data_machine_ttl: 30
            data_machine_interval: 10
            delta_offset: 1000
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local t = {}
            local ids = {}
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function()
                    local httpc = http.new()
                    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/opentracing"
                    local res, err = httpc:request_uri(uri,
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/json",
                            }
                        }
                    )
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    local id = res.headers["X-Request-Id"]
                    if not id then
                        return -- ignore if the data is not synced yet.
                    end
                    if ids[id] == true then
                        ngx.say("ids not unique")
                        return
                    end
                    ids[id] = true
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
            ngx.say("true")
        }
    }
--- request
GET /t
--- wait: 5
--- response_body
true
--- no_error_log
[error]



=== TEST 17: wrong delta_offset
--- yaml_config
plugins:
    - request-id
plugin_attr:
    request-id:
        snowflake:
            enable: true
            delta_offset: 1001
--- config
    location /t {
        content_by_lua_block {
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
ailed to check the plugin_attr[request-id]: property "snowflake" validation failed: property "delta_offset" validation failed: matches none of the enum values
