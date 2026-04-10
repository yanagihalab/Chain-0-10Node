#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
  echo "usage: $0 <count> <amount-denom> <outdir> [interval_sec=0.0] [from_key=validator]" >&2
  exit 1
fi
COUNT="$1"
AMOUNT="$2"
OUTDIR="$3"
INTERVAL="${4:-0.0}"
FROM_KEY="${5:-validator}"
TO_KEY="${TO_KEY:-user1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUTDIR/tx_raw"
SUMMARY="$OUTDIR/summary.csv"

echo 'sequence_no,local_submit_ts,txhash,amount,from_key,to_key,from_addr,to_addr,code,raw_log' > "$SUMMARY"
for i in $(seq 1 "$COUNT"); do
  JSON=$("$SCRIPT_DIR/send-bank-tx.sh" "$AMOUNT" "$FROM_KEY" "$TO_KEY" "$OUTDIR/tx_raw")
  echo "$JSON" | jq -r --arg seq "$i" '[ $seq, .local_submit_ts, .txhash, .amount, .from_key, .to_key, .from_addr, .to_addr, (.code|tostring), .raw_log ] | @csv' >> "$SUMMARY"
  python3 - <<PY
import time
interval=float("$INTERVAL")
if interval>0:
    time.sleep(interval)
PY
done

echo "wrote: $SUMMARY"
