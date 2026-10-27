#!/usr/bin/env bash
# 第6章の開始状態を、新しい minikube に作る。
# 使い方（サンプル repo の直下で）: bash ch06/up.sh
# やり直すときは、先に minikube delete で今のクラスターを消してから実行する
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

reach_end_of 5
show_start_state 6
