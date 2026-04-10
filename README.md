# Chain-0 8-Node Tx Processing Local Test Environment

## 1. 概要

本構成は、Cosmos SDK / CometBFT ベースの **8 ノード / 8 validator** 構成の `chain-0` を Docker 上で起動し、分散合意を含む Tx 処理実験を行うためのローカル実験環境です。

単一ノード版と異なり、本版では次を観測できます。

- 8 validator による block 生成
- ノード数増加時の Tx inclusion 挙動
- burst load 時の処理遅延
- block time と validator 集合の影響
- validator 一覧 / voting power / proposer priority

本パッケージでは、**node1 を送信・観測の基準ノード**として使います。

---

## 2. ディレクトリ構成

```text
chain-0-8node-package/
├─ README.md
├─ docker-compose.yml
├─ node-addresses.csv            # init後に生成
├─ chains/
│  ├─ node1/
│  ├─ node2/
│  ├─ node3/
│  ├─ node4/
│  ├─ node5/
│  ├─ node6/
│  ├─ node7/
│  └─ node8/
└─ scripts/
   ├─ init-8node.sh
   ├─ start-8node.sh
   ├─ stop-8node.sh
   ├─ query-status-all.sh
   ├─ query-validators.sh
   ├─ query-balances.sh
   ├─ send-bank-tx.sh
   ├─ wait-tx.sh
   ├─ burst-bank-load.sh
   ├─ audit-tx-inclusion.sh
   ├─ export-block-times.sh
   └─ summarize-load-result.sh
```

---

## 3. ノード名とポート

各ノードは共通 chain-id `chain-0` に属します。

| Node | Container | RPC | API | gRPC | P2P |
|---|---|---:|---:|---:|---:|
| node1 | `chain-0-node-1` | 37657 | 13717 | 9490 | 36656 |
| node2 | `chain-0-node-2` | 37658 | 13718 | 9491 | 36657 |
| node3 | `chain-0-node-3` | 37659 | 13719 | 9492 | 36658 |
| node4 | `chain-0-node-4` | 37660 | 13720 | 9493 | 36659 |
| node5 | `chain-0-node-5` | 37661 | 13721 | 9494 | 36660 |
| node6 | `chain-0-node-6` | 37662 | 13722 | 9495 | 36661 |
| node7 | `chain-0-node-7` | 37663 | 13723 | 9496 | 36662 |
| node8 | `chain-0-node-8` | 37664 | 13724 | 9497 | 36663 |

---

## 4. 前提条件

- Docker / Docker Compose が使えること
- `sudo docker ...` を実行できること
- ホスト側で `jq`, `curl`, `python3` が使えること
- `ghcr.io/cosmos/ibc-go-simd:release-v10.4.x` を pull できること

---

## 5. 初期化

```bash
chmod +x scripts/*.sh
./scripts/init-8node.sh
```

このスクリプトでは以下を行います。

1. 8 ノード分の `simd init`
2. 各ノードに `validator` キー作成
3. node1 に `user1` キー作成
4. node1 の genesis に 8 validator と user1 を追加
5. 共通 genesis を全ノードへ配布
6. 8 ノードすべてで `gentx` 生成
7. node1 に gentx 集約して `collect-gentxs`
8. 最終 genesis を全ノードへ再配布
9. `persistent_peers` を 8 ノード分自動設定
10. `node-addresses.csv` を生成

---

## 6. 起動

```bash
./scripts/start-8node.sh
```

または直接:

```bash
sudo docker compose up -d --remove-orphans
```

---

## 7. 全ノード状態確認

```bash
./scripts/query-status-all.sh
```

確認ポイント:

- `network` がすべて `chain-0`
- 各ノードの `latest_block_height` が増えている
- `catching_up: false`

---

## 8. validator 一覧確認

node1 の RPC から validator 一覧を確認します。

```bash
./scripts/query-validators.sh
```

出力項目:

- `address`
- `voting_power`
- `proposer_priority`

---

## 9. 残高確認

node1 の `validator` と `user1` を確認します。

```bash
./scripts/query-balances.sh
```

---

