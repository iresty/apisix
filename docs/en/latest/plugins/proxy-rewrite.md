---
title: proxy-rewrite
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

The `proxy-rewrite` is an upstream proxy information rewriting plugin, which supports the rewriting of information such as `scheme`, `uri`, and `host`.

## Attributes

| Name      | Type          | Requirement | Default | Valid             | Description                                                  |
| --------- | ------------- | ----------- | ------- | ----------------- | ------------------------------------------------------------ |
| scheme    | string        | optional    | "http"  | ["http", "https"] | Upstream new `schema` forwarding protocol. This option is deprecated. It's recommended to set the proxy `scheme` in the Upstream object's `scheme` field instead.|
| uri       | string        | optional    |         |                   | Upstream new `uri` forwarding address. Supports the use of [Nginx variables](https://nginx.org/en/docs/http/ngx_http_core_module.html). Variables must start with `$`, such as `$arg_name`. |
| regex_uri | array[string] | optional    |         |                   | Upstream new `uri` forwarding address. Use regular expression to match URL from client, when the match is successful, the URL template will be forwarded upstream. If the match is not successful, the URL from the client will be forwarded to the upstream. When `uri` and `regex_uri` are both exist, `uri` is used first. For example: [" ^/iresty/(.*)/(.*)/(.*)", "/$1-$2-$3"], the first element represents the matching regular expression and the second element represents the URL template that is forwarded to the upstream. |
| host      | string        | optional    |         |                   | Upstream new `host` forwarding address, example `iresty.com`. |
| headers   | object        | optional    |         |                   | Forward to the new `headers` of the upstream, can set up multiple. If it exists, will rewrite the header, otherwise will add the header. You can set the corresponding value to an empty string to remove a header. Support the use of Nginx variables. Need to start with `$`, such as `client_addr: $remote_addr`: it means that the request header `client_addr` is the client IP. |
| method    | string        | optional    |         | ["GET", "POST","PUT","DELETE","PATCH","HEAD","OPTIONS","CONNECT","TRACE"] | New HTTP method.                        |

## How To Enable

Here's an example, enable the `proxy-rewrite` plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {
        "proxy-rewrite": {
            "uri": "/test/home.html",
            "scheme": "http",
            "host": "iresty.com",
            "headers": {
                "X-Api-Version": "v1",
                "X-Api-Engine": "apisix",
                "X-Api-useless": ""
            }
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

## Test Plugin

Testing based on the above examples :

```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

Send the request and see upstream `access.log', if the output information is consistent with the configuration :

```
127.0.0.1 - [26/Sep/2019:10:52:20 +0800] iresty.com GET /test/home.html HTTP/1.1 200 38 - curl/7.29.0 - 0.000 199 107
```

This means that the `proxy-rewrite` plugin is in effect.

## Disable Plugin

When you want to disable the `proxy-rewrite` plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately :

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/test/index.html",
    "plugins": {},
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:80": 1
        }
    }
}'
```

The `proxy-rewrite` plugin has been disabled now. It works for other plugins.
