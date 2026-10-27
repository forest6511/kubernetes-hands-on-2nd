# 第8章 Helm 4でアプリをパッケージにする

Kustomize では、適用したあとにアプリ全体を前の状態に戻す方法がありません。Helm で Todo アプリを1つのパッケージ（チャート）にしてリリースとして入れ、更新のたびに記録されるリビジョンを使って、失敗した更新を前の版に戻します。

## この章で使うファイル

- `helm/todo/Chart.yaml` — チャートの名前と版
- `helm/todo/values.yaml` — 入れるときに変えられる値（台数・イメージのタグ・見出しなど。`--set` で上書きできる）
- `helm/todo/templates/` — マニフェストのテンプレート（todo-frontend・todo-api・todo-db・ConfigMap・HTTPRoute）
- `up.sh` — この章の開始状態（第7章の終わり）を作る

チャートは、前の章で作った PVC（todo-db-data）・Secret（todo-db）・Gateway（todo-gateway）を使い、自分では作りません。

## 始める前に

第7章の終わりの状態（Kustomize の dev で入れた Todo アプリ）から始めます。やり直すときは次を打ちます。

```bash
minikube delete
bash ch08/up.sh
```

Helm v4.3.1 を入れておきます。macOS は `brew install helm`、Linux と WSL2 の Ubuntu は書籍 第8章の手順で入れます。

```bash
helm version --short    # v4.3.1 と表示されること
```

## 手順

```bash
# 公開されているチャートを入れて、消してみる
helm install podinfo oci://ghcr.io/stefanprodan/charts/podinfo --version 6.17.0
helm list
helm uninstall podinfo

# Todo アプリのチャートを確かめる
helm template todo ch08/helm/todo --show-only templates/todo-config.yaml
helm lint ch08/helm/todo

# Kustomize で入れたアプリを消し、Helm で入れ直す（PVC と Gateway は残る）
kubectl delete -k ch07/kustomize/overlays/dev
kubectl get pvc,gateway
helm install todo ch08/helm/todo
kubectl get pods

# 更新して、記録を見る
helm upgrade todo ch08/helm/todo --set api.replicas=2
helm history todo

# わざと失敗させる: 存在しないイメージ（v9）への更新 → 番号を指定して戻す
helm upgrade todo ch08/helm/todo --set api.tag=v9 --wait=watcher --timeout=90s
helm history todo
kubectl get pods -l app=todo-api
helm rollback todo 2
helm history todo

# 失敗したら自動で戻す
helm upgrade todo ch08/helm/todo --set api.tag=v9 --rollback-on-failure --timeout=90s
helm history todo
helm list
```

`minikube service todo-gateway-nginx --url` を別のターミナルで動かすと、Helm で入れた Todo アプリをブラウザーで開けます。

## 確かめ方

- `delete -k` のあとも `kubectl get pvc,gateway` に PVC と Gateway が残り、`helm install` のあと前の章の Todo が見える
- `helm history todo` で、upgrade のたびにリビジョンの番号が増える
- v9 への更新は失敗し、history に `failed` が出る。その間も古い todo-api で画面は動く
- `helm rollback todo 2` のあと、history に `Rollback to 2` の新しい番号が増える（戻しても番号は増える）
- `--rollback-on-failure` を付けると、失敗した更新が自動で前の版に戻る
- 最後に `helm list` で `todo` が `deployed`

書籍に載せた実行結果は `../docs/logs/ch08-*.txt` にあります。

## 後片付け

本書のハンズオンはこれで終わりです。`minikube service` を動かしているターミナルで Ctrl+C を押して止めます。クラスターを止めるときは `minikube stop`、クラスターごと消すときは `minikube delete` を打ちます（中のものはすべて消えます）。

前の章: [第7章 Kustomizeでマニフェストを管理する](../ch07/) ・ [リポジトリのトップへ](../)
