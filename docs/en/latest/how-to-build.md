---
title: How to build Apache APISIX
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

## Step 1: Install dependencies

The Apache APISIX runtime environment requires dependencies on NGINX and etcd.

Before installing Apache APISIX, please install dependencies according to the operating system you are using. We provide the dependencies installation instructions for **CentOS7**, **Fedora 31 & 32**, **Ubuntu 16.04 & 18.04**, **Debian 9 & 10**, and **MacOS**, please refer to [Install Dependencies](install-dependencies.md) for more details.

## Step 2: Install Apache APISIX

You can install Apache APISIX via source release packages, RPM package, Docker and Helm Chart. Please choose one from the following options.

### Installation via Source Release Package

1. Create a directory named `apisix-2.7`.

  ```shell
  mkdir apisix-2.7
  ```

2. Download Apache APISIX Release source package.

  ```shell
  wget https://downloads.apache.org/apisix/2.7/apache-apisix-2.7-src.tgz
  ```

  You can also download the Apache APISIX Release source package from the Apache APISIX website. The [Apache APISIX Official Website - Download Page](https://apisix.apache.org/downloads/) also provides source packages for Apache APISIX, APISIX Dashboard and APISIX Ingress Controller.

3. Unzip the Apache APISIX Release source package.

  ```shell
  tar zxvf apache-apisix-2.7-src.tgz -C apisix-2.7
  ```

4. Install the runtime dependent Lua libraries.

  ```shell
  # Switch to the apisix-2.7 directory
  cd apisix-2.7
  # Create dependencies
  make deps
  ```

### Installation via RPM Package(CentOS 7)

This installation method is suitable for CentOS 7, please run the following command to install Apache APISIX.

```shell
sudo yum install -y https://github.com/apache/apisix/releases/download/2.7/apisix-2.7-0.x86_64.rpm
```

### Installation via Docker

Please refer to: [Installing Apache APISIX with Docker](https://hub.docker.com/r/apache/apisix).

### Installation via Helm Chart

Please refer to: [Installing Apache APISIX with Helm Chart](https://github.com/apache/apisix-helm-chart).

## Step 3: Manage Apache APISIX Server

We can initialize dependencies, start service, and stop service with commands in the Apache APISIX directory, we can also view all commands and their corresponding functions with the `make help` command.

### Initializing Dependencies

Run the following command to initialize the NGINX configuration file and etcd.

```shell
# initialize NGINX config file and etcd
make init
```

### Start Apache APISIX

Run the following command to start Apache APISIX.

```shell
# start Apache APISIX server
make run
```

### Stop Apache APISIX

Both `make quit` and `make stop` can stop Apache APISIX. The main difference is that `make quit` stops Apache APISIX gracefully, while `make stop` stops Apache APISIX immediately.

It is recommended to use gracefully stop command `make quit` because it ensures that Apache APISIX will complete all the requests it has received before stopping down. In contrast, `make stop` will trigger a forced shutdown, it stops Apache APISIX immediately, in which case the incoming requests will not be processed before the shutdown.

The command to perform a graceful shutdown is shown below.

```shell
# stop Apache APISIX server gracefully
make quit
```

The command to perform a forced shutdown is shown below.

```shell
# stop Apache APISIX server immediately
make stop
```

### View Other Operations

Run the `make help` command to see the returned results and get commands and descriptions of other operations.

```shell
# more actions find by `help`
make help
```

## Step 4: Run Test Cases

1. Install `cpanminus`, the package manager for `perl`.

2. Then install the test-nginx dependencies via `cpanm`:

  ```shell
  sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)
  ```

3. Run the `git clone` command to clone the latest source code locally, please use the version we forked out：

  ```shell
  git clone https://github.com/iresty/test-nginx.git
  ```

4. Load the test-nginx library with the `prove` command in `perl` and run the test case set in the `/t` directory.

  - Append the current directory to the perl module directory: `export PERL5LIB=.:$PERL5LIB`, then run `make test` command.

  - Or you can specify the NGINX binary path by running this command: `TEST_NGINX_BINARY=/usr/local/bin/openresty prove -Itest-nginx/lib -r t`.

  :::note Note
  Some of the tests rely on external services and system configuration modification. For a complete test environment build, you can refer to `ci/linux_openresty_common_runner.sh`.
  :::

### Troubleshoot Testing

**Configuring NGINX Path**

The solution to the `Error unknown directive "lua_package_path" in /API_ASPIX/apisix/t/servroot/conf/nginx.conf` error is as shown below.

Ensure that Openresty is set to the default NGINX, and export the path as follows:

* `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * Linux default installation path:
    * `export PATH=/usr/local/openresty/nginx/sbin:$PATH`
  * MacOS default installation path via homebrew:
    * `export PATH=/usr/local/opt/openresty/nginx/sbin:$PATH`

**Run a Single Test Case**

Run the specified test case using the following command.

```shell
prove -Itest-nginx/lib -r t/plugin/openid-connect.t
```

## Step 5: Update Admin API token to Protect Apache APISIX

You need to modify the Admin API key to protect Apache APISIX.

Please modify `apisix.admin_key` in `conf/config.yaml` and restart the service as shown below.

```yaml
apisix:
  # ... ...
  admin_key
    -
      name: "admin"
      key: abcdefghabcdefgh # Modify the original key to abcdefghabcdefgh
      role: admin
```

When we need to access the Admin API, we can use the key above, as shown below.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=abcdefghabcdefgh -i
```

The status code 200 in the returned result indicates that the access was successful, as shown below.

```shell
HTTP/1.1 200 OK
Date: Fri, 28 Feb 2020 07:48:04 GMT
Content-Type: text/plain
... ...
{"node":{...},"action":"get"}
```

At this point, if the key you enter does not match the value of `apisix.admin_key` in `conf/config.yaml`, for example, we know that the correct key is `abcdefghabcdefgh`, but we enter an incorrect key, such as `wrong- key`, as shown below.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes?api_key=wrong-key -i
```

The status code `401` in the returned result indicates that the access failed because the `key` entered was incorrect and did not pass authentication, triggering an `Unauthorized` error, as shown below.

```shell
HTTP/1.1 401 Unauthorized
Date: Fri, 28 Feb 2020 08:17:58 GMT
Content-Type: text/html
... ...
{"node":{...},"action":"get"}
```

## Step 6: Build OpenResty for Apache APISIX

Some features require additional NGINX modules to be introduced into OpenResty. If you need these features, you can build OpenResty with [this script](https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh).

## Step 7: Add Systemd Unit File for Apache APISIX

If you are using CentOS 7 and you installed Apache APISIX via the RPM package in step 2, the configuration file is already in place automatically and you can run the following command directly.

```shell
systemctl start apisix
systemctl stop apisix
```

If you installed Apache APISIX by other methods, you can refer to the [configuration file template](https://github.com/api7/apisix-build-tools/blob/master/usr/lib/systemd/system/apisix.service) for modification and put it in the `/usr/lib/systemd/system/apisix.service` path.
