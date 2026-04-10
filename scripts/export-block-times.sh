#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "usage: $0 <num_blocks> <out.csv>" >&2
  exit 1
fi
NUM_BLOCKS="$1"
OUT="$2"
RPC_PORT="${RPC_PORT:-37657}"
END_HEIGHT=$(curl -s "http://localhost:${RPC_PORT}/status" | jq -r '.result.sync_info.latest_block_height')
START_HEIGHT=$(( END_HEIGHT - NUM_BLOCKS + 1 ))
if (( START_HEIGHT < 1 )); then START_HEIGHT=1; fi

echo 'height,block_time,delta_from_prev_secs' > "$OUT"
PREV_TS=""
for h in $(seq "$START_HEIGHT" "$END_HEIGHT"); do
  TS=$(curl -s "http://localhost:${RPC_PORT}/block?height=$h" | jq -r '.result.block.header.time')
  if [[ -n "$PREV_TS" ]]; then
    DELTA=$(python3 - <<PY
from datetime import datetime
prev = "$PREV_TS".replace('Z', '+00:00')
cur = "$TS".replace('Z', '+00:00')
print(f"{datetime.fromisoformat(cur).timestamp()-datetime.fromisoformat(prev).timestamp():.6f}")
PY
)
  else
    DELTA=""
  fi
  echo "$h,$TS,$DELTA" >> "$OUT"
  PREV_TS="$TS"
done

echo "wrote: $OUT"
