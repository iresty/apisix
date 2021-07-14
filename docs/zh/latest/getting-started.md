---
title: 快速入门指南
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

## 概述

本文是 Apache APISIX 的快速入门指南。快速入门分为三个步骤：

1. 通过 [Docker Compose](https://docs.docker.com/compose/) 安装 Apache APISIX。
1. 创建路由并绑定上游。
1. 使用命令行语句 `curl` 验证绑定之后返回的结果是否符合预期。

除此之外，本文也提供了 Apache APISIX 的一些进阶操作技巧，包括：添加身份验证、为路由添加前缀、使用 APISIX Dashboard 以及常见问题排查。

我们将以下面的 `echo` 端点为例，它将返回我们传递的参数。

**请求内容**

请求 URL 由以下这些参数构成：

- Protocol：即网络传输协议，示例中使用的是最常见的 `HTTP` 协议。
- Port：即端口，示例中使用的 `80` 端口。
- Host：即宿主机，示例中的主机是 `httpbin.org`。
- Path：即路径，示例中的路径是`/get`。
- Query Parameters：即查询字符串，这里有两个字符串，分别是`foo1`和`foo2`。

运行以下命令，发送请求：

```bash
curl --location --request GET "http://httpbin.org/get?foo1=bar1&foo2=bar2"
```

**响应内容**

```json
{
  "args": {
    "foo1": "bar1",
    "foo2": "bar2"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/7.29.0",
    "X-Amzn-Trace-Id": "Root=1-6088fe84-24f39487166cce1f0e41efc9"
  },
  "origin": "58.152.81.42",
  "url": "http://httpbin.org/get?foo1=bar1&foo2=bar2"
}
```

## 前提条件

- 已安装[Docker Compose 组件](https://docs.docker.com/compose/)。

- 本文使用 [curl](https://curl.se/docs/manpage.html) 命令行进行 API 测试。您也可以使用其他工具例如 [Postman](https://www.postman.com/)等，进行测试。

:::note 说明
如果您已经安装了 Apache APISIX，请直接阅读 [第二步](getting-started.md#第二步：创建路由)
:::

## 第一步：安装 Apache APISIX

得益于 Docker，我们可以通过执行以下命令来启动 Apache APISIX 并启用 [Admin API](./admin-api.md)。

```bash
#将 Apache APISIX 的 Docker 镜像下载到本地
git clone https://github.com/apache/apisix-docker.git
# 将当前的目录切换到 apisix-docker/example 路径下
cd apisix-docker/example
# 运行 docker-compose 命令，安装 Apache APISIX
docker-compose -p docker-apisix up -d
```

下载所需的所有文件将花费一些时间，这取决于您的网络，请耐心等待。

下载完成后，在运行 Docker 的宿主机上执行`curl`命令访问 Admin API，根据返回数据判断 Apache APISIX 是否成功启动。

```bash
# 注意：请在运行 Docker 的宿主机上执行 curl 命令。
curl "http://127.0.0.1:9080/apisix/admin/services/" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

返回数据如下所示，表示Apache APISIX 成功启动：

```json
{
  "count":1,
  "action":"get",
  "node":{
    "key":"/apisix/services",
    "nodes":{},
    "dir":true
  }
}
```

## 第二步：创建路由

您现在已经拥有一个运行中的 Apache APISIX 实例了！接下来，让我们来创建一个路由（Route）。

### 工作原理

Apache APISIX 提供了强大的 [Admin API](./admin-api.md) 和 [Dashboard](https://github.com/apache/apisix-dashboard) 可供我们使用。在本文中，我们使用 Admin API 来做演示。

我们可以创建一个 [Route](./architecture-design/route.md) 并与上游服务（通常也被称为[Upstream](./architecture-design/upstream.md)或后端服务）绑定，当一个 `请求（Request）` 到达 Apache APISIX 时，Apache APISIX 就会明白这个请求应该转发到哪个上游服务中。

因为我们为 Route 对象配置了匹配规则，所以 Apache APISIX 可以将请求转发到对应的上游服务。以下代码是一个 Route 配置示例：

```json
{
  "methods": ["GET"],
  "host": "example.com",
  "uri": "/services/users/*",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "httpbin.org:80": 1
    }
  }
}
```

这条路由配置意味着，当它们满足下述的 **所有** 规则时，所有匹配的入站请求都将被转发到 `httpbin.org:80` 这个上游服务：

- 请求的 HTTP 方法为 `GET`。
- 请求头包含 `host` 字段，且它的值为 `example.com`。
- 请求路径匹配 `/services/users/*`，`*` 意味着任意的子路径，例如 `/services/users/getAll?limit=10`。

当这条路由创建后，我们可以使用 Apache APISIX 对外暴露的地址去访问上游服务：

```bash
curl -i -X GET "http://{APISIX_BASE_URL}/services/users/getAll?limit=10" -H "Host: example.com"
```

这将会被 Apache APISIX 转发到 `http://httpbin.org:80/services/users/getAll?limit=10`。

### 创建上游服务（Upstream）

读完上一节，我们知道必须为 `Route` 设置 `Upstream`。只需执行下面的命令即可创建一个上游服务：

```bash
curl "http://127.0.0.1:9080/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

我们使用 `roundrobin` 作为负载均衡机制，并将 `httpbin.org:80` 设置为我们的上游服务，其 ID 为 `1`。更多字段信息，请参阅 [Admin API](./admin-api.md)。

:::note 注意
创建上游服务实际上并不是必需的，因为我们可以使用 [插件](./architecture-design/plugin.md) 拦截请求，然后直接响应。但在本指南中，我们假设需要设置至少一个上游服务。
:::

### 绑定路由与上游服务

我们刚刚创建了一个上游服务，现在让我们为它绑定一个路由！

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "upstream_id": "1"
}'
```

## 第三步：验证

我们已创建了路由与上游服务，并将它们进行了绑定。现在让我们访问 Apache APISIX 来测试这条路由：

```bash
curl -i -X GET "http://127.0.0.1:9080/get?foo1=bar1&foo2=bar2" -H "Host: httpbin.org"
```

它从我们的上游服务（实际是 `httpbin.org`）返回数据，并且结果符合预期。

## 进阶操作

本节提供了 Apache APISIX 的一些进阶操作技巧，包括：添加身份验证、为路由添加前缀、使用 APISIX Dashboard 以及常见问题排查。

### 添加身份验证

我们在第二步中创建的路由是公共的，只要知道 Apache APISIX 对外暴露的地址，**任何人** 都可以访问这个上游服务，这种访问方式没有保护措施，存在一定的安全隐患。在实际应用场景中，我们需要为路由添加身份验证。

现在我们希望只有特定的用户 `John` 可以访问这个上游服务，需要使用[消费者（Consumer）](./architecture-design/consumer.md) 和 [插件（Plugin）](./architecture-design/plugin.md) 来实现身份验证。

首先，让我们用 [key-auth](./plugins/key-auth.md) 插件创建一个 [消费者（Consumer）](./architecture-design/consumer.md) `John`，我们需要提供一个指定的密钥：

```bash
curl "http://127.0.0.1:9080/apisix/admin/consumers" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "username": "john",
  "plugins": {
    "key-auth": {
      "key": "key-of-john"
    }
  }
}'
```

接下来，让我们绑定 `消费者（John）` 到路由上，我们只需要为路由 **启用** [key-auth](./plugins/key-auth.md) 插件即可。

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "plugins": {
    "key-auth": {}
  },
  "upstream_id": "1"
}'
```

现在当我们访问第二步创建的路由时，会触发 **Unauthorized Error（未经授权的错误）**。

访问那个路由的正确方式是添加一个带有正确密钥的名为 `apikey` 的 `Header`，如下方代码所示。

```bash
curl -i -X GET http://127.0.0.1:9080/get -H "Host: httpbin.org" -H 'apikey: superSecretAPIKey'
```

### 为路由添加前缀

现在，假设您要向路由添加前缀（例如：samplePrefix），并且不想使用 `host` 头， 则可以使用 `proxy-rewrite` 插件来完成。

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/samplePrefix/get",
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": ["^/samplePrefix/get(.*)", "/get$1"]
    },
    "key-auth": {}
  },
  "upstream_id": "1"
}'
```

现在您可以使用以下命令来调用路由：

```bash
curl -i -X GET "http://127.0.0.1:9080/samplePrefix/get?param1=foo&param2=bar" -H "apikey: key-of-john"
```

### APISIX Dashboard

Apache APISIX 提供了一个 [Dashboard](https://github.com/apache/apisix-dashboard)，让我们的操作更直观更轻松。

![Dashboard](../../assets/images/dashboard.jpeg)

:::note 注意
APISIX Dashboard 目前仍然是一个实验性功能。
:::

### 常见问题排查

- 确保所需的所有端口（**默认的 9080/9443/2379**）未被其他系统/进程使用。

    下面是终止正在侦听特定端口（基于 unix 的系统）的进程的命令。

    ```bash
    sudo fuser -k 9443/tcp
    ```

- 如果 Docker 容器持续不断地重启或失败，请登录容器并观察日志以诊断问题。

    ```bash
    docker logs -f --tail container_id
    ```
