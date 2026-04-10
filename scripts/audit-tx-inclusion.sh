#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <summary.csv> <out.csv>" >&2
  exit 1
fi
SUMMARY="$1"
OUT="$2"
CONTAINER="${CONTAINER:-chain-0-node-1}"
NODE="${NODE:-tcp://127.0.0.1:26657}"

echo 'sequence_no,txhash,submit_code,local_submit_ts,height,tx_time,local_submit_to_inclusion_secs,gas_wanted,gas_used,tx_code,codespace' > "$OUT"
tail -n +2 "$SUMMARY" | while IFS=, read -r sequence_no local_submit_ts txhash amount from_key to_key from_addr to_addr code raw_log; do
  txhash=$(printf '%s' "$txhash" | sed 's/^"//; s/"$//')
  local_submit_ts=$(printf '%s' "$local_submit_ts" | sed 's/^"//; s/"$//')
  code=$(printf '%s' "$code" | sed 's/^"//; s/"$//')
  if [[ -z "$txhash" ]]; then
    echo "$sequence_no,$txhash,$code,$local_submit_ts,,,,,,," >> "$OUT"
    continue
  fi
  TX_JSON=$(sudo docker exec "$CONTAINER" simd query tx "$txhash" --node "$NODE" -o json 2>/dev/null || true)
  if [[ -z "$TX_JSON" ]]; then
    echo "$sequence_no,$txhash,$code,$local_submit_ts,,,,,,," >> "$OUT"
    continue
  fi
  height=$(echo "$TX_JSON" | jq -r '.height // empty')
  tx_time=$(echo "$TX_JSON" | jq -r '.timestamp // empty')
  gas_wanted=$(echo "$TX_JSON" | jq -r '.gas_wanted // empty')
  gas_used=$(echo "$TX_JSON" | jq -r '.gas_used // empty')
  tx_code=$(echo "$TX_JSON" | jq -r '.code // 0')
  codespace=$(echo "$TX_JSON" | jq -r '.codespace // empty')
  delta=$(python3 - <<PY
from datetime import datetime
submit_ts = float("${local_submit_ts:-0}")
ts = """$tx_time""".strip()
if not ts:
    print("")
else:
    ts = ts.replace('Z', '+00:00')
    print(f"{datetime.fromisoformat(ts).timestamp()-submit_ts:.6f}")
PY
)
  echo "$sequence_no,$txhash,$code,$local_submit_ts,$height,$tx_time,$delta,$gas_wanted,$gas_used,$tx_code,$codespace" >> "$OUT"
done

echo "wrote: $OUT"
