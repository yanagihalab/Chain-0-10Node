#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHAINS_DIR="$ROOT_DIR/chains"

IMAGE="${IMAGE:-ghcr.io/cosmos/ibc-go-simd:release-v10.4.x}"

CHAIN_ID="${CHAIN_ID:-chain-0}"

## 以下変更可能な箇所については日本語でコメントをつきしています. 
# keyring backend
# ローカル実験では test のままで問題ありません。
KEYRING_BACKEND="${KEYRING_BACKEND:-test}"

# 基軸 denom
# stake 以外を使いたい場合はここを変更してください。
DENOM="${DENOM:-stake}"

# ノード名の接頭辞
# コンテナ名・moniker の見え方を変えたい場合に変更します。
MONIKER_PREFIX="${MONIKER_PREFIX:-chain-0-node}"

# ノード数
# 10 ノード構成を前提としていますが、別の値に変更可能です。
NUM_NODES="${NUM_NODES:-10}"

# validator 向け初期残高
# 各 validator アドレスに付与する初期残高です。
VALIDATOR_TOKENS="${VALIDATOR_TOKENS:-1000000000${DENOM}}"

# user1 向け初期残高
# 送金先として利用する user1 の初期残高です。
USER_TOKENS="${USER_TOKENS:-1000000000${DENOM}}"

# gentx 用ステーク量
# validator の自己委任量に相当します。
STAKE_TOKENS="${STAKE_TOKENS:-500000000${DENOM}}"

# burst 実験用 wallet 数
# 100, 200, 300 ... と段階的に使いたい場合は、
# 最大想定数をここでまとめて用意してください。
BURST_WALLET_COUNT="${BURST_WALLET_COUNT:-8000}"

# burst 実験用 wallet 名の接頭辞
# wallet001, wallet002, ... のような名前になります。
BURST_WALLET_PREFIX="${BURST_WALLET_PREFIX:-wallet}"

# 各 burst wallet に配る初期残高
# 同時送信回数や fee を増やす場合はここを増額してください。
BURST_WALLET_TOKENS="${BURST_WALLET_TOKENS:-1000000${DENOM}}"

fix_ownership() {
  sudo chown -R "$USER:$USER" "$ROOT_DIR" 2>/dev/null || true
}

run_in_node() {
  local node_dir="$1"
  shift
  sudo docker run --rm -v "$node_dir:/root/.simapp" --entrypoint sh "$IMAGE" -lc "$*"
}

