---
title: 如何构建 Apache APISIX
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

## 步骤1：安装依赖

Apache APISIX 的运行环境需要依赖 NGINX 和 etcd，所以在安装 Apache APISIX 前，请根据您使用的操作系统安装对应的依赖。我们提供了 **CentOS7** 、**Fedora 31 & 32** 、**Ubuntu 16.04 & 18.04** 、 **Debian 9 & 10** 和 **MacOS** 上的依赖安装操作步骤，详情请参考[安装依赖](install-dependencies.md)。

通过 Docker 或 Helm Chart 安装 Apache APISIX 时，已经包含了所需的 NGINX 和 etcd，请参照各自对应的文档。

## 步骤2：安装 Apache APISIX

你可以通过源码包、RPM 包、Docker、Helm Chart 等多种方式来安装 Apache APISIX。请在以下选项中选择其中一种执行。

### 通过源码包安装

1. 创建一个名为 `apisix-2.7` 的目录。

  ```shell
  mkdir apisix-2.7
  ```

2. 下载 Apache APISIX Release 源码包：

  ```shell
  wget https://downloads.apache.org/apisix/2.7/apache-apisix-2.7-src.tgz
  ```

  您也可以通过 Apache APISIX 官网下载 Apache APISIX Release 源码包。 Apache APISIX 官网也提供了 Apache APISIX、APISIX Dashboard 和 APISIX Ingress Controller 的源码包，详情请参考[Apache APISIX 官网-下载页](https://apisix.apache.org/zh/downloads)。

3. 解压 Apache APISIX Release 源码包：

  ```shell
  tar zxvf apache-apisix-2.7-src.tgz -C apisix-2.7
  ```

4. 安装运行时依赖的 Lua 库：

  ```shell
  # 切换到 apisix-2.7 目录
  cd apisix-2.7
  # 创建依赖
  make deps
  ```

### 通过 RPM 包安装（CentOS 7）

这种安装方式适用于 CentOS 7 操作系统，请运行以下命令安装 Apache APISIX。

```shell
sudo yum install -y https://github.com/apache/apisix/releases/download/2.7/apisix-2.7-0.x86_64.rpm
```

### 通过 Docker 安装

详情请参考：[使用 Docker 安装 Apache APISIX](https://hub.docker.com/r/apache/apisix)。

### 通过 Helm Chart 安装

详情请参考：[使用 Helm Chart 安装 Apache APISIX](https://github.com/apache/apisix-helm-chart)。

## 步骤3：管理 Apache APISIX 服务

我们可以在 Apache APISIX 的目录下使用命令初始化依赖、启动服务和停止服务，也可以通过 `make help` 命令查看所有命令和对应的功能。

### 初始化依赖

运行以下命令初始化 NGINX 配置文件和 etcd。

```shell
# initialize NGINX config file and etcd
make init
```

### 启动 Apache APISIX

运行以下命令启动 Apache APISIX。

```shell
# start Apache APISIX server
make run
```

### 停止运行 Apache APISIX

优雅停机 `make quit` 和强制停机 `make stop`都可以停止运行 Apache APISIX。建议您优先选择优雅停机的方式停止 Apache APISIX，因为这种停止方式能够保证 Apache APISIX 完成了已经接受到的请求之后再停止；而强制停机则是立即停止 Apache APISIX，在这种情况下，Apache APISIX 接收到但未完成的请求会随着强制停机一并停止。

执行优雅停机的命令如下所示：

```shell
# stop Apache APISIX server gracefully
make quit
```

执行强制停机的命令如下所示：

```shell
# stop Apache APISIX server immediately
make stop
```

### 查看其他操作

运行 `make help` 命令，查看返回结果，获取其他操作的命令和描述。

```shell
# more actions find by `help`
make help
```

## 步骤4：运行测试案例

1. 安装 `perl` 的包管理器 `cpanminus`。

2. 然后通过 `cpanm` 来安装 test-nginx 的依赖：

  ```shell
  sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)
  ```

3. 运行 `git clone` 命令，将最新的源码克隆到本地，请使用我们 fork 出来的版本：

  ```shell
  git clone https://github.com/iresty/test-nginx.git
  ```

4. 通过 `perl` 的 `prove` 命令来加载 test-nginx 的库，并运行 `/t` 目录下的测试案例集：

  - 追加当前目录到perl模块目录： `export PERL5LIB=.:$PERL5LIB`，然后运行 `make test` 命令。

  - 或指定 NGINX 二进制路径：`TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`。

  :::note 说明
  部分测试需要依赖外部服务和修改系统配置。如果想要完整地构建测试环境，可以参考 `ci/linux_openresty_common_runner.sh`。
  :::

### 问题排查

**配置 NGINX 路径**

出现`Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf` 报错的解决方法如下：

确保将 Openresty 设置为默认的 NGINX，并按如下所示导出路径：

* `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * Linux 默认安装路径：
    * `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * MacOS 通过 homebrew 默认安装路径：
    * `export PATH=/usr/local/opt/openresty/nginx/sbin:$PATH`

**运行单个测试用例**

使用以下命令运行指定的测试用例：

```shell
prove -Itest-nginx/lib -r t/plugin/openid-connect.t
```

## 步骤5：修改 Admin API key

您需要修改 Admin API 的 key，以保护 Apache APISIX。

请修改 `conf/config.yaml` 中的 `apisix.admin_key` 并重启服务，如下所示：

```yaml
apisix:
  # ... ...
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh # 将原有的 key 修改为abcdefghabcdefgh
      role: admin
```

当我们需要访问 Admin API 时，就可以使用上面记录的 key 了，如下所示：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=abcdefghabcdefgh -i
```

返回结果中的状态码 200 说明访问成功，如下所示：

```shell
HTTP/1.1 200 OK
Date: Fri, 28 Feb 2020 07:48:04 GMT
Content-Type: text/plain
... ...
{"node":{...},"action":"get"}
```

在这个时候，如果您输入的 key 与 `conf/config.yaml` 中 `apisix.admin_key` 的值不匹配，例如，我们已知正确的 key 是 `abcdefghabcdefgh`，但是我们选择输入一个错误的 key，例如 `wrong-key`，如下所示：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=wrong-key -i
```

返回结果中的状态码 `401` 说明访问失败，原因是输入的 `key` 有误，未通过认证，触发 `Unauthorized` 错误，如下所示：

```shell
HTTP/1.1 401 Unauthorized
Date: Fri, 28 Feb 2020 08:17:58 GMT
Content-Type: text/html
... ...
{"node":{...},"action":"get"}
```

## 步骤6：为 Apache APISIX 构建 OpenResty

有些功能需要引入额外的 NGINX 模块到 OpenResty 当中。如果您需要这些功能，你可以用[这个脚本](https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh)构建 OpenResty。

## 步骤7：为 Apache APISIX 添加 systemd 配置文件

如果您使用的操作系统是 CentOS 7，且在步骤 2 中通过 RPM 包安装 Apache APISIX，配置文件已经自动安装到位，你可以直接运行以下命令：

```shell
systemctl start apisix
systemctl stop apisix
```

如果通过其他方法安装，可以参考[配置文件模板](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service)进行修改，并将其放置在 `/usr/lib/systemd/system/apisix.service`路径下。
