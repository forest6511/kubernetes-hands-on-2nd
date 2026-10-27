#!/usr/bin/env bash
# 各章の up.sh と e2e が共通で使う関数。本文の手順と同じコマンドを、同じ順で実行する。
# minikube のプロファイルは環境変数 MINIKUBE_PROFILE で変えられる（既定は minikube）。

K8S_VERSION=v1.37.0
NGF_VERSION=v2.8.0
NGF_RAW=https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}

# 第2章: minikube を起動する（本書で使う版と大きさを全部指定する）
start_minikube() {
  minikube start --driver=docker --container-runtime=containerd \
    --kubernetes-version="${K8S_VERSION}" --cpus=2 --memory=3072
  kubectl wait --for=condition=Ready node --all --timeout=180s
}

# 第3章: 自分のイメージを作って minikube に渡す
load_images_v1() {
  docker build -t todo-api:v1 app/api
  docker build -t todo-frontend:v1 app/frontend
  minikube image load todo-api:v1
  minikube image load todo-frontend:v1
}

# 第4章: 見出しの色だけを変えた todo-frontend の v2
load_frontend_v2() {
  docker build -t todo-frontend:v2 --build-arg VERSION=v2 app/frontend
  minikube image load todo-frontend:v2
}

# 第5章: Gateway API の CRD と NGINX Gateway Fabric を入れる
install_gateway_api() {
  kubectl kustomize \
    "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}" \
    | kubectl apply -f -
  kubectl apply --server-side -f "${NGF_RAW}/deploy/crds.yaml"
  kubectl apply -f "${NGF_RAW}/deploy/nodeport/deploy.yaml"
  kubectl wait -n nginx-gateway --for=condition=Available deployment --all --timeout=300s
}

# 第N章の終わりの状態を作る（N=2〜7）。前の章の終わりを順に積み上げる
reach_end_of() {
  local n=$1
  start_minikube
  [ "$n" -ge 3 ] || return 0
  # 第3章の終わり: 3つの Deployment（todo-api と todo-frontend は名前が引けずに止まっている）
  load_images_v1
  kubectl apply -f ch03/todo-db.yaml -f ch03/todo-api.yaml -f ch03/todo-frontend.yaml
  [ "$n" -ge 4 ] || return 0
  # 第4章の終わり: 3つの Service と、v2 の todo-frontend
  kubectl apply -f ch04/todo-db-service.yaml -f ch04/todo-api-service.yaml \
    -f ch04/todo-frontend-service.yaml
  load_frontend_v2
  kubectl set image deployment/todo-frontend nginx=todo-frontend:v2
  kubectl rollout restart deployment/todo-frontend
  kubectl rollout status deployment/todo-frontend --timeout=300s
  kubectl rollout status deployment/todo-api --timeout=300s
  [ "$n" -ge 5 ] || return 0
  # 第5章の終わり: Gateway と HTTPRoute
  install_gateway_api
  kubectl apply -f ch05/gateway.yaml
  kubectl wait --for=condition=Programmed gateway/todo-gateway --timeout=300s
  kubectl apply -f ch05/httproute.yaml
  # Gateway の Pod（todo-gateway-nginx）が準備できるまで待つ（minikube service で URL を出すため）
  kubectl wait --for=condition=Available deployment/todo-gateway-nginx --timeout=300s
  [ "$n" -ge 6 ] || return 0
  # 第6章の終わり: ConfigMap・Secret・PVC
  kubectl apply -f ch06/todo-config.yaml
  kubectl create secret generic todo-db --from-literal=password=todo-pass \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f ch06/todo-db-pvc.yaml
  kubectl apply -f ch06/todo-db.yaml -f ch06/todo-api.yaml
  kubectl rollout status deployment/todo-db --timeout=300s
  kubectl rollout status deployment/todo-api --timeout=300s
  [ "$n" -ge 7 ] || return 0
  # 第7章の終わり: Kustomize の dev で入れたアプリ
  kubectl apply -k ch07/kustomize/shared
  kubectl apply -k ch07/kustomize/overlays/dev
  kubectl rollout restart deployment/todo-api
  kubectl rollout status deployment/todo-api --timeout=300s
}

# 章の開始状態を表示し、ブラウザで開く方法を案内する
show_start_state() {
  local n=$1
  kubectl get pods
  if [ "$n" -ge 6 ]; then
    echo
    echo "別のターミナルで次を実行し、表示された URL をブラウザで開いてください:"
    echo "  minikube service todo-gateway-nginx --url"
  fi
}
