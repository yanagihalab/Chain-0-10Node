
# chain-0 10-node local consensus test environment

## 1. 概要

本リポジトリは、Cosmos SDK / CometBFT ベースの単一チェーン `chain-0` を  
**10 ノード・10 validator** 構成で Docker 上に構築し、  
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
   ├─ burst-bank-load-reuse.sh
   ├─ burst-bank-load-saturating.sh
   ├─ audit-tx-inclusion.sh
   ├─ summarize-load-result.sh
   ├─ export-block-times.sh
   ├─ export-tx-raw-timestamps.sh
   ├─ detect-unparsed-timestamps.sh
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

* 10 ノード分の `simd init`
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

### 12.1 基本実行例

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

### 12.4 100 wallet 実験

```bash
./scripts/burst-bank-load.sh 100 1stake burst-100-wallets 0.0
./scripts/audit-tx-inclusion.sh burst-100-wallets/summary.csv burst-100-wallets/audit.csv
./scripts/summarize-load-result.sh burst-100-wallets/audit.csv
```

### 12.5 10000 件飽和送信実験（3000 wallet, p500）

```bash
rm -rf burst-10000-wallets-sat-p500

./scripts/burst-bank-load-saturating.sh 10000 1stake burst-10000-wallets-sat-p500 3000 500 wallet user1 0.00
./scripts/audit-tx-inclusion.sh burst-10000-wallets-sat-p500/summary.csv burst-10000-wallets-sat-p500/audit.csv
./scripts/summarize-load-result.sh burst-10000-wallets-sat-p500/audit.csv
```

### 12.6 10000 件再利用実験（3000 wallet, p300）

```bash
rm -rf burst-10000-wallets-p500

./scripts/burst-bank-load-reuse.sh 10000 1stake burst-10000-wallets-p500 3000 300 0.0 wallet user1 0.0
./scripts/audit-tx-inclusion.sh burst-10000-wallets-p500/summary.csv burst-10000-wallets-p500/audit.csv
./scripts/summarize-load-result.sh burst-10000-wallets-p500/audit.csv
```

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

10 ノード環境では、node1 が他の 9 ノードと接続していれば `"9"` が返る。

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

* 10 ノード / 10 validator 構成で block が継続進行
* gossip network が形成されている
* proposal gossip / commit が継続している
* 単発 Tx が受理・commit される
* `num_txs=1` のブロックを確認できる
* burst 実験および block time 観測が可能

---

## 19. 30ノード構成との比較メモ

30 ノード構成では、

* peer 設定異常
* その後の timeout の厳しさ

により、height 1 commit が安定しなかった。

一方、10 ノード構成では同系統の consensus-related 設定でも安定して block が進行した。

したがって、ローカル単機での多ノード実験としては、
**10 ノード構成が現実的な運用条件**である。

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

---

## 22. 最短コマンド

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

### node1 / node5 / node10 への確定 Tx 問い合わせ

* `37657` = node1
* `37661` = node5
* `37666` = node10

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

### compose 管理下コンテナを完全に落として再新規作成したい場合

```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep '^chain-0-node-' || true
sudo docker rm -f $(sudo docker ps -aq --filter "name=^/chain-0-node-") 2>/dev/null || true
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep '^chain-0-node-' || true
```

---

## 23. `config.toml` 初期値 → 現在値 対応表（10ノード環境）

前提:

* **初期値** = CometBFT の `config.toml` 公式ドキュメントに載っている default 値
* **現在値** = `init-10node.sh` で 10 ノード環境向けに上書きしている値

| 項目                     | 初期値                     | 現在値                         | 役割 / 変更理由                             |
| ---------------------- | ----------------------- | --------------------------- | ------------------------------------- |
| `laddr`                | `tcp://127.0.0.1:26657` | `tcp://0.0.0.0:26657`       | RPC を localhost 限定から全インターフェース待受へ変更    |
| `pprof_laddr`          | `""`                    | `0.0.0.0:6060`              | profiling を有効化し、外部から確認可能に変更           |
| `cors_allowed_origins` | `[]`                    | `["*"]`                     | CORS を全許可に変更                          |
| `moniker`              | `my.host.name`          | `chain-0-node-N`            | ノード識別のため明示的な名前に変更                     |
| `persistent_peers`     | `""`                    | `node1`〜`node10` の全 peer 一覧 | 10 ノード間で固定接続ネットワークを形成                 |
| `addr_book_strict`     | `true`                  | `false`                     | ローカル実験環境で private network アドレスを許可     |
| `allow_duplicate_ip`   | `false`                 | `true`                      | Docker ローカル環境で同一 IP 上の複数ノード接続を許可      |
| `pex`                  | `true`                  | `false`                     | peer exchange を止め、固定 peer 構成に限定       |
| `timeout_propose`      | `3s`                    | `1.8s`                      | proposal timeout を短縮し、Osmosis 寄り設定へ調整 |
| `timeout_commit`       | `1s`                    | `500ms`                     | commit timeout を短縮し、Osmosis 寄り設定へ調整   |

### 補足

* `persistent_peers` は 10 ノード環境では各ノードを相互接続するために全列挙している。
* `pex = false` のため、peer discovery に依存せず、固定接続で動作させている。
* `timeout_propose` と `timeout_commit` は、初期値より短く設定しているため、ローカル多ノード環境での安定性確認が重要になる。
* 上記は **`init-10node.sh` で実際に書き換えている `config.toml` 項目のみ** を対象としている。

---

## 24. `persistent_peers` について

