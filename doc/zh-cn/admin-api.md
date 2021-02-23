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

# 目录

* [Route](#route)
* [Service](#service)
* [Consumer](#consumer)
* [Upstream](#upstream)
* [SSL](#ssl)
* [Global Rule](#global-rule)
* [Plugin Config](#plugin-config)
* [Plugin Metadata](#plugin-metadata)
* [Plugin](#plugin)

## Route

*地址*：/apisix/admin/routes/{id}?ttl=0

*说明*：Route 字面意思就是路由，通过定义一些规则来匹配客户端的请求，然后根据匹配结果加载并执行相应的
插件，并把请求转发给到指定 Upstream。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/routes|无|获取资源列表|
|GET      |/apisix/admin/routes/{id}|无|获取资源|
|PUT      |/apisix/admin/routes/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/routes     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/routes/{id}|无|删除资源|
|PATCH    |/apisix/admin/routes/{id}|{...}|标准 PATCH ，修改已有 Route 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为null 即可删除；特别地，当需要修改属性的值为数组时，该属性将全量更新|
|PATCH    |/apisix/admin/routes/{id}/{path}|{...}|SubPath PATCH，通过 {path} 指定 Route 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。两种 PATCH 的区别可以参考后面的示例|

> URL 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|ttl     |可选 |辅助   |超过这个时间会被自动删除，单位：秒|ttl=1|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|uri      |与 `uris` 二选一 |匹配规则|除了如 `/foo/bar`、`/foo/gloo` 这种全量匹配外，使用不同 [Router](architecture-design.md#router) 还允许更高级匹配，更多见 [Router](architecture-design.md#router)。|"/hello"|
|uris     |与 `uri` 二选一 |匹配规则|非空数组形式，可以匹配多个 `uri`|["/hello", "/world"]|
|plugins  |`plugins`、`script`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Plugin|详见 [Plugin](architecture-design.md#plugin) ||
|script  |`plugins`、`script`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Script|详见 [Script](architecture-design.md#script) ||
|upstream |`plugins`、`script`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Upstream|启用的 Upstream 配置，详见 [Upstream](architecture-design.md#upstream)||
|upstream_id|`plugins`、`script`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Upstream|启用的 upstream id，详见 [Upstream](architecture-design.md#upstream)||
|service_id|`plugins`、`script`、`upstream`/`upstream_id`、`service_id`至少选择一个 |Service|绑定的 Service 配置，详见 [Service](architecture-design.md#service)||
|plugin_config_id|可选，无法跟 script 一起配置|Plugin|绑定的 Plugin config 配置，详见 [Plugin config](architecture-design.md#plugin-config)||
|name     |可选 |辅助   |标识路由名称|route-xxxx|
|desc     |可选 |辅助   |标识描述、使用场景等。|客户 xxxx|
|host     |可选 |匹配规则|当前请求域名，比如 `foo.com`；也支持泛域名，比如 `*.foo.com`。|"foo.com"|
|hosts    |可选 |匹配规则|非空列表形态的 `host`，表示允许有多个不同 `host`，匹配其中任意一个即可。|{"foo.com", "*.bar.com"}|
|remote_addr|可选 |匹配规则|客户端请求 IP 地址: `192.168.1.101`、`192.168.1.102` 以及 CIDR 格式的支持 `192.168.1.0/24`。特别的，APISIX 也完整支持 IPv6 地址匹配：`::1`，`fe80::1`, `fe80::1/64` 等。|"192.168.1.0/24"|
|remote_addrs|可选 |匹配规则|非空列表形态的 `remote_addr`，表示允许有多个不同 IP 地址，符合其中任意一个即可。|{"127.0.0.1", "192.0.0.0/8", "::1"}|
|methods  |可选 |匹配规则|如果为空或没有该选项，代表没有任何 `method` 限制，也可以是一个或多个的组合：`GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`，`CONNECT`，`TRACE`。|{"GET", "POST"}|
|priority  |可选 |匹配规则|如果不同路由包含相同 `uri`，根据属性 `priority` 确定哪个 `route` 被优先匹配，值越大优先级越高，默认值为 0。|priority = 10|
|vars       |可选  |匹配规则|由一个或多个`{var, operator, val}`元素组成的列表，类似这样：`{{var, operator, val}, {var, operator, val}, ...}}`。例如：`{"arg_name", "==", "json"}`，表示当前请求参数 `name` 是 `json`。这里的 `var` 与 Nginx 内部自身变量命名是保持一致，所以也可以使用 `request_uri`、`host` 等。更多细节请参考[lua-resty-expr](https://github.com/api7/lua-resty-expr) |{{"arg_name", "==", "json"}, {"arg_age", ">", 18}}|
|filter_func|可选|匹配规则|用户自定义的过滤函数。可以使用它来实现特殊场景的匹配要求实现。该函数默认接受一个名为 vars 的输入参数，可以用它来获取 Nginx 变量。|function(vars) return vars["arg_name"] == "json" end|
|labels   |可选 |匹配规则|标识附加属性的键值对|{"version":"v2","build":"16","env":"production"}|
|enable_websocket|可选 |辅助| 是否启用 `websocket`(boolean), 缺省 `false`.||
|status          |可选 |辅助| 是否启用此路由, 缺省 `1`。|`1` 表示启用，`0` 表示禁用|
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|

有两点需要特别注意：

* 除了 `uri`/`uris` 是必选的之外，`plugins`、`script`、`upstream`/`upstream_id`、`service_id` 这三类必须选择其中至少一个。
* 对于同一类参数比如 `uri`与 `uris`，`upstream` 与 `upstream_id`，`host` 与 `hosts`，`remote_addr` 与 `remote_addrs` 等，是不能同时存在，二者只能选择其一。如果同时启用，接口会报错。

route 对象 json 配置内容：

```shell
{
    "id": "1",                  # id，非必填
    "uris": ["/a","/b"],        # 一组 URL 路径
    "methods": ["GET","POST"],  # 可以填多个方法
    "hosts": ["a.com","b.com"], # 一组 host 域名
    "plugins": {},              # 指定 route 绑定的插件
    "priority": 0,              # apisix 支持多种匹配方式，可能会在一次匹配中同时匹配到多条路由，此时优先级高的优先匹配中
    "name": "路由xxx",
    "desc": "hello world",
    "remote_addrs": ["127.0.0.1"],  # 一组客户端请求 IP 地址
    "vars": [],                 # 由一个或多个 {var, operator, val} 元素组成的列表
    "upstream_id": "1",         # upstream 对象在 etcd 中的 id ，建议使用此值
    "upstream": {},             # upstream 信息对象，建议尽量不要使用
    "filter_func": "",          # 用户自定义的过滤函数，非必填
}
```

具体示例：

```shell
# 创建一个路由
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/index.html",
    "hosts": ["foo.com", "*.bar.com"],
    "remote_addrs": ["127.0.0.0/8"],
    "methods": ["PUT", "GET"],
    "enable_websocket": true,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
...

# 创建一个有效期为 60 秒的路由，过期后自动删除
$ curl http://127.0.0.1:9080/apisix/admin/routes/2?ttl=60 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/aa/index.html",
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
...


# 给路由增加一个 upstream node
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "39.97.63.216:80": 1
        }
    }
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将更新为：
{
    "39.97.63.215:80": 1,
    "39.97.63.216:80": 1
}


# 给路由更新一个 upstream node 的权重
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "39.97.63.216:80": 10
        }
    }
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将更新为：
{
    "39.97.63.215:80": 1,
    "39.97.63.216:80": 10
}


# 给路由删除一个 upstream node
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "39.97.63.215:80": null
        }
    }
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将更新为：
{
    "39.97.63.216:80": 10
}


# 替换路由的 methods -- 数组
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '{
    "methods": ["GET", "POST"]
}'
HTTP/1.1 200 OK
...

执行成功后，methods 将不保留原来的数据，整个更新为：
["GET", "POST"]


# 替换路由的 upstream nodes -- sub path
$ curl http://127.0.0.1:9080/apisix/admin/routes/1/upstream/nodes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "39.97.63.200:80": 1
}'
HTTP/1.1 200 OK
...

执行成功后，nodes 将不保留原来的数据，整个更新为：
{
    "39.97.63.200:80": 1
}


# 替换路由的 methods  -- sub path
$ curl http://127.0.0.1:9080/apisix/admin/routes/1/methods -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '["POST", "DELETE", "PATCH"]'
HTTP/1.1 200 OK
...

执行成功后，methods 将不保留原来的数据，整个更新为：
["POST", "DELETE", "PATCH"]


# 禁用路由
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "status": 0
}'
HTTP/1.1 200 OK
...

执行成功后，status 将更新为：
{
    "status": 0
}


# 启用路由
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "status": 1
}'
HTTP/1.1 200 OK
...

执行成功后，status 将更新为：
{
    "status": 1
}


```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## Service

*地址*：/apisix/admin/services/{id}

*说明*：`Service` 是某类 API 的抽象（也可以理解为一组 Route 的抽象）。它通常与上游服务抽象是一一对应的，`Route`
与 `Service` 之间，通常是 N:1 的关系。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/services|无|获取资源列表|
|GET      |/apisix/admin/services/{id}|无|获取资源|
|PUT      |/apisix/admin/services/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/services     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/services/{id}|无|删除资源|
|PATCH    |/apisix/admin/services/{id}|{...}|标准 PATCH ，修改已有 Service 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为null 即可删除；特别地，当需要修改属性的值为数组时，该属性将全量更新|
|PATCH    |/apisix/admin/services/{id}/{path}|{...}|SubPath PATCH，通过 {path} 指定 Service 需要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|plugins  |可选 |Plugin|详见 [Plugin](architecture-design.md#plugin) ||
|upstream | upstream 或 upstream_id 两个选一个 |Upstream|启用的 Upstream 配置，详见 [Upstream](architecture-design.md#upstream)||
|upstream_id| upstream 或 upstream_id 两个选一个 |Upstream|启用的 upstream id，详见 [Upstream](architecture-design.md#upstream)||
|name     |可选 |辅助   |标识服务名称。||
|desc     |可选 |辅助   |服务描述、使用场景等。||
|labels   |可选 |匹配规则|标识附加属性的键值对|{"version":"v2","build":"16","env":"production"}|
|enable_websocket|可选 |辅助| 是否启用 `websocket`(boolean), 缺省 `false`.||
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|

serivce 对象 json 配置内容：

```shell
{
    "id": "1",              # id
    "plugins": {},          # 指定 service 绑定的插件
    "upstream_id": "1",     # upstream 对象在 etcd 中的 id ，建议使用此值
    "upstream": {},         # upstream 信息对象，不建议使用
    "name": "测试svc",  # service 名称
    "desc": "hello world",  # service 描述
    "enable_websocket": true, #启动 websocket 功能
}
```

具体示例：

```shell
# 创建一个Service
$ curl http://127.0.0.1:9080/apisix/admin/services/201  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "plugins": {
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    },
    "enable_websocket": true,
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'

# 返回结果

HTTP/1.1 201 Created
...


# 给 Service 增加一个 upstream node
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "39.97.63.216:80": 1
        }
    }
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将更新为：
{
    "39.97.63.215:80": 1,
    "39.97.63.216:80": 1
}


# 给 Service 更新一个 upstream node 的权重
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "39.97.63.216:80": 10
        }
    }
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将更新为：
{
    "39.97.63.215:80": 1,
    "39.97.63.216:80": 10
}


# 给 Service 删除一个 upstream node
$ curl http://127.0.0.1:9080/apisix/admin/services/201 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "upstream": {
        "nodes": {
            "39.97.63.215:80": null
        }
    }
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将更新为：
{
    "39.97.63.216:80": 10
}


# 替换 Service 的 upstream nodes
$ curl http://127.0.0.1:9080/apisix/admin/services/201/upstream/nodes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "39.97.63.200:80": 1
}'
HTTP/1.1 200 OK
...

执行成功后，upstream nodes 将不保留原来的数据，整个更新为：
{
    "39.97.63.200:80": 1
}

```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## Consumer

*地址*：/apisix/admin/consumers/{username}

*说明*：Consumer 是某类服务的消费者，需与用户认证体系配合才能使用。Consumer 使用 `username` 作为唯一标识，只支持使用 HTTP `PUT` 方法创建 Consumer。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/consumers|无|获取资源列表|
|GET      |/apisix/admin/consumers/{id}|无|获取资源|
|PUT      |/apisix/admin/consumers|{...}|创建资源|
|DELETE   |/apisix/admin/consumers/{id}|无|删除资源|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|username|必需|辅助|Consumer 名称。||
|plugins|可选|Plugin|该 Consumer 对应的插件配置，它的优先级是最高的：Consumer > Route > Service。对于具体插件配置，可以参考 [Plugins](#plugin) 章节。||
|desc     |可选 |辅助|consumer描述||
|labels   |可选 |匹配规则|标识附加属性的键值对|{"version":"v2","build":"16","env":"production"}|
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|

consumer 对象 json 配置内容：

```shell
{
    "plugins": {},          # 指定 consumer 绑定的插件
    "username": "name",     # 必填
    "desc": "hello world",  # consumer 描述
}
```

绑定认证插件有些特别，当它需要与 consumer 联合使用时，需要提供用户名、密码等信息；另一方面，当它与 route/service 绑定时，是不需要任何参数的。因为这时候是根据用户请求数据来反向推出用户对应的是哪个 consumer

示例：

```shell
# 创建 Consumer ，指定认证插件 key-auth ，并开启特定插件 limit-count
$ curl http://127.0.0.1:9080/apisix/admin/consumers  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "username": "jack",
    "plugins": {
        "key-auth": {
            "key": "auth-one"
        },
        "limit-count": {
            "count": 2,
            "time_window": 60,
            "rejected_code": 503,
            "key": "remote_addr"
        }
    }
}'
HTTP/1.1 200 OK
Date: Thu, 26 Dec 2019 08:17:49 GMT
...

{"node":{"value":{"username":"jack","plugins":{"key-auth":{"key":"auth-one"},"limit-count":{"time_window":60,"count":2,"rejected_code":503,"key":"remote_addr","policy":"local"}}},"createdIndex":64,"key":"\/apisix\/consumers\/jack","modifiedIndex":64},"prevNode":{"value":"{\"username\":\"jack\",\"plugins\":{\"key-auth\":{\"key\":\"auth-one\"},\"limit-count\":{\"time_window\":60,\"count\":2,\"rejected_code\":503,\"key\":\"remote_addr\",\"policy\":\"local\"}}}","createdIndex":63,"key":"\/apisix\/consumers\/jack","modifiedIndex":63},"action":"set"}
```

从 `v2.2` 版本之后，同一个 consumer 可以绑定多个认证插件。

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## Upstream

*地址*：/apisix/admin/upstreams/{id}

*说明*：Upstream 是虚拟主机抽象，对给定的多个服务节点按照配置规则进行负载均衡。Upstream 的地址信息可以直接配置到 `Route`（或 `Service`) 上，当 Upstream 有重复时，就需要用“引用”方式避免重复了。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/upstreams|无|获取资源列表|
|GET      |/apisix/admin/upstreams/{id}|无|获取资源|
|PUT      |/apisix/admin/upstreams/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/upstreams     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/upstreams/{id}|无|删除资源|
|PATCH    |/apisix/admin/upstreams/{id}|{...}|标准 PATCH ，修改已有 Upstream 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为null 即可删除；特别地，当需要修改属性的值为数组时，该属性将全量更新|
|PATCH    |/apisix/admin/upstreams/{id}/{path}|{...}|SubPath PATCH，通过 {path} 指定 Upstream 需要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。|

> body 请求参数：

APISIX 的 Upstream 除了基本的复杂均衡算法选择外，还支持对上游做主被动健康检查、重试等逻辑，具体看下面表格。

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|type            |必需|枚举||负载均衡算法||
|nodes           |必需，不能和 `service_name` 一起用|Node|哈希表，内部元素的 key 是上游机器地址列表，格式为`地址 + Port`，其中地址部分可以是 IP 也可以是域名，比如 `192.168.1.100:80`、`foo.com:80`等。value 则是节点的权重，特别的，当权重值为 `0` 有特殊含义，通常代表该上游节点失效，永远不希望被选中。`nodes` 可以为空，这通常用作占位符。客户端命中这样的上游会返回 502。|`192.168.1.100:80`|
|service_name   |必需，不能和 `nodes` 一起用|string|服务发现时使用的服务名，见[集成服务发现注册中心](./discovery.md)|`a-bootiful-client`|
|discovery_type   |必需，如果设置了 `service_name` |string|服务发现类型，见[集成服务发现注册中心](./discovery.md)|`eureka`|
|key             |条件必需|匹配类型|该选项只有类型是 `chash` 才有效。根据 `key` 来查找对应的 node `id`，相同的 `key` 在同一个对象中，永远返回相同 id，目前支持的 Nginx 内置变量有 `uri, server_name, server_addr, request_uri, remote_port, remote_addr, query_string, host, hostname, arg_***`，其中 `arg_***` 是来自URL的请求参数，[Nginx 变量列表](http://nginx.org/en/docs/varindex.html)||
|checks          |可选|health_checker|配置健康检查的参数，详细可参考[health-check](../health-check.md)||
|retries         |可选|整型|使用底层的 Nginx 重试机制将请求传递给下一个上游，默认启用重试且次数为后端可用的 node 数量。如果指定了具体重试次数，它将覆盖默认值。`0` 代表不启用重试机制。||
|timeout         |可选|超时时间对象|设置连接、发送消息、接收消息的超时时间||
|hash_on         |可选|辅助|`hash_on` 支持的类型有 `vars`（Nginx内置变量），`header`（自定义header），`cookie`，`consumer`，默认值为 `vars`|
|name     |可选 |辅助|标识上游服务名称、使用场景等。||
|desc     |可选 |辅助|上游服务描述、使用场景等。||
|pass_host            |可选|枚举|`pass` 透传客户端请求的 host, `node` 不透传客户端请求的 host, 使用 upstream node 配置的 host, `rewrite` 使用 `upstream_host` 配置的值重写 host 。默认为 `pass`。||
|upstream_host    |可选|辅助|只在 `pass_host` 配置为 `rewrite` 时有效。||
|scheme|可选 |辅助|跟上游通信时使用的 scheme。需要是 ['http', 'https', 'grpc', 'grpcs'] 其中的一个，默认是 'http'。|
|labels   |可选 |匹配规则|标识附加属性的键值对|{"version":"v2","build":"16","env":"production"}|
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|

`type` 可以是以下的一种：

* `roundrobin`: 带权重的 roundrobin
* `chash`: 一致性哈希
* `ewma`: 选择延迟最小的节点，计算细节参考 https://en.wikipedia.org/wiki/EWMA_chart
* `least_conn`: 选择 `(active_conn + 1) / weight` 最小的节点。注意这里的 `active connection` 概念跟 Nginx 的相同：它是当前正在被请求使用的连接。
* `swrr`: 平滑的基于权重的轮询算法（smooth weighted round-robin）

`hash_on` 比较复杂，这里专门说明下：

1. 设为 `vars` 时，`key` 为必传参数，目前支持的 Nginx 内置变量有 `uri, server_name, server_addr, request_uri, remote_port, remote_addr, query_string, host, hostname, arg_***`，其中 `arg_***` 是来自URL的请求参数，[Nginx 变量列表](http://nginx.org/en/docs/varindex.html)
1. 设为 `header` 时, `key` 为必传参数，其值为自定义的 header name, 即 "http_`key`"
1. 设为 `cookie` 时, `key` 为必传参数，其值为自定义的 cookie name，即 "cookie_`key`"
1. 设为 `consumer` 时，`key` 不需要设置。此时哈希算法采用的 `key` 为认证通过的 `consumer_name`。
1. 如果指定的 `hash_on` 和 `key` 获取不到值时，就是用默认值：`remote_addr`。

upstream 对象 json 配置内容：

```shell
{
    "id": "1",                  # id
    "retries": 1,               # 请求重试次数
    "timeout": {                # 设置连接、发送消息、接收消息的超时时间
        "connect":15,
        "send":15,
        "read":15,
    },
    "nodes": {"host:80": 100},  # 上游机器地址列表，格式为`地址 + Port`
    "type":"roundrobin",
    "checks": {},               # 配置健康检查的参数
    "hash_on": "",
    "key": "",
    "name": "upstream-xxx",      # upstream 名称
    "desc": "hello world",      # upstream 描述
}
```

具体示例：

```shell
# 创建一个upstream
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "type":"roundrobin",
    "nodes":{
        "127.0.0.1:80":1,
        "127.0.0.2:80":2,
        "foo.com:80":3
    }
}'
HTTP/1.1 201 Created
...


# 给 Upstream 增加一个 node
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "nodes": {
        "39.97.63.216:80": 1
    }
}'
HTTP/1.1 200 OK
...

执行成功后，nodes 将更新为：
{
    "39.97.63.215:80": 1,
    "39.97.63.216:80": 1
}


# 给 Upstream 更新一个 node 的权重
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "nodes": {
        "39.97.63.216:80": 10
    }
}'
HTTP/1.1 200 OK
...

执行成功后，nodes 将更新为：
{
    "39.97.63.215:80": 1,
    "39.97.63.216:80": 10
}


# 给 Upstream 删除一个 node
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "nodes": {
        "39.97.63.215:80": null
    }
}'
HTTP/1.1 200 OK
...

执行成功后，nodes 将更新为：
{
    "39.97.63.216:80": 10
}


# 替换 Upstream 的  nodes
$ curl http://127.0.0.1:9080/apisix/admin/upstreams/100/nodes -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PATCH -i -d '
{
    "39.97.63.200:80": 1
}'
HTTP/1.1 200 OK
...

执行成功后，nodes 将不保留原来的数据，整个更新为：
{
    "39.97.63.200:80": 1
}

```

> 应答参数

目前是直接返回与 etcd 交互后的结果。

[Back to TOC](#目录)

## SSL

*地址*：/apisix/admin/ssl/{id}

*说明*：SSL.

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/ssl|无|获取资源列表|
|GET      |/apisix/admin/ssl/{id}|无|获取资源|
|PUT      |/apisix/admin/ssl/{id}|{...}|根据 id 创建资源|
|POST     |/apisix/admin/ssl     |{...}|创建资源，id 由后台服务自动生成|
|DELETE   |/apisix/admin/ssl/{id}|无|删除资源|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|cert|必需|证书|https 证书||
|key|必需|私钥|https 证书私钥||
|certs|可选|证书字符串数组|当你想给同一个域名配置多个证书时，除了第一个证书需要通过cert传递外，剩下的证书可以通过该参数传递上来||
|keys|可选|私钥字符串数组|certs 对应的证书私钥，注意要跟 certs 一一对应||
|snis|必需|匹配规则|非空数组形式，可以匹配多个 SNI||
|labels|可选|匹配规则|标识附加属性的键值对|{"version":"v2","build":"16","env":"production"}|
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|status|可选 |辅助| 是否启用此SSL, 缺省 `1`。|`1` 表示启用，`0` 表示禁用|

ssl 对象 json 配置内容：

```shell
{
    "id": "1",          # id
    "cert": "cert",     # 证书
    "key": "key",       # 私钥
    "snis": ["t.com"]   # HTTPS 握手时客户端发送的 SNI
}
```

[Back to TOC](#目录)

## Global Rule

*地址*：/apisix/admin/global_rules/{id}

*说明*：设置全局运行的插件。这一类插件在所有路由级别的插件之前优先运行。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/global_rules|无|获取资源列表|
|GET      |/apisix/admin/global_rules/{id}|无|获取资源|
|PUT      |/apisix/admin/global_rules/{id}|{...}|根据 id 创建资源|
|DELETE   |/apisix/admin/global_rules/{id}|无|删除资源|
|PATCH    |/apisix/admin/global_rules/{id}|{...}|标准 PATCH ，修改已有 Global Rule 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为null 即可删除；特别地，当需要修改属性的值为数组时，该属性将全量更新|
|PATCH    |/apisix/admin/global_rules/{id}/{path}|{...}|SubPath PATCH，通过 {path} 指定 Global Rule 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|plugins  |必需|Plugin|详见 [Plugin](architecture-design.md#plugin) ||
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|

[Back to TOC](#目录)

## Plugin Config

*地址*：/apisix/admin/plugin_configs/{id}

*说明*：配置一组可以在路由间复用的插件。

> 请求方法：

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/plugin_configs|无|获取资源列表|
|GET      |/apisix/admin/plugin_configs/{id}|无|获取资源|
|PUT      |/apisix/admin/plugin_configs/{id}|{...}|根据 id 创建资源|
|DELETE   |/apisix/admin/plugin_configs/{id}|无|删除资源|
|PATCH    |/apisix/admin/plugin_configs/{id}|{...}|标准 PATCH ，修改已有 Plugin Config 的部分属性，其他不涉及的属性会原样保留；如果你要删除某个属性，将该属性的值设置为null 即可删除；特别地，当需要修改属性的值为数组时，该属性将全量更新|
|PATCH    |/apisix/admin/plugin_configs/{id}/{path}|{...}|SubPath PATCH，通过 {path} 指定 Plugin Config 要更新的属性，全量更新该属性的数据，其他不涉及的属性会原样保留。|

> body 请求参数：

|名字      |可选项   |类型 |说明        |示例|
|---------|---------|----|-----------|----|
|plugins  |必需|Plugin|详见 [Plugin](architecture-design.md#plugin) ||
|desc     |可选|辅助|标识描述、使用场景等|customer xxxx|
|create_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|
|update_time|可选|辅助|单位为秒的 epoch 时间戳，如果不指定则自动创建|1602883670|

[Back to TOC](#目录)

## Plugin Metadata

*地址*：/apisix/admin/plugin_metadata/{plugin_name}

*说明*: 插件元数据。

> 请求方法:

|Method   |请求 URI|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/plugin_metadata/{plugin_name}|无|获取资源|
|PUT      |/apisix/admin/plugin_metadata/{plugin_name}|{...}|根据 plugin name 创建资源|
|DELETE   |/apisix/admin/plugin_metadata/{plugin_name}|无|删除资源|

> body 请求参数：

一个根据插件 ({plugin_name}) 的 `metadata_schema` 定义的数据结构的 json object 。

例子:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/plugin_metadata/example-plugin  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -i -X PUT -d '
{
    "skey": "val",
    "ikey": 1
}'
HTTP/1.1 201 Created
Date: Thu, 26 Dec 2019 04:19:34 GMT
Content-Type: text/plain
```

[Back to TOC](#目录)

## Plugin

*地址*：/apisix/admin/plugins/{plugin_name}

*说明*: 插件

> 请求方法:

|名字      |请求 uri|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/plugins/list|无|获取资源列表|
|GET      |/apisix/admin/plugins/{plugin_name}|无|获取资源|

> body 请求参数：

获取插件 ({plugin_name}) 数据结构的 json object 。

例子:

```shell
$ curl "http://127.0.0.1:9080/apisix/admin/plugins/list" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
["zipkin","request-id",...]

$ curl "http://127.0.0.1:9080/apisix/admin/plugins/key-auth" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
{"properties":{"disable":{"type":"boolean"}},"additionalProperties":false,"type":"object"}
```

*地址*：/apisix/admin/plugins?all=true

*说明*: 所有插件的所有属性，每个插件包括 `name`, `priority`, `type`, `schema`, `consumer_schema` and `version`。

> 请求方法:

|Method   |请求 URI|请求 body|说明        |
|---------|-------------------------|--|------|
|GET      |/apisix/admin/plugins?all=true|无|获取资源|

[Back to TOC](#目录)