wallet_name_of() {
  local idx="$1"
  printf '%s%03d' "$BURST_WALLET_PREFIX" "$idx"
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

printf '[3/10] Create validator keys on all nodes, user1 on node1, and %s burst wallets on node1\n' "$BURST_WALLET_COUNT"
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  run_in_node "$node_dir" "simd keys add validator --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp >/root/.simapp/validator-key.txt 2>&1"

  if [[ "$i" == "1" ]]; then
    run_in_node "$node_dir" "simd keys add user1 --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp >/root/.simapp/user1-key.txt 2>&1"

    printf '[3/10] Start creating burst wallets on node1: total=%s\n' "$BURST_WALLET_COUNT"
    for w in $(seq 1 "$BURST_WALLET_COUNT"); do
      wallet_name="$(wallet_name_of "$w")"
      run_in_node "$node_dir" "simd keys add ${wallet_name} --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp >/root/.simapp/${wallet_name}-key.txt 2>&1"

      if (( w % 100 == 0 || w == BURST_WALLET_COUNT )); then
        printf '[3/10] Burst wallets created on node1: %s / %s\n' "$w" "$BURST_WALLET_COUNT"
      fi
    done
  fi
done
fix_ownership

printf '[4/10] Build base genesis on node1 and add all genesis accounts\n'
NODE1="$CHAINS_DIR/node1"

printf '[4/10] Add validator genesis accounts: total=%s\n' "$NUM_NODES"
for i in $(seq 1 "$NUM_NODES"); do
  addr="$(run_in_node "$CHAINS_DIR/node$i" "simd keys show validator -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')"
  run_in_node "$NODE1" "simd genesis add-genesis-account ${addr} ${VALIDATOR_TOKENS} --home /root/.simapp >/dev/null 2>&1 || true"

  if (( i % 10 == 0 || i == NUM_NODES )); then
    printf '[4/10] Validator genesis accounts added: %s / %s\n' "$i" "$NUM_NODES"
  fi
done

USER1_ADDR="$(run_in_node "$NODE1" "simd keys show user1 -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')"
run_in_node "$NODE1" "simd genesis add-genesis-account ${USER1_ADDR} ${USER_TOKENS} --home /root/.simapp >/dev/null 2>&1 || true"
printf '[4/10] Added user1 genesis account\n'

printf '[4/10] Add burst wallet genesis accounts: total=%s\n' "$BURST_WALLET_COUNT"
for w in $(seq 1 "$BURST_WALLET_COUNT"); do
  wallet_name="$(wallet_name_of "$w")"
  wallet_addr="$(run_in_node "$NODE1" "simd keys show ${wallet_name} -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')"
  run_in_node "$NODE1" "simd genesis add-genesis-account ${wallet_addr} ${BURST_WALLET_TOKENS} --home /root/.simapp >/dev/null 2>&1 || true"

  if (( w % 100 == 0 || w == BURST_WALLET_COUNT )); then
    printf '[4/10] Burst wallet genesis accounts added: %s / %s\n' "$w" "$BURST_WALLET_COUNT"
  fi
done

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

echo "[7.5/10] Apply consensus-related settings"
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
declare -a NODE_IDS
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  NODE_IDS[$i]="$(run_in_node "$node_dir" "simd tendermint show-node-id --home /root/.simapp" | tr -d '\r')"
done
fix_ownership

for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  config="$node_dir/config/config.toml"
  app="$node_dir/config/app.toml"

  peer_list=""
  for j in $(seq 1 "$NUM_NODES"); do
    if [[ "$i" != "$j" ]]; then
      if [[ -n "$peer_list" ]]; then
        peer_list+=","
      fi
      peer_list+="${NODE_IDS[$j]}@node${j}:26656"
    fi
  done

  # RPC の待受を localhost 限定から全インターフェースへ変更
  sed -i 's#^laddr = "tcp://127.0.0.1:26657"#laddr = "tcp://0.0.0.0:26657"#' "$config"

  # pprof を有効化
  sed -i 's#^pprof_laddr = ""#pprof_laddr = "0.0.0.0:6060"#' "$config" || true

  # CORS を全許可
  sed -i 's#^cors_allowed_origins = \[\]#cors_allowed_origins = ["*"]#' "$config"

  # ローカルネットワーク用に厳格なアドレス制約を緩和
  sed -i 's#^addr_book_strict = true#addr_book_strict = false#' "$config" || true

  # ノード名を分かりやすく設定
  sed -i "s#^moniker = .*#moniker = \"${MONIKER_PREFIX}-${i}\"#" "$config"

  # 全ノードを persistent peers として登録
  # 相互完全接続を避けたい場合はここを調整してください。
  sed -i "s#^persistent_peers = .*#persistent_peers = \"${peer_list}\"#" "$config"

  # Docker ローカル環境では duplicate IP を許可
  sed -i 's#^allow_duplicate_ip = false#allow_duplicate_ip = true#' "$config" || true

  # proposal timeout
  # コンセンサスをさらに攻めたい／緩めたい場合はここを編集します。
  sed -i 's#^timeout_propose = .*#timeout_propose = "1.8s"#' "$config" || true

  # commit timeout
  # block cadence を調整したい場合はここを編集します。
  sed -i 's#^timeout_commit = .*#timeout_commit = "500ms"#' "$config" || true

  # 全キーをインデックス対象にする
  sed -i 's#^index_all_keys = false#index_all_keys = true#' "$config" || true

  # peer exchange を無効化
  # 固定 peer 構成で動かしたいので false
  sed -i 's#^pex = true#pex = false#' "$config" || true

  # 最低 gas price
  # send-bank-tx.sh の gas-prices と整合させてください。
  sed -i 's#^minimum-gas-prices = .*#minimum-gas-prices = "0.03stake"#' "$app"

  sed -i '0,/^enable = false/s//enable = true/' "$app" || true
  sed -i 's#^address = "tcp://localhost:1317"#address = "tcp://0.0.0.0:1317"#' "$app" || true
  sed -i 's#^address = "localhost:9090"#address = "0.0.0.0:9090"#' "$app" || true
  sed -i 's#^enable = false#enable = true#' "$app" || true

  rm -f "$node_dir/config/addrbook.json"
done

printf '[9/10] Write node address summary\n'
summary="$ROOT_DIR/node-addresses.csv"
echo 'node,validator_addr,node_id,rpc_port,api_port,grpc_port,p2p_port' > "$summary"
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  val_addr="$(run_in_node "$node_dir" "simd keys show validator -a --keyring-backend ${KEYRING_BACKEND} --home /root/.simapp" | tr -d '\r')"
  node_id="${NODE_IDS[$i]}"
  rpc=$((37656 + i))
  api=$((13716 + i))
  grpc=$((9489 + i))
  p2p=$((36655 + i))
  echo "node${i},${val_addr},${node_id},${rpc},${api},${grpc},${p2p}" >> "$summary"
done
fix_ownership

printf '[10/10] Done\n'
printf 'Initialized %s-node chain data under: %s\n' "$NUM_NODES" "$CHAINS_DIR"
printf 'Created %s funded burst wallets on node1 keyring\n' "$BURST_WALLET_COUNT"
printf 'Next: ./scripts/start-10node.sh\n'