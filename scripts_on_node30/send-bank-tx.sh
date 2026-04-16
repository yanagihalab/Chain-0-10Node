#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "usage: $0 <amount-denom> [from_key=validator] [to_key=user1] [outdir=.]" >&2
  exit 1
fi

AMOUNT="$1"
FROM_KEY="${2:-validator}"
TO_KEY="${3:-user1}"
OUTDIR="${4:-.}"

CONTAINER="${CONTAINER:-chain-0-node-1}"
CHAIN_ID="${CHAIN_ID:-chain-0}"
NODE="${NODE:-tcp://127.0.0.1:26657}"
FEES="${FEES:-0stake}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"
WAIT_INTERVAL="${WAIT_INTERVAL:-0.4}"

mkdir -p "$OUTDIR"

LOCAL_SUBMIT_TS=$(python3 - <<'PY'
import time
print(f"{time.time():.6f}")
PY
)

FROM_ADDR=$(sudo docker exec "$CONTAINER" simd keys show "$FROM_KEY" -a --keyring-backend test --home /root/.simapp)
TO_ADDR=$(sudo docker exec "$CONTAINER" simd keys show "$TO_KEY" -a --keyring-backend test --home /root/.simapp)

RAW_JSON=$(sudo docker exec "$CONTAINER" simd tx bank send "$FROM_ADDR" "$TO_ADDR" "$AMOUNT" \
  --chain-id "$CHAIN_ID" \
  --keyring-backend test \
  --home /root/.simapp \
  --node "$NODE" \
  --yes \
  --broadcast-mode sync \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 0.03stake \
  -o json)

TXHASH=$(echo "$RAW_JSON" | jq -r '.txhash // empty')
CODE=$(echo "$RAW_JSON" | jq -r '.code // 0')
RAW_LOG=$(echo "$RAW_JSON" | jq -c '.raw_log // empty')

BASENAME="tx-${TXHASH:-unknown}"
printf '%s\n' "$RAW_JSON" > "$OUTDIR/${BASENAME}-submit.json"

# submit 自体が失敗ならそのまま返す
if [[ -z "$TXHASH" || "$CODE" != "0" ]]; then
  jq -n \
    --arg local_submit_ts "$LOCAL_SUBMIT_TS" \
    --arg txhash "$TXHASH" \
    --arg amount "$AMOUNT" \
    --arg from_key "$FROM_KEY" \
    --arg to_key "$TO_KEY" \
    --arg from_addr "$FROM_ADDR" \
    --arg to_addr "$TO_ADDR" \
    --argjson code "${CODE:-0}" \
    --arg raw_log "$RAW_LOG" \
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
    }' > "$OUTDIR/${BASENAME}-summary.json"

  cat "$OUTDIR/${BASENAME}-summary.json"
  exit 0
fi

# tx inclusion を待つ
FOUND=0
START_TS=$(python3 - <<'PY'
import time
print(time.time())
PY
)

while true; do
  if sudo docker exec "$CONTAINER" simd query tx "$TXHASH" --node "$NODE" -o json > "$OUTDIR/${BASENAME}-tx.json" 2>/dev/null; then
    FOUND=1
    break
  fi

  NOW_TS=$(python3 - <<'PY'
import time
print(time.time())
PY
)

  ELAPSED=$(python3 - <<PY
start=float("$START_TS")
now=float("$NOW_TS")
print(now-start)
PY
)

  TIMEOUT_REACHED=$(python3 - <<PY
elapsed=float("$ELAPSED")
timeout=float("$WAIT_TIMEOUT")
print("1" if elapsed >= timeout else "0")
PY
)

  if [[ "$TIMEOUT_REACHED" == "1" ]]; then
    break
  fi

  python3 - <<PY
import time
time.sleep(float("$WAIT_INTERVAL"))
PY
done

jq -n \
  --arg local_submit_ts "$LOCAL_SUBMIT_TS" \
  --arg txhash "$TXHASH" \
  --arg amount "$AMOUNT" \
  --arg from_key "$FROM_KEY" \
  --arg to_key "$TO_KEY" \
  --arg from_addr "$FROM_ADDR" \
  --arg to_addr "$TO_ADDR" \
  --argjson code "${CODE:-0}" \
  --arg raw_log "$RAW_LOG" \
  --arg waited "$( [[ "$FOUND" == "1" ]] && echo true || echo false )" \
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
  }' > "$OUTDIR/${BASENAME}-summary.json"

cat "$OUTDIR/${BASENAME}-summary.json"