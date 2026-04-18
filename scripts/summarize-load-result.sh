#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <audit.csv>" >&2
  exit 1
fi

AUDIT="$1"

python3 - "$AUDIT" <<'PY'
import csv
import statistics
import sys

path = sys.argv[1]

rows = []
delays = []

with open(path, newline="") as f:
    r = csv.DictReader(f)
    for row in r:
        rows.append(row)
        v = (row.get("local_submit_to_inclusion_secs") or "").strip()
        if v != "":
            try:
                delays.append(float(v))
            except ValueError:
                pass

print(f"count={len(rows)}")

if not delays:
    print("mean=")
    print("median=")
    print("p90=")
    print("p99=")
    print("min=")
    print("max=")
    sys.exit(0)

delays_sorted = sorted(delays)

def percentile(values, p):
    if len(values) == 1:
        return values[0]
    k = (len(values) - 1) * p
    f = int(k)
    c = min(f + 1, len(values) - 1)
    if f == c:
        return values[f]
    return values[f] * (c - k) + values[c] * (k - f)

print(f"mean={statistics.mean(delays):.6f}")
print(f"median={statistics.median(delays):.6f}")
print(f"p90={percentile(delays_sorted, 0.90):.6f}")
print(f"p99={percentile(delays_sorted, 0.99):.6f}")
print(f"min={min(delays):.6f}")
print(f"max={max(delays):.6f}")
PY
