#!/usr/bin/env bash
# 全章の e2e を、新しい minikube（専用のプロファイル）で頭から流す。
#   bash scripts/e2e-all.sh            第1章（Compose）→ 第2〜8章を1つのクラスターで続けて → 各章の up.sh の確認
#   CAPTURE=1 bash scripts/e2e-all.sh  本に載せる実行結果も docs/logs/ に保存する
# 読者の既定のプロファイル（minikube）には触らない。kubeconfig も専用のファイルを使う
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

export MINIKUBE_PROFILE=${E2E_PROFILE:-k8s-book}
if [ "$MINIKUBE_PROFILE" = minikube ]; then
  echo "既定のプロファイル minikube では実行しない（E2E_PROFILE を別の名前にする）" >&2
  exit 2
fi
WORK=$(mktemp -d)
export KUBECONFIG=$WORK/kubeconfig
export E2E_RESULTS=$WORK/results.tsv
: >"$E2E_RESULTS"
START=$(date +%s)

fresh() { minikube delete >/dev/null 2>&1; }

rc=0
# 第1章（Docker Compose）
E2E_TRACE=docs/logs/trace-ch01.txt; : >"$E2E_TRACE"; export E2E_TRACE
bash scripts/e2e.sh 01 || rc=1

# 第2〜8章を、新しいクラスターで続けて流す（前の章の終わりが次の章の始まり）
fresh
for n in 02 03 04 05 06 07 08; do
  export E2E_TRACE=docs/logs/trace-ch$n.txt; : >"$E2E_TRACE"
  bash scripts/e2e.sh "$n" || rc=1
done

# 各章の up.sh が、新しいクラスターにその章の開始状態を作れるか
up_check() { # up_check <章> <確かめるコマンド...>
  local n=$1; shift
  fresh
  if bash "ch$n/up.sh" >"$WORK/up-$n.log" 2>&1 && "$@" >/dev/null 2>&1; then
    printf 'PASS\tup.sh\tch%s\t%s\n' "$n" "ch$n/up.sh で開始状態ができる" >>"$E2E_RESULTS"
    echo "PASS [up.sh] ch$n"
  else
    printf 'FAIL\tup.sh\tch%s\t%s\n' "$n" "ch$n/up.sh（ログ: $WORK/up-$n.log）" >>"$E2E_RESULTS"
    echo "FAIL [up.sh] ch${n}（$WORK/up-$n.log）" >&2; rc=1
    tail -40 "$WORK/up-$n.log" >&2
    kubectl get pods -A >&2 || true
  fi
}
unset E2E_TRACE
up_check 03 kubectl wait --for=condition=Ready node --all --timeout=60s
up_check 04 bash -c "kubectl get pods -l app=todo-api -o jsonpath='{.items[0].status.containerStatuses[0].ready}' | grep -q false"
up_check 05 kubectl rollout status deployment/todo-frontend --timeout=120s
up_check 06 kubectl wait --for=condition=Programmed gateway/todo-gateway --timeout=120s
up_check 07 bash -c "kubectl get pvc todo-db-data -o jsonpath='{.status.phase}' | grep -q Bound"
up_check 08 bash -c "kubectl get configmap todo-config -o jsonpath='{.data.APP_TITLE}' | grep -q '開発'"
fresh

# 項目ごとの件数
echo
echo "== e2e の結果（$(( $(date +%s) - START ))秒・profile=${MINIKUBE_PROFILE}）"
awk -F'\t' '{n[$2" "$1]++} END {for (k in n) print k": "n[k]}' "$E2E_RESULTS" | sort
echo "合計: PASS $(grep -c '^PASS' "$E2E_RESULTS") / FAIL $(grep -c '^FAIL' "$E2E_RESULTS")"
cp "$E2E_RESULTS" docs/logs/e2e-results.tsv
grep '^FAIL' "$E2E_RESULTS" && rc=1
rm -rf "$WORK"
exit $rc
