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

start_minikube() {
    curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl

    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
    sudo dpkg -i --force-architecture minikube_latest_amd64.deb
    minikube start
}

modify_config() {
    DNS_IP=$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o 'jsonpath={..spec.clusterIP}')
    echo "dns_resolver:
  - ${DNS_IP}
etcd:
  host:
  - \"http://etcd.default.svc.cluster.local:2379\"
plugin_attr:
  prometheus:
    enable_export_server: false
  " > ./conf/config.yaml
    sed -i -e 's/apisix:latest/apisix:alpine-local/g' kubernetes/deployment.yaml
}

port_forward() {
    apisix_pod_name=$(kubectl get pod -l app=apisix-gw -o 'jsonpath={.items[0].metadata.name}')
    nohup kubectl port-forward svc/apisix-gw-lb 9080:9080 >/dev/null 2>&1 &
    nohup kubectl port-forward $apisix_pod_name 9091:9091 >/dev/null 2>&1 &
    ps aux | grep '[p]ort-forward'
}

"$@"
