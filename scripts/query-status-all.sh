#!/usr/bin/env bash
set -euo pipefail

NUM_NODES="${NUM_NODES:-30}"

for i in $(seq 1 "$NUM_NODES"); do
  RPC=$((37656 + i))
  echo "=== node$i : http://localhost:${RPC}/status ==="
  curl -s "http://localhost:${RPC}/status" | jq '{
    node_info: .result.node_info.moniker,
    network: .result.node_info.network,
    latest_block_height: .result.sync_info.latest_block_height,
    latest_block_time: .result.sync_info.latest_block_time,
    catching_up: .result.sync_info.catching_up
  }'
  echo
done
