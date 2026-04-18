#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <summary.csv> <audit.csv>" >&2
  exit 1
fi

SUMMARY="$1"
AUDIT="$2"

NODE="${NODE:-http://127.0.0.1:37657}"

if [[ ! -f "$SUMMARY" ]]; then
  echo "summary file not found: $SUMMARY" >&2
  exit 1
fi

echo 'sequence_no,txhash,submit_code,local_submit_ts,height,tx_time,local_submit_to_inclusion_secs,gas_wanted,gas_used,tx_code,codespace' > "$AUDIT"

python3 - "$SUMMARY" "$AUDIT" "$NODE" <<'PY'
import csv
import json
import sys
import urllib.request
import urllib.parse
from datetime import datetime

summary_path = sys.argv[1]
audit_path = sys.argv[2]
node = sys.argv[3].rstrip("/")

def parse_local_ts(x: str) -> float:
    return float(x)

def parse_block_time(ts: str) -> float:
    ts = ts.strip()

    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"

    if "." in ts:
        head, tail = ts.split(".", 1)
        if "+" in tail:
            frac, tz = tail.split("+", 1)
            frac = frac[:6]
            ts = f"{head}.{frac}+{tz}"
        elif "-" in tail:
            frac, tz = tail.split("-", 1)
            frac = frac[:6]
            ts = f"{head}.{frac}-{tz}"

    return datetime.fromisoformat(ts).timestamp()

with open(summary_path, newline="") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

with open(audit_path, "a", newline="") as f:
    writer = csv.writer(f)

    for row in rows:
        txhash = row.get("txhash", "").strip()
        submit_code = row.get("code", "").strip()
        local_submit_ts = row.get("local_submit_ts", "").strip()

        if not txhash:
            continue

        try:
            url = f"{node}/tx?hash=0x{urllib.parse.quote(txhash)}"
            with urllib.request.urlopen(url, timeout=10) as resp:
                data = json.load(resp)
        except Exception:
            continue

        result = data.get("result")
        if not result:
            continue

        tx_result = result.get("tx_result", {})
        height = result.get("height", "")
        tx_code = tx_result.get("code", "")
        codespace = tx_result.get("codespace", "")
        gas_wanted = tx_result.get("gas_wanted", "")
        gas_used = tx_result.get("gas_used", "")

        tx_time = ""
        local_submit_to_inclusion_secs = ""

        try:
            block_url = f"{node}/block?height={height}"
            with urllib.request.urlopen(block_url, timeout=10) as resp:
                block_data = json.load(resp)
            tx_time = block_data["result"]["block"]["header"]["time"]
            inclusion_secs = parse_block_time(tx_time) - parse_local_ts(local_submit_ts)
            local_submit_to_inclusion_secs = f"{inclusion_secs:.6f}"
        except Exception:
            tx_time = ""
            local_submit_to_inclusion_secs = ""

        writer.writerow([
            row.get("sequence_no", ""),
            txhash,
            submit_code,
            local_submit_ts,
            height,
            tx_time,
            local_submit_to_inclusion_secs,
            gas_wanted,
            gas_used,
            tx_code,
            codespace,
        ])
PY

echo "wrote: $AUDIT"
