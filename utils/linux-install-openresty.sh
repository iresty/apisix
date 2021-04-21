#!/usr/bin/env bash
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
set -euo pipefail

wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y update --fix-missing
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb https://openresty.org/package/ubuntu $(lsb_release -sc) main"

sudo apt-get update

if [ "$OPENRESTY_VERSION" == "source" ]; then
    cd ..
    wget https://raw.githubusercontent.com/api7/apisix-build-tools/master/build-apisix-openresty.sh
    chmod +x build-apisix-openresty.sh
    ./build-apisix-openresty.sh latest

    sudo apt-get install openresty-openssl111-debug-dev
    exit 0
fi

if [ "$OPENRESTY_VERSION" == "default" ]; then
    openresty='openresty-debug'
else
    openresty="openresty-debug=$OPENRESTY_VERSION*"
fi

sudo apt-get install "$openresty" lua5.1 liblua5.1-0-dev openresty-openssl111-debug-dev libldap2-dev
