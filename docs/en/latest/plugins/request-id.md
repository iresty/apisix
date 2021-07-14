---
title: request-id
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

`request-id` plugin adds a unique ID (UUID) to each request proxied through APISIX. This plugin can be used to track an
API request. The plugin will not add a request id if the `header_name` is already present in the request.

## Attributes

| Name                | Type    | Requirement | Default        | Valid | Description                                                    |
| ------------------- | ------- | ----------- | -------------- | ----- | -------------------------------------------------------------- |
| header_name         | string  | optional    | "X-Request-Id" |       | Request ID header name                                         |
| include_in_response | boolean | optional    | true          |       | Option to include the unique request ID in the response header |

## How To Enable

Create a route and enable the request-id plugin on the route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/hello",
    "plugins": {
        "request-id": {
            "include_in_response": true
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```

## Test Plugin

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
......
```

## Disable Plugin

Remove the corresponding json configuration in the plugin configuration to disable the `request-id`.
APISIX plugins are hot-reloaded, therefore no need to restart APISIX.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/5 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/get",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:8080": 1
        }
    }
}'
```
