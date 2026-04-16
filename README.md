# chain-0 10-node local consensus test environment

## 1. 概要

本リポジトリは、Cosmos SDK / CometBFT ベースの単一チェーン `chain-0` を  
**10ノード・10 validator** 構成で Docker 上に構築し、  
ローカル環境で以下を観測するための実験環境である。

- コンセンサス挙動
- Tx 処理
- gossip protocol
- block time
- consensus-related 設定変更時の安定性

本環境は、単一ノード版および多ノード試行版を整理したものであり、  
最終的に **10 ノード構成で block が継続進行し、Tx 送信および gossip 確認まで可能** な構成としてまとめている。

---

## 2. 目的

本環境の主な目的は以下である。

- 10 validator 構成でのローカルコンセンサス実験
- proposal / commit の継続観測
- peer 接続と gossip protocol の確認
- 単発 Tx および burst Tx の処理確認
- block time の観測
- consensus-related 設定変更時の安定性比較

---

## 3. 構成

### 3.1 チェーン

- chain ID: `chain-0`

### 3.2 ノード数

- 10 nodes
- 10 validators

### 3.3 コンテナ名

- `chain-0-node-1`
- `chain-0-node-2`
- ...
- `chain-0-node-10`

### 3.4 基本ポート割当

各ノードのホストポートは以下の規則で割り当てる。

- RPC: `37656 + node番号`
- REST API: `13716 + node番号`
- gRPC: `9489 + node番号`
- P2P: `36655 + node番号`

例:

#### node1
- RPC: `37657`
- API: `13717`
- gRPC: `9490`
- P2P: `36656`

#### node10
- RPC: `37666`
- API: `13726`
- gRPC: `9499`
- P2P: `36665`

---

## 4. ディレクトリ構成