`persistent_peers` を全列挙しないようにすれば、10 ノードを相互完全接続にしない構成にもできる。
CometBFT では、`persistent_peers` は常時接続したい相手の一覧であり、`pex` は peer discovery を有効化する設定である。
また、`max_num_outbound_peers` と `max_num_inbound_peers` により通常の接続上限を持てる。

現在は各ノードで `persistent_peers` に **node1〜node10 の全ノード**を入れているため、ほぼ完全接続となっている。
これをやめて、各ノードごとに別の `persistent_peers` を設定すれば、リング接続やスター接続なども実現できる。

現在の生成ロジック:

```bash
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

この作り方だと **全ノード共通の peer_list** ができるため、完全接続に近い構成となる。
ノードごとに別の `persistent_peers` を作る方式に変更すれば、接続構造を意図的に制御できる。

---

## 25. 1000 wallet 再利用版の大規模 burst 実験

本環境では、初期作成 wallet 数を **1000** に抑えたうえで、それらを再利用しながら **合計 10000 件** の Tx を送信する実験を行える。
この実験では、wallet をラウンド分割ではなく、**空いた wallet から順に再利用して送信を継続する飽和送信方式**を用いる。

### 目的

* 初期 wallet 数を抑えた条件での大規模 burst 実験
* wallet 再利用時の安定性確認
* `max_parallel` 制御下での送信継続性確認
* mempool から block への取り込み遅延の観測
* 1000 wallet 再利用時の throughput / latency 傾向確認

### 前提

この実験では、`init-10node.sh` 実行時に **1000 wallet** を作成しておく。

```bash
./scripts/stop-10node.sh || true
rm -rf chains node-addresses.csv
mkdir -p chains

NUM_NODES=10 BURST_WALLET_COUNT=1000 ./scripts/init-10node.sh
NUM_NODES=10 ./scripts/gen-docker-compose-10.sh
./scripts/start-10node.sh
```

### 実行コマンド

```bash
rm -rf burst-10000-wallets-sat-p500-w1000

WAIT_TIMEOUT=180 ./scripts/burst-bank-load-saturating.sh 10000 1stake burst-10000-wallets-sat-p500-w1000 1000 500 wallet user1 0.05
./scripts/audit-tx-inclusion.sh burst-10000-wallets-sat-p500-w1000/summary.csv burst-10000-wallets-sat-p500-w1000/audit.csv
./scripts/summarize-load-result.sh burst-10000-wallets-sat-p500-w1000/audit.csv
```

### 引数の意味

| 位置 |                                    値 | 意味               |
| -- | -----------------------------------: | ---------------- |
| 1  |                              `10000` | 総送信数             |
| 2  |                             `1stake` | 1 回あたり送金額        |
| 3  | `burst-10000-wallets-sat-p500-w1000` | 出力ディレクトリ         |
| 4  |                               `1000` | 利用する wallet 数    |
| 5  |                                `500` | 最大並列数            |
| 6  |                             `wallet` | wallet 名プレフィックス  |
| 7  |                              `user1` | 送信先 key 名        |
| 8  |                               `0.05` | 送信ループの polling 秒 |

### 動作方式

この方式では、`wallet001` ～ `wallet1000` を固定集合として扱い、

* 空いている wallet があれば次の送信に使う
* 送信中の wallet は再利用しない
* 送信完了後に wallet を再び利用可能に戻す
* これを繰り返して合計 10000 件に到達するまで送信を継続する

つまり、**ラウンド単位で待つのではなく、空いた wallet から順に継続投入する飽和送信**である。

### 特徴

* 1000 wallet を再利用しながら 10000 件送信可能
* `max_parallel=500` により、送信側 PC の負荷を抑えつつ高並列を維持
* wallet 数より少ない並列数を使うことで、同一 wallet の競合を避けやすい
* `WAIT_TIMEOUT=180` により、後半の Tx も `query tx` で追跡しやすい

### 出力

* `burst-10000-wallets-sat-p500-w1000/summary.csv`
* `burst-10000-wallets-sat-p500-w1000/audit.csv`
* `burst-10000-wallets-sat-p500-w1000/tx_raw/`

### 補助確認

`tx_raw` に保存された `*-tx.json` から timestamp 傾向を確認できる。

```bash
./scripts/export-tx-raw-timestamps.sh burst-10000-wallets-sat-p500-w1000/tx_raw burst-10000-wallets-sat-p500-w1000/tx_raw_timestamps.csv
./scripts/detect-unparsed-timestamps.sh burst-10000-wallets-sat-p500-w1000/tx_raw_timestamps.csv timestamp
```

### 注意

* 1000 wallet 再利用方式では、3000 wallet 利用時よりも wallet の再利用頻度が高くなる
* そのため、`WAIT_TIMEOUT` は長めに設定する方が安定しやすい
* `max_parallel=500` は比較的攻めた設定であり、必要なら 300 程度に落として比較するとよい
* メモリ増大により処理落ちが発生する可能であり

### 比較用の実行例

```bash
rm -rf burst-10000-wallets-sat-p300-w1000

WAIT_TIMEOUT=180 ./scripts/burst-bank-load-saturating.sh 10000 1stake burst-10000-wallets-sat-p300-w1000 1000 300 wallet user1 0.05
./scripts/audit-tx-inclusion.sh burst-10000-wallets-sat-p300-w1000/summary.csv burst-10000-wallets-sat-p300-w1000/audit.csv
./scripts/summarize-load-result.sh burst-10000-wallets-sat-p300-w1000/audit.csv
```

---

## 26. 今後の拡張候補

* 1ノード / 8ノード / 10ノード比較
* timeout パラメータ探索
* block time 分布比較
* burst 負荷拡大
* Tx gossip の多点観測
* Graphviz による gossip 接続図可視化
* 30ノード構成再挑戦

