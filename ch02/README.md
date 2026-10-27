# 第2章 minikubeで環境を構築する

手元のパソコンに minikube で Kubernetes のクラスターを作り、kubectl で最初のコンテナ（nginx）を動かします。この章にマニフェストはありません。コマンドだけで進みます。

## この章で使うファイル

- `up.sh` — Docker が動いているかを確かめる

## 始める前に

- Docker Desktop を起動し、Docker に 4GB 以上のメモリを割り当てておきます（設定の場所は書籍 第2章）
- minikube と kubectl を入れておきます。macOS は `brew install minikube kubectl`、Linux と WSL2 の Ubuntu は書籍 第2章の手順で、本書と同じ版を入れます

```bash
bash ch02/up.sh
minikube version
kubectl version --client
```

## 手順

```bash
# クラスターを起動する（本書と同じ版と大きさを指定する。初回は数分かかる）
minikube start --driver=docker --container-runtime=containerd \
  --kubernetes-version=v1.37.0 --cpus=2 --memory=3072
minikube status
kubectl config current-context    # minikube と表示されること
kubectl get nodes

# 最初のコンテナを動かす
kubectl run hello --image=nginx:1.30.6-alpine
kubectl get pods

# 手元の 8000 番から Pod の 80 番に届ける（このターミナルは開いたままにする）
kubectl port-forward pod/hello 8000:80
```

別のターミナルで http://localhost:8000 を開くと、nginx の画面が出ます。確かめたら port-forward を Ctrl+C で止めます。

```bash
kubectl delete pod hello
kubectl get pods -A               # kube-system で Kubernetes の部品が動いている

# クラスターを止めて、もう一度起動する
minikube stop
minikube start
```

## 確かめ方

- `kubectl get nodes` で `minikube` が `Ready`
- `kubectl get pods` で `hello` が `Running`
- port-forward の間、http://localhost:8000 に「Welcome to nginx!」が出る

書籍に載せた実行結果は `../docs/logs/ch02-*.txt` にあります。

## 後片付けと中断

次の章は、このクラスターをそのまま使います。中断するときは `minikube stop` で止めます。最初からやり直すときは、`minikube delete` でクラスターを消してから `minikube start` を打ち直します。

次の章: [第3章 コンテナをKubernetesで動かす](../ch03/)
