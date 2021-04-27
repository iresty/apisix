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

-[English](../../plugins/auth-hook.md)

# table of Contents

- [**Name**](#name)
- [**Attribute**](#Attribute)
- [**Dependencies**](#Dependencies)
- [**How to enable**](#How-to-enable)
- [**Test plugin**](#Test-plugin)
- [**Disable plugins**](#Disable-plugins)

## name

`auth-hook` is an authentication/authorization plug-in, add `auth-hook` to a `service` or `route`.
The auth-hook function is provided by its own auth-server, and it is sufficient to provide an authorization authentication interface according to the corresponding data structure.

## Attributes

| Name                      | Type          | Required | Default Value | Valid Value | Description                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------- | ------------- | -------- | ------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| auth_hook_uri             | string        | Required |               |             | Set the access route of `auth-server` The plug-in will automatically carry the requested `path, action, client_ip` to the back of the domain name as query parameters `?hook_path=path&hook_action=action&hook_client_ip=client_ip`.                                                                                                                                                                                     |
| auth_hook_id              | string        | Optional | "unset"       |             | Set `auth_hook_id`, the `auth_hook_id` will be carried in the header `Auth-Hook-Id` to request a custom auth-server service .                                                                                                                                                                                                                                                                                            |
| auth_hook_method          | string        | Optional | "GET"         |             | Set the access method of `auth-server`, the default is `GET`, only `POST`, `GET` are allowed .                                                                                                                                                                                                                                                                                                                           |
| hook_headers              | array[string] | Optional |               |             | Specify the header parameters of the business request. Proxy request hook service, which will carry `Authorization` by default.                                                                                                                                                                                                                                                                                          |
| hook_args                 | array[string] | Optional |               |             | Specify request query parameters, proxy requests hook service with query parameters.                                                                                                                                                                                                                                                                                                                                     |
| hook_res_to_headers       | array[string] | Optional |               |             | Specify the fields in the data body of the data returned by the hook service, add the headers parameter and pass it to the upstream service, such as `user_id=15` in the data data, splicing `hook_res_to_header_prefix` and Replace the next `_` with `-` into the header, request upstream services with `X-user-id`, if the selected field is an object or array, it will be converted to a json string as its value. |
| hook_res_to_header_prefix | string        | Optional | "X-"          |             | User `hook_res_to_headers` carries parameters and converts to header field prefix.                                                                                                                                                                                                                                                                                                                                       |
| hook_cache                | boolean       | Optional | false         |             | Whether to cache the same token requesting the data body of the hook service, the default is `false` According to your own business conditions, if it is enabled, it will be cached for 60S.                                                                                                                                                                                                                             |
| check_termination         | boolean       | Optional | true          |             | Whether to request the auth-server to immediately interrupt the request and return an error message after verification, `true` is enabled by default to intercept and return immediately, if set to `false`, auth-server will also return an error Continue to release and delete all mapping header fields set by `hook_res_to_headers`.                                                                                |

## Dependencies

### Deploy your own auth service

The service needs to provide auth interface routing, and at least the following data structure is required to return the data body, we need the `data` data body

```json
{
    "message":"success",
    "data":{
        "user_id":15,
        "......": "......"
    }
}
```

## How to enable

1. Create a Route or Service object and enable the `auth-hook` plugin.

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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

## Test plugin

#### First get the custom `auth-server` authentication service token:

Assume:

```shell script
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIjoxMDE0czONTV9.WYqjytm6.
```

#### Use the obtained token to make a request attempt

- Missing token

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" -i

HTTP/1.1 401 Unauthorized
...
{"message":"Missing rbac token in request"}
```

- Put token in the request header (`Authorization`):

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H'Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIjoxMDE0NTQCET-MDE0NTV9.

HTTP/1.1 200 OK

<!DOCTYPE html>
```

- Put token in the request header (`x_auth_token`):

```shell
curl http://127.0.0.1:9080/ -H"Host: www.baidu.com" \
-H'x_auth_token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm3LCJ1c2VyX2lkIm9.


HTTP/1.1 200 OK

<!DOCTYPE html>
```

- The token is placed in the request parameters:

```shell
curl 'http://127.0.0.1:9080?auth_token=V1%23restful%23eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6NzQ5LCJ1c2VybmFtZSI6InRlc3QiLCJtYW5hZ2VyIjoiIiwiYXBwaWQiOiJyZXN0ZnVsIiwiaWF0IjoxNTc5NDQ5ODQxLCJleHAiOjE1ODAwNTQ2NDF9.n2-830zbhrEh6OAxn4K_yYtg5pqfmjpZAjoQXgtcuts' -H "Host: www.baidu.com" -i


HTTP/1.1 200 OK

<!DOCTYPE html>
```

- The token is placed in the cookie:

```shell
curl http://127.0.0.1:9080 -H"Host: www.baidu.com" \
--cookie auth_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2MTI2OTY1NTIsInN0dWRlbnRfaWQiOjk0ODY3LCJ1c2VyXVyXCs-O-Sc2VyX2lkIjoxMDE0QiOjk0ODY3LCJ1c2VyXVyXV9.


HTTP/1.1 200 OK

<!DOCTYPE html>
```

## Disable plugin

When you want to remove the `auth-hook` plug-in, it is very simple, just delete the corresponding `plug-in` configuration in the plug-in configuration in routes, no need to restart the service, it will take effect immediately:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
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
