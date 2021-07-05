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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ok, err = plugin.check_schema({
                uri = '/apisix/home',
                host = 'apisix.iresty.com',
                scheme = 'http'
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



=== TEST 2: wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ok, err = plugin.check_schema({
                uri = '/apisix/home',
                host = 'apisix.iresty.com',
                scheme = 'tcp'
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
property "scheme" validation failed: matches none of the enum values
done
--- no_error_log
[error]



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/test/add",
                            "scheme": "https",
                            "host": "apisix.iresty.com"
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



=== TEST 4: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/test/update",
                            "scheme": "http",
                            "host": "apisix.iresty.com"
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



=== TEST 5: disable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
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



=== TEST 6: set route(rewrite host)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "scheme": "http",
                                "host": "apisix.iresty.com"
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



=== TEST 7: rewrite host
--- request
GET /hello HTTP/1.1
--- response_body
uri: /plugin_proxy_rewrite
host: apisix.iresty.com
scheme: http
method: GET
--- no_error_log
[error]



=== TEST 8: set route(rewrite host + scheme)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "scheme": "https",
                                "host": "test.com"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1983": 1
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



=== TEST 9: rewrite host + scheme
--- request
GET /hello HTTP/1.1
--- response_body
uri: /plugin_proxy_rewrite
host: test.com
scheme: https
method: GET
--- no_error_log
[error]



=== TEST 10: set route(rewrite headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api-Version": "v2"
                                }
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



=== TEST 11: rewrite headers
--- request
GET /hello HTTP/1.1
--- more_headers
X-Api-Version:v1
--- response_body
uri: /uri/plugin_proxy_rewrite
host: localhost
x-api-version: v2
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 12: set route(add headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api-Engine": "apisix"
                                }
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



=== TEST 13: add headers
--- request
GET /hello HTTP/1.1
--- response_body
uri: /uri/plugin_proxy_rewrite
host: localhost
x-api-engine: apisix
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 14: set route(rewrite empty headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api-Test": "hello"
                                }
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



=== TEST 15: rewrite empty headers
--- request
GET /hello HTTP/1.1
--- more_headers
X-Api-Test:
--- response_body
uri: /uri/plugin_proxy_rewrite
host: localhost
x-api-test: hello
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 16: set route(rewrite uri args)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite_args"
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



=== TEST 17: rewrite uri args
--- request
GET /hello?q=apisix&a=iresty HTTP/1.1
--- response_body
uri: /plugin_proxy_rewrite_args
a: iresty
q: apisix
--- no_error_log
[error]



=== TEST 18: set route(rewrite uri empty args)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite_args"
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



=== TEST 19: rewrite uri empty args
--- request
GET /hello HTTP/1.1
--- response_body
uri: /plugin_proxy_rewrite_args
--- no_error_log
[error]



=== TEST 20: remove header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api-Engine": "APISIX",
                                    "X-Api-Test": ""
                                }
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



=== TEST 21: remove header
--- request
GET /hello HTTP/1.1
--- more_headers
X-Api-Test: foo
X-Api-Engine: bar
--- response_body
uri: /uri/plugin_proxy_rewrite
host: localhost
x-api-engine: APISIX
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 22: set route(only using regex_uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "regex_uri": ["^/test/(.*)/(.*)/(.*)", "/$1_$2_$3"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/test/*"
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



=== TEST 23: hit route(rewrite uri using regex_uri)
--- request
GET /test/plugin/proxy/rewrite HTTP/1.1
--- response_body
uri: /plugin_proxy_rewrite
host: localhost
scheme: http
method: GET
--- no_error_log
[error]



=== TEST 24: hit route(404 not found)
--- request
GET /test/not/found HTTP/1.1
--- error_code: 404
--- no_error_log
[error]



=== TEST 25: set route(Using both uri and regex_uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/hello",
                                "regex_uri": ["^/test/(.*)", "/${1}1"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/test/*"
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



=== TEST 26: hit route(rewrite uri using uri & regex_uri property)
--- request
GET /test/hello HTTP/1.1
--- response_body
hello world
--- no_error_log
[error]



=== TEST 27: set route(invalid regex_uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "regex_uri": ["^/test/(.*)"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/test/*"
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
--- error_code: 400
--- no_error_log
[error]



=== TEST 28: set route(invalid regex syntax for the first element)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "regex_uri": ["[^/test/(.*)", "/$1"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/test/*"
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
--- error_code: 400
--- response_body eval
qr/invalid regex_uri/
--- no_error_log
[error]



=== TEST 29: set route(invalid regex syntax for the second element)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "regex_uri": ["^/test/(.*)", "/$`1"]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/test/*"
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
--- error_code: 400
--- error_log
invalid capturing variable name found



=== TEST 30: set route(invalid uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "hello"
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
--- error_code: 400
--- response_body eval
qr/failed to match pattern/
--- no_error_log
[error]



=== TEST 31: wrong value of uri
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ok, err = plugin.check_schema({
                uri = 'home'
            })
            if not ok then
                ngx.say(err)
                return
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "uri" validation failed: failed to match pattern "^\\/.*" with "home"
--- no_error_log
[error]



=== TEST 32: set route(invalid header field)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api:Version": "v2"
                                }
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
--- error_code: 400
--- response_body eval
qr/invalid field character/
--- no_error_log
[error]
--- error_log
header field: X-Api:Version



=== TEST 33: set route(invalid header value)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri/plugin_proxy_rewrite",
                                "headers": {
                                    "X-Api-Version": "v2\r\n"
                                }
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
--- error_code: 400
--- response_body eval
qr/invalid value character/
--- no_error_log
[error]



=== TEST 34: set route(rewrite uri with args)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                      "plugins": {
                          "proxy-rewrite": {
                              "uri": "/plugin_proxy_rewrite_args?q=apisix"
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



=== TEST 35: rewrite uri with args
--- request
GET /hello?a=iresty
--- response_body_like eval
qr/uri: \/plugin_proxy_rewrite_args(
q: apisix
a: iresty|
a: iresty
q: apisix)
/
--- no_error_log
[error]



=== TEST 36: print the plugin `conf` in etcd, no dirty data
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local encode_with_keys_sorted = require("toolkit.json").encode

            local code, _, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/uri/plugin_proxy_rewrite",
                            "headers": {
                                "X-Api": "v2"
                            }
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

            local resp_data = core.json.decode(body)
            ngx.say(encode_with_keys_sorted(resp_data.node.value.plugins))
        }
    }
--- request
GET /t
--- response_body
{"proxy-rewrite":{"headers":{"X-Api":"v2"},"uri":"/uri/plugin_proxy_rewrite"}}
--- no_error_log
[error]



=== TEST 37:  additional property
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ok, err = plugin.check_schema({
                uri = '/apisix/home',
                host = 'apisix.iresty.com',
                scheme = 'http',
                invalid_att = "invalid",
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
additional properties forbidden, found invalid_att
--- no_error_log
[error]



=== TEST 38: set route(header contains nginx variables)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/uri",
                            "headers": {
                                "x-api": "$remote_addr",
                                "name": "$arg_name",
                                "x-key": "$http_key"
                            }
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



=== TEST 39: hit route(header supports nginx variables)
--- request
GET /hello?name=Bill HTTP/1.1
--- more_headers
key: X-APISIX
--- response_body
uri: /uri
host: localhost
key: X-APISIX
name: Bill
x-api: 127.0.0.1
x-key: X-APISIX
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 40: set route(nginx variable does not exist)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/uri",
                            "headers": {
                                "x-api": "$helle",
                                "name": "$arg_world",
                                "x-key": "$http_key",
                                "Version": "nginx_var_does_not_exist"
                            }
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



=== TEST 41: hit route(get nginx variable is nil)
--- request
GET /hello HTTP/1.1
--- response_body
uri: /uri
host: localhost
version: nginx_var_does_not_exist
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 42: set route(rewrite uri based on ctx.var)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/$arg_new_uri"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/test"
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



=== TEST 43: hit route(upstream uri: should be /hello)
--- request
GET /test?new_uri=hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 44: host with port
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ok, err = plugin.check_schema({
                host = 'apisix.iresty.com:6443',
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



=== TEST 45: set route(rewrite host with port)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/uri",
                                "host": "test.com:6443"
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



=== TEST 46: rewrite host with port
--- request
GET /hello
--- response_body
uri: /uri
host: test.com:6443
x-real-ip: 127.0.0.1
--- no_error_log
[error]



=== TEST 47: set route(rewrite HTTP method)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "POST"
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



=== TEST 48: rewrite HTTP method (GET to POST)
--- request
GET /hello
--- response_body
uri: /plugin_proxy_rewrite
host: localhost
scheme: http
method: POST
--- error_log eval
qr/changed HTTP method from GET to POST/



=== TEST 49: set route(rewrite HTTP method)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PATCH,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/plugin_proxy_rewrite",
                                "method": "PUT"
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



=== TEST 50: rewrite HTTP method (GET to PUT)
--- request
GET /hello
--- response_body
uri: /plugin_proxy_rewrite
host: localhost
scheme: http
method: PUT
--- error_log eval
qr/changed HTTP method from GET to PUT/
