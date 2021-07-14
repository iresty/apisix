---
title: Global rule
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

[Plugin](plugin.md) 只能绑定在 [Service](service.md) 或者 [Route](route.md) 上，如果我们需要一个能作用于所有请求的 [Plugin](plugin.md) 该怎么办呢？
这时候我们可以使用 `GlobalRule` 来注册一个全局的 [Plugin](plugin.md):

```shell
curl -X PUT \
  https://{apisix_listen_address}/apisix/admin/global_rules/1 \
  -H 'Content-Type: application/json' \
  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' \
  -d '{
        "plugins": {
            "limit-count": {
                "time_window": 60,
                "policy": "local",
                "count": 2,
                "key": "remote_addr",
                "rejected_code": 503
            }
        }
    }'
```

如上所注册的 `limit-count` 插件将会作用于所有的请求。

我们可以通过以下接口查看所有的 `GlobalRule`:
当 `Route` 和 `Service` 都开启同一个插件时，Route 参数的优先级是高于 Service 的。但是`GlobalRule`优先级高于`Route`和`Service`

```shell
curl https://{apisix_listen_address}/apisix/admin/global_rules -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```
