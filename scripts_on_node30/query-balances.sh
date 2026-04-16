#!/usr/bin/env bash
set -euo pipefail
CONTAINER="${CONTAINER:-chain-0-node-1}"
NODE="${NODE:-tcp://127.0.0.1:26657}"
VAL=$(sudo docker exec "$CONTAINER" simd keys show validator -a --keyring-backend test --home /root/.simapp)
USER1=$(sudo docker exec "$CONTAINER" simd keys show user1 -a --keyring-backend test --home /root/.simapp)
echo "validator(node1)=$VAL"
echo "user1(node1)=$USER1"
sudo docker exec "$CONTAINER" simd query bank balances "$VAL" --node "$NODE" -o json | jq .
sudo docker exec "$CONTAINER" simd query bank balances "$USER1" --node "$NODE" -o json | jq .
