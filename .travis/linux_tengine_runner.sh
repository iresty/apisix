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
    docker run --rm -itd -e KEYCLOAK_USER=admin -e KEYCLOAK_PASSWORD=123456 -p 8090:8080 -p 8443:8443 sshniro/keycloak-apisix
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

    # start RabbitMQ
    docker pull rabbitmq:3-management
    docker run --rm -d  -p 15672:15672 -p 5672:5672 rabbitmq:3-management
}

tengine_install() {
    if [ -d "build-cache${OPENRESTY_PREFIX}" ]; then
        # sudo rm -rf build-cache${OPENRESTY_PREFIX}
        sudo mkdir -p ${OPENRESTY_PREFIX}
        sudo cp -r build-cache${OPENRESTY_PREFIX}/* ${OPENRESTY_PREFIX}/
        ls -l ${OPENRESTY_PREFIX}/
        ls -l ${OPENRESTY_PREFIX}/bin
        return
    fi

    export OPENRESTY_VERSION=1.17.8.2
    wget https://openresty.org/download/openresty-$OPENRESTY_VERSION.tar.gz
    tar zxf openresty-$OPENRESTY_VERSION.tar.gz
    wget https://codeload.github.com/alibaba/tengine/tar.gz/2.3.2
    tar zxf 2.3.2

    rm -rf openresty-$OPENRESTY_VERSION/bundle/nginx-1.17.8
    mv tengine-2.3.2 openresty-$OPENRESTY_VERSION/bundle/

    sed -i 's/= auto_complete "nginx";/= auto_complete "tengine";/g' openresty-$OPENRESTY_VERSION/configure

    cd openresty-$OPENRESTY_VERSION

    # patching start
    # https://github.com/alibaba/tengine/issues/1381#issuecomment-541493008
    # other patches for tengine 2.3.2 from upstream openresty
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-always_enable_cc_feature_tests.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-balancer_status_code.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-cache_manager_exit.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-daemon_destroy_pool.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-delayed_posted_events.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-hash_overflow.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-init_cycle_pool_release.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-larger_max_error_str.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-log_escape_non_ascii.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-no_Werror.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-pcre_conf_opt.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-proxy_host_port_vars.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-resolver_conf_parsing.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-reuseport_close_unused_fds.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-safe_resolver_ipv6_option.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-single_process_graceful_exit.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-ssl_cert_cb_yield.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-ssl_sess_cb_yield.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-stream_balancer_export.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-stream_proxy_get_next_upstream_tries.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-stream_proxy_timeout_fields.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-stream_ssl_preread_no_skip.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-upstream_pipelining.patch
    wget -P patches https://raw.githubusercontent.com/openresty/openresty/master/patches/nginx-1.17.4-upstream_timeout_fields.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/openresty/master/patches/tengine-2.3.2-privileged_agent_process.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-delete_unused_variable.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-keepalive_post_request_status.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-tolerate_backslash_zero_in_uri.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-avoid-limit_req_zone-directive-in-multiple-variables.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-segmentation-fault-in-master-process.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-support-dtls-offload.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-support-prometheus-to-upstream_check_module.patch
    wget -P patches https://raw.githubusercontent.com/totemofwolf/tengine/feature/patches/tengine-2.3.2-vnswrr-adaptated-to-dynamic_resolve.patch

    cd bundle/tengine-2.3.2
    patch -p1 < ../../patches/nginx-1.17.4-always_enable_cc_feature_tests.patch
    patch -p1 < ../../patches/nginx-1.17.4-balancer_status_code.patch
    patch -p1 < ../../patches/nginx-1.17.4-cache_manager_exit.patch
    patch -p1 < ../../patches/nginx-1.17.4-daemon_destroy_pool.patch
    patch -p1 < ../../patches/nginx-1.17.4-delayed_posted_events.patch
    patch -p1 < ../../patches/nginx-1.17.4-hash_overflow.patch
    patch -p1 < ../../patches/nginx-1.17.4-init_cycle_pool_release.patch
    patch -p1 < ../../patches/nginx-1.17.4-larger_max_error_str.patch
    patch -p1 < ../../patches/nginx-1.17.4-log_escape_non_ascii.patch
    patch -p1 < ../../patches/nginx-1.17.4-no_Werror.patch
    patch -p1 < ../../patches/nginx-1.17.4-pcre_conf_opt.patch
    patch -p1 < ../../patches/nginx-1.17.4-proxy_host_port_vars.patch
    patch -p1 < ../../patches/nginx-1.17.4-resolver_conf_parsing.patch
    patch -p1 < ../../patches/nginx-1.17.4-reuseport_close_unused_fds.patch
    patch -p1 < ../../patches/nginx-1.17.4-safe_resolver_ipv6_option.patch
    patch -p1 < ../../patches/nginx-1.17.4-single_process_graceful_exit.patch
    patch -p1 < ../../patches/nginx-1.17.4-ssl_cert_cb_yield.patch
    patch -p1 < ../../patches/nginx-1.17.4-ssl_sess_cb_yield.patch
    patch -p1 < ../../patches/nginx-1.17.4-stream_balancer_export.patch
    patch -p1 < ../../patches/nginx-1.17.4-stream_proxy_get_next_upstream_tries.patch
    patch -p1 < ../../patches/nginx-1.17.4-stream_proxy_timeout_fields.patch
    patch -p1 < ../../patches/nginx-1.17.4-stream_ssl_preread_no_skip.patch
    patch -p1 < ../../patches/nginx-1.17.4-upstream_pipelining.patch
    patch -p1 < ../../patches/nginx-1.17.4-upstream_timeout_fields.patch
    patch -p1 < ../../patches/tengine-2.3.2-privileged_agent_process.patch
    patch -p1 < ../../patches/tengine-2.3.2-delete_unused_variable.patch
    patch -p1 < ../../patches/tengine-2.3.2-keepalive_post_request_status.patch
    patch -p1 < ../../patches/tengine-2.3.2-tolerate_backslash_zero_in_uri.patch
    patch -p1 < ../../patches/tengine-2.3.2-avoid-limit_req_zone-directive-in-multiple-variables.patch
    patch -p1 < ../../patches/tengine-2.3.2-segmentation-fault-in-master-process.patch
    patch -p1 < ../../patches/tengine-2.3.2-support-dtls-offload.patch
    patch -p1 < ../../patches/tengine-2.3.2-support-prometheus-to-upstream_check_module.patch
    patch -p1 < ../../patches/tengine-2.3.2-vnswrr-adaptated-to-dynamic_resolve.patch

    cd -
    # patching end

    ./configure --prefix=${OPENRESTY_PREFIX} --with-debug \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_degradation_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_realip_module \
        --with-stream_ssl_preread_module \
        --with-stream_sni \
        --with-pcre \
        --with-pcre-jit \
        --without-mail_pop3_module \
        --without-mail_imap_module \
        --without-mail_smtp_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_vnswrr_module/ \
        --add-module=bundle/tengine-2.3.2/modules/mod_dubbo \
        --add-module=bundle/tengine-2.3.2/modules/ngx_multi_upstream_module \
        --add-module=bundle/tengine-2.3.2/modules/mod_config \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_concat_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_footer_filter_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_proxy_connect_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_reqstat_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_slice_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_sysguard_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_trim_filter_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_check_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_consistent_hash_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_dynamic_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_dyups_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_http_upstream_session_sticky_module \
        --add-module=bundle/tengine-2.3.2/modules/ngx_http_user_agent_module \
        --add-dynamic-module=bundle/tengine-2.3.2/modules/ngx_slab_stat \
        > build.log 2>&1 || (cat build.log && exit 1)

    make > build.log 2>&1 || (cat build.log && exit 1)

    sudo PATH=$PATH make install > build.log 2>&1 || (cat build.log && exit 1)

    cd ..

    mkdir -p build-cache${OPENRESTY_PREFIX}
    cp -r ${OPENRESTY_PREFIX}/* build-cache${OPENRESTY_PREFIX}
    ls build-cache${OPENRESTY_PREFIX}
    rm -rf openresty-${OPENRESTY_VERSION}

    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb https://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo apt-get update
    sudo apt-get install openresty-openssl-debug-dev
}

do_install() {
    export_or_prefix

    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common

    sudo apt-get update
    sudo apt-get install lua5.1 liblua5.1-0-dev

    tengine_install

    ./utils/linux-install-luarocks.sh

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

    sudo luarocks install luacheck > build.log 2>&1 || (cat build.log && exit 1)

    ./utils/linux-install-etcd-client.sh

    git clone https://github.com/iresty/test-nginx.git test-nginx
    make utils

    git clone https://github.com/apache/openwhisk-utilities.git .travis/openwhisk-utilities
    cp .travis/ASF* .travis/openwhisk-utilities/scancode/

    ls -l ./
}

script() {
    export_or_prefix
    openresty -V


    ./build-cache/grpc_server_example &

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start
    mkdir -p logs
    sleep 1
    ./bin/apisix stop
    sleep 1
    make lint && make license-check || exit 1
    # APISIX_ENABLE_LUACOV=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
}

after_success() {
    cat luacov.stats.out
    luacov-coveralls
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
