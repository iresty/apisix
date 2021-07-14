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

## 目录

- [**名称**](#名称)
- [**属性**](#属性)
- [**如何启用**](#如何启用)
- [**测试插件**](#测试插件)
- [**禁用插件**](#禁用插件)

## 名称

`request-id` 插件通过 APISIX 为每一个请求代理添加唯一 ID（UUID），以用于追踪 API 请求。该插件在 `header_name` 已经在请求中存在时不会为请求添加新的 ID。

## 属性

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| header_name         | string  | 可选 | "X-Request-Id" |                       | Request ID header name         |
| include_in_response | boolean | 可选 | false          |                       | 是否需要在返回头中包含该唯一ID |
| algorithm           | string  | 可选 | "uuid"         | ["uuid", "snowflake"] | ID 生成算法 |

## 如何启用

创建一条路由并在该路由上启用 `request-id` 插件：

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

## 测试插件

```shell
$ curl -i http://127.0.0.1:9080/hello
HTTP/1.1 200 OK
X-Request-Id: fe32076a-d0a5-49a6-a361-6c244c1df956
......
```

### 使用 snowflake 算法

> 支持使用 snowflake 算法来生成ID。
> 在决定使用snowflake时，请优先阅读一下文档。因为一旦启用配置信息则不可随意调整配置信息。否则可能会导致生成重复ID。

snowflake 算法默认是不启用的，需要在 `conf/config.yaml` 中开启配置。

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1609459200000
      data_machine_bits: 12
      sequence_bits: 10
      data_machine_ttl: 30
      data_machine_interval: 10
```

#### 配置参数

| 名称                | 类型    | 必选项   | 默认值         | 有效值 | 描述                           |
| ------------------- | ------- | -------- | -------------- | ------ | ------------------------------ |
| enable                     | boolean  | 可选 | false          |  | 当设置为true时， 启用snowflake算法。      |
| snowflake_epoc             | integer  | 可选 | 1609459200000  |  | 起始时间戳（单位： 毫秒）       |
| data_machine_bits          | integer  | 可选 | 12             |  | 数据机器位`datacenterId` + `workerId`（1 << node_id_bits） |
| sequence_bits              | integer  | 可选 | 10             |  | 每个节点每毫秒内最多产生ID数量 （1 << sequence_bits） |
| delta_offset               | integer  | 可选 | 1              |  | 时间戳增量偏移（单位： 毫秒） |
| data_machine_ttl          | integer  | 可选 | 30             |  | `etcd` 中 `data_machine` 注册有效时间（单位： 秒）|
| data_machine_interval     | integer  | 可选 | 10             |  | `etcd` 中 `data_machine` 续约间隔时间（单位： 秒）|

- snowflake_epoc 默认起始时间为 `2021-01-01T00:00:00Z`, 按默认配置可以支持 `69年` 大约可以使用到 `2090-09-07 15:47:35Z`
- data_machine_bits 对应的是 snowflake 定义中的 WorkerID 和 DatacenterIDd的集合，插件会为每一个进程分配一个唯一ID，最大支持进程数为 `pow(2, data_machine_bits)`。默认占 `12 bits` 最多支持 `4096` 个进程。
- sequence_bits 默认占 `10 bits`, 每个进程每秒最多生成 `1024` 个ID
- delta_offset 时间戳增量偏移 (单位: 毫秒) [`delta_offset=1` 每毫秒, `delta_offset=10` 每10毫秒, `delta_offset=100` 每100毫秒, `delta_offset=1000` 每1秒`]

#### 配置示例

> snowflake 支持灵活配置来满足各式各样的需求

- snowflake 原版配置

> - 起始时间 2014-10-20T15:00:00.000Z， 精确到毫秒为单位。大约可以使用 `69年`
> - 最多支持 `1024` 个进程
> - 每个进程每秒最多产生 `4096` 个ID

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1413817200000
      data_machine_bits: 10
      sequence_bits: 12
```

- [sonyflake](https://github.com/sony/sonyflake)

> - 39 bit 为时间戳，精确到 `10ms` 大约可以使用174年。
> - 16 bit 做为机器号， 可同时支持 `65536` 个进程运行。
> - 8 bit 做为序列号，每10毫最大生成256个，1秒最多生成25600个。

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1413817200000
      data_machine_bits: 16
      sequence_bits: 8
      delta_offset: 10
```

- [baidu UidGenerator](https://github.com/baidu/uid-generator)

不支持 Double RingBuffer

> - delta seconds (28 bits)
> - 当前时间，相对于时间基点"2016-05-20"的增量值，单位：秒，最多可支持约8.7年
> - worker id (22 bits) 机器id，最多可支持约420w次机器启动。内置实现为在启动时由数据库分配，默认分配策略为用后即弃，后续可提供复用策略。
> - sequence (13 bits) 每秒下的并发序列，13 bits可支持每秒8192个并发。

```yaml
plugin_attr:
  request-id:
    snowflake:
      enable: true
      snowflake_epoc: 1463644800000
      data_machine_bits: 22
      sequence_bits: 13
      delta_offset: 1000
```

## 禁用插件

在路由 `plugins` 配置块中删除 `request-id 配置，即可禁用该插件，无需重启 APISIX。

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
