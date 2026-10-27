# 第3章 コンテナをKubernetesで動かす

マニフェストで Pod を作り、消すと戻らないことを確かめてから、Deployment で数を保たせます（自己修復）。最後に、Todo アプリの3つ（todo-db・todo-api・todo-frontend）を Deployment で載せます。

## この章で使うファイル

- `pod.yaml` — nginx の Pod（hello）を1つ作る
- `deployment.yaml` — 同じ nginx を Deployment（hello）で動かす
- `typo.yaml` — わざと失敗させる Deployment。イメージ名が1文字違う（`nginx` → `ngnix`）
- `todo-db.yaml`・`todo-api.yaml`・`todo-frontend.yaml` — Todo アプリの3つの Deployment
- `up.sh` — この章の開始状態（起動した minikube）を作る

## 始める前に

第2章のクラスターが動いていれば、そのまま始められます。第2章を飛ばしたときや、やり直すときは次を打ちます。

```bash
minikube delete    # 今のクラスターがあれば消す
bash ch03/up.sh
```

## 手順

```bash
# Pod を直接作る → 消すと戻らない
kubectl apply -f ch03/pod.yaml
kubectl get pods
kubectl delete pod hello
kubectl get pods

# Deployment で作る → Pod を消しても新しい Pod ができる
kubectl apply -f ch03/deployment.yaml
kubectl get pods
kubectl delete pod <hello-で始まる Pod の名前>
kubectl get pods
kubectl get replicasets
kubectl get pods --show-labels
kubectl scale deployment hello --replicas=3

# わざと失敗させる: get → describe で原因を読む
kubectl apply -f ch03/typo.yaml
kubectl get pods -l app=typo
kubectl describe pod -l app=typo
kubectl delete -f ch03/typo.yaml
kubectl delete -f ch03/deployment.yaml

# 自分のイメージを minikube に渡す（渡す前は ImagePullBackOff になる）
docker build -t todo-api:v1 app/api
kubectl apply -f ch03/todo-api.yaml
kubectl get pods
minikube image load todo-api:v1
minikube image ls | grep todo
kubectl delete pod -l app=todo-api

# Todo アプリの残りの2つを載せる
docker build -t todo-frontend:v1 app/frontend
minikube image load todo-frontend:v1
kubectl apply -f ch03/todo-db.yaml -f ch03/todo-frontend.yaml
kubectl get pods
kubectl logs deployment/todo-api --tail=2
kubectl logs deployment/todo-frontend
```

## 確かめ方

- Pod だけのときは、`delete` のあと `kubectl get pods` に何も出ない
- Deployment のときは、`delete` のあと名前の違う Pod が `Running` で出る
- `typo` は `ImagePullBackOff`（または `ErrImagePull`）になり、`describe` の Events に原因が出る
- 章の終わりは、todo-db が `Running`、todo-api が `0/1`、todo-frontend が `CrashLoopBackOff`。ログに、`todo-db`・`todo-api` という名前が引けないエラーが出ます。**これで正しい状態です。** 次の章で Service を作ると直ります

書籍に載せた実行結果は `../docs/logs/ch03-*.txt` にあります。

## 後片付けと中断

何も消さずに次の章へ進みます。中断するときは `minikube stop` で止めます。やり直すときは `minikube delete` のあと `bash ch03/up.sh` を打ちます。

次の章: [第4章 Podをネットワークで接続する](../ch04/)
