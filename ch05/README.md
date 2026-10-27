# 第5章 Gateway APIでトラフィックを管理する

port-forward はアプリごとにターミナルを開いたままにする必要があり、入口がアプリの数だけ増えます。Gateway API の実装（NGINX Gateway Fabric）を入れ、Gateway と HTTPRoute で、`/api` は todo-api に、それ以外は todo-frontend に振り分ける1つの入口を作ります。

## この章で使うファイル

- `gateway.yaml` — クラスターの入口になる Gateway（todo-gateway）
- `httproute.yaml` — 振り分けのルール（HTTPRoute todo）
- `httproute-typo.yaml` — わざと失敗させる HTTPRoute。`parentRefs` の Gateway の名前が1文字違う（`todo-gateway` → `todo-gatewey`）
- `up.sh` — この章の開始状態（第4章の終わり）を作る

## 始める前に

第4章の終わりの状態（3つの Deployment と3つの Service、todo-frontend は v2）から始めます。やり直すときは次を打ちます。

```bash
minikube delete
bash ch05/up.sh
```

## 手順

最初のコマンド（`kubectl kustomize <URL>`）は、URL の先の GitHub のリポジトリを git で取得します。第1章で ZIP を使った人は、ここで git を入れておきます。

```bash
# Gateway API の CRD と NGINX Gateway Fabric v2.8.0 を入れる
kubectl kustomize \
  "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.8.0" \
  | kubectl apply -f -
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.8.0/deploy/crds.yaml
kubectl apply \
  -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.8.0/deploy/nodeport/deploy.yaml
kubectl wait -n nginx-gateway --for=condition=Available deployment --all --timeout=300s
kubectl get gatewayclass

# Gateway を作る（Service todo-gateway-nginx が自動でできる）
kubectl apply -f ch05/gateway.yaml
kubectl get gateway
kubectl get service todo-gateway-nginx

# HTTPRoute で振り分ける
kubectl apply -f ch05/httproute.yaml
kubectl get httproute
kubectl wait --for=condition=Available deployment/todo-gateway-nginx --timeout=300s
```

**新しいターミナルを開いて**、次を打ちます。表示された URL（`http://127.0.0.1:<番号>`。番号は毎回違う）をブラウザーで開きます。macOS と WSL2 では、このコマンドは動き続けるので、ターミナルは開いたままにします。

```bash
minikube service todo-gateway-nginx --url
```

最初のターミナルに戻って確かめます。`<URL>` は、表示された URL に置き換えます。

```bash
curl -s <URL>/api/todos
kubectl describe httproute todo

# わざと失敗させる: parentRefs の名前の間違い → 404 になり、Parents が空になる
kubectl apply -f ch05/httproute-typo.yaml
kubectl describe httproute todo
kubectl apply -f ch05/httproute.yaml
```

## 確かめ方

- `kubectl get gatewayclass` で `nginx` の `ACCEPTED` が `True`
- `kubectl get gateway` で `todo-gateway` の `PROGRAMMED` が `True`
- `minikube service` の URL で Todo アプリが開き、前の章の Todo が並んでいる
- `kubectl describe httproute todo` の `Parents` に `Accepted` が `True`。名前を間違えると Parents が空になり、`curl` が 404 になる

書籍に載せた実行結果は `../docs/logs/ch05-*.txt` にあります。

## 後片付けと中断

`minikube service` を動かしているターミナルで Ctrl+C を押して止めます。Gateway と HTTPRoute は、そのまま次の章で使います。中断するときは `minikube stop`、やり直すときは `minikube delete` のあと `bash ch05/up.sh` を打ちます。

次の章: [第6章 アプリの設定とデータを外部化する](../ch06/)
