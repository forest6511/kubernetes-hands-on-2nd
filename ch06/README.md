# 第6章 アプリの設定とデータを外部化する

DB のパスワードがマニフェストに直接書いてあること、DB の Pod を消すと Todo が消えることの2つを直します。設定を ConfigMap に、パスワードを Secret に出し、DB のデータを PersistentVolumeClaim（PVC）に保存します。

## この章で使うファイル

- `todo-config.yaml` — 画面の見出し（`APP_TITLE`）を入れる ConfigMap
- `todo-api.yaml` — ConfigMap と Secret から値を読む todo-api
- `todo-api-wrong-key.yaml` — わざと失敗させる todo-api。Secret に無いキー（`passwd`）を参照する
- `todo-db-pvc.yaml` — DB のデータを置く PVC（todo-db-data）
- `todo-db.yaml` — Secret からパスワードを読み、PVC にデータを置く todo-db（入れ替えは `Recreate`）
- `up.sh` — この章の開始状態（第5章の終わり）を作る

## 始める前に

第5章の終わりの状態（Gateway と HTTPRoute で Todo アプリが開ける）から始めます。やり直すときは次を打ちます。

```bash
minikube delete
bash ch06/up.sh
```

**新しいターミナルを開いて** `minikube service todo-gateway-nginx --url` を動かし、表示された URL をブラウザーで開いておきます。

## 手順

```bash
# 困りごと1: パスワードが2つのマニフェストに直接書いてある
grep -rn todo-pass ch03

# 困りごと2: DB の Pod を消すと Todo が消える（Todo を1つ追加してから試す）
kubectl delete pod -l app=todo-db

# ConfigMap と Secret を作る
kubectl apply -f ch06/todo-config.yaml
kubectl create secret generic todo-db --from-literal=password=todo-pass --dry-run=client -o yaml
kubectl create secret generic todo-db --from-literal=password=todo-pass
kubectl get secret todo-db -o jsonpath='{.data.password}'
kubectl get secret todo-db -o jsonpath='{.data.password}' | base64 -d

# わざと失敗させる: Secret に無いキー → CreateContainerConfigError
kubectl apply -f ch06/todo-api-wrong-key.yaml
kubectl get pods -l app=todo-api
kubectl describe pod <todo-api-で始まり、エラーになっている Pod の名前>
kubectl apply -f ch06/todo-api.yaml
kubectl rollout status deployment/todo-api
curl -s <URL>/api/config

# ConfigMap の値を変える（ch06/todo-config.yaml の APP_TITLE を「わたしの Todo」に書き換えて）
kubectl apply -f ch06/todo-config.yaml
kubectl rollout restart deployment/todo-api
kubectl rollout status deployment/todo-api

# データを PVC に保存する
kubectl get storageclass
kubectl apply -f ch06/todo-db-pvc.yaml
kubectl get pvc
kubectl apply -f ch06/todo-db.yaml
kubectl rollout status deployment/todo-db
kubectl get pvc,pv

# DB の Pod を消しても Todo が残る（Todo を1つ追加してから試す）
kubectl delete pod -l app=todo-db
curl -s <URL>/api/todos
```

`<URL>` は、`minikube service` が表示した URL に置き換えます。

## 確かめ方

- `base64 -d` で元のパスワード `todo-pass` に戻る（Secret の base64 は暗号ではない）
- キーを間違えると todo-api の新しい Pod が `CreateContainerConfigError` になり、`describe` に `couldn't find key passwd in Secret default/todo-db` と出る。古い Pod は動き続ける
- `/api/config` の見出しは、ConfigMap を変えて `apply` しただけでは変わらず、`rollout restart` のあとに変わる
- `kubectl get pvc` で `todo-db-data` が `Bound`
- DB の Pod を消しても、`minikube stop` と `minikube start` のあとでも、Todo が残る

書籍に載せた実行結果は `../docs/logs/ch06-*.txt` にあります。

## 後片付けと中断

`minikube service` を動かしているターミナルで Ctrl+C を押して止めます。アプリはそのまま次の章で使います。中断するときは `minikube stop`（Todo は残ります）、やり直すときは `minikube delete` のあと `bash ch06/up.sh` を打ちます。

次の章: [第7章 Kustomizeでマニフェストを管理する](../ch07/)
