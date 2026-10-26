#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""单文件内联 JS 规模上限。前端业务逻辑在逐步搬进 shared/，行内 JS 从约 7,700 行
往 3,000 以下压；复制份数维持 3（源 + 两个壳镜像）。

本脚本做两件事：
  1. 统计「手写内联 JS 行数」= 全部内联脚本行 − AP 生成区行，超过上限即判红
     （上限只许降不许涨，写在 CEILING，每次搬完一段就手动往下调）；
  2. 统计活的页面副本数（源 + Windows 壳 + Android 壳），多于 3 份即判红。

用法：
    python scripts/verify_inline_js.py            # 校验并写报告
    python scripts/verify_inline_js.py --check    # 只校验（CI / verify_all 用）
退出码：0 = 达标；1 = 超限
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "deploy" / "monolith-web" / "index.html"
REPORT = ROOT / "eval" / "inline-js-report.md"

# 行数上限：只许往下调。目标 3,000。
# 2026-10-25 搬完 kg-text 后 7309；10-26 搬完智能体路由 + 计划调度后 7072，上限跟着下调。
CEILING = 7100
TARGET = 3000
MAX_COPIES = 3

COPIES = [
    "deploy/monolith-web/index.html",
    "src/AstralPath.Monolith/Resources/index.html",
    "src/AstralPath.Native/app/src/main/assets/www/index.html",
]


def count(src: str):
    blocks = re.findall(r"<script\b([^>]*)>(.*?)</script>", src, re.S)
    total = sum(b.count("\n") + 1 for a, b in blocks if "src=" not in a)
    gens = re.findall(r"/\* AP:BEGIN .*?\*/(.*?)/\* AP:END", src, re.S)
    gen = sum(g.count("\n") + 1 for g in gens)
    return total, gen, len(gens), total - gen


def main() -> int:
    check = "--check" in sys.argv[1:]
    if not SOURCE.exists():
        print("[INLINE] 源文件缺失：", SOURCE)
        return 1
    src = SOURCE.read_text(encoding="utf-8")
    total, gen, nregions, hand = count(src)
    copies = [c for c in COPIES if (ROOT / c).exists()]

    ok = hand <= CEILING and len(copies) <= MAX_COPIES
    print(
        f"[INLINE] 内联总行 {total} · 生成区 {gen}（{nregions} 块）· 手写 {hand}"
        f"（上限 {CEILING}，目标 {TARGET}）· 页面副本 {len(copies)}/{MAX_COPIES}"
    )
    if not check:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(
            "# 单文件内联 JS 规模报告\n\n"
            f"- 内联脚本总行：{total}\n"
            f"- AP 生成区行：{gen}（{nregions} 块）\n"
            f"- 手写内联 JS：{hand}（棘轮上限 {CEILING}，目标 {TARGET}）\n"
            f"- 页面副本：{len(copies)} 份（上限 {MAX_COPIES}：源 + Windows 壳 + Android 壳）\n\n"
            + "\n".join(f"- {c}" for c in copies)
            + "\n",
            encoding="utf-8",
        )
    if hand > CEILING:
        print(f"FAILED: 手写内联 JS {hand} 行超过棘轮上限 {CEILING}，请把逻辑搬进 shared/ 后下调上限")
        return 1
    if len(copies) > MAX_COPIES:
        print(f"FAILED: 页面副本 {len(copies)} 份，超过 {MAX_COPIES} 份上限")
        return 1
    print(f"ALL GREEN · 手写 {hand} 行（距目标还差 {max(0, hand - TARGET)} 行）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
