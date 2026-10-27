# Kubernetes入門ハンズオン（改訂版）— サンプルコード

書籍『Kubernetes入門ハンズオン ― minikubeで学ぶPod・Service・Helm 4』（2026年10月 改訂版）のサンプルコードです。
Docker Compose で動く1つの Todo アプリ（画面・API・DB）を、手元のパソコンの minikube に1章ずつ載せ替えながら、Pod・Deployment・Service・Gateway API・ConfigMap・Secret・PVC・Kustomize・Helm 4 を学びます。

> **本書および本リポジトリは、The Linux Foundation・Cloud Native Computing Foundation とは無関係の非公式な出版物です。**

Kindle 版: [Kubernetes入門ハンズオン](https://www.amazon.co.jp/dp/B0GGYSLR1P)

## 料金について

> [!NOTE]
> **このリポジトリの手順は、手元のパソコンの minikube だけで動きます。クラウドの有料サービスは使わず、料金はかかりません。**
>
> イメージのダウンロードに、インターネットの接続が必要です（Docker Hub・registry.k8s.io・GitHub など）。

詳細は [DISCLAIMER.md](DISCLAIMER.md) を参照してください。

## 動作環境

本書の手順は次の版で確認しています（macOS・Apple シリコン。Linux は GitHub Actions の Ubuntu で全章を確認）。

- Docker Desktop（Linux では Docker Engine）。Docker に 4GB 以上のメモリを割り当てる
- minikube v1.39.0（ドライバーは docker）、Kubernetes v1.37.0
- kubectl v1.37.1（Kustomize v5.8.1 を同梱）
- Helm v4.3.1
- Gateway API v1.6.3、NGINX Gateway Fabric v2.8.0
- アプリ: Go 1.27、PostgreSQL 18.6（`postgres:18.6-alpine`）、nginx 1.30.6（`nginx:1.30.6-alpine`）

Windows では WSL2 の Ubuntu で実行します。各ツールの入れ方は書籍 第2章にあります。

## 使い方

```bash
# 1. ホームディレクトリにクローンする
cd ~
git clone https://github.com/forest6511/kubernetes-hands-on-2nd.git
cd kubernetes-hands-on-2nd

# 2. 第1章から順に、書籍の手順どおりにコマンドを打つ
docker compose -f ch01/compose.yaml up -d
```

**コマンドは、すべてこの `kubernetes-hands-on-2nd` ディレクトリの直下で打ちます。** 書籍のコードの枠の上にある「ファイル: `ch03/pod.yaml`」は、このディレクトリから見たパスです。

各章のディレクトリに README があります。その章で使うファイル、始める前の状態、打つコマンドの順番、うまくいったかの確かめ方、後片付けをまとめています。

画面は、手元の次のポートで開きます。

- 第1章（Docker Compose）: 画面 http://localhost:8000
- 第2章（`kubectl port-forward`）: nginx の画面 http://localhost:8000
- 第4章（`kubectl port-forward`）: 画面 http://localhost:8000 、API http://localhost:8001
- 第5章以降（Gateway API）: `minikube service todo-gateway-nginx --url` が表示する URL

## 途中の章から始める

第3章以降の各章には、その章の開始状態を新しい minikube に作る `up.sh` があります。前の章を飛ばしたいとき、途中でクラスターを壊してやり直したいときに使います。

```bash
minikube delete       # 今のクラスターを消す（中のものはすべて消える）
bash ch05/up.sh       # 第5章の開始状態を作る（数分かかる）
```

`up.sh` は、前の章までの手順を書籍と同じ順番で実行します（中身は `scripts/lib.sh`）。第1・2章の `up.sh` は、Docker が動いているかを確かめるだけです。

## 章の一覧

章ごとのディレクトリは、前の章の続きから使います。第3章以降は、前の章で作ったクラスターにリソースを積み上げていきます。

- [`ch01/`](ch01/) — 第1章 なぜKubernetesが必要なのか（Docker Compose で Todo アプリを動かし、コンテナを消すと戻らないことを確かめる）
- [`ch02/`](ch02/) — 第2章 minikubeで環境を構築する（クラスターの起動と、最初のコンテナ）
- [`ch03/`](ch03/) — 第3章 コンテナをKubernetesで動かす（Pod・Deployment・ReplicaSet と、Todo アプリの3つの Deployment）
- [`ch04/`](ch04/) — 第4章 Podをネットワークで接続する（Service・DNS・ローリングアップデート）
- [`ch05/`](ch05/) — 第5章 Gateway APIでトラフィックを管理する（Gateway と HTTPRoute）
- [`ch06/`](ch06/) — 第6章 アプリの設定とデータを外部化する（ConfigMap・Secret・PVC）
- [`ch07/`](ch07/) — 第7章 Kustomizeでマニフェストを管理する（base と overlay）
- [`ch08/`](ch08/) — 第8章 Helm 4でアプリをパッケージにする（チャート・upgrade・rollback）

## ディレクトリ構成

- `app/api/` — Todo API（Go）。PostgreSQL に Todo を保存します
- `app/frontend/` — 画面（nginx）。`/api` を todo-api に中継します。第4章で使う v2 は見出しの色だけが違います
- `ch01/`〜`ch08/` — 各章のマニフェスト・`compose.yaml`・Kustomize・Helm のチャートと、開始状態を作る `up.sh`
- `scripts/lib.sh` — `up.sh` が使う共通の手順（書籍と同じコマンドを同じ順番で実行する）
- `scripts/e2e.sh`・`scripts/e2e-all.sh` — 全章の手順を通しで実行し、結果を確かめるテスト
- `docs/logs/` — 書籍に載せた実行結果（自分の画面と見比べるときに使えます）

ファイル名に `typo`・`wrong-key` が付いたものは、書籍の「わざと失敗させる」節で使う、わざと間違えたマニフェストです。

## 検査

```bash
make check                 # Go の整形・静的検査・テスト・脆弱性、YAML、マニフェストのスキーマ、ワークフロー、シェル
bash scripts/e2e-all.sh    # 全章の手順を専用の minikube のプロファイル（k8s-book）で通しで実行する（数十分かかる）
```

`e2e-all.sh` は、普段使う `minikube` のクラスターとは別のプロファイルで動くので、読み進めている途中のクラスターには触りません。同じ検査を GitHub Actions（`.github/workflows/e2e.yml`）でも実行しています。

## 利用上の注意

> [!WARNING]
> **このコードは学習用です。本番環境にそのまま使わないでください。**
> 本書の構成は、手順を追いやすくするために単純化しています。実運用では次の検討が必要です。
>
> - Secret の扱い（本書の DB のパスワードは学習用の固定値です）
> - DB の冗長化とバックアップ（本書の PostgreSQL は1つの Pod だけです）
> - リソースの requests・limits、ネットワークの分離とアクセス制御
> - 監視とアラート

## 初版のリポジトリ

初版の読者は、旧リポジトリ [kubernetes-hands-on](https://github.com/forest6511/kubernetes-hands-on) を使ってください。

## ライセンス

[MIT License](LICENSE)

ライセンスはコードの利用許諾です。損害の免責については [DISCLAIMER.md](DISCLAIMER.md) を参照してください。
