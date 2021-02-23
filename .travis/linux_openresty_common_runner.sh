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

. ./.travis/common.sh

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
    docker pull redis:3.0-alpine
    docker run --rm -itd -p 6379:6379 --name apisix_redis redis:3.0-alpine
    docker run --rm -itd -e HTTP_PORT=8888 -e HTTPS_PORT=9999 -p 8888:8888 -p 9999:9999 mendhak/http-https-echo
    # Runs Keycloak version 10.0.2 with inbuilt policies for unit tests
    docker run --rm -itd -e KEYCLOAK_USER=admin -e KEYCLOAK_PASSWORD=123456 -p 8090:8080 -p 8443:8443 sshniro/keycloak-apisix:1.0.0
    # spin up kafka cluster for tests (1 zookeper and 1 kafka instance)
    docker pull bitnami/zookeeper:3.6.0
    docker pull bitnami/kafka:latest
    docker network create kafka-net --driver bridge
    docker run --name zookeeper-server -d -p 2181:2181 --network kafka-net -e ALLOW_ANONYMOUS_LOGIN=yes bitnami/zookeeper:3.6.0
    docker run --name kafka-server1 -d --network kafka-net -e ALLOW_PLAINTEXT_LISTENER=yes -e KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper-server:2181 -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://127.0.0.1:9092 -p 9092:9092 -e KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true bitnami/kafka:latest
    docker pull bitinit/eureka
    docker run --name eureka -d -p 8761:8761 --env ENVIRONMENT=apisix --env spring.application.name=apisix-eureka --env server.port=8761 --env eureka.instance.ip-address=127.0.0.1 --env eureka.client.registerWithEureka=true --env eureka.client.fetchRegistry=false --env eureka.client.serviceUrl.defaultZone=http://127.0.0.1:8761/eureka/ bitinit/eureka
    sleep 5
    docker exec -i kafka-server1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server:2181 --replication-factor 1 --partitions 1 --topic test2
    docker exec -i kafka-server1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server:2181 --replication-factor 1 --partitions 3 --topic test3

    # start skywalking
    docker run --rm --name skywalking -d -p 1234:1234 -p 11800:11800 -p 12800:12800 apache/skywalking-oap-server

    # start RabbitMQ
    docker pull rabbitmq:3-management
    docker run --rm -d  -p 15672:15672 -p 5672:5672 rabbitmq:3-management
}

do_install() {
    export_or_prefix

    ./utils/linux-install-openresty.sh

    ./utils/linux-install-luarocks.sh
    sudo luarocks install luacheck > build.log 2>&1 || (cat build.log && exit 1)

    ./utils/linux-install-etcd-client.sh

    if [ ! -f "build-cache/apisix-master-0.rockspec" ]; then
        create_lua_deps

    else
        src=`md5sum rockspec/apisix-master-0.rockspec | awk '{print $1}'`
        src_cp=`md5sum build-cache/apisix-master-0.rockspec | awk '{print $1}'`
        if [ "$src" = "$src_cp" ]; then
            echo "Use lua deps cache"
            sudo cp -r build-cache/deps ./
        else
            create_lua_deps
        fi
    fi

    # sudo apt-get install tree -y
    # tree deps

    git clone https://github.com/iresty/test-nginx.git test-nginx
    make utils

    git clone https://github.com/apache/openwhisk-utilities.git .travis/openwhisk-utilities
    cp .travis/ASF* .travis/openwhisk-utilities/scancode/

    ls -l ./
    if [ ! -f "build-cache/grpc_server_example_20210122" ]; then
        wget https://github.com/api7/grpc_server_example/releases/download/20210122/grpc_server_example-amd64.tar.gz
        tar -xvf grpc_server_example-amd64.tar.gz
        mv grpc_server_example build-cache/

        git clone --depth 1 https://github.com/api7/grpc_server_example.git grpc_server_example
        pushd grpc_server_example/ || exit 1
        mv proto/ ../build-cache/
        popd || exit 1

        touch build-cache/grpc_server_example_20210122
    fi

    if [ ! -f "build-cache/grpcurl" ]; then
        wget https://github.com/api7/grpcurl/releases/download/20200314/grpcurl-amd64.tar.gz
        tar -xvf grpcurl-amd64.tar.gz
        mv grpcurl build-cache/
    fi
}

script() {
    export_or_prefix
    openresty -V

    ./utils/set-dns.sh

    ./build-cache/grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key \
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

    #start again  --> fial
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

    sudo bash ./utils/check-plugins-code.sh

    make lint && make license-check || exit 1

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
