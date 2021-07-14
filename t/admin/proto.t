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
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: put proto (id:1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message = t('/apisix/admin/proto/1',
                 ngx.HTTP_PUT,
                 [[{
                        "content": "syntax = \"proto3\";
                            package proto;
                            message HelloRequest{
                            string name = 1;
                                }

                            message HelloResponse{
                            int32 code = 1;
                            string msg = 2;
                                }
                                // The greeting service definition.
                            service Hello {
                                    // Sends a greeting
                            rpc SayHi (HelloRequest) returns (HelloResponse){}
                                }"
                }]],
                [[
                    {
                        "action": "set"
                    }
                ]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say("[put proto] code: ", code, " message: ", message)
                return
            end

            ngx.say("[put proto] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[put proto] code: 200 message: passed
--- no_error_log
[error]



=== TEST 2: delete proto(id:1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message = t('/apisix/admin/proto/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say("[delete proto] code: ", code, " message: ", message)
                return
            end

            ngx.say("[delete proto] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[delete proto] code: 200 message: passed
--- no_error_log
[error]



=== TEST 3: put proto (id:2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message = t('/apisix/admin/proto/2',
                 ngx.HTTP_PUT,
                 [[{
                        "content": "syntax = \"proto3\";
                            package proto;
                            message HelloRequest{
                            string name = 1;
                                }

                            message HelloResponse{
                            int32 code = 1;
                            string msg = 2;
                                }
                                // The greeting service definition.
                            service Hello {
                                    // Sends a greeting
                            rpc SayHi (HelloRequest) returns (HelloResponse){}
                                }"
                }]],
                [[
                    {
                        "action": "set"
                    }
                ]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say("[put proto] code: ", code, " message: ", message)
                return
            end

            ngx.say("[put proto] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[put proto] code: 200 message: passed
--- no_error_log
[error]



=== TEST 4: route refer proto(proto id 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "grpc-transcode": {
                            "disable": false,
                            "method": "SayHi",
                            "proto_id": 2,
                            "service": "proto.Hello"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/grpc/sayhi",
                        "name": "hi-grpc"
                }]],
                [[{
                    "action": "set"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say("[route refer proto] code: ", code, " message: ", message)
                return
            end

            ngx.say("[route refer proto] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[route refer proto] code: 200 message: passed
--- no_error_log
[error]



=== TEST 5: delete proto(proto id 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, message = t('/apisix/admin/proto/2',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )

            ngx.say("[delete proto] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete proto] code: 400
--- no_error_log
[error]
