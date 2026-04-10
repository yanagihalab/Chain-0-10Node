# chain-0 10-node local consensus test environment

## 1. 概要

本リポジトリは、Cosmos SDK / CometBFT ベースの
単一チェーン `chain-0` を
**10ノード・10 validator** 構成で
Docker 上に構築し、
ローカル環境でコンセンサス挙動、
Tx 処理、
gossip protocol、
block time などを観測するための
実験環境である。

本環境は、もともとの単一ノード版および
多ノード試行版をもとに整理したものであり、
最終的に **10 ノード構成で安定して block が進行し、
Tx 送信および gossip の確認まで行える**
構成としてまとめている。

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

- node1
  - RPC: `37657`
  - API: `13717`
  - gRPC: `9490`
  - P2P: `36656`

- node10
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

または、10ノード対応済みの compose を直接利用してもよい。

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

既定では

* 送信元: `validator`
* 送信先: `user1`

で `bank send` を行う。

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

以前は sequence 競合により
同一 `txhash` の重複や
`submit_code=19` が出ていたため、
送信スクリプト側で
Tx inclusion を待つ実装へ修正している。

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

10ノード環境では、node1 が他の 9 ノードと接続していれば
`"9"` が返る。

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

10ノード環境では、実験時点で
各ノードが他の 9 ノードと接続しており、
**ほぼ完全グラフ**
として gossip network が形成されていた。

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

単発 Tx を送信後、node1 ログで

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

本環境では、Osmosis の変更履歴を参考にした
consensus-related 設定を試験的に反映している。

### 17.1 genesis の block params

* `max_bytes = "5000000"`
* `max_gas = "300000000"`

### 17.2 `config.toml`

* `timeout_propose = "1.8s"`
* `timeout_commit = "500ms"`

### 17.3 `app.toml`

* `minimum-gas-prices = "0.03stake"`

### 17.4 注意

`minimum-gas-prices` と送信スクリプトの fee / gas-prices が不整合だと、
`insufficient fee` で Tx が reject される。
そのため、送信側も `stake` ベースで揃えること。

---

## 18. 10ノード構成での到達点

本環境では、以下を確認できている。

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

により height 1 commit が安定しなかった。

一方、10ノード構成では
同系統の consensus-related 設定でも
安定して block が進行した。

したがって、
ローカル単機での多ノード実験としては、
**10ノード構成が現実的な運用条件**
である。

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

`chains/` 配下や実験ログは巨大になりやすいため、
通常は Git 管理対象から除外する。

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

## 22. 今後の拡張候補

* 1ノード / 8ノード / 10ノード比較
* timeout パラメータ探索
* block time 分布比較
* burst 負荷拡大
* Tx gossip の多点観測
* Graphviz による gossip 接続図可視化
* 30ノード構成再挑戦


