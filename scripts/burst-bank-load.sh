#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 6 ]]; then
  echo "usage: $0 <count> <amount-denom> <outdir> [interval_sec=0.0] [wallet_prefix=wallet] [to_key=user1]" >&2
  exit 1
fi

COUNT="$1"
AMOUNT="$2"
OUTDIR="$3"
INTERVAL="${4:-0.0}"
WALLET_PREFIX="${5:-wallet}"
TO_KEY="${6:-user1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUTDIR/tx_raw"
SUMMARY="$OUTDIR/summary.csv"
TMPDIR="$OUTDIR/tmp_rows"

rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

echo 'sequence_no,local_submit_ts,txhash,amount,from_key,to_key,from_addr,to_addr,code,raw_log' > "$SUMMARY"

pids=()

for i in $(seq 1 "$COUNT"); do
  from_key=$(printf '%s%03d' "$WALLET_PREFIX" "$i")
  row_file="$TMPDIR/row_${i}.csv"

  (
    JSON=$("$SCRIPT_DIR/send-bank-tx.sh" "$AMOUNT" "$from_key" "$TO_KEY" "$OUTDIR/tx_raw")
    echo "$JSON" | jq -r --arg seq "$i" '[ $seq, .local_submit_ts, .txhash, .amount, .from_key, .to_key, .from_addr, .to_addr, (.code|tostring), .raw_log ] | @csv' > "$row_file"
  ) &

  pids+=($!)

  python3 - <<PY
import time
interval=float("$INTERVAL")
if interval > 0:
    time.sleep(interval)
PY
done

for pid in "${pids[@]}"; do
  wait "$pid"
done

for i in $(seq 1 "$COUNT"); do
  cat "$TMPDIR/row_${i}.csv" >> "$SUMMARY"
done