#!/usr/bin/env bash
set -euo pipefail

RPC="${1:-http://127.0.0.1:37657}"
INTERVAL="${2:-1}"

while true; do
  TS="$(date '+%Y-%m-%d %H:%M:%S')"
  COUNT="$(curl -s "${RPC}/num_unconfirmed_txs" | jq -r '.result.n_txs // "NA"')"
  TOTAL="$(curl -s "${RPC}/num_unconfirmed_txs" | jq -r '.result.total // "NA"')"
  echo "${TS} n_txs=${COUNT} total=${TOTAL}"
  sleep "$INTERVAL"
done
