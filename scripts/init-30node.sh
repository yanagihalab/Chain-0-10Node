#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHAINS_DIR="$ROOT_DIR/chains"
IMAGE="${IMAGE:-ghcr.io/cosmos/ibc-go-simd:release-v10.4.x}"
CHAIN_ID="${CHAIN_ID:-chain-0}"
KEYRING_BACKEND="${KEYRING_BACKEND:-test}"
DENOM="${DENOM:-stake}"
MONIKER_PREFIX="${MONIKER_PREFIX:-chain-0-node}"
NUM_NODES="${NUM_NODES:-30}"
VALIDATOR_TOKENS="${VALIDATOR_TOKENS:-1000000000${DENOM}}"
USER_TOKENS="${USER_TOKENS:-1000000000${DENOM}}"
STAKE_TOKENS="${STAKE_TOKENS:-500000000${DENOM}}"

fix_ownership() {
  sudo chown -R "$USER:$USER" "$ROOT_DIR" 2>/dev/null || true
}

run_in_node() {
  local node_dir="$1"
  shift
  sudo docker run --rm -v "$node_dir:/root/.simapp" --entrypoint sh "$IMAGE" -lc "$*"
}

mkdir -p "$CHAINS_DIR"
fix_ownership
rm -rf "$CHAINS_DIR"/node*

printf '[1/10] Pull image: %s\n' "$IMAGE"
sudo docker pull "$IMAGE"

printf '[2/10] Initialize %s nodes\n' "$NUM_NODES"
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  mkdir -p "$node_dir"
  run_in_node "$node_dir" "simd init ${MONIKER_PREFIX}-${i} --chain-id ${CHAIN_ID} --home /root/.simapp"
done
fix_ownership

printf '[3/10] Create validator keys on all nodes and user1 on node1\n'
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  run_in_node "$node_dir" "simd keys add validator --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp >/root/.simapp/validator-key.txt 2>&1"
  if [[ "$i" == "1" ]]; then
    run_in_node "$node_dir" "simd keys add user1 --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp >/root/.simapp/user1-key.txt 2>&1"
  fi
done
fix_ownership

printf '[4/10] Build base genesis on node1 and add all genesis accounts\n'
NODE1="$CHAINS_DIR/node1"
for i in $(seq 1 "$NUM_NODES"); do
  addr=$(run_in_node "$CHAINS_DIR/node$i" "simd keys show validator -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')
  run_in_node "$NODE1" "simd genesis add-genesis-account ${addr} ${VALIDATOR_TOKENS} --home /root/.simapp >/dev/null 2>&1 || true"
done
USER1_ADDR=$(run_in_node "$NODE1" "simd keys show user1 -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')
run_in_node "$NODE1" "simd genesis add-genesis-account ${USER1_ADDR} ${USER_TOKENS} --home /root/.simapp >/dev/null 2>&1 || true"
fix_ownership

echo "[5/10] Copy shared genesis from node1 to all nodes"
fix_ownership
for i in $(seq 2 "$NUM_NODES"); do
  cp "$NODE1/config/genesis.json" "$CHAINS_DIR/node$i/config/genesis.json"
done

printf '[6/10] Generate gentx on every node\n'
fix_ownership
rm -rf "$NODE1/config/gentx"
mkdir -p "$NODE1/config/gentx"

for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  run_in_node "$node_dir" "rm -rf /root/.simapp/config/gentx && mkdir -p /root/.simapp/config/gentx && simd genesis gentx validator ${STAKE_TOKENS} --chain-id ${CHAIN_ID} --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp >/dev/null"
done

fix_ownership

for i in $(seq 2 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  cp "$node_dir/config/gentx/"*.json "$NODE1/config/gentx/"
done

printf '[7/10] Collect gentxs on node1 and distribute final genesis\n'
run_in_node "$NODE1" "simd genesis collect-gentxs --home /root/.simapp >/dev/null"
fix_ownership
for i in $(seq 2 "$NUM_NODES"); do
  cp "$NODE1/config/genesis.json" "$CHAINS_DIR/node$i/config/genesis.json"
done

echo "[7.5/10] Apply Osmosis changelog-based consensus-related settings"
fix_ownership
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  genesis="$node_dir/config/genesis.json"

  tmp="$(mktemp)"
  jq '
    .consensus_params.block.max_bytes = "5000000"
    | .consensus_params.block.max_gas = "300000000"
  ' "$genesis" > "$tmp"
  mv "$tmp" "$genesis"
done

printf '[8/10] Compute persistent peers and node-specific settings\n'
peer_list=""
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  node_id=$(run_in_node "$node_dir" "simd tendermint show-node-id --home /root/.simapp" | tr -d '\r')
  if [[ -n "$peer_list" ]]; then
    peer_list+=","
  fi
  peer_list+="${node_id}@node${i}:26656"
done
fix_ownership

for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  config="$node_dir/config/config.toml"
  app="$node_dir/config/app.toml"

  sed -i 's#^laddr = "tcp://127.0.0.1:26657"#laddr = "tcp://0.0.0.0:26657"#' "$config"
  sed -i 's#^pprof_laddr = "localhost:6060"#pprof_laddr = "0.0.0.0:6060"#' "$config" || true
  sed -i 's#^cors_allowed_origins = \[\]#cors_allowed_origins = ["*"]#' "$config"
  sed -i 's#^addr_book_strict = true#addr_book_strict = false#' "$config" || true
  sed -i "s#^moniker = .*#moniker = \"${MONIKER_PREFIX}-${i}\"#" "$config"
  sed -i "s#^persistent_peers = .*#persistent_peers = \"${peer_list}\"#" "$config"
  sed -i 's#^allow_duplicate_ip = false#allow_duplicate_ip = true#' "$config" || true
  sed -i 's#^timeout_commit = .*#timeout_commit = "500ms"#' "$config" || true
  sed -i 's#^timeout_propose = .*#timeout_propose = "1.8s"#' "$config" || true
  sed -i 's#^index_all_keys = false#index_all_keys = true#' "$config" || true

  sed -i 's#^minimum-gas-prices = .*#minimum-gas-prices = "0.03uosmo"#' "$app"
  sed -i '0,/^enable = false/s//enable = true/' "$app" || true
  sed -i 's#^address = "tcp://localhost:1317"#address = "tcp://0.0.0.0:1317"#' "$app" || true
  sed -i 's#^address = "localhost:9090"#address = "0.0.0.0:9090"#' "$app" || true
  sed -i 's#^enable = false#enable = true#' "$app" || true
done

printf '[9/10] Write node address summary\n'
summary="$ROOT_DIR/node-addresses.csv"
echo 'node,validator_addr,node_id,rpc_port,api_port,grpc_port,p2p_port' > "$summary"
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  val_addr=$(run_in_node "$node_dir" "simd keys show validator -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')
  node_id=$(run_in_node "$node_dir" "simd tendermint show-node-id --home /root/.simapp" | tr -d '\r')
  rpc=$((37656 + i))
  api=$((13716 + i))
  grpc=$((9489 + i))
  p2p=$((36655 + i))
  echo "node${i},${val_addr},${node_id},${rpc},${api},${grpc},${p2p}" >> "$summary"
done
fix_ownership

printf '[10/10] Done\n'
printf 'Initialized %s-node chain data under: %s\n' "$NUM_NODES" "$CHAINS_DIR"
printf 'Next: ./scripts/start-30node.sh\n'