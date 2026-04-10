#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <txhash> [timeout_sec=60]" >&2
  exit 1
fi
TXHASH="$1"
TIMEOUT_SEC="${2:-60}"
CONTAINER="${CONTAINER:-chain-0-node-1}"
NODE="${NODE:-tcp://127.0.0.1:26657}"
START=$(date +%s)
while true; do
  if OUT=$(sudo docker exec "$CONTAINER" simd query tx "$TXHASH" --node "$NODE" -o json 2>/dev/null); then
    echo "$OUT"
    exit 0
  fi
  NOW=$(date +%s)
  if (( NOW - START >= TIMEOUT_SEC )); then
    echo "timeout waiting for tx: $TXHASH" >&2
    exit 1
  fi
  sleep 1
done
