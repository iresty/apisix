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

## 目录

- [简介](#简介)
- [属性](#属性)
- [如何启用](#如何启用)
- [测试插件](#测试插件)
- [禁用插件](#禁用插件)

## 简介

proxy-rewrite 是上游代理信息重写插件，支持对 `scheme`、`uri`、`host` 等信息的重写。

## 属性

| Name      | Type          | Requirement | Default | Valid             | Description                                                                                                                                                                                                                                                                                        |
| --------- | ------------- | ----------- | ------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| scheme    | string        | 可选        | "http"  | ["http", "https"] | 不推荐使用。应该在 Upstream 的 scheme 字段设置上游的 scheme。
| uri       | string        | 可选        |         |                   | 转发到上游的新 `uri` 地址。                                                                                                                                                                                                                                                                             |
| regex_uri | array[string] | 可选        |         |                   | 转发到上游的新 `uri` 地址, 使用正则表达式匹配来自客户端的uri，当匹配成功后使用模板替换转发到上游的uri, 未匹配成功时将客户端请求的uri转发至上游。当`uri`和`regex_uri`同时存在时，`uri`优先被使用。例如：["^/iresty/(.*)/(.*)/(.*)","/$1-$2-$3"] 第一个元素代表匹配来自客户端请求的uri正则表达式，第二个元素代表匹配成功后转发到上游的uri模板。 |
| host      | string        | 可选        |         |                   | 转发到上游的新 `host` 地址，例如：`iresty.com` 。                                                                                                                                                                                                                                                        |
| headers   | object        | 可选        |         |                   | 转发到上游的新`headers`，可以设置多个。头信息如果存在将重写，不存在则添加。想要删除某个 header 的话，把对应的值设置为空字符串即可。支持使用 Nginx 的变量，需要以 `$` 开头，如 `client_addr: $remote_addr` ：表示请求头 `client_addr` 为客户端IP。                                                                               |
| method    | string        | 可选        |       | ["GET", "POST","PUT","DELETE","PATCH","HEAD","OPTIONS","CONNECT","TRACE"] | 转发到上游的新请求方法 |

## 如何启用

下面是一个示例，在指定的 route 上开启了 `proxy-rewrite` 插件:

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

## 测试插件

基于上述配置进行测试：

```shell
curl -X GET http://127.0.0.1:9080/test/index.html
```

发送请求，查看上游服务`access.log`，如果输出信息与配置一致：

```
127.0.0.1 - [26/Sep/2019:10:52:20 +0800] iresty.com GET /test/home.html HTTP/1.1 200 38 - curl/7.29.0 - 0.000 199 107
```

即表示 `proxy-rewrite` 插件生效了。

## 禁用插件

当你想去掉 `proxy-rewrite` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

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

现在就已经移除了 `proxy-rewrite` 插件了。其他插件的开启和移除也是同样的方法。
