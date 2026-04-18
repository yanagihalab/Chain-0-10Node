#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 7 ]]; then
  echo "usage: $0 <count> <amount-denom> <outdir> [interval_sec=0.0] [wallet_prefix=wallet] [to_key=user1] [max_parallel=100]" >&2
  exit 1
fi

COUNT="$1"
AMOUNT="$2"
OUTDIR="$3"
INTERVAL="${4:-0.0}"
WALLET_PREFIX="${5:-wallet}"
TO_KEY="${6:-user1}"
MAX_PARALLEL="${7:-100}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUTDIR/tx_raw"
SUMMARY="$OUTDIR/summary.csv"
TMPDIR="$OUTDIR/tmp_rows"

rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

echo 'sequence_no,local_submit_ts,txhash,amount,from_key,to_key,from_addr,to_addr,code,raw_log' > "$SUMMARY"

run_one() {
  local i="$1"
  local from_key
  local json_file
  from_key=$(printf '%s%03d' "$WALLET_PREFIX" "$i")
  json_file="$TMPDIR/row_${i}.json"

  if JSON=$("$SCRIPT_DIR/send-bank-tx.sh" "$AMOUNT" "$from_key" "$TO_KEY" "$OUTDIR/tx_raw" 2>/dev/null); then
    printf '%s\n' "$JSON" > "$json_file"
  else
    jq -n \
      --arg local_submit_ts "" \
      --arg txhash "" \
      --arg amount "$AMOUNT" \
      --arg from_key "$from_key" \
      --arg to_key "$TO_KEY" \
      --arg from_addr "" \
      --arg to_addr "" \
      --argjson code 999 \
      --arg raw_log "send-bank-tx.sh failed" \
      --arg waited "false" \
      '{
        local_submit_ts:$local_submit_ts,
        txhash:$txhash,
        amount:$amount,
        from_key:$from_key,
        to_key:$to_key,
        from_addr:$from_addr,
        to_addr:$to_addr,
        code:$code,
        raw_log:$raw_log,
        waited_for_inclusion:$waited
      }' > "$json_file"
  fi
}

export SCRIPT_DIR AMOUNT TO_KEY OUTDIR TMPDIR WALLET_PREFIX
export -f run_one

pids=()

for i in $(seq 1 "$COUNT"); do
  bash -c "run_one $i" &
  pids+=($!)

  while [[ $(jobs -pr | wc -l) -ge "$MAX_PARALLEL" ]]; do
    sleep 0.05
  done

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
  json_file="$TMPDIR/row_${i}.json"
  from_key=$(printf '%s%03d' "$WALLET_PREFIX" "$i")

  if [[ -f "$json_file" ]]; then
    jq -r --arg seq "$i" '
      [
        $seq,
        .local_submit_ts,
        .txhash,
        .amount,
        .from_key,
        .to_key,
        .from_addr,
        .to_addr,
        (.code|tostring),
        .raw_log
      ] | @csv
    ' "$json_file" >> "$SUMMARY"
  else
    jq -n \
      --arg seq "$i" \
      --arg amount "$AMOUNT" \
      --arg from_key "$from_key" \
      --arg to_key "$TO_KEY" \
      '[
        $seq,
        "",
        "",
        $amount,
        $from_key,
        $to_key,
        "",
        "",
        "998",
        "missing row json"
      ] | @csv' -r >> "$SUMMARY"
  fi
done
