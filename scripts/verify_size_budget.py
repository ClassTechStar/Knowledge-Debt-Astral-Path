# -*- coding: utf-8 -*-
"""交付体积预算门禁（B4：防仓库与产物体积回弹，打法同图谱性能预算）。
三道预算：
  ① 自包含单文件产物 astralpath-monolith.html ≤ 35MB（首屏下载预算）；
  ② 页面源 index.html ≤ 1MB（常规路径要轻）；
  ③ git 跟踪的大文件（>1MB）总字节 ≤ 棘轮上限——只许降不许涨，
     每瘦身一段就手动往下调（同 verify_inline_js 的棘轮约定）。
用法：python scripts/verify_size_budget.py
退出码：0 = 全部达标；1 = 超预算
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MONOLITH_MAX = 35_000_000   # 单文件产物：极端离线发行版，也是首屏下载上限
INDEX_MAX = 1_000_000       # 页面源：常规路径保持轻量
# 棘轮：git 跟踪的 >1MB 文件总字节上限，只许往下调。
# 2026-11-17 基线 152.3MB（19 个）；发布二进制与 dist 截图出库后 76.5MB（14 个），上限跟着下调。
TRACKED_BIG_CEILING = 86_000_000


def tracked_big():
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=ROOT)
    if out.returncode != 0:
        return None, "git ls-files 失败：" + (out.stderr or "")[:200]
    total, files = 0, []
    for rel in out.stdout.splitlines():
        p = ROOT / rel
        if not p.is_file():
            continue
        size = p.stat().st_size
        if size > 1_000_000:
            total += size
            files.append((size, rel))
    return (total, files), None


def main() -> int:
    problems = []

    mono = ROOT / "deploy" / "monolith-web" / "astralpath-monolith.html"
    if mono.exists():
        size = mono.stat().st_size
        print(f"  单文件产物 {size:,} / {MONOLITH_MAX:,} 字节")
        if size > MONOLITH_MAX:
            problems.append(f"astralpath-monolith.html {size:,} 超预算 {MONOLITH_MAX:,}")
    else:
        print("  [SKIP] 单文件产物不存在（未构建）")

    idx = ROOT / "deploy" / "monolith-web" / "index.html"
    if idx.exists():
        size = idx.stat().st_size
        print(f"  页面源     {size:,} / {INDEX_MAX:,} 字节")
        if size > INDEX_MAX:
            problems.append(f"index.html {size:,} 超预算 {INDEX_MAX:,}")

    data, err = tracked_big()
    if err:
        problems.append(err)
    else:
        total, files = data
        print(f"  跟踪大文件 {total:,} / {TRACKED_BIG_CEILING:,} 字节（{len(files)} 个 >1MB）")
        if total > TRACKED_BIG_CEILING:
            top = ", ".join(f"{rel}({s:,})" for s, rel in sorted(files, reverse=True)[:5])
            problems.append(f"跟踪大文件总量 {total:,} 超棘轮上限 {TRACKED_BIG_CEILING:,}，最大几个：{top}")

    if problems:
        print("[SIZE]")
        for p in problems:
            print("  - " + p)
        print("FAILED: 体积预算未达标（瘦身完成后请同步下调棘轮上限）")
        return 1
    print("ALL GREEN · 产物与仓库体积都在预算内")
    return 0


if __name__ == "__main__":
    sys.exit(main())
