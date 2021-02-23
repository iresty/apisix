--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

package = "apisix"
version = "master-0"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/apache/apisix",
    branch = "master",
}

description = {
    summary = "Apache APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.",
    homepage = "https://github.com/apache/apisix",
    license = "Apache License 2.0",
}

dependencies = {
    "lua-resty-ctxdump = 0.1-0",
    "lua-resty-dns-client = 5.2.0",
    "lua-resty-template = 1.9",
    "lua-resty-etcd = 1.4.3",
    "lua-resty-balancer = 0.02rc5",
    "lua-resty-ngxvar = 0.5.2",
    "lua-resty-jit-uuid = 0.0.7",
    "lua-resty-healthcheck-api7 = 2.2.0",
    "lua-resty-jwt = 0.2.0",
    "lua-resty-hmac-ffi = 0.05",
    "lua-resty-cookie = 0.1.0",
    "lua-resty-session = 2.24",
    "opentracing-openresty = 0.1",
    "lua-resty-radixtree = 2.6.1",
    "lua-protobuf = 0.3.1",
    "lua-resty-openidc = 1.7.2-1",
    "luafilesystem = 1.7.0-2",
    "lua-tinyyaml = 1.0",
    "nginx-lua-prometheus = 0.20201218",
    "jsonschema = 0.9.3",
    "lua-resty-ipmatcher = 0.6",
    "lua-resty-kafka = 0.07",
    "lua-resty-logger-socket = 2.0-0",
    "skywalking-nginx-lua = 0.3-0",
    "base64 = 1.5-2",
    "binaryheap = 0.4",
    "dkjson = 2.5-2",
    "resty-redis-cluster = 1.02-4",
    "lua-resty-expr = 1.1.0",
    "graphql = 0.0.2",
    "argparse = 0.7.1-1",
    "luasocket = 3.0rc1-2",
    "luasec = 0.9-1",
    "amqp-client = 1.4.0-1",
}

build = {
    type = "make",
    build_variables = {
        CFLAGS="$(CFLAGS)",
        LIBFLAG="$(LIBFLAG)",
        LUA_LIBDIR="$(LUA_LIBDIR)",
        LUA_BINDIR="$(LUA_BINDIR)",
        LUA_INCDIR="$(LUA_INCDIR)",
        LUA="$(LUA)",
        OPENSSL_INCDIR="$(OPENSSL_INCDIR)",
        OPENSSL_LIBDIR="$(OPENSSL_LIBDIR)",
    },
    install_variables = {
        INST_PREFIX="$(PREFIX)",
        INST_BINDIR="$(BINDIR)",
        INST_LIBDIR="$(LIBDIR)",
        INST_LUADIR="$(LUADIR)",
        INST_CONFDIR="$(CONFDIR)",
    },
}
