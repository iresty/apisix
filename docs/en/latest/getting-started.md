---
title: Getting Started
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

This article is a quick start guide for Apache APISIX. The Quick Start is divided into the following three steps:

1. Install Apache APISIX via [Docker Compose](https://docs.docker.com/compose/).
1. Create a route and bind it with a Upstream.
1. Use `curl` command to verify that the results returned after binding are as expected.

In addition, this article provides some advanced operations on how to use Apache APISIX, including adding authentication, prefixing Route, using the APISIX Dashboard, and troubleshooting.

We will use the following `echo` endpoint as an example, which will return the parameters we passed.

**Request**

The request URL consists of these parameters:

- Protocol: the network transport protocol, `HTTP` protocol is used in our example.
- Port: The port, `80` is used in our example.
- Host: The host, `httpbin.org` is used in our example.
- Path: The path, `/get` is used in our example.
- Query Parameters: the query string, two strings `foo1` and `foo2` are listed in our example.

Run the following command to send the request:

```bash
curl --location --request GET "http://httpbin.org/get?foo1=bar1&foo2=bar2"
```

**Response**

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

## Pre-requisites

- Installed [Docker](https://www.docker.com/) and [Docker Compose component](https://docs.docker.com/compose/).

- We use the [curl](https://curl.se/docs/manpage.html) command for API testing. You can also use other tools such as [Postman](https://www.postman.com/) for testing.

:::note Note
If you already have Apache APISIX installed, please skip Step 1, and go to [Step 2](getting-started.md#step-2-create-a-route) directly.
:::

## Step 1: Install Apache APISIX

Thanks to Docker, we can start Apache APISIX and enable it by enabling [Admin API](./admin-api.md).

```bash
# Download the Docker image of Apache APISIX
git clone https://github.com/apache/apisix-docker.git
# Switch the current directory to the apisix-docker/example path
cd apisix-docker/example
# Run the docker-compose command to install Apache APISIX
docker-compose -p docker-apisix up -d
```

It will take some time to download all required files, please be patient.

Once the download is complete, execute the `curl` command on the host running Docker to access the Admin API, and determine if Apache APISIX was successfully started based on the returned data.

```bash
# Note: Please execute the curl command on the host where you are running Docker.
curl "http://127.0.0.1:9080/apisix/admin/services/" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1'
```

The following data is returned to indicate that Apache APISIX was successfully started:

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

## Step 2: Create a Route

Now we have a running instance of Apache APISIX! Next, let's create a Route.

### How it works

Apache APISIX provides users with a powerful [Admin API](./admin-api.md) and [APISIX Dashboard](https://github.com/apache/apisix-dashboard). In this article, we use the Admin API to walk you through the procedures of creating a Route.

We can create a [Route](./architecture-design/route.md) and connect it to an Upstream service(also known as the [Upstream](./architecture-design/upstream.md)). When a `Request` arrives at Apache APISIX, Apache APISIX knows which Upstream the request should be forwarded to.

Because we have configured matching rules for the Route object, Apache APISIX can forward the request to the corresponding Upstream service. The following code is an example of a Route configuration:

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

This routing configuration means that all matching inbound requests will be forwarded to the Upstream service `httpbin.org:80` when they meet **all** the rules listed below:

- The HTTP method of the request is `GET`.
- The request header contains the `host` field, and its value is `example.com`.
- The request path matches `/services/users/*`, `*` means any subpath, for example `/services/users/getAll?limit=10`.

Once this route is created, we can access the Upstream service using the address exposed by Apache APISIX.

```bash
curl -i -X GET "http://{APISIX_BASE_URL}/services/users/getAll?limit=10" -H "Host: example.com"
```

This will be forwarded to `http://httpbin.org:80/services/users/getAll?limit=10` by Apache APISIX.

### Create an Upstream

After reading the previous section, we know that we must set up an `Upstream` for  the `Route`. An Upstream can be created by simply executing the following command:

```bash
curl "http://127.0.0.1:9080/apisix/admin/upstreams/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "type": "roundrobin",
  "nodes": {
    "httpbin.org:80": 1
  }
}'
```

We use `roundrobin` as the load balancing mechanism, and set `httpbin.org:80` as our upstream target (Upstream service) with an ID of `1`. For more information on the fields, see [Admin API](./admin-api.md).

:::note Note
Creating an Upstream service is not actually necessary, as we can use [Plugin](./architecture-design/plugin.md) to intercept the request and then respond directly. However, for the purposes of this guide, we assume that at least one Upstream service needs to be set up.
:::

### Bind the Route to the Upstream

We've just created an Upstream service (referencing our backend service), now let's bind a Route for it!

```bash
curl "http://127.0.0.1:9080/apisix/admin/routes/1" -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" -X PUT -d '
{
  "uri": "/get",
  "host": "httpbin.org",
  "upstream_id": "1"
}'
```

## Step 3: Validation

We have created the route and the Upstream service and bound them. Now let's access Apache APISIX to test this route.

```bash
curl -i -X GET "http://127.0.0.1:9080/get?foo1=bar1&foo2=bar2" -H "Host: httpbin.org"
```

It returns data from our Upstream service (actually `httpbin.org`) and the result is as expected.

## Advanced Operations

This section provides some advanced operations such as adding authentication, prefixing Route, using the APISIX Dashboard, and troubleshooting.

### Add Authentication

The route we created in step 2 is public. Thus, **anyone** can access this Upstream service as long as they know the address that Apache APISIX exposes to the outside world. This is unsafe, it creates certain security risks. In a practical application scenario, we need to add authentication to the route.

Now we want only a specific user `John` to have access to this Upstream service, and we need to use [Consumer](./architecture-design/consumer.md) and [Plugin](./architecture-design/plugin.md) to implement authentication.

First, let's use [key-auth](./plugins/key-auth.md) plugin to create a [Consumer](./architecture-design/consumer.md) `John`, we need to provide a specified key.

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

Next, let's bind `consumer (John)` to the route, we just need to **enable** the [key-auth](./plugins/key-auth.md) plugin.

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

Now when we access the route created in step 2, an **Unauthorized Error** will be triggered.

The correct way to access that route is to add a `Header` named `apikey` with the correct key, as shown in the code below:

```bash
curl -i -X GET http://127.0.0.1:9080/get -H "Host: httpbin.org" -H 'apikey: superSecretAPIKey'
```

### Prefixing a Route

Now, suppose you want to add a prefix to a route (e.g. samplePrefix) and don't want to use the `host` header, then you can use the `proxy-rewrite` plugin to do so.

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

You can now use the following command to invoke the route:

```bash
curl -i -X GET "http://127.0.0.1:9080/samplePrefix/get?param1=foo&param2=bar" -H "apikey: key-of-john"
```

### APISIX Dashboard

Apache APISIX provides a [Dashboard](https://github.com/apache/apisix-dashboard) to make our operation more intuitive and easier.

![Dashboard](../../assets/images/dashboard.jpeg)

:::note Note
APISIX Dashboard is an experimental feature for now.
:::

### Troubleshooting

- Make sure that all required ports (**default 9080/9443/2379**) are not used by other systems or processes.

    The following are commands to terminate a process that is listening on a specific port (on unix-based systems).

    ```bash
    sudo fuser -k 9443/tcp
    ```

- If the Docker container keeps restarting or failing, log in to the container and observe the logs to diagnose the problem.

    ```bash
    docker logs -f --tail container_id
    ```
