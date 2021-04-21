---
title: ldap-auth
---

<!--
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
-->

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

`ldap-auth` is an authentication plugin that can works with `consumer`. Add Ldap Authentication to a `service` or `route`.

The `consumer` then authenticate against the Ldap server using Basic authentication.

For more information on Basic authentication, refer to [Wiki](https://en.wikipedia.org/wiki/Basic_access_authentication) for more information.

This authentication plugin use [lualdap](https://lualdap.github.io/lualdap/) plugin to connect against the ldap server

## Attributes

| Name     | Type   | Requirement | Default | Valid | Description                                                                                                                                                      |
| -------- | ------ | ----------- | ------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| base_dn | string | required    |         |       | the base dn of the `ldap` server (example : `ou=users,dc=example,dc=org`)   |
| ldap_uri | string | required    |         |       | the uri of the ldap server  |
| use_tls | boolean | optional    |    `true`     |       | Boolean flag indicating if Transport Layer Security (TLS) should be used. |
| uid | string | optional    |     `cn`      |     | the `uid` attribute |

## How To Enable

### 1. set a consumer and config the value of the `ldap-auth` option

```shell
curl http://127.0.0.1:9080/apisix/admin/consumers -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "username": "foo",
    "plugins": {
        "ldap-auth": {
            "user_dn": "cn=user01,ou=users,dc=example,dc=org"
        }
    }
}'
```

you can visit Dashboard `http://127.0.0.1:9080/apisix/dashboard/` and add a Consumer through the web console.

then add ldap-auth plugin in the Consumer page

### 2. add a Route or add a Service, and enable the `ldap-auth` plugin

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {
        "ldap-auth": {
            "base_dn": "ou=users,dc=example,dc=org",
            "ldap_uri": "localhost:1389",
            "uid": "cn"
        },
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

## Test Plugin

- missing Authorization header

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Missing authorization in request"}
```

- user is not exists:

```shell
$ curl -i -uuser:password1 http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Invalid user key in authorization"}
```

- password is invalid:

```shell
$ curl -i -uuser01:passwordfalse http://127.0.0.1:9080/hello
HTTP/1.1 401 Unauthorized
...
{"message":"Password is error"}
```

- success:

```shell
$ curl -i -uuser01:password1 http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
...
hello, world
```

## Disable Plugin

When you want to disable the `ldap-auth` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/apisix/admin/routes/1 -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/hello",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```
