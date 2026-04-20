#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 6 || $# -gt 9 ]]; then
  echo "usage: $0 <total_count> <amount-denom> <outdir> <wallet_count> <max_parallel> <interval_sec=0.0> [wallet_prefix=wallet] [to_key=user1] [round_pause_sec=0.0]" >&2
  exit 1
fi

TOTAL_COUNT="$1"
AMOUNT="$2"
OUTDIR="$3"
WALLET_COUNT="$4"
MAX_PARALLEL="$5"
INTERVAL="${6:-0.0}"
WALLET_PREFIX="${7:-wallet}"
TO_KEY="${8:-user1}"
ROUND_PAUSE="${9:-0.0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUMMARY="$OUTDIR/summary.csv"
TX_RAW_DIR="$OUTDIR/tx_raw"
TMPDIR="$OUTDIR/tmp_rows"

mkdir -p "$TX_RAW_DIR"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

echo 'sequence_no,local_submit_ts,txhash,amount,from_key,to_key,from_addr,to_addr,code,raw_log' > "$SUMMARY"

run_one() {
  local seq_no="$1"
  local wallet_idx="$2"
  local from_key
  local json_file

  from_key=$(printf '%s%03d' "$WALLET_PREFIX" "$wallet_idx")
  json_file="$TMPDIR/row_${seq_no}.json"

  if JSON=$("$SCRIPT_DIR/send-bank-tx.sh" "$AMOUNT" "$from_key" "$TO_KEY" "$TX_RAW_DIR" 2>/dev/null); then
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
      '{
        local_submit_ts:$local_submit_ts,
        txhash:$txhash,
        amount:$amount,
        from_key:$from_key,
        to_key:$to_key,
        from_addr:$from_addr,
        to_addr:$to_addr,
        code:$code,
        raw_log:$raw_log
      }' > "$json_file"
  fi
}

export SCRIPT_DIR AMOUNT TO_KEY TX_RAW_DIR TMPDIR WALLET_PREFIX
export -f run_one

seq_no=1
round_no=1

while [[ "$seq_no" -le "$TOTAL_COUNT" ]]; do
  round_start="$seq_no"
  round_end=$(( round_start + WALLET_COUNT - 1 ))
  if [[ "$round_end" -gt "$TOTAL_COUNT" ]]; then
    round_end="$TOTAL_COUNT"
  fi

  pids=()

  wallet_idx=1
  for current_seq in $(seq "$round_start" "$round_end"); do
    bash -c "run_one $current_seq $wallet_idx" &
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

    wallet_idx=$((wallet_idx + 1))
  done

  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  python3 - <<PY
import time
pause=float("$ROUND_PAUSE")
if pause > 0:
    time.sleep(pause)
PY

  round_no=$((round_no + 1))
  seq_no=$((round_end + 1))
done

for i in $(seq 1 "$TOTAL_COUNT"); do
  json_file="$TMPDIR/row_${i}.json"
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
      '[
        $seq,
        "",
        "",
        $amount,
        "",
        "",
        "",
        "",
        "998",
        "missing row json"
      ] | @csv' -r >> "$SUMMARY"
  fi
done
