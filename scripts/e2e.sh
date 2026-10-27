#!/usr/bin/env bash
# shellcheck disable=SC2329  # 章の関数は "ch$CH" で呼ぶ（間接呼び出し）
# 本文の手順を章ごとに実行し、章の判定項目を確かめる。
#   bash scripts/e2e.sh 04          第4章（開始状態は第3章の終わり。無ければ先に ch04/up.sh）
#   CAPTURE=1 bash scripts/e2e.sh 04  本に載せる実行結果を docs/logs/ に保存する
# 判定の結果は「PASS <項目> <内容>」の行で出し、最後に項目ごとの件数を出す。
# minikube のプロファイルは MINIKUBE_PROFILE で指定する（e2e-all.sh は k8sbook-e2e を使い、既定の minikube には触らない）
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source scripts/lib.sh

CH=${1:?章の番号（01〜08）}
LOGDIR=docs/logs
RESULTS=${E2E_RESULTS:-$(mktemp)}
TRACE=${E2E_TRACE:-/dev/null}
PROFILE=${MINIKUBE_PROFILE:-minikube}
FRONT_PORT=8000
API_PORT=8001
BG_PIDS=()

cleanup() {
  for p in "${BG_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  return 0
}
trap cleanup EXIT

# ---- 判定 ------------------------------------------------------------
pass() { echo "PASS [$1] $2"; echo "PASS	$1	ch$CH	$2" >>"$RESULTS"; }
fail() { echo "FAIL [$1] $2" >&2; echo "FAIL	$1	ch$CH	$2" >>"$RESULTS"; }
check() { # check <項目> <内容> <コマンド...>（終了コードで判定）
  local cat=$1 desc=$2; shift 2
  if "$@" >/dev/null 2>&1; then pass "$cat" "$desc"; else fail "$cat" "$desc"; fi
}
retry() { # retry <回数> <間隔秒> <コマンド...>
  local n=$1 s=$2; shift 2
  for _ in $(seq 1 "$n"); do "$@" && return 0; sleep "$s"; done
  return 1
}

