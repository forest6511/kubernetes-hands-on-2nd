# 第7章 Kustomizeでマニフェストを管理する

開発用と本番用で、台数と見出しだけが違うマニフェストが欲しくなりました。ファイルをコピーすると、同じ内容が2か所に増えます。Kustomize で、共通の部分を base に、環境ごとの違いだけを overlay に書きます。

## この章で使うファイル

- `copy/dev/`・`copy/prod/` — コピーで作った開発用と本番用（違いを `diff` で見るための比較用。適用しない）
- `kustomize/base/` — どの環境でも同じマニフェスト（todo-frontend・todo-api・todo-db・ConfigMap・HTTPRoute）と `kustomization.yaml`
- `kustomize/overlays/dev/` — 開発用。見出しを「Todo（開発）」に変える patch
- `kustomize/overlays/prod/` — 本番用。todo-api と todo-frontend の台数を増やす patch
- `kustomize/overlays/typo/` — わざと失敗させる overlay。patch の対象の名前が1文字違う（`todo-api` → `todo-apl`）
- `kustomize/shared/` — アプリを入れ直しても残したいもの（Gateway・PVC）
- `up.sh` — この章の開始状態（第6章の終わり）を作る

## 始める前に

第6章の終わりの状態（ConfigMap・Secret・PVC を使う Todo アプリ）から始めます。やり直すときは次を打ちます。

```bash
minikube delete
bash ch07/up.sh
```

**新しいターミナルを開いて** `minikube service todo-gateway-nginx --url` を動かし、表示された URL をブラウザーで開いておきます。

## 手順

```bash
# コピーで作ると、ほとんど同じファイルが2組できる
diff -r ch07/copy/dev ch07/copy/prod

# Kustomize で組み立てた結果を見る（適用はしない）
kubectl kustomize ch07/kustomize/overlays/dev
diff <(kubectl kustomize ch07/kustomize/overlays/dev) <(kubectl kustomize ch07/kustomize/overlays/prod)

# わざと失敗させる: patch の対象の名前の間違い → 組み立ての時点でエラー
kubectl kustomize ch07/kustomize/overlays/typo

# 残したいもの（Gateway・PVC）と、開発用のアプリを適用する
kubectl apply -k ch07/kustomize/shared
kubectl apply -k ch07/kustomize/overlays/dev
kubectl rollout restart deployment/todo-api
kubectl rollout status deployment/todo-api
```

## 確かめ方

- dev と prod の `diff` に出るのは、台数（`replicas`）と見出し（`APP_TITLE`）だけ。prod でも todo-db は1つ
- `typo` は `kubectl kustomize` の時点でエラーになり、クラスターには何も届かない
- ブラウザーを再読み込みすると、見出しが「Todo（開発）」になり、前の章の Todo が残っている

書籍に載せた実行結果は `../docs/logs/ch07-*.txt` にあります。

## 後片付けと中断

`minikube service` を動かしているターミナルで Ctrl+C を押して止めます。Kustomize で入れたアプリは、そのまま次の章で使います。中断するときは `minikube stop`、やり直すときは `minikube delete` のあと `bash ch07/up.sh` を打ちます。

次の章: [第8章 Helm 4でアプリをパッケージにする](../ch08/)
