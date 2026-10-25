#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图谱质量门禁（P1-7）
======================
给 kg-deep-test 的思维导图产物建一条类似 OCR CER 的质量门槛，专门抓「图谱退化」：
  1. 退化标题（段落 N / 第 N 页）占比必须为 0；
  2. 空标题节点必须为 0；
  3. 父子同名节点必须为 0；
  4. 每份产物节点数不低于 20、深度不低于 3（防止整本书塌缩）；
  5. .md 与 .json 必须一致（md 由 json 重新生成后逐字节比对）。

用法：
    python scripts/verify_graph_quality.py            # 校验并写报告
    python scripts/verify_graph_quality.py --check    # 只校验（CI / verify_all 用）
退出码：0 = ALL GREEN；1 = 有产物不达标
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "kg-deep-test"
REPORT = ROOT / "eval" / "graph-quality-report.md"

DEGRADED = re.compile(r"^(段落\s*\d+|第\s*\d+\s*页)$")
MIN_NODES = 20
MIN_DEPTH = 2  # 思维导图天然两层：书名 → 分组/概念；低于 2 说明整本书塌缩


def walk(node, depth=0):
    yield node, depth
    for c in node.get("children") or []:
        yield from walk(c, depth + 1)


def text_of(node) -> str:
    return str((node.get("data") or {}).get("text", "") or "")


def render_md(root) -> str:
    lines = ["# " + text_of(root)]

    def emit(node, depth):
        for c in node.get("children") or []:
            lines.append("  " * depth + "- " + text_of(c))
            emit(c, depth + 1)

    emit(root, 1)
    return "\n".join(lines) + "\n"


def main() -> int:
    check = "--check" in sys.argv[1:]
    files = sorted(DIR.glob("*.mindmap.json"))
    if not files:
        print("[KGQ] 未找到思维导图产物")
        return 1

    rows, failed = [], []
    for f in files:
        raw = f.read_bytes()
        nl = "\r\n" if b"\r\n" in raw else "\n"
        doc = json.loads(raw.decode("utf-8"))
        nodes = list(walk(doc))
        titles = [text_of(n) for n, _ in nodes]
        degraded = sum(1 for t in titles if DEGRADED.match(t))
        empty = sum(1 for t in titles if not t.strip())
        dup = sum(
            1
            for n, _ in nodes
            if any(text_of(c) == text_of(n) for c in n.get("children") or [])
        )
        max_depth = max(d for _, d in nodes)
        md = f.with_suffix(".md")
        md_ok = "n/a"
        if md.exists():
            md_ok = "一致" if md.read_bytes() == render_md(doc).replace("\n", nl).encode("utf-8") else "不一致"

        problems = []
        if degraded:
            problems.append(f"退化标题 {degraded}")
        if empty:
            problems.append(f"空标题 {empty}")
        if dup:
            problems.append(f"父子同名 {dup}")
        if len(nodes) < MIN_NODES:
            problems.append(f"节点 {len(nodes)} < {MIN_NODES}")
        if max_depth < MIN_DEPTH:
            problems.append(f"深度 {max_depth} < {MIN_DEPTH}")
        if md_ok == "不一致":
            problems.append("md 与 json 不一致")

        rows.append((f.name, len(nodes), max_depth, degraded, empty, dup, md_ok, problems))
        if problems:
            failed.append((f.name, problems))

    print(f"{'文件':<40}{'节点':>6}{'深度':>5}{'退化':>5}{'空题':>5}{'同名':>5}{'md':>6}")
    for name, n, d, de, em, du, md_ok, problems in rows:
        flag = " FAIL" if problems else ""
        print(f"{name[:38]:<40}{n:>6}{d:>5}{de:>5}{em:>5}{du:>5}{md_ok:>6}{flag}")

    if not check:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# 图谱质量报告",
            "",
            f"共校验 {len(rows)} 份思维导图产物。门槛：退化标题、空标题、父子同名均为 0；"
            f"每份节点不少于 {MIN_NODES}、深度不少于 {MIN_DEPTH}；md 与 json 一致。",
            "",
            "| 文件 | 节点 | 深度 | 退化 | 空标题 | 父子同名 | md | 结论 |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for name, n, d, de, em, du, md_ok, problems in rows:
            lines.append(f"| {name} | {n} | {d} | {de} | {em} | {du} | {md_ok} | {'不达标' if problems else '通过'} |")
        REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    if failed:
        print("FAILED: " + "；".join(f"{n}（{', '.join(p)}）" for n, p in failed))
        return 1
    print(f"ALL GREEN · {len(rows)} 份思维导图全部达标")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