## 10. 単発 Tx 実験

node1 の `validator` から `user1` に `1000stake` を送ります。

```bash
./scripts/send-bank-tx.sh 1000stake
```

出力先ディレクトリ指定例:

```bash
./scripts/send-bank-tx.sh 1000stake validator user1 single-run
```

---

## 11. Tx inclusion 待機

```bash
./scripts/wait-tx.sh <txhash> 60
```

---

## 12. burst load 実験

10 本:

```bash
./scripts/burst-bank-load.sh 10 1stake burst-10
```

50 本、0.2 秒間隔:

```bash
./scripts/burst-bank-load.sh 50 1stake burst-50 0.2
```

100 本、0.1 秒間隔:

```bash
./scripts/burst-bank-load.sh 100 1stake burst-100 0.1
```

---

## 13. inclusion 監査

```bash
./scripts/audit-tx-inclusion.sh burst-10/summary.csv burst-10/audit.csv
```

主な列:

- `height`
- `tx_time`
- `local_submit_to_inclusion_secs`
- `gas_wanted`
- `gas_used`
- `tx_code`
- `codespace`

---

## 14. 監査結果の要約

```bash
./scripts/summarize-load-result.sh burst-10/audit.csv
```

---

## 15. block time 抽出

直近 200 block の時刻差を CSV 出力します。

```bash
./scripts/export-block-times.sh 200 block-times.csv
```

既定では node1 RPC (`37657`) を参照します。別ノードを見るときは:

```bash
RPC_PORT=37660 ./scripts/export-block-times.sh 200 node4-block-times.csv
```

---

## 16. 推奨実験フロー

### A. 初期化と起動

```bash
chmod +x scripts/*.sh
./scripts/init-8node.sh
./scripts/start-8node.sh
./scripts/query-status-all.sh
./scripts/query-validators.sh
./scripts/query-balances.sh
```

### B. 単発 Tx

```bash
./scripts/send-bank-tx.sh 1000stake validator user1 single-run
```

返ってきた `txhash` を使って:

```bash
./scripts/wait-tx.sh <txhash> 60
```

### C. burst 10

```bash
./scripts/burst-bank-load.sh 10 1stake burst-10
./scripts/audit-tx-inclusion.sh burst-10/summary.csv burst-10/audit.csv
./scripts/summarize-load-result.sh burst-10/audit.csv
```

### D. burst 50

```bash
./scripts/burst-bank-load.sh 50 1stake burst-50 0.2
./scripts/audit-tx-inclusion.sh burst-50/summary.csv burst-50/audit.csv
./scripts/summarize-load-result.sh burst-50/audit.csv
```

### E. block time 取得

```bash
./scripts/export-block-times.sh 500 block-times-500.csv
```

---

## 17. 実験上の注意

### 17.1 これは 8 validator 構成

本パッケージは **8ノード = 8 validator** です。full node 専用ノードは含みません。

### 17.2 submit は node1 基準

`send-bank-tx.sh`, `wait-tx.sh`, `audit-tx-inclusion.sh` は既定で node1 コンテナを使います。

### 17.3 送信方式

`send-bank-tx.sh` は `--broadcast-mode sync` を使います。submit 成功と inclusion は別なので、`wait-tx.sh` または `audit-tx-inclusion.sh` で確認してください。

### 17.4 sequence 競合

短い間隔で大量送信すると sequence 競合が起こりえます。必要なら `interval_sec` を増やしてください。

### 17.5 ローカル資源

8 ノード同時起動なので、単一ノード版より CPU / メモリ消費が増えます。

---

## 18. 停止

```bash
./scripts/stop-8node.sh
```

完全に消す場合:

```bash
sudo docker compose down -v --remove-orphans
```

---

## 19. 正直な注意

このパッケージは、`simd` の multi-node 初期化パターンに沿って作っていますが、こちらでは実機 Docker 上で end-to-end 実行検証まではしていません。もし `simd genesis ...` 系サブコマンドや設定ファイルの細部が、あなたの取得したイメージ版と少し違う場合は、初回ログに合わせた微修正が必要になる可能性があります。
