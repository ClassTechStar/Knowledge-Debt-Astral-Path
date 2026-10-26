#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""知识图谱性能基准：用固定种子的合成语料跑一遍「分章 → 构图」全链，
给出耗时基准再和预算比对，防止算法改动带来隐性性能退化（类似 OCR 的耗时/精度门槛）。

语料用固定种子生成（不依赖仓库内的真实教材，CI 可重复执行）。

用法：
    python scripts/bench_kg.py            # 跑基准并写报告
    python scripts/bench_kg.py --check    # 只校验是否超预算（CI / verify_all 用）
退出码：0 = 在预算内；1 = 超出预算
"""
from __future__ import annotations

import json
import random
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import kg_builder as kg  # noqa: E402

REPORT = ROOT / "eval" / "perf-baseline.md"

# 预算（毫秒）：本机实测章节约 19 ms、构图约 124 ms；CI 机器按 5~10 倍放宽容差，
# 目的是抓住量级退化（例如构图退化回 O(V²)），而不是卡毫秒级抖动。
BUDGET = {
    "extract_chapters_ms": 250,
    "build_graph_ms": 2000,
}

TERMS = ["会计要素", "会计等式", "借贷记账法", "复式记账", "资产", "负债", "所有者权益",
         "收入", "费用", "利润", "凭证", "账簿", "报表", "折旧", "摊销", "存货",
         "应收账款", "应付账款", "成本核算", "预算管理", "内部控制", "审计"]


def make_corpus(chapters: int = 40, per_chapter: int = 400) -> str:
    rnd = random.Random(20261025)
    out = []
    for c in range(1, chapters + 1):
        out.append(f"第 {c} 章 " + TERMS[c % len(TERMS)])
        for _ in range(per_chapter):
            t1, t2 = rnd.choice(TERMS), rnd.choice(TERMS)
            out.append(f"{t1}与{t2}之间存在先修关系，掌握{t1}是理解{t2}的前提；本章还讨论了{t2}的应用场景。")
    return "\n".join(out)


def measure(fn, *a, **kw):
    t0 = time.perf_counter()
    r = fn(*a, **kw)
    return r, (time.perf_counter() - t0) * 1000.0


def main() -> int:
    check = "--check" in sys.argv[1:]
    text = make_corpus()
    chs, t_ch = measure(kg.extract_chapters, text, 40)
    graph, t_bg = measure(kg.build_graph, text, "bench-kg", 24)

    rows = [
        ("extract_chapters", t_ch, BUDGET["extract_chapters_ms"]),
        ("build_graph", t_bg, BUDGET["build_graph_ms"]),
    ]
    over = [(n, ms, b) for n, ms, b in rows if ms > b]
    print(f"[PERF] 语料 {len(text):,} 字 · 章节 {len(chs)} · 节点 {len(graph.get('nodes', []))} · 边 {len(graph.get('edges', []))}")
    for n, ms, b in rows:
        print(f"  {n:<20} {ms:8.1f} ms  (预算 {b} ms)  {'超预算' if ms > b else '通过'}")

    if not check:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(
            "# 知识图谱性能基准\n\n"
            f"- 语料：确定性合成语料 {len(text):,} 字（40 章 × 400 句），种子 20261025\n"
            f"- 分章结果：{len(chs)} 章；构图结果：{len(graph.get('nodes', []))} 节点 / {len(graph.get('edges', []))} 边\n\n"
            "| 阶段 | 实测 | 预算 | 结论 |\n|---|---|---|---|\n"
            + "\n".join(f"| {n} | {ms:.1f} ms | {b} ms | {'超预算' if ms > b else '通过'} |" for n, ms, b in rows)
            + "\n",
            encoding="utf-8",
        )
    if over:
        print("FAILED: " + "；".join(f"{n} {ms:.0f}ms > {b}ms" for n, ms, b in over))
        return 1
    print("ALL GREEN · 图谱全链在预算内")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
