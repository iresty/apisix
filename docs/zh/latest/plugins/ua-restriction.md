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

## 目录

- [**名字**](#名字)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`ua-restriction` 可以通过以下方式限制对服务或接口的访问，可以将指定 `User-Agent` 列入白名单或黑名单。

## 属性

| 参数名    | 类型          | 可选项 | 默认值 | 有效值 | 描述                             |
| --------- | ------------- | ------ | ------ | ------ | -------------------------------- |
| allowlist | array[string] | 可选   |        |        | 加入白名单的 User-Agent |
| denylist | array[string] | 可选   |        |        | 加入黑名单的 User-Agent |
| message | string | 可选   | Not allowed. | [1, 1024] | 在未允许的 User-Agent 访问的情况下返回的信息 |

白名单或黑名单可以同时启用，此插件对 User-Agent 的检查先后顺序依次如下：白名单、黑名单。`message`可以由用户自定义。

## 如何启用

下面是一个示例，在指定的 route 上开启了 `ua-restriction` 插件:

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

当未允许的 User-Agent 访问时，默认返回`{"message":"Not allowed"}`。如果你想使用自定义的`message`，可以在插件部分进行配置:

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

## 测试插件

通过正常的 UA 访问：

```shell
$ curl http://127.0.0.1:9080/index.html --header 'User-Agent: YourApp/2.0.0'
HTTP/1.1 200 OK
```

通过爬虫 User-Agent 访问：

```shell
$ curl http://127.0.0.1:9080/index.html --header 'User-Agent: Twitterspider/2.0'
HTTP/1.1 403 Forbidden
```

## 禁用插件

当你想去掉 `ua-restriction` 插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
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

现在就已移除 `ua-restriction` 插件，其它插件的开启和移除也类似。
