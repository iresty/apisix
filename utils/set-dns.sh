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

set -ex

# test a domain name is configured as upstream
echo "127.0.0.1 test.com" | sudo tee -a /etc/hosts
# test certificate verification
echo "127.0.0.1 admin.apisix.dev" | sudo tee -a /etc/hosts
cat /etc/hosts # check GitHub Action's configuration

echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "search apache.org" | sudo tee -a /etc/resolv.conf

mkdir -p build-cache

echo `uname -a`
UNAME=`uname -a | grep -o aarch64 | wc -l`
ARCH="amd64"
if [ $UNAME -ne 0 ]; then
    ARCH="arm64"
fi
echo $ARCH

if [ ! -f "build-cache/coredns_1_8_1" ]; then
    wget https://github.com/coredns/coredns/releases/download/v1.8.1/coredns_1.8.1_linux_${ARCH}.tgz
    tar -xvf coredns_1.8.1_linux_amd64.tgz
    mv coredns build-cache/

    touch build-cache/coredns_1_8_1
fi

pushd t/coredns || exit 1
../../build-cache/coredns -dns.port=1053 &
popd || exit 1
