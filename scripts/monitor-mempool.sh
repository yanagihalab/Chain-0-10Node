#!/usr/bin/env bash
set -euo pipefail

RPC="${1:-http://127.0.0.1:37657}"
INTERVAL="${2:-1}"
OUT_CSV="${3:-mempool_watch.csv}"

# ヘッダが無ければ作成
if [[ ! -f "$OUT_CSV" ]]; then
  echo "timestamp,n_txs,total" > "$OUT_CSV"
fi

while true; do
  TS="$(date '+%Y-%m-%d %H:%M:%S')"

  RESP="$(curl -s "${RPC}/num_unconfirmed_txs")"
  COUNT="$(echo "$RESP" | jq -r '.result.n_txs // "NA"')"
  TOTAL="$(echo "$RESP" | jq -r '.result.total // "NA"')"

  echo "${TS} n_txs=${COUNT} total=${TOTAL}"
  echo "${TS},${COUNT},${TOTAL}" >> "$OUT_CSV"

  sleep "$INTERVAL"
done