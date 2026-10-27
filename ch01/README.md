# 第1章 なぜKubernetesが必要なのか

Todo アプリ（画面・API・DB の3つのコンテナ）を Docker Compose で動かします。API のコンテナを消すと、誰も元に戻さないことを確かめ、Kubernetes が何をするのかを考えます。

## この章で使うファイル

- `compose.yaml` — Todo アプリの3つのコンテナ（todo-frontend・todo-api・todo-db）
- `up.sh` — Docker が動いているかを確かめる
- アプリのコード: `../app/frontend/`・`../app/api/`（`compose.yaml` の `build:` が参照する）

## 始める前に

Docker Desktop（Linux では Docker Engine）を起動しておきます。

```bash
bash ch01/up.sh            # 「Docker は動いています。」と出れば準備できています
docker compose version     # Docker Compose の版が表示されること
```

## 手順

```bash
# Todo アプリを起動する（初回はイメージのビルドに数分かかる）
docker compose -f ch01/compose.yaml up -d
docker compose -f ch01/compose.yaml ps --format "table {{.Service}}\t{{.Status}}"
```

ブラウザーで http://localhost:8000 を開き、Todo を1つ追加します。

```bash
# API から Todo の一覧を取る
curl -s http://localhost:8000/api/todos

# API のコンテナを消す → 画面の操作と API がエラーになり、待っても戻らない
docker rm -f ch01-todo-api-1
curl -s http://localhost:8000/api/todos

# もう一度 up を打つと戻る（Todo も残っている）
docker compose -f ch01/compose.yaml up -d
curl -s http://localhost:8000/api/todos
```

## 確かめ方

- `docker compose ps` で3つのサービスが `Up` になっている
- API のコンテナを消したあとは、`curl` の結果が Todo の一覧にならない（10秒待っても戻らない）
- `up -d` をもう一度打つと、追加した Todo が一覧に戻る

書籍に載せた実行結果は `../docs/logs/ch01-*.txt` にあります。

## 後片付け

この章のコンテナは、次の章では使いません。止めて消しておきます（`-v` で、追加した Todo のボリュームも消えます）。

```bash
docker compose -f ch01/compose.yaml down -v
```

イメージ（`todo-api:v1`・`todo-frontend:v1`）は残ります。第3章で minikube に渡して使います。

次の章: [第2章 minikubeで環境を構築する](../ch02/)
