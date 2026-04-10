#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "usage: $0 <audit.csv>" >&2
  exit 1
fi
python3 - "$1" <<'PY'
import csv, statistics, sys
rows=[]
with open(sys.argv[1], newline='') as f:
    for r in csv.DictReader(f):
        if r['local_submit_to_inclusion_secs']:
            rows.append(float(r['local_submit_to_inclusion_secs']))
print(f"count={len(rows)}")
if rows:
    s=sorted(rows)
    def pct(p):
        idx=max(0,min(len(s)-1,int((len(s)-1)*p)))
        return s[idx]
    print(f"mean={statistics.mean(rows):.6f}")
    print(f"median={statistics.median(rows):.6f}")
    print(f"p90={pct(0.90):.6f}")
    print(f"p99={pct(0.99):.6f}")
    print(f"min={min(rows):.6f}")
    print(f"max={max(rows):.6f}")
PY
