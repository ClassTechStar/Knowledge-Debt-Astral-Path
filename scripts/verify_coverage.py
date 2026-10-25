#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""覆盖率阈值门禁（T21 阶段三 / P2-10）
=====================================
coverage 作业此前是 report-only（continue-on-error），覆盖率掉了也不会红。
本脚本把 Cobertura 报告解析成行/分支覆盖率，低于阈值即判红。

阈值按当前实测留余量：Core 实测行覆盖约 54.6%，阈值取 50.0%；
分支实测约 49.0%，阈值取 40.0%。改动后如需调整，请同步更新这里的注释。

用法：
    python scripts/verify_coverage.py            # 校验并写报告
    python scripts/verify_coverage.py --check    # 只校验（CI 用）
退出码：0 = 达标；1 = 未达标或报告缺失
"""
from __future__ import annotations

import glob
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / "eval" / "coverage-report.md"

LINE_MIN = 50.0
BRANCH_MIN = 40.0


def main() -> int:
    check = "--check" in sys.argv[1:]
    files = sorted(glob.glob(str(ROOT / "artifacts" / "**" / "coverage.cobertura.xml"), recursive=True))
    if not files:
        print("[失败] 未找到 coverage.cobertura.xml，请先跑 dotnet test --collect:\"XPlat Code Coverage\"")
        return 1
    # 本地反复跑测试会在 artifacts/coverage 下累积多次运行；只取最新一次，
    # 否则「覆盖行」会把历史运行重复累加。CI 每次是干净工作区，不受影响。
    latest_dir = max((Path(f).parent for f in files), key=lambda p: p.stat().st_mtime)
    files = [f for f in files if Path(f).parent == latest_dir]

    line_sum = branch_sum = 0.0
    covered = valid = 0
    for f in files:
        s = Path(f).read_text(encoding="utf-8", errors="replace")
        m = re.search(r'<coverage[^>]*line-rate="([0-9.]+)"[^>]*branch-rate="([0-9.]+)"', s)
        if m:
            line_sum += float(m.group(1))
            branch_sum += float(m.group(2))
        for lm in re.finditer(r'lines-covered="(\d+)" lines-valid="(\d+)"', s):
            covered += int(lm.group(1))
            valid += int(lm.group(2))
    n = len(files)
    line_rate = line_sum / n * 100.0
    branch_rate = branch_sum / n * 100.0

    ok_line = line_rate >= LINE_MIN
    ok_branch = branch_rate >= BRANCH_MIN
    print(f"[COV] 行覆盖 {line_rate:.2f}%（阈值 {LINE_MIN}%）· 分支覆盖 {branch_rate:.2f}%"
          f"（阈值 {BRANCH_MIN}%）· 覆盖行 {covered}/{valid}")

    if not check:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(
            "# 覆盖率报告\n\n"
            f"- 行覆盖：{line_rate:.2f}%（阈值 {LINE_MIN}%）\n"
            f"- 分支覆盖：{branch_rate:.2f}%（阈值 {BRANCH_MIN}%）\n"
            f"- 覆盖行：{covered} / {valid}\n"
            f"- 报告文件：{len(files)} 份 Cobertura\n",
            encoding="utf-8",
        )
    if not ok_line or not ok_branch:
        print("FAILED: 覆盖率低于阈值")
        return 1
    print("ALL GREEN · 覆盖率达标")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
