#!/usr/bin/env python3
"""谱系报告:把 population/ 里的 EVAL 结果按分数排序打印 + 追加 history.md 一行。
用法: python3 reporter.py
"""
import glob
import json
import os
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    rows = []
    for f in glob.glob(os.path.join(HERE, "population", "*.json")):
        with open(f) as fh:
            r = json.load(fh)
        r["gen"] = os.path.basename(f).split("_")[0].lstrip("gen")
        rows.append(r)

    rows.sort(key=lambda r: r["score"], reverse=True)
    for r in rows[:10]:
        print(f"gen{r['gen']:>3}  {r['file']:<16} score={r['score']:>8}  time_ms={r['time_ms']}  parent={r.get('parent')}")
    print(f"\ntotal evaluated: {len(rows)}, best: {rows[0]['file']} @ {rows[0]['score']}")

    with open(os.path.join(HERE, "history.md"), "a") as fh:
        fh.write(f"| {time.strftime('%H:%M:%S')} | {len(rows)} | {rows[0]['file']} | {rows[0]['score']} |\n")


main()
