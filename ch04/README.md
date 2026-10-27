# 第4章 Podをネットワークで接続する

Pod の IP は作り直すたびに変わります。Service で `todo-db`・`todo-api`・`todo-frontend` という決まった名前の宛先を作り、Todo アプリをブラウザーから使えるようにします。最後に、画面を v2 に入れ替えて（ローリングアップデート）、前の版に戻します。

## この章で使うファイル

- `todo-db-service.yaml`・`todo-api-service.yaml`・`todo-frontend-service.yaml` — 3つの Service
- `todo-api-service-typo.yaml` — わざと失敗させる Service。selector のラベルが1文字違う（`todo-api` → `todo-apl`）
- `up.sh` — この章の開始状態（第3章の終わり）を作る

## 始める前に

第3章の終わりの状態（todo-api が `0/1`、todo-frontend が `CrashLoopBackOff`）から始めます。やり直すときは次を打ちます。

```bash
minikube delete
bash ch04/up.sh
```

## 手順

```bash
# Pod を作り直すと、名前と IP が変わる
kubectl get pods -o wide
kubectl delete pod -l app=todo-db
kubectl get pods -o wide

# todo-db の Service を作る → todo-api が READY 1/1 になる
kubectl apply -f ch04/todo-db-service.yaml
kubectl get service todo-db
kubectl get endpointslices -l kubernetes.io/service-name=todo-db

# todo-api と todo-frontend の Service を作る
kubectl apply -f ch04/todo-api-service.yaml -f ch04/todo-frontend-service.yaml
kubectl rollout restart deployment/todo-frontend
kubectl rollout status deployment/todo-frontend
kubectl get pods
kubectl get services

# 画面を手元の 8000 番で開く（このターミナルは開いたままにする）
kubectl port-forward service/todo-frontend 8000:80
```

別のターミナルで http://localhost:8000 を開き、Todo を追加します。

```bash
# DNS 名を確かめる
kubectl run tmp --rm -i --restart=Never \
  --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 -- nslookup todo-db

# API を直接呼ぶ（さらに別のターミナルで port-forward を動かしておく）
kubectl port-forward service/todo-api 8001:8080
curl -s http://localhost:8001/api/todos

# わざと失敗させる: selector の札の間違い → ENDPOINTS が空になる
kubectl apply -f ch04/todo-api-service-typo.yaml
kubectl get endpointslices -l kubernetes.io/service-name=todo-api
kubectl apply -f ch04/todo-api-service.yaml

# 画面を v2 に入れ替えて、戻して、もう一度 v2 にする
docker build -t todo-frontend:v2 --build-arg VERSION=v2 app/frontend
minikube image load todo-frontend:v2
kubectl set image deployment/todo-frontend nginx=todo-frontend:v2
kubectl rollout status deployment/todo-frontend
kubectl rollout undo deployment/todo-frontend
kubectl rollout status deployment/todo-frontend
kubectl set image deployment/todo-frontend nginx=todo-frontend:v2
kubectl rollout status deployment/todo-frontend
```

Pod が入れ替わると port-forward は切れます。入れ替えのあとは、port-forward を Ctrl+C で止めて打ち直してから、画面を開き直します。

## 確かめ方

- Service を作ると、3つの Pod がすべて `Running`・`1/1` になる
- http://localhost:8000 で Todo の追加・完了・削除ができる
- `nslookup` で `todo-db.default.svc.cluster.local` が引ける
- selector を間違えると EndpointSlice の `ENDPOINTS` が空になり、直すと戻る
- 画面の見出しの横の版が v2 → v1 → v2 と変わり、Todo は残っている

書籍に載せた実行結果は `../docs/logs/ch04-*.txt` にあります。

## 後片付けと中断

port-forward を動かしているターミナルを、すべて Ctrl+C で止めます。アプリは todo-frontend が v2 のまま、次の章で使います。中断するときは `minikube stop`、やり直すときは `minikube delete` のあと `bash ch04/up.sh` を打ちます。

次の章: [第5章 Gateway APIでトラフィックを管理する](../ch05/)
