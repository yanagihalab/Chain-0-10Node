#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 || $# -gt 8 ]]; then
  echo "usage: $0 <total_count> <amount-denom> <outdir> <wallet_count> <max_parallel> [wallet_prefix=wallet] [to_key=user1] [poll_sec=0.05]" >&2
  exit 1
fi

TOTAL_COUNT="$1"
AMOUNT="$2"
OUTDIR="$3"
WALLET_COUNT="$4"
MAX_PARALLEL="$5"
WALLET_PREFIX="${6:-wallet}"
TO_KEY="${7:-user1}"
POLL_SEC="${8:-0.05}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUMMARY="$OUTDIR/summary.csv"
TX_RAW_DIR="$OUTDIR/tx_raw"
TMPDIR="$OUTDIR/tmp_rows"

mkdir -p "$TX_RAW_DIR"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

echo 'sequence_no,local_submit_ts,txhash,amount,from_key,to_key,from_addr,to_addr,code,raw_log' > "$SUMMARY"

declare -a WALLET_BUSY=()
for i in $(seq 1 "$WALLET_COUNT"); do
  WALLET_BUSY[$i]=0
done

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

declare -A PID_TO_WALLET=()
declare -A PID_TO_SEQ=()

next_seq=1

while true; do
  if [[ ${#PID_TO_WALLET[@]} -gt 0 ]]; then
    for pid in "${!PID_TO_WALLET[@]}"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" || true
        wallet_idx="${PID_TO_WALLET[$pid]}"
        WALLET_BUSY[$wallet_idx]=0
        unset PID_TO_WALLET["$pid"]
        unset PID_TO_SEQ["$pid"]
      fi
    done
  fi

  running=${#PID_TO_WALLET[@]}

  if [[ "$next_seq" -gt "$TOTAL_COUNT" && "$running" -eq 0 ]]; then
    break
  fi

  while [[ "$running" -lt "$MAX_PARALLEL" && "$next_seq" -le "$TOTAL_COUNT" ]]; do
    selected_wallet=0

    for wallet_idx in $(seq 1 "$WALLET_COUNT"); do
      if [[ "${WALLET_BUSY[$wallet_idx]}" -eq 0 ]]; then
        selected_wallet="$wallet_idx"
        break
      fi
    done

    if [[ "$selected_wallet" -eq 0 ]]; then
      break
    fi

    WALLET_BUSY[$selected_wallet]=1
    bash -c "run_one $next_seq $selected_wallet" &
    pid=$!
    PID_TO_WALLET["$pid"]="$selected_wallet"
    PID_TO_SEQ["$pid"]="$next_seq"

    next_seq=$((next_seq + 1))
    running=$((running + 1))
  done

  python3 - <<PY
import time
time.sleep(float("$POLL_SEC"))
PY
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
