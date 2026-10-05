#!/bin/bash
# 选择器:从 population/ 的 EVAL 结果里挑出最高分,写入 current_genome.py
# 用法: bash selector.sh
set -e
cd "$(dirname "$0")"

best=$(grep -h . population/*.json 2>/dev/null | python3 -c '
import sys, json
records = [json.loads(l) for l in sys.stdin if l.strip()]
ok = [r for r in records if r.get("ok")]
if not ok:
    print("NO_VALID", file=sys.stderr); sys.exit(1)
print(max(ok, key=lambda r: r["score"])["file"])
') || { echo "no valid genome yet"; exit 1; }

cp "population/$best.py" current_genome.py
echo "selected: $best"
