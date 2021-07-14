---
title: ua-restriction
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

The `ua-restriction` can restrict access to a Service or a Route by either `allowlist` or `denylist` `User-Agent`.

## Attributes

| Name      | Type          | Requirement | Default | Valid | Description                              |
| --------- | ------------- | ----------- | ------- | ----- | ---------------------------------------- |
| allowlist | array[string] | optional    |         |       | List of User-Agent of allowlist. |
| denylist | array[string] | optional    |         |       | List of User-Agent of denylist. |
| message | string | optional             | Not allowed. | [1, 1024] | Message of deny reason. |

Any of `allowlist` or `denylist` can be optional, and can work together in this order: allowlist->denylist

The message can be user-defined.

## How To Enable

Creates a route or service object, and enable plugin `ua-restriction`.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/index.html",
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
             ],
             "denylist": [
                 "my-bot2",
                 "(Twitterspider)/(\\d+)\\.(\\d+)"
             ]
        }
    }
}'
```

Default returns `{"message":"Not allowed"}` when rejected. If you want to use a custom message, you can configure it in the plugin section.

```json
"plugins": {
    "ua-restriction": {
        "denylist": [
            "my-bot2",
            "(Twitterspider)/(\\d+)\\.(\\d+)"
        ],
        "message": "Do you want to do something bad?"
    }
}
```

## Test Plugin

Requests from normal User-Agent:

```shell
$ curl http://127.0.0.1:9080/index.html -i
HTTP/1.1 200 OK
...
```

Requests from bot User-Agent:

```shell
$ curl http://127.0.0.1:9080/index.html --header 'User-Agent: Twitterspider/2.0'
HTTP/1.1 403 Forbidden
```

## Disable Plugin

When you want to disable the `ua-restriction` plugin, it is very simple,
you can delete the corresponding json configuration in the plugin configuration,
no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
{
    "uri": "/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The `ua-restriction` plugin has been disabled now. It works for other plugins.
