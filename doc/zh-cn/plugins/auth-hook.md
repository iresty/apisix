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

- [English](../../plugins/auth-hook.md)

# 目录

- [**名字**](#名字)
- [**属性**](#属性)
- [**依赖项**](#依赖项)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名字

`auth-hook` 是一个认证及授权插件，添加 `auth-hook` 到一个 `service` 或 `route` 中。
auth-hook 功能由自己 auth-server 提供,按照对应的数据结构提供权限认证接口即可。

## 属性

| 名称                      | 类型          | 必选项 | 默认值  | 有效值 | 描述                                                                                                                                                                                                                                                                    |
| ------------------------- | ------------- | ------ | ------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| auth_hook_uri             | string        | 必选   |         |        | 设置`auth-server` 的访问路由 插件会自动携带请求的`path,action,client_ip`携带到域名后面作为 query 参数`?hook_path=path&hook_action=action&hook_client_ip=client_ip`                                                                                                      |
| auth_hook_id              | string        | 可选   | "unset" |        | 设置`auth_hook_id`, 该`auth_hook_id`将携带在 header 中`Auth-Hook-Id`请求自定义的 auth-server 服务                                                                                                                                                                       |
| auth_hook_method          | string        | 可选   | "GET"   |        | 设置 `auth-server` 的访问方法，默认是`GET`,只允许`POST`,`GET`                                                                                                                                                                                                           |
| hook_headers              | array[string] | 可选   |         |        | 指定业务请求的 header 参数 代理请求 hook 服务，默认会携带`Authorization`                                                                                                                                                                                                |
| hook_args                 | array[string] | 可选   |         |        | 指定请求 query 参数 代理以 query 参数请求 hook 服务                                                                                                                                                                                                                     |
| hook_res_to_headers       | array[string] | 可选   |         |        | 指定 hook 服务返回数据 data 数据体中的字段，加入 headers 参数传递到上游服务，如 data 数据中有`user_id=15`,将拼接`hook_res_to_header_prefix`并将下`_`替换为`-`放入 header 中，以`X-user-id` 请求上游服务，若选择字段是一个对象或许数组，将转换为 json 字符串作为其 value |
| hook_res_to_header_prefix | string        | 可选   | X-      |        | 用户`hook_res_to_headers` 携带参数转换为 header 字段的前缀                                                                                                                                                                                                              |
| hook_cache                | boolean       | 可选   | false   |        | 是否缓存相同 token 请求 hook 服务的数据体，默认`false` 根据自己业务情况考虑,若开启，将缓存 60S                                                                                                                                                                          |
| check_termination         | boolean       | 可选   | true    |        | 是否请求 auth-server 验证后立即中断请求并返回错误信息，`true` 默认开启立即拦截返回，若设置`false` ，auth-server 若返回错误，也将继续放行，同时将 `hook_res_to_headers` 设置的所有映射 header 字段删除。                                                                 |

## 依赖项

### 部署自己 auth 服务

服务需要提供 auth 接口路由，并且至少需要以下数据结构返回数据数据体，我们需要其中的`data`数据体

```json
{
    "message":"success",
    "data":{
        "user_id":15,
        "......":"......"
    }
}
```

## 如何启用

1. 创建 Route 或 Service 对象，并开启 `auth-hook` 插件。

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
        "auth-hook": {
                       "auth_hook_id": "order",
                       "auth_hook_method": "POST",
                       "auth_hook_uri": "http://xxx.your.com/api/user/gateway-auth",
                       "hook_cache": false,
                       "check_termination": true,
                       "hook_headers": [
                         "X-app-name"
                       ],
                       "hook_res_to_header_prefix": "XT-",
                       "hook_res_to_headers": [
                         "user_id",
                         "student_id"
                       ]
                     }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
}'
```

## 测试插件

#### 首先获取自定义 `auth-server` 鉴权服务 token:

假设为：

```shell script
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIjoxMDE0NTV9.WYHLjtm6cZgczX0g_Oq3Ycs-AFgmxuVkET3SCjcKeO8
```

#### 使用获取到的 token 进行请求尝试

- 缺少 token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i

HTTP/1.1 401 Unauthorized
...
{"message":"Missing rbac token in request"}
```

- token 放到请求头(`Authorization`)中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIjoxMDE0NTV9.WYHLjtm6cZgczX0g_Oq3Ycs-AFgmxuVkET3SCjcKeO8' -i

HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到请求头(`x_auth_token`)中：

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H 'x_auth_token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIjoxMDE0NTV9.WYHLjtm6cZgczX0g_Oq3Ycs-AFgmxuVkET3SCjcKeO8' -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到请求参数中：

```shell
curl 'http://127.0.0.1:9080?auth_token=V1%23restful%23eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -H"Host: www.baidu.com" -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

- token 放到 cookie 中：

```shell
curl http://127.0.0.1:9080 -H"Host: www.baidu.com" \
--cookie auth_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIjoxMDE0NTV9.WYHLjtm6cZgczX0g_Oq3Ycs-AFgmxuVkET3SCjcKeO8 -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

## 禁用插件

当你想去掉 `auth-hook` 插件的时候，很简单，在 routes 中的插件配置中把对应的 `插件` 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/*",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "www.baidu.com:80": 1
        }
    }
}'
```
