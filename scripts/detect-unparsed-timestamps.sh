#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <csv_file> [timestamp_column=timestamp]" >&2
  exit 1
fi

CSV_FILE="$1"
TIMESTAMP_COLUMN="${2:-timestamp}"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "file not found: $CSV_FILE" >&2
  exit 1
fi

python3 - "$CSV_FILE" "$TIMESTAMP_COLUMN" <<'PY'
import csv
import sys
from datetime import datetime

csv_file = sys.argv[1]
timestamp_column = sys.argv[2]

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

total = 0
ok = 0
bad = []

with open(csv_file, newline="") as f:
    r = csv.DictReader(f)
    if timestamp_column not in r.fieldnames:
        print(f"column not found: {timestamp_column}", file=sys.stderr)
        print("available columns:", ", ".join(r.fieldnames), file=sys.stderr)
        sys.exit(1)

    for idx, row in enumerate(r, start=2):
        ts = (row.get(timestamp_column) or "").strip()
        if ts == "":
            continue
        total += 1
        try:
            parse_block_time(ts)
            ok += 1
        except Exception as e:
            bad.append((idx, ts, str(e)))

print(f"checked={total}")
print(f"parsed_ok={ok}")
print(f"parsed_ng={len(bad)}")

if bad:
    print("unparsed timestamps:")
    for line_no, ts, err in bad:
        print(f"line={line_no}\ttimestamp={ts}\terror={err}")
PY