# ---- 本文のコマンドを実行する ----------------------------------------
# run: 本文に書くコマンド。トレース（本文との照合用）に残して実行する
run() { echo "\$ $*"; echo "$*" >>"$TRACE"; "$@"; }
# cap <名前> <コマンド...>: run と同じ。CAPTURE=1 なら出力を docs/logs/chNN-<名前>.txt に保存する
cap() {
  local name=$1; shift
  echo "\$ $*"; echo "$*" >>"$TRACE"
  local out rc
  out=$("$@" 2>&1); rc=$?
  echo "$out"
  LAST_OUT=$out
  if [ "${CAPTURE:-0}" = 1 ]; then
    mkdir -p "$LOGDIR"
    printf '%s\n' "$out" | normalize >"$LOGDIR/ch$CH-$name.txt"
  fi
  return $rc
}
# 本に載せる出力は、プロファイル名・ホームのパスを読者の画面と同じ形にそろえる
normalize() {
  sed -e "s/${PROFILE}/minikube/g" -e "s#${HOME}#/Users/you#g" \
    -e '/^  - MINIKUBE_PROFILE=/d' -e '/^  - KUBECONFIG=/d'
}
# capt <名前> <行数> <コマンド...>: cap と同じ。保存するのは最後の <行数> 行だけ（本では「最後の部分」と書く）
capt() {
  local name=$1 n=$2; shift 2
  echo "\$ $*"; echo "$*" >>"$TRACE"
  local out rc
  out=$("$@" 2>&1); rc=$?
  echo "$out"
  LAST_OUT=$out
  if [ "${CAPTURE:-0}" = 1 ]; then
    mkdir -p "$LOGDIR"
    printf '%s\n' "$out" | tail -n "$n" | normalize >"$LOGDIR/ch$CH-$name.txt"
  fi
  return $rc
}
# bg <名前> <コマンド...>: 別のターミナルで動かし続けるコマンド（port-forward など）
bg() {
  local name=$1; shift
  echo "\$ $* &"; echo "$*" >>"$TRACE"
  "$@" >"/tmp/e2e-$PROFILE-$name.log" 2>&1 &
  BG_PIDS+=($!)
  sleep 3
}
stop_bg() { for p in "${BG_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; BG_PIDS=(); sleep 1; }

# last_has <正規表現>: 直前の cap / capt の出力に一致する行があるか
last_has() { grep -Eq -- "$1" <<<"$LAST_OUT"; }
LAST_OUT=

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"; }
body() { curl -s --max-time 5 "$@"; }
is_200() { [ "$(http_code "$1")" = 200 ]; }

# Todo の追加・一覧・完了・削除を、HTTP の中身まで確かめる
crud() { # crud <基準の URL> <項目> <題名>
  local base=$1 cat=$2 title=$3 id
  id=$(curl -s --max-time 5 -X POST "$base/api/todos" -H 'Content-Type: application/json' \
    -d "{\"title\":\"$title\"}" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
  if [ -n "$id" ]; then pass "$cat" "追加（id=${id}）"; else fail "$cat" "追加"; return; fi
  check "$cat" "一覧に「${title}」がある" grep -q "\"$title\"" <(body "$base/api/todos")
  check "$cat" "完了にする（done=true）" grep -q '"done":true' \
    <(curl -s --max-time 5 -X PATCH "$base/api/todos/$id" -d '{"done":true}')
  check "$cat" "削除（204）" test "$(http_code -X DELETE "$base/api/todos/$id")" = 204
  check "$cat" "削除後の一覧に無い" bash -c "! curl -s '$base/api/todos' | grep -q '\"id\":$id,'"
}

add_todo() { curl -s --max-time 5 -X POST "$1/api/todos" -d "{\"title\":\"$2\"}" >/dev/null; }
pod_phase_reason() { # 最初のコンテナの待ち理由（ImagePullBackOff など）
  kubectl get pods -l "app=$1" -o jsonpath='{.items[*].status.containerStatuses[0].state.waiting.reason}'
}
wait_reason() { # wait_reason <app> <理由の正規表現> <秒>
  for _ in $(seq 1 "$3"); do pod_phase_reason "$1" | grep -Eq "$2" && return 0; sleep 1; done
  return 1
}
gateway_url() { # minikube service --url を別のターミナルで動かし、URL を返す
  stop_bg
  bg service minikube service todo-gateway-nginx --url
  for _ in $(seq 1 30); do
    GW=$(grep -o 'http://[0-9.:]*' "/tmp/e2e-$PROFILE-service.log" | head -1)
    [ -n "$GW" ] && break; sleep 1
  done
  retry 30 2 is_200 "$GW/" >/dev/null
  echo "gateway: $GW"
}

# ---- 章ごとの手順 ----------------------------------------------------
ch01() {
  local cf=ch01/compose.yaml
  capt compose-up 8 docker compose -f $cf up -d
  retry 30 1 is_200 "http://localhost:$FRONT_PORT/api/todos"
  cap compose-ps docker compose -f $cf ps --format "table {{.Service}}\t{{.Status}}"
  check CRUD "Compose: 画面が HTTP 200" is_200 "http://localhost:$FRONT_PORT/"
  crud "http://localhost:$FRONT_PORT" CRUD "テスト"
  add_todo "http://localhost:$FRONT_PORT" "牛乳を買う"
  cap curl-todos curl -s "http://localhost:$FRONT_PORT/api/todos"
  cap compose-rm docker rm -f ch01-todo-api-1
  cap curl-after-rm curl -s "http://localhost:$FRONT_PORT/api/todos"
  check 自己修復 "Compose: API のコンテナを消すと API がエラー（504）" \
    test "$(http_code --max-time 10 "http://localhost:$FRONT_PORT/api/todos")" = 504
  sleep 10
  check 自己修復 "Compose: 待っても戻らない（10 秒後も 200 以外）" \
    test "$(http_code --max-time 10 "http://localhost:$FRONT_PORT/api/todos")" != 200
  run docker compose -f $cf up -d
  retry 20 1 is_200 "http://localhost:$FRONT_PORT/api/todos"
  cap curl-after-up curl -s "http://localhost:$FRONT_PORT/api/todos"
  check 自己修復 "Compose: up -d をもう一度打つと戻り、Todo も残る" grep -q '牛乳を買う' <(body "http://localhost:$FRONT_PORT/api/todos")
  cap compose-down docker compose -f $cf down -v
}

ch02() {
  cap versions bash -c "minikube version; kubectl version --client"
  cap minikube-start minikube start --driver=docker --container-runtime=containerd \
    --kubernetes-version="${K8S_VERSION}" --cpus=2 --memory=3072
  cap minikube-status minikube status
  cap current-context kubectl config current-context
  check 起動 "コンテキストが minikube（のプロファイル）" test "$(kubectl config current-context)" = "$PROFILE"
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  cap get-nodes kubectl get nodes
  check 起動 "node が Ready" kubectl wait --for=condition=Ready node --all --timeout=60s
  cap run-hello kubectl run hello --image=nginx:1.30.6-alpine
  kubectl wait --for=condition=Ready pod/hello --timeout=180s >/dev/null
  cap get-pods-hello kubectl get pods
  check 起動 "hello の Pod が Running" test "$(kubectl get pod hello -o jsonpath='{.status.phase}')" = Running
  bg pf-hello kubectl port-forward pod/hello $FRONT_PORT:80
  retry 10 1 is_200 "http://localhost:$FRONT_PORT/"
  check 起動 "port-forward で nginx の画面（HTTP 200）" grep -q 'Welcome to nginx' <(body "http://localhost:$FRONT_PORT/")
  [ "${CAPTURE:-0}" = 1 ] && head -2 "/tmp/e2e-$PROFILE-pf-hello.log" >"$LOGDIR/ch02-port-forward.txt"
  stop_bg
  cap delete-hello kubectl delete pod hello
  check 起動 "delete のあと Pod が無い" bash -c '! kubectl get pod hello'
  cap get-pods-all kubectl get pods -A
  check 起動 "kube-system で Kubernetes の部品が動いている" grep -q kube-apiserver <(kubectl get pods -n kube-system)
  cap minikube-stop minikube stop
  cap minikube-start-again minikube start
  check 起動 "stop と start のあと node が Ready" kubectl wait --for=condition=Ready node --all --timeout=180s
}

ch03() {
  cap apply-pod kubectl apply -f ch03/pod.yaml
  kubectl wait --for=condition=Ready pod/hello --timeout=120s >/dev/null
  cap get-pods-pod kubectl get pods
  cap delete-pod kubectl delete pod hello
  cap get-pods-empty kubectl get pods
  check 自己修復 "Pod を直接作ると、消したあと戻らない" bash -c '! kubectl get pod hello'
  cap apply-deployment kubectl apply -f ch03/deployment.yaml
  kubectl rollout status deployment/hello --timeout=120s >/dev/null
  cap get-pods-deploy kubectl get pods
  local before after
  before=$(kubectl get pods -l app=hello -o jsonpath='{.items[0].metadata.name}')
  cap delete-deploy-pod kubectl delete pod "$before"
  kubectl rollout status deployment/hello --timeout=120s >/dev/null
  kubectl wait --for=condition=Ready pod -l app=hello --timeout=120s >/dev/null
  cap get-pods-healed kubectl get pods
  after=$(kubectl get pods -l app=hello --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
  check 自己修復 "Deployment の Pod は消すと別の名前で戻る（$before → ${after}）" \
    test -n "$after" -a "$before" != "$after"
  cap get-rs kubectl get replicasets
  cap get-pods-labels kubectl get pods --show-labels
  cap scale kubectl scale deployment hello --replicas=3
  kubectl rollout status deployment/hello --timeout=120s >/dev/null
  cap get-pods-3 kubectl get pods
  local one
  one=$(kubectl get pods -l app=hello -o jsonpath='{.items[0].metadata.name}')
  run kubectl delete pod "$one"
  sleep 3
  kubectl rollout status deployment/hello --timeout=120s >/dev/null
  check 自己修復 "3つのうち1つを消しても3つに戻る" \
    test "$(kubectl get deployment hello -o jsonpath='{.status.readyReplicas}')" = 3
  # 最初の失敗: イメージ名の誤り
  cap apply-typo kubectl apply -f ch03/typo.yaml
  check 失敗 "イメージ名の誤りで ImagePullBackOff / ErrImagePull" wait_reason typo 'ImagePullBackOff|ErrImagePull' 120
  wait_reason typo 'ImagePullBackOff' 60
  cap get-pods-typo kubectl get pods -l app=typo
  cap describe-typo bash -c "kubectl describe pod -l app=typo | sed -n '/^Events:/,\$p'"
  cap delete-typo kubectl delete -f ch03/typo.yaml
  run kubectl delete -f ch03/deployment.yaml
  # 自分のイメージ
  capt build-api 3 docker build -t todo-api:v1 app/api
  cap apply-api-before-load kubectl apply -f ch03/todo-api.yaml
  check 失敗 "minikube に渡す前は todo-api が ImagePullBackOff" wait_reason todo-api 'ImagePullBackOff|ErrImagePull' 120
  cap get-pods-before-load kubectl get pods
  cap image-load-api minikube image load todo-api:v1
  cap image-ls bash -c "minikube image ls | grep todo"
  # 本文: 待つ代わりに Pod を消して、Deployment に作り直させる
  cap delete-api-pod kubectl delete pod -l app=todo-api
  check 更新 "image load のあと todo-api のコンテナが動く" \
    retry 90 2 bash -c "kubectl get pods -l app=todo-api -o jsonpath='{.items[*].status.containerStatuses[0].state.running}' | grep -q startedAt"
  run docker build -t todo-frontend:v1 app/frontend
  run minikube image load todo-frontend:v1
  cap apply-todo kubectl apply -f ch03/todo-db.yaml -f ch03/todo-frontend.yaml
  kubectl wait --for=condition=Ready pod -l app=todo-db --timeout=180s >/dev/null
  check 失敗 "todo-frontend が CrashLoopBackOff / Error" \
    retry 90 2 bash -c "kubectl get pods -l app=todo-frontend -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' | grep -qv '^0$'"
  sleep 5
  cap get-pods-todo kubectl get pods
  check DNS "todo-api が READY 0/1" test "$(kubectl get pods -l app=todo-api -o jsonpath='{.items[0].status.containerStatuses[0].ready}')" = false
  cap logs-api kubectl logs deployment/todo-api --tail=2
  check DNS "todo-api のログに todo-db の名前解決の失敗" grep -q 'lookup todo-db.*no such host' <(kubectl logs deployment/todo-api)
  cap logs-frontend kubectl logs deployment/todo-frontend
  check DNS "todo-frontend のログに upstream todo-api の失敗" \
    grep -q 'host not found in upstream "todo-api"' <(kubectl logs deployment/todo-frontend)
}

ch04() {
  cap get-pods-wide kubectl get pods -o wide
  # 困りごと: DB の Pod を消すと名前（と IP）が変わる
  local old_db new_db
  old_db=$(kubectl get pod -l app=todo-db -o jsonpath='{.items[0].metadata.name}')
  run kubectl delete pod -l app=todo-db
  kubectl wait --for=condition=Ready pod -l app=todo-db --timeout=120s >/dev/null
  cap get-pods-wide-after kubectl get pods -o wide
  new_db=$(kubectl get pod -l app=todo-db -o jsonpath='{.items[0].metadata.name}')
  check DNS "Pod を作り直すと名前が変わる（$old_db → ${new_db}）" test "$old_db" != "$new_db"
  cap apply-db-svc kubectl apply -f ch04/todo-db-service.yaml
  cap get-svc-db kubectl get service todo-db
  sleep 2
  cap endpointslices-db kubectl get endpointslices -l kubernetes.io/service-name=todo-db
  check DNS "todo-db の EndpointSlice に DB の Pod の IP" \
    grep -q "$(kubectl get pod -l app=todo-db -o jsonpath='{.items[0].status.podIP}')" \
    <(kubectl get endpointslices -l kubernetes.io/service-name=todo-db)
  check DNS "Service ができると todo-api が READY 1/1" kubectl wait --for=condition=Ready pod -l app=todo-api --timeout=120s
  cap apply-api-svc kubectl apply -f ch04/todo-api-service.yaml -f ch04/todo-frontend-service.yaml
  cap restart-frontend kubectl rollout restart deployment/todo-frontend
  run kubectl rollout status deployment/todo-frontend
  check DNS "todo-frontend が Running（READY 1/1）" \
    retry 60 2 bash -c "[ \"\$(kubectl get deployment todo-frontend -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  cap get-pods-ok kubectl get pods
  cap get-svc kubectl get services
  bg pf-front kubectl port-forward service/todo-frontend $FRONT_PORT:80
  [ "${CAPTURE:-0}" = 1 ] && head -2 "/tmp/e2e-$PROFILE-pf-front.log" >"$LOGDIR/ch04-port-forward.txt"
  retry 20 1 is_200 "http://localhost:$FRONT_PORT/api/todos"
  check CRUD "port-forward で画面（HTTP 200）" is_200 "http://localhost:$FRONT_PORT/"
  crud "http://localhost:$FRONT_PORT" CRUD "テスト"
  add_todo "http://localhost:$FRONT_PORT" "牛乳を買う"
  cap nslookup bash -c "kubectl run tmp --rm -i --restart=Never --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 -- nslookup todo-db 2>&1 | grep -v -e '^If you' -e '^All commands'"
  check DNS "nslookup で todo-db.default.svc.cluster.local が引ける" last_has 'Name:.*todo-db\.default\.svc\.cluster\.local' 
  bg pf-api kubectl port-forward service/todo-api $API_PORT:8080
  retry 10 1 is_200 "http://localhost:$API_PORT/api/todos"
  cap curl-api curl -s "http://localhost:$API_PORT/api/todos"
  check CRUD "API の port-forward で /api/todos（HTTP 200）" is_200 "http://localhost:$API_PORT/api/todos"
  # わざと失敗: Service の selector の誤り
  cap apply-svc-typo kubectl apply -f ch04/todo-api-service-typo.yaml
  sleep 3
  check 失敗 "selector の誤りで画面から API に届かない（502）" \
    test "$(http_code -X POST "http://localhost:$FRONT_PORT/api/todos" -d '{"title":"x"}')" = 502
  cap endpointslices-typo kubectl get endpointslices -l kubernetes.io/service-name=todo-api
  check 失敗 "selector の誤りで EndpointSlice が空" \
    test -z "$(kubectl get endpointslices -l kubernetes.io/service-name=todo-api -o jsonpath='{.items[*].endpoints[*].addresses[*]}')"
  cap apply-svc-fixed kubectl apply -f ch04/todo-api-service.yaml
  check 失敗 "selector を直すと戻る" retry 10 1 is_200 "http://localhost:$FRONT_PORT/api/todos"
  # ローリングアップデート
  capt build-v2 3 docker build -t todo-frontend:v2 --build-arg VERSION=v2 app/frontend
  run minikube image load todo-frontend:v2
  cap set-image kubectl set image deployment/todo-frontend nginx=todo-frontend:v2
  cap rollout-status kubectl rollout status deployment/todo-frontend
  cap get-pods-rolled kubectl get pods -l app=todo-frontend
  stop_bg
  bg pf-front kubectl port-forward service/todo-frontend $FRONT_PORT:80
  retry 10 1 is_200 "http://localhost:$FRONT_PORT/"
  check 更新 "rollout で v2 に入れ替わる（画面に v2）" grep -q '>v2<' <(body "http://localhost:$FRONT_PORT/")
  cap rollout-undo kubectl rollout undo deployment/todo-frontend
  run kubectl rollout status deployment/todo-frontend
  check 更新 "undo で v1 に戻る" test "$(kubectl get deployment todo-frontend -o jsonpath='{.spec.template.spec.containers[0].image}')" = todo-frontend:v1
  stop_bg
  bg pf-front kubectl port-forward service/todo-frontend $FRONT_PORT:80
  retry 10 1 is_200 "http://localhost:$FRONT_PORT/"
  check 更新 "undo のあと画面が v1" grep -q '>v1<' <(body "http://localhost:$FRONT_PORT/")
  run kubectl set image deployment/todo-frontend nginx=todo-frontend:v2
  run kubectl rollout status deployment/todo-frontend
  stop_bg
  bg pf-front kubectl port-forward service/todo-frontend $FRONT_PORT:80
  retry 10 1 is_200 "http://localhost:$FRONT_PORT/"
  check 更新 "もう一度 v2 にする" grep -q '>v2<' <(body "http://localhost:$FRONT_PORT/")
  check CRUD "v2 でも前の Todo が見える" grep -q '牛乳を買う' <(body "http://localhost:$FRONT_PORT/api/todos")
  stop_bg
}

ch05() {
  cap install-crds bash -c "kubectl kustomize 'https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}' | kubectl apply -f - | tail -3"
  cap install-ngf-crds bash -c "kubectl apply --server-side -f ${NGF_RAW}/deploy/crds.yaml | tail -3"
  cap install-ngf bash -c "kubectl apply -f ${NGF_RAW}/deploy/nodeport/deploy.yaml | tail -4"
  cap wait-ngf kubectl wait -n nginx-gateway --for=condition=Available deployment --all --timeout=300s
  retry 30 2 bash -c "kubectl get gatewayclass nginx -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}' | grep -q True"
  cap get-gatewayclass kubectl get gatewayclass
  check Gateway "GatewayClass nginx が ACCEPTED" grep -q True <(kubectl get gatewayclass nginx)
  cap apply-gateway kubectl apply -f ch05/gateway.yaml
  kubectl wait --for=condition=Programmed gateway/todo-gateway --timeout=180s >/dev/null
  cap get-gateway kubectl get gateway
  check Gateway "Gateway が PROGRAMMED" kubectl wait --for=condition=Programmed gateway/todo-gateway --timeout=10s
  cap get-svc-gateway kubectl get service todo-gateway-nginx
  check Gateway "Service todo-gateway-nginx が自動でできる（NodePort）" grep -q NodePort <(kubectl get service todo-gateway-nginx)
  cap apply-httproute kubectl apply -f ch05/httproute.yaml
  cap get-httproute kubectl get httproute
  kubectl wait --for=condition=Available deployment/todo-gateway-nginx --timeout=180s >/dev/null
  gateway_url
  [ "${CAPTURE:-0}" = 1 ] && normalize <"/tmp/e2e-$PROFILE-service.log" >"$LOGDIR/ch05-service-url.txt"
  check Gateway "minikube service --url の URL で / が HTML" grep -q '<title>' <(body "$GW/")
  crud "$GW" Gateway "Gateway 経由"
  add_todo "$GW" "Gateway 経由"
  cap curl-gateway curl -s "$GW/api/todos"
  local gw_ip front_ip
  gw_ip=$(kubectl get pods -l app.kubernetes.io/instance=todo-gateway -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
  [ -z "$gw_ip" ] && gw_ip=$(kubectl get pods -o wide | awk '/^todo-gateway-nginx/{print $6}')
  front_ip=$(kubectl get pod -l app=todo-frontend -o jsonpath='{.items[0].status.podIP}')
  cap logs-api-gateway kubectl logs deployment/todo-api --tail=2
  cap pods-wide-gateway kubectl get pods -o wide
  check Gateway "/api は todo-frontend を通らず Gateway から直接 todo-api に届く（送り元 ${gw_ip}）" \
    bash -c "kubectl logs deployment/todo-api | grep access | tail -1 | grep -q 'remote=$gw_ip:' && [ '$gw_ip' != '$front_ip' ]"
  cap describe-httproute bash -c "kubectl describe httproute todo | sed -n '/^Status:/,\$p'"
  # わざと失敗: parentRefs の誤り
  cap apply-httproute-typo kubectl apply -f ch05/httproute-typo.yaml
  sleep 3
  check 失敗 "parentRefs の誤りで 404" retry 10 1 bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' '$GW/api/todos')\" = 404 ]"
  cap describe-httproute-typo bash -c "kubectl describe httproute todo | sed -n '/^Status:/,\$p'"
  check 失敗 "describe で Parents が空（Accepted が無い）" bash -c "! kubectl describe httproute todo | grep -q Accepted"
  run kubectl apply -f ch05/httproute.yaml
  check Gateway "parentRefs を直すと戻る" retry 10 1 is_200 "$GW/api/todos"
  stop_bg
}

ch06() {
  gateway_url
  cap grep-password grep -rn todo-pass ch03
  check 設定 "パスワードが2つのマニフェストに直接書いてある" test "$(grep -rln todo-pass ch03 | wc -l | tr -d ' ')" = 2
  add_todo "$GW" "消える Todo"
  check 永続化 "（困りごと）DB の Pod を消す前は Todo がある" grep -q '消える Todo' <(body "$GW/api/todos")
  cap delete-db-pod kubectl delete pod -l app=todo-db
  kubectl wait --for=condition=Ready pod -l app=todo-db --timeout=120s >/dev/null
  retry 20 1 is_200 "$GW/api/todos"
  check 永続化 "（困りごと）PVC が無いと DB の Pod を消すと Todo が消える" bash -c "! curl -s '$GW/api/todos' | grep -q '消える Todo'"
  # ConfigMap と Secret
  cap apply-config kubectl apply -f ch06/todo-config.yaml
  cap secret-dry-run kubectl create secret generic todo-db --from-literal=password=todo-pass --dry-run=client -o yaml
  cap create-secret kubectl create secret generic todo-db --from-literal=password=todo-pass
  cap secret-jsonpath kubectl get secret todo-db -o jsonpath='{.data.password}'
  cap secret-decode bash -c "kubectl get secret todo-db -o jsonpath='{.data.password}' | base64 -d"
  check 設定 "base64 -d で元のパスワードに戻る" test "$(kubectl get secret todo-db -o jsonpath='{.data.password}' | base64 -d)" = todo-pass
  # わざと失敗: 存在しないキー
  cap apply-wrong-key kubectl apply -f ch06/todo-api-wrong-key.yaml
  check 失敗 "存在しないキーで CreateContainerConfigError" wait_reason todo-api CreateContainerConfigError 90
  cap get-pods-wrong-key kubectl get pods -l app=todo-api
  # ラベルで複数の Pod を指定すると describe は Events を出さないので、失敗している Pod の名前で指定する。Events に出るまで数秒かかる
  local bad
  bad=$(kubectl get pods -l app=todo-api -o jsonpath='{range .items[*]}{.metadata.name} {.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' | awk '$2=="CreateContainerConfigError"{print $1}' | head -1)
  retry 30 1 bash -c "kubectl describe pod $bad | grep -q \"couldn't find key passwd\""
  cap describe-wrong-key bash -c "kubectl describe pod $bad | sed -n '/^Events:/,\$p'"
  check 失敗 "describe に「couldn't find key passwd」" last_has "couldn't find key passwd in Secret default/todo-db"
  check 失敗 "失敗している間も古い todo-api は動いている" retry 5 1 is_200 "$GW/api/todos"
  cap apply-api kubectl apply -f ch06/todo-api.yaml
  cap rollout-api kubectl rollout status deployment/todo-api
  retry 20 1 is_200 "$GW/api/config"
  cap curl-config curl -s "$GW/api/config"
  check 設定 "APP_TITLE が ConfigMap から入る（Todo）" grep -q '"title":"Todo"' <(body "$GW/api/config")
  # 本文: ch06/todo-config.yaml の APP_TITLE を書き換えて apply する
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/ch06"; sed 's/"Todo"/"わたしの Todo"/' ch06/todo-config.yaml >"$tmp/ch06/todo-config.yaml"
  echo "kubectl apply -f ch06/todo-config.yaml" >>"$TRACE"; kubectl apply -f "$tmp/ch06/todo-config.yaml"
  check 設定 "apply しただけでは画面の見出しは変わらない" grep -q '"title":"Todo"' <(body "$GW/api/config")
  cap restart-api kubectl rollout restart deployment/todo-api
  run kubectl rollout status deployment/todo-api
  sleep 3
  check 設定 "restart のあと APP_TITLE が変わる（わたしの Todo）" retry 10 1 bash -c "curl -s '$GW/api/config' | grep -q 'わたしの Todo'"
  # PVC
  cap get-storageclass kubectl get storageclass
  cap apply-pvc kubectl apply -f ch06/todo-db-pvc.yaml
  cap get-pvc kubectl get pvc
  check 永続化 "PVC が Bound" retry 20 1 bash -c "kubectl get pvc todo-db-data -o jsonpath='{.status.phase}' | grep -q Bound"
  cap apply-db kubectl apply -f ch06/todo-db.yaml
  cap rollout-db kubectl rollout status deployment/todo-db
  cap get-pvc-pv kubectl get pvc,pv
  check 永続化 "DB の PGDATA が PVC の中（/var/lib/postgresql/18/docker）" \
    test "$(kubectl exec deployment/todo-db -- sh -c 'echo $PGDATA')" = /var/lib/postgresql/18/docker
  check 永続化 "strategy が Recreate" test "$(kubectl get deployment todo-db -o jsonpath='{.spec.strategy.type}')" = Recreate
  retry 30 1 is_200 "$GW/api/todos"
  add_todo "$GW" "消えない Todo"
  cap delete-db-pod-again kubectl delete pod -l app=todo-db
  kubectl wait --for=condition=Ready pod -l app=todo-db --timeout=120s >/dev/null
  retry 30 1 bash -c "curl -s '$GW/api/todos' | grep -q '消えない Todo'"
  cap curl-after-delete curl -s "$GW/api/todos"
  check 永続化 "PVC があると DB の Pod を消しても Todo が残る" grep -q '消えない Todo' <(body "$GW/api/todos")
  stop_bg
  run minikube stop
  run minikube start
  kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null
  kubectl rollout status deployment/todo-db --timeout=300s >/dev/null
  kubectl rollout status deployment/todo-api --timeout=300s >/dev/null
  kubectl wait --for=condition=Available deployment/todo-gateway-nginx --timeout=300s >/dev/null
  gateway_url
  check 永続化 "minikube stop と start のあとも Todo が残る" retry 30 2 bash -c "curl -s '$GW/api/todos' | grep -q '消えない Todo'"
  stop_bg
}

ch07() {
  gateway_url
  cap diff-copy diff -r ch07/copy/dev ch07/copy/prod
  cap kustomize-dev bash -c "kubectl kustomize ch07/kustomize/overlays/dev | head -20"
  local dev prod
  dev=$(kubectl kustomize ch07/kustomize/overlays/dev); prod=$(kubectl kustomize ch07/kustomize/overlays/prod)
  cap diff-render bash -c "diff <(kubectl kustomize ch07/kustomize/overlays/dev) <(kubectl kustomize ch07/kustomize/overlays/prod)"
  check 設定 "dev と prod の違いは replicas と APP_TITLE だけ" \
    test "$(diff <(echo "$dev") <(echo "$prod") | grep -E '^[<>]' | grep -vcE 'replicas:|APP_TITLE:')" = 0
  check 設定 "prod でも todo-db は1つ" test "$(echo "$prod" | awk '/^---/{d=0;f=0} /^kind: Deployment/{d=1} d&&/^  name: todo-db$/{f=1} f&&/replicas:/{print $2; exit}')" = 1
  cap kustomize-typo kubectl kustomize ch07/kustomize/overlays/typo
  check 失敗 "パッチの対象の名前の誤りで kubectl kustomize がエラー" bash -c '! kubectl kustomize ch07/kustomize/overlays/typo'
  cap apply-shared kubectl apply -k ch07/kustomize/shared
  cap apply-dev kubectl apply -k ch07/kustomize/overlays/dev
  cap restart-api kubectl rollout restart deployment/todo-api
  run kubectl rollout status deployment/todo-api
  check 設定 "dev の見出し（Todo（開発））が出る" retry 20 1 bash -c "curl -s '$GW/api/config' | grep -q 'Todo（開発）'"
  crud "$GW" CRUD "Kustomize で入れた"
  add_todo "$GW" "Kustomize で入れた"
  check 永続化 "前の章の Todo が残る" grep -q '消えない Todo' <(body "$GW/api/todos")
  stop_bg
}

ch08() {
  cap helm-version helm version --short
  cap podinfo-install bash -c "helm install podinfo oci://ghcr.io/stefanprodan/charts/podinfo --version 6.17.0 2>&1 | head -8"
  cap helm-list-podinfo helm list
  check Helm移行 "podinfo が deployed" grep -q 'podinfo.*deployed' <(helm list)
  check Helm移行 "podinfo の Pod が動く" kubectl wait --for=condition=Available deployment/podinfo --timeout=180s
  cap podinfo-uninstall helm uninstall podinfo
  check Helm移行 "uninstall で podinfo が消える" bash -c '! helm list | grep -q podinfo'
  kubectl wait --for=delete pod -l app.kubernetes.io/name=podinfo --timeout=120s >/dev/null 2>&1
  cap helm-template helm template todo ch08/helm/todo --show-only templates/todo-config.yaml
  check Helm移行 "helm template で APP_TITLE が values の値になる" last_has 'APP_TITLE: "Todo"' 
  cap helm-lint helm lint ch08/helm/todo
  check Helm移行 "helm lint が通る" helm lint ch08/helm/todo
  cap delete-k kubectl delete -k ch07/kustomize/overlays/dev
  cap get-kept kubectl get pvc,gateway
  check Helm移行 "delete -k のあとも PVC と Gateway が残る" bash -c 'kubectl get pvc todo-db-data && kubectl get gateway todo-gateway'
  cap helm-install helm install todo ch08/helm/todo
  kubectl rollout status deployment/todo-db --timeout=300s >/dev/null
  kubectl rollout status deployment/todo-api --timeout=300s >/dev/null
  cap get-pods-helm kubectl get pods
  gateway_url
  retry 30 1 is_200 "$GW/api/todos"
  check Helm移行 "Helm のリリースだけで Gateway 経由の画面" grep -q '<title>' <(body "$GW/")
  check Helm移行 "前の章の Todo（消えない Todo）が残る" grep -q '消えない Todo' <(body "$GW/api/todos")
  crud "$GW" CRUD "Helm で入れた"
  cap helm-upgrade-replicas bash -c "helm upgrade todo ch08/helm/todo --set api.replicas=2 | head -6"
  cap helm-history-2 helm history todo
  check Helm移行 "upgrade でリビジョンが 2" grep -qE '^2.*deployed' <(helm history todo)
  local start end
  start=$(date +%s)
  cap helm-upgrade-fail helm upgrade todo ch08/helm/todo --set api.tag=v9 --wait=watcher --timeout=90s
  local rc=$?; end=$(date +%s)
  check 失敗 "存在しないタグの upgrade が失敗する（exit=${rc}・$((end-start))秒）" test "$rc" -ne 0
  cap helm-history-failed helm history todo
  check 失敗 "history に failed" grep -qE '^3.*failed' <(helm history todo)
  check 失敗 "失敗している間も古い todo-api で画面が動く" retry 5 1 is_200 "$GW/api/todos"
  cap get-pods-failed kubectl get pods -l app=todo-api
  cap helm-rollback helm rollback todo 2
  cap helm-history-rollback helm history todo
  check 失敗 "rollback で番号が1つ増える（4: Rollback to 2）" grep -qE '^4.*deployed.*Rollback to 2' <(helm history todo)
  kubectl rollout status deployment/todo-api --timeout=180s >/dev/null
  check 失敗 "rollback でイメージが todo-api:v1 に戻る" test "$(kubectl get deployment todo-api -o jsonpath='{.spec.template.spec.containers[0].image}')" = todo-api:v1
  crud "$GW" 失敗 "rollback のあと"
  cap helm-rollback-on-failure helm upgrade todo ch08/helm/todo --set api.tag=v9 --rollback-on-failure --timeout=90s
  cap helm-history-auto helm history todo
  check 失敗 "--rollback-on-failure で自動で戻る（6: Rollback to 4）" grep -qE '^6.*deployed.*Rollback to 4' <(helm history todo)
  kubectl rollout status deployment/todo-api --timeout=180s >/dev/null
  cap helm-list-final helm list
  check Helm移行 "最後に Helm のリリース todo が deployed" grep -qE '^todo.*deployed' <(helm list)
  crud "$GW" CRUD "完成"
  stop_bg
}

echo "== 第${CH}章（profile=${PROFILE}）"
"ch$CH"
echo "== 第${CH}章 おわり"
grep -c "^FAIL	.*	ch$CH	" "$RESULTS" >/dev/null && exit 1
exit 0
