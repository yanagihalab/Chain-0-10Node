#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <tx_raw_dir> <out_csv>" >&2
  exit 1
fi

TX_RAW_DIR="$1"
OUT_CSV="$2"

if [[ ! -d "$TX_RAW_DIR" ]]; then
  echo "tx_raw dir not found: $TX_RAW_DIR" >&2
  exit 1
fi

python3 - "$TX_RAW_DIR" "$OUT_CSV" <<'PY'
import csv
import glob
import json
import os
import sys

tx_raw_dir = sys.argv[1]
out_csv = sys.argv[2]

files = sorted(glob.glob(os.path.join(tx_raw_dir, "*-tx.json")))

rows = []

for path in files:
    name = os.path.basename(path)
    txhash = name.replace("tx-", "").replace("-tx.json", "")

    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        continue

    if "tx_response" in data:
        r = data["tx_response"]
        height = r.get("height", "")
        timestamp = r.get("timestamp", "")
        gas_wanted = r.get("gas_wanted", "")
        gas_used = r.get("gas_used", "")
        code = r.get("code", "")
    else:
        height = data.get("height", "")
        timestamp = data.get("timestamp", "")
        gas_wanted = data.get("gas_wanted", "")
        gas_used = data.get("gas_used", "")
        code = data.get("code", "")

    rows.append([txhash, height, timestamp, gas_wanted, gas_used, code])

with open(out_csv, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["txhash", "height", "timestamp", "gas_wanted", "gas_used", "code"])
    w.writerows(rows)

print(f"wrote: {out_csv}")
print(f"count={len(rows)}")
PY