```text
chain-0-10node-package/
├─ README.md
├─ docker-compose.yml
├─ .gitignore
├─ chains/
│  ├─ node1/
│  ├─ node2/
│  ├─ ...
│  └─ node10/
├─ node-addresses.csv
└─ scripts/
   ├─ init-10node.sh
   ├─ start-10node.sh
   ├─ stop-10node.sh
   ├─ query-status-all.sh
   ├─ query-validators.sh
   ├─ query-balances.sh
   ├─ send-bank-tx.sh
   ├─ wait-tx.sh
   ├─ burst-bank-load.sh
   ├─ audit-tx-inclusion.sh
   ├─ summarize-load-result.sh
   ├─ export-block-times.sh
   └─ gen-docker-compose-10.sh
````

---

## 5. 事前要件

* Docker
* Docker Compose
* `jq`
* `curl`
* `python3`

確認例:

```bash
sudo docker --version
sudo docker compose version
jq --version
curl --version
python3 --version
```

---

## 6. 初期化

### 6.1 実行権限付与

```bash
chmod +x scripts/*.sh
```

### 6.2 初期化

```bash
NUM_NODES=10 ./scripts/init-10node.sh
```

このスクリプトでは以下を行う。

* 10ノード分の `simd init`
* 各ノードの validator key 作成
* node1 の `user1` 作成
* genesis account 追加
* gentx 生成
* gentx 集約
* final genesis 配布
* peer 設定
* `config.toml` / `app.toml` 調整
* `node-addresses.csv` 出力

---

## 7. Docker Compose 生成

```bash
NUM_NODES=10 ./scripts/gen-docker-compose-10.sh
```

確認:

```bash
grep -E '^  node[0-9]+:' docker-compose.yml | wc -l
```

期待値:

```text
10
```

---

## 8. 起動・停止

### 8.1 起動

```bash
./scripts/start-10node.sh
```

### 8.2 停止

```bash
./scripts/stop-10node.sh
```

---

## 9. 起動確認

### 9.1 全ノード状態確認

```bash
NUM_NODES=10 ./scripts/query-status-all.sh
```

期待する状態:

* 全ノードで `network = chain-0`
* `latest_block_height > 0`
* 全ノードで同程度の高さ
* `catching_up = false`

### 9.2 コンテナ数確認

```bash
sudo docker ps --format '{{.Names}}' | grep '^chain-0-node-' | wc -l
```

期待値:

```text
10
```

---

## 10. validator / 残高確認

### 10.1 validator 一覧

```bash
./scripts/query-validators.sh
```

### 10.2 残高確認

```bash
./scripts/query-balances.sh
```

---

## 11. 単発 Tx 実験

### 11.1 実行

```bash
./scripts/send-bank-tx.sh 1stake
```

### 11.2 期待結果

* `code = 0`
* `waited_for_inclusion = true`
* `txhash` が返る

### 11.3 送信内容

既定では以下で `bank send` を行う。

* 送信元: `validator`
* 送信先: `user1`

---

## 12. burst Tx 実験

### 12.1 実行例

```bash
./scripts/burst-bank-load.sh 10 1stake burst-10 0.3
./scripts/audit-tx-inclusion.sh burst-10/summary.csv burst-10/audit.csv
./scripts/summarize-load-result.sh burst-10/audit.csv
```

### 12.2 出力

* `burst-10/summary.csv`
* `burst-10/audit.csv`

### 12.3 注意

以前は sequence 競合により、同一 `txhash` の重複や `submit_code=19` が出ていたため、
送信スクリプト側で **Tx inclusion を待つ実装** に修正している。

---

## 13. block time 観測

```bash
./scripts/export-block-times.sh 200 block-times.csv
```

取得対象:

* height
* block timestamp
* 前ブロックとの差分秒数

---

## 14. gossip protocol の確認

### 14.1 接続数確認

```bash
curl -s http://localhost:37657/net_info | jq '.result.n_peers'
```

10ノード環境では、node1 が他の 9 ノードと接続していれば `"9"` が返る。

### 14.2 peer 一覧

```bash
curl -s http://localhost:37657/net_info | jq '.result.peers[] | {id: .node_info.id, moniker: .node_info.moniker}'
```

### 14.3 接続エッジ一覧出力

```bash
for i in $(seq 1 10); do
  RPC=$((37656 + i))
  curl -s "http://localhost:${RPC}/net_info" \
    | jq -r --arg src "node$i" '.result.peers[] | "\($src),\(.node_info.moniker)"'
done | sort -u > gossip-edges.csv
```

### 14.4 解釈

実験時点では、各ノードが他の 9 ノードと接続しており、
**ほぼ完全グラフ** として gossip network が形成されていた。

---

## 15. consensus / gossip の運用観測

node1 のログ例:

```bash
sudo docker logs --tail 150 chain-0-node-1
```

確認すべきログ:

* `received proposal`
* `received complete proposal`
* `finalizing commit of block`
* `indexed block events`

これらが連続して出ていれば、

* proposal gossip
* vote 集約
* commit

が正常に回っていると判断できる。

---

## 16. Tx gossip の確認

単発 Tx 送信後、node1 のログで

* `num_txs=1`

が出ることを確認する。

```bash
./scripts/send-bank-tx.sh 1stake
sudo docker logs --tail 150 chain-0-node-1
```

これにより、

* Tx が mempool に入った
* consensus を通って commit された

ことを確認できる。

必要に応じて node5 / node10 でもログを確認し、
送信ノード以外でも proposal / commit が継続していることを確認する。

---

## 17. consensus-related 設定

本環境では、Osmosis の変更履歴を参考にした consensus-related 設定を試験的に反映している。

### 17.1 genesis の block params

* `max_bytes = "5000000"`
* `max_gas = "300000000"`

### 17.2 `config.toml`

* `timeout_propose = "1.8s"`
* `timeout_commit = "500ms"`

### 17.3 `app.toml`

* `minimum-gas-prices = "0.03stake"`

### 17.4 注意

`minimum-gas-prices` と送信スクリプトの fee / gas-prices が不整合だと
`insufficient fee` で Tx が reject される。
そのため、送信側も `stake` ベースで揃えること。

---

## 18. 10ノード構成での到達点

本環境では以下を確認できている。

* 10ノード / 10 validator 構成で block が継続進行
* gossip network が形成されている
* proposal gossip / commit が継続している
* 単発 Tx が受理・commit される
* `num_txs=1` のブロックを確認できる
* burst 実験および block time 観測が可能

---

## 19. 30ノード構成との比較メモ

30ノード構成では、

* peer 設定異常
* その後の timeout の厳しさ

により、height 1 commit が安定しなかった。

一方、10ノード構成では同系統の consensus-related 設定でも安定して block が進行した。

したがって、ローカル単機での多ノード実験としては、
**10ノード構成が現実的な運用条件** である。

---

## 20. よく使うコマンドまとめ

### 起動

```bash
./scripts/start-10node.sh
```

### 停止

```bash
./scripts/stop-10node.sh
```

### 状態確認

```bash
NUM_NODES=10 ./scripts/query-status-all.sh
```

### validator

```bash
./scripts/query-validators.sh
```

### 残高

```bash
./scripts/query-balances.sh
```

### 単発 Tx

```bash
./scripts/send-bank-tx.sh 1stake
```

### burst

```bash
./scripts/burst-bank-load.sh 10 1stake burst-10 0.3
./scripts/audit-tx-inclusion.sh burst-10/summary.csv burst-10/audit.csv
./scripts/summarize-load-result.sh burst-10/audit.csv
```

### burstV1
100 wallet:

./scripts/burst-bank-load.sh 100 1stake burst-100-wallets 0.0
./scripts/audit-tx-inclusion.sh burst-100-wallets/summary.csv burst-100-wallets/audit.csv
./scripts/summarize-load-result.sh burst-100-wallets/audit.csv

200 wallet:

./scripts/burst-bank-load.sh 200 1stake burst-200-wallets 0.0
./scripts/audit-tx-inclusion.sh burst-200-wallets/summary.csv burst-200-wallets/audit.csv
./scripts/summarize-load-result.sh burst-200-wallets/audit.csv

300 wallet:

./scripts/burst-bank-load.sh 300 1stake burst-300-wallets 0.0
./scripts/audit-tx-inclusion.sh burst-300-wallets/summary.csv burst-300-wallets/audit.csv
./scripts/summarize-load-result.sh burst-300-wallets/audit.csv

./scripts/burst-bank-load.sh 500 1stake burst-500-wallets 0.0
./scripts/audit-tx-inclusion.sh burst-500-wallets/summary.csv burst-500-wallets/audit.csv
./scripts/summarize-load-result.sh burst-500-wallets/audit.csv

### block time

```bash
./scripts/export-block-times.sh 200 block-times.csv
```

### gossip 接続一覧

```bash
for i in $(seq 1 10); do
  RPC=$((37656 + i))
  curl -s "http://localhost:${RPC}/net_info" \
    | jq -r --arg src "node$i" '.result.peers[] | "\($src),\(.node_info.moniker)"'
done | sort -u > gossip-edges.csv
```

---

## 21. Git 管理時の注意

`chains/` 配下や実験ログは巨大になりやすいため、通常は Git 管理対象から除外する。

例:

```gitignore
chains/
node-addresses.csv
burst-*/
*.csv
*.json
gossip-edges.csv
gossip.dot
gossip.png
block-times*.csv
```

## 22.最短コマンド

### 10ノード版の最短実行手順
```bash
chmod +x scripts/*.sh

./scripts/stop-10node.sh || true
rm -rf chains node-addresses.csv
mkdir -p chains

NUM_NODES=10 ./scripts/init-10node.sh
NUM_NODES=10 ./scripts/gen-docker-compose-10.sh
./scripts/start-10node.sh
sleep 10

NUM_NODES=10 ./scripts/query-status-all.sh
./scripts/query-balances.sh

./scripts/send-bank-tx.sh 1stake
sudo docker logs --tail 150 chain-0-node-1

./scripts/burst-bank-load.sh 10 1stake burst-10 0.3
./scripts/audit-tx-inclusion.sh burst-10/summary.csv burst-10/audit.csv
./scripts/summarize-load-result.sh burst-10/audit.csv

./scripts/export-block-times.sh 200 block-times.csv
```

37657 = node1
37661 = node5
37666 = node10
に確定TXを問い合わせは以下のコマンド
```bash
./scripts/send-bank-tx.sh 1stake
TXHASH=""

for port in 37657 37661 37666; do
  echo "=== RPC $port ==="
  curl -s "http://localhost:${port}/tx?hash=0x${TXHASH}" | jq '.result.hash, .result.height, .result.tx_result.code'
done
```

### 終了するとき
```bash
./scripts/stop-10node.sh
```
ディレクトリの compose 管理下コンテナも一度落とす（再新規作成）
```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep '^chain-0-node-' || true
sudo docker rm -f $(sudo docker ps -aq --filter "name=^/chain-0-node-") 2>/dev/null || true
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep '^chain-0-node-' || true
```
---

Config.toml
**あなたの 10 ノード環境で `init-10node.sh` が実際に触っている `config.toml` 項目だけ**を抜き出して、**公式の初期値 → 現在値**の対応にする。

前提:

* **初期値** = CometBFT の `config.toml` 公式ドキュメントに載っている default 値
* **現在値** = あなたの `init-10node.sh` で 10 ノード環境向けに上書きしている値

CometBFT 公式 docs では、`config.toml` は `cometbft init` により **default 値入りで生成**されると説明されています。 ([docs.cometbft.com][1])

---

## 対応表

### 1. RPC 待受アドレス

* **項目**: `laddr`
* **初期値**: `tcp://127.0.0.1:26657` ([docs.cometbft.com][1])
* **現在値**: `tcp://0.0.0.0:26657`

意味:

* 初期状態では localhost のみ
* 今は外部からも RPC にアクセスできるように全インターフェース待受に変更

---

### 2. pprof 待受アドレス

* **項目**: `pprof_laddr`
* **初期値**: `""`（無効） ([docs.cometbft.com][1])
* **現在値**: `0.0.0.0:6060`

意味:

* 初期状態では profiling 無効
* 今は profiling を外部から見られる形に変更

---

### 3. CORS 許可オリジン

* **項目**: `cors_allowed_origins`
* **初期値**: `[]` ([docs.cometbft.com][1])
* **現在値**: `["*"]`

意味:

* 初期状態では CORS 無効
* 今は任意 origin を許可

---

### 4. ノード名

* **項目**: `moniker`
* **初期値**: `"my.host.name"`（docs の default 例） ([docs.cometbft.com][1])
* **現在値**: `chain-0-node-<n>`

意味:

* 初期状態では一般的なホスト名
* 今は各ノードを識別しやすい名前に変更

---

### 5. 永続 peer

* **項目**: `persistent_peers`
* **初期値**: `""` ([docs.cometbft.com][1])
* **現在値**: `node1`〜`node10` の node ID を全列挙した接続一覧

意味:

* 初期状態では永続 peer なし
* 今は 10 ノード全体で固定接続ネットワークを形成

補足:

* CometBFT では `persistent_peers` は通常の outbound 上限に数えない扱いです。 ([docs.cometbft.com][1])

---

### 6. アドレス帳の厳格性

* **項目**: `addr_book_strict`
* **初期値**: `true` ([docs.cometbft.com][1])
* **現在値**: `false`

意味:

* 初期状態では private network のアドレスを厳しく扱う
* 今はローカル実験用に private network アドレスを許可

---

### 7. 同一 IP の重複許可

* **項目**: `allow_duplicate_ip`
* **初期値**: `false` ([docs.cometbft.com][1])
* **現在値**: `true`

意味:

* 初期状態では同一 IP からの複数接続を防ぐ
* 今は Docker ローカル実験のため重複 IP 接続を許可

---

### 8. PEX（peer exchange）

* **項目**: `pex`
* **初期値**: `true` ([docs.cometbft.com][1])
* **現在値**: `false`

意味:

* 初期状態では peer discovery 有効
* 今は `persistent_peers` 固定運用にして、余計な peer 探索を抑制

---

### 9. `timeout_propose`

* **項目**: `timeout_propose`
* **初期値**: `"3s"` ([docs.cometbft.com][1])
* **現在値**: `"1.8s"`

意味:

* 初期状態より短縮して、Osmosis 由来設定寄りに詰めている

---

### 10. `timeout_commit`

* **項目**: `timeout_commit`
* **初期値**: `"1s"` ([docs.cometbft.com][1])
* **現在値**: `"500ms"`

意味:

* 初期状態より短縮して、commit 間隔を攻めている

---

## 触っている項目だけを一行でまとめると

* `laddr`: `127.0.0.1:26657` → `0.0.0.0:26657`
* `pprof_laddr`: `""` → `0.0.0.0:6060`
* `cors_allowed_origins`: `[]` → `["*"]`
* `moniker`: `"my.host.name"` → `chain-0-node-N`
* `persistent_peers`: `""` → 10ノード全列挙
* `addr_book_strict`: `true` → `false`
* `allow_duplicate_ip`: `false` → `true`
* `pex`: `true` → `false`
* `timeout_propose`: `"3s"` → `"1.8s"`
* `timeout_commit`: `"1s"` → `"500ms"`

---

## 補足

あなたのスクリプトには `index_all_keys = false -> true` という置換もありましたが、**CometBFT の公式 `config.toml` リファレンスではそのキーを確認できませんでした**。
なので、上の対応表では **公式 default を確認できた項目だけ**に絞っています。

必要なら次に、
**この対応表を README にそのまま貼れる節（「初期値と現在値の差分」）として整形した版**を作れます。

[1]: https://docs.cometbft.com/main/references/config/config.toml "CometBFT Documentation - Config.toml - main"


## `config.toml` 初期値 → 現在値 対応表（10ノード環境）

| 項目 | 初期値 | 現在値 | 役割 / 変更理由 |
|---|---|---|---|
| `laddr` | `tcp://127.0.0.1:26657` | `tcp://0.0.0.0:26657` | RPC を localhost 限定から全インターフェース待受へ変更 |
| `pprof_laddr` | `""` | `0.0.0.0:6060` | profiling を有効化し、外部から確認可能に変更 |
| `cors_allowed_origins` | `[]` | `["*"]` | CORS を全許可に変更 |
| `moniker` | `my.host.name` | `chain-0-node-N` | ノード識別のため明示的な名前に変更 |
| `persistent_peers` | `""` | `node1`〜`node10` の全 peer 一覧 | 10ノード間で固定接続ネットワークを形成 |
| `addr_book_strict` | `true` | `false` | ローカル実験環境で private network アドレスを許可 |
| `allow_duplicate_ip` | `false` | `true` | Docker ローカル環境で同一IP上の複数ノード接続を許可 |
| `pex` | `true` | `false` | peer exchange を止め、固定 peer 構成に限定 |
| `timeout_propose` | `3s` | `1.8s` | proposal timeout を短縮し、Osmosis寄り設定へ調整 |
| `timeout_commit` | `1s` | `500ms` | commit timeout を短縮し、Osmosis寄り設定へ調整 |

### 補足
- `persistent_peers` は 10ノード環境では各ノードを相互接続するために全列挙している。
- `pex = false` のため、peer discovery に依存せず、固定接続で動作させている。
- `timeout_propose` と `timeout_commit` は、初期値より短く設定しているため、ローカル多ノード環境での安定性確認が重要になる。
- 上記は **`init-10node.sh` で実際に書き換えている `config.toml` 項目のみ** を対象としている。

## persistent_peersについて
**`persistent_peers` を全列挙しない**ようにすれば、10 ノードを相互完全接続にしない構成にできます。CometBFT では、`persistent_peers` は常時接続したい相手の一覧で、`pex` は peer discovery を有効化する設定です。`max_num_outbound_peers` と `max_num_inbound_peers` で通常の接続上限も持てます。([docs.cometbft.com](https://docs.cometbft.com/main/references/config/config.toml))

今は各ノードで `persistent_peers` に **node1〜node10 の全ノード**を入れているので、ほぼ完全接続になります。
これをやめて、各ノードが **2〜3 ノードだけ**を持つ形にします。

### 例1: リング接続

各ノードが「前後 2 ノード」だけを persistent peer にします。

* node1 → node2, node10
* node2 → node1, node3
* ...
* node10 → node9, node1

この場合、完全接続ではなく **輪っか状の gossip network** になります。

### 例2: スター接続

node1 をハブにして、

* node2〜10 → node1
* node1 → node2,3,4 など一部だけ

のようにすると、中心ノード依存の構造になります。

## どこを変えるか

`init-10node.sh` のこの部分です。

```bash id="wwh7aw"
peer_list=""
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  node_id=$(run_in_node "$node_dir" "simd tendermint show-node-id --home /root/.simapp" | tr -d '\r')
  if [[ -n "$peer_list" ]]; then
    peer_list+=","
  fi
  peer_list+="${node_id}@node${i}:26656"
done
```


この作り方だと **全ノード共通の peer_list** ができるので、完全接続になります。
**ノードごとに別の `persistent_peers`** を作る方式となる．

---

<!-- ## リング接続にする差し替え例

`[8/10] Compute persistent peers and node-specific settings` の前あたりで、まず node ID を配列化します。

```bash id="5x3jiq"
declare -a NODE_IDS
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  NODE_IDS[$i]=$(run_in_node "$node_dir" "simd tendermint show-node-id --home /root/.simapp" | tr -d '\r')
done
```

その後、各ノードごとに前後 1 ノードだけを peer にします。

```bash id="m26nzu"
for i in $(seq 1 "$NUM_NODES"); do
  node_dir="$CHAINS_DIR/node$i"
  config="$node_dir/config/config.toml"

  prev=$((i-1))
  next=$((i+1))
  if [[ $prev -lt 1 ]]; then prev=$NUM_NODES; fi
  if [[ $next -gt $NUM_NODES ]]; then next=1; fi

  peer_list="${NODE_IDS[$prev]}@node${prev}:26656,${NODE_IDS[$next]}@node${next}:26656"

  sed -i "s#^persistent_peers = .*#persistent_peers = \"$peer_list\"#" "$config"
done
```

これで **各ノードは 2 本だけ** persistent peer を持つようになります。

---

## あわせて設定した方がよい項目

完全接続を避けたいなら、これも重要です。

```toml id="8c4hbp"
pex = false
max_num_outbound_peers = 2
max_num_inbound_peers = 10
```

* `pex = false`
  追加 peer を勝手に探しに行かない
* `max_num_outbound_peers = 2`
  自分から張る接続を 2 本に制限
* `max_num_inbound_peers`
  受ける側の上限

ただし、`persistent_peers` は通常の outbound 上限カウントとは別扱いなので、**本当に構造を制限したいなら `persistent_peers` 自体を少数にすることが本体**です。([docs.cometbft.com](https://docs.cometbft.com/main/references/config/config.toml))

---

## 実験的におすすめの構造

10 ノードなら、まずはこれが分かりやすいです。

### リング型

* 各ノードが 2 接続
* gossip がどのくらい回るか見やすい

### 2-hop リング型

* 各ノードが 4 接続
* 例: 前後1つずつ + 2つ先ずつ

これは完全接続より軽く、でもリングより安定しやすいです。

---

## 結論

**相互接続させないように設定することは可能**です。
やることは次の 2 つです。

1. `persistent_peers` を全列挙しない
2. 必要なら `pex = false` と `max_num_outbound_peers` を併用する

必要なら次に、**あなたの `init-10node.sh` を「リング接続版」にした完成差し替えコード**をそのまま書きます。 -->


## 22. 今後の拡張候補

* 1ノード / 8ノード / 10ノード比較
* timeout パラメータ探索
* block time 分布比較
* burst 負荷拡大
* Tx gossip の多点観測
* Graphviz による gossip 接続図可視化
* 30ノード構成再挑戦

