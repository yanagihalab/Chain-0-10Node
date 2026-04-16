#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT_DIR/docker-compose.yml"
IMAGE="${IMAGE:-ghcr.io/cosmos/ibc-go-simd:release-v10.4.x}"
NUM_NODES="${NUM_NODES:-10}"

cat > "$OUT" <<YAML
services:
YAML

for i in $(seq 1 "$NUM_NODES"); do
  RPC=$((37656 + i))
  API=$((13716 + i))
  GRPC=$((9489 + i))
  P2P=$((36655 + i))

  cat >> "$OUT" <<YAML
  node$i:
    image: $IMAGE
    container_name: chain-0-node-$i
    command: >
      start
      --home /root/.simapp
      --rpc.laddr tcp://0.0.0.0:26657
      --grpc.address 0.0.0.0:9090
      --api.enable=true
      --p2p.laddr tcp://0.0.0.0:26656
    volumes:
      - ./chains/node$i:/root/.simapp
    ports:
      - "$RPC:26657"
      - "$API:1317"
      - "$GRPC:9090"
      - "$P2P:26656"

YAML
done

echo "wrote: $OUT"
