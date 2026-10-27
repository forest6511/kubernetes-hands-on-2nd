#!/usr/bin/env bash
# 第1章の開始状態を確かめる（Docker Desktop が動いていれば、この章から始められる）。
# 使い方（サンプル repo の直下で）: bash ch01/up.sh
set -euo pipefail
if docker info >/dev/null 2>&1; then
  echo "Docker は動いています。第1章を始められます。"
else
  echo "Docker が動いていません。Docker Desktop を起動してから、もう一度実行してください。" >&2
  exit 1
fi
