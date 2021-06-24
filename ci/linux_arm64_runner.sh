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

. ./ci/common.sh

install_etcd() {
    docker run -d -p 2379:2379 -p 2380:2380 \
        -e ALLOW_NONE_AUTHENTICATION=yes \
        -e ETCD_ADVERTISE_CLIENT_URLS=https://0.0.0.0:2379 \
        -e ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:2379 \
        gcr.io/etcd-development/etcd:v3.4.0-arm64

    docker run -d -p 12379:12379 -p 12380:12380 \
        -e ALLOW_NONE_AUTHENTICATION=yes \
        -e ETCD_ADVERTISE_CLIENT_URLS=https://0.0.0.0:12379 \
        -e ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:12379 \
        -e ETCD_CERT_FILE=/certs/etcd.pem \
        -e ETCD_KEY_FILE=/certs/etcd.key \
        -v /home/runner/work/apisix/apisix/t/certs:/certs \
        gcr.io/etcd-development/etcd:v3.4.0-arm64
}

install_redis() {
    docker run -d -p 5000:6379 -p 5001:6380 -p 5002:6381 -p 5003:6382 -p 5004:6383 -p 5005:6384 --name redis-cluster yiyiyimu/redis-cluster:latest
    sudo apt install -y redis-tools
    docker ps -a
    redis-cli -h 127.0.0.1 -p 5000 ping
    redis-cli -h 127.0.0.1 -p 5000 cluster nodes
}

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)

    ./ci/install-ext-services-via-docker.sh
}

do_install() {
    export_or_prefix

    # install development tools
    sudo apt install -y cpanminus build-essential libncurses5-dev libreadline-dev libssl-dev perl libpcre3-dev zip

    # install openresty
    wget -O - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    echo "deb http://openresty.org/package/arm64/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list
    sudo apt-get update
    sudo apt-get -y install openresty openresty-openssl111-dev

    # install luarocks
    ./utils/linux-install-luarocks.sh

    # install etcdctl
    install_etcd
    wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-arm64.tar.gz
    tar -xvf etcd-v3.4.13-linux-arm64.tar.gz && \
        cd etcd-v3.4.13-linux-arm64 && \
        sudo cp -a etcd etcdctl /usr/bin/

    install_redis

    # install test::nginx
    sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # install and start grpc_server_example
    ## install golang to build grpc_server_example for arm for now
    wget https://golang.org/dl/go1.16.4.linux-arm64.tar.gz
    tar -C /usr/local -xzf go1.16.4.linux-arm64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    go version

    mkdir build-cache

    mv grpc_server_example build-cache/
    git clone https://github.com/iresty/grpc_server_example.git grpc_server_example
    cd grpc_server_example
    go build
    mv grpc_server_example ../build-cache/ && mv proto/ ../build-cache/
    cd ..
    ./build-cache/grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 -grpcs-mtls-address :50053 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key -ca ./t/certs/mtls_ca.crt \
        > grpc_server_example.log 2>&1 || (cat grpc_server_example.log && exit 1)&

    # wait for grpc_server_example to fully start
    sleep 3

    # install dependencies
    git clone https://github.com/iresty/test-nginx.git test-nginx
    make deps
}

script() {
    export_or_prefix
    openresty -V

    ./utils/set-dns.sh

    ./build-cache/grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 -grpcs-mtls-address :50053 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key -ca ./t/certs/mtls_ca.crt \
        &

    # listen 9081 for http2 with plaintext
    echo '
apisix:
    node_listen:
        - port: 9080
          enable_http2: false
        - port: 9081
          enable_http2: true
    ' > conf/config.yaml

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start

    #start again  --> fail
    res=`./bin/apisix start`
    if ! echo "$res" | grep "APISIX is running"; then
        echo "failed: APISIX runs repeatedly"
        exit 1
    fi

    #kill apisix
    sudo kill -9 `ps aux | grep apisix | grep nginx | awk '{print $2}'`

    #start -> ok
    res=`./bin/apisix start`
    if echo "$res" | grep "APISIX is running"; then
        echo "failed: shouldn't stop APISIX running after kill the old process."
        exit 1
    fi

    sleep 1
    cat logs/error.log

    ./t/grpc-proxy-test.sh
    sleep 1

    ./bin/apisix stop
    sleep 1

    # APISIX_ENABLE_LUACOV=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
    FLUSH_ETCD=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
}

after_success() {
    # cat luacov.stats.out
    # luacov-coveralls
    echo "done"
}

case_opt=$1
shift

case ${case_opt} in
before_install)
    before_install "$@"
    ;;
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
after_success)
    after_success "$@"
    ;;
esac
