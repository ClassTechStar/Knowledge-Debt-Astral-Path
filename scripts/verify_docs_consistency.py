# -*- coding: utf-8 -*-
"""文档—代码一致性门禁（迁移自 ReciteHelper 的文档漂移反面教材）。

背景：ReciteHelper 的 docs/manual-*.md 写"采纳门槛 70%"，实现里却是 60%；
这类漂移不会让测试失败，却会让读者按错误口径决策。本门禁锁死目标项目里
最容易漂移的"当前态"数字，历史变更记录（"A → B"式陈述）豁免。

锁死项：
  ① README「N 步 ALL GREEN」== verify_all.ps1 的 Step + SkipStep 定义数
  ② README 产物表里的"自包含单文件"字节数 == 实际产物字节数
  ③ 当前态的 OCR 引擎版本 == vendor 下载脚本里的版本

不校验：变更记录里的历史值、带箭头的迁移描述（那些是历史事实，不是当前口径）。

用法：python scripts/verify_docs_consistency.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
problems = []


def read(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


def main():
    readme = read("README.md")
    verify_all = read("scripts/verify_all.ps1")
    steps = len(re.findall(r'^\s*Step\s+"', verify_all, re.M))
    skips = len(re.findall(r'^\s*SkipStep\s+"', verify_all, re.M))
    actual_steps = steps + skips

    # ① 当前门禁步数（只匹配 "ALL GREEN" 这种当前态表述）
    doc_steps = [int(x) for x in re.findall(r"(\d+)\s*步\s*ALL GREEN", readme)]
    if doc_steps and any(x != actual_steps for x in doc_steps):
        problems.append(f"README 门禁步数 {sorted(set(doc_steps))} ≠ verify_all 实际 {actual_steps}（Step {steps}+SkipStep {skips}）")
    else:
        print(f"  OK  门禁步数           README 与 verify_all 一致（{actual_steps} = {steps}+{skips}）")

    # ② 当前产物体积：只读 README 产物表里"自包含单文件"那一行
    mono = ROOT / "deploy" / "monolith-web" / "astralpath-monolith.html"
    if mono.exists():
        actual_size = mono.stat().st_size
        row = re.search(r"\|\s*自包含单文件\s*\|[^|]*\|\s*([\d,]+)\s*字节", readme)
        if row:
            doc_size = int(row.group(1).replace(",", ""))
            if doc_size != actual_size:
                problems.append(f"README 产物表单文件 {doc_size:,} ≠ 实际 {actual_size:,} 字节")
            else:
                print(f"  OK  单文件体积         README 产物表与实际一致（{actual_size:,} 字节）")

    # ③ 当前 OCR 引擎版本：vendor 下载脚本 vs README 的"当前版本"表述
    vendor = read("deploy/monolith-web/ocr-engine/dl-vendor.ps1")
    vendor_ver = set(re.findall(r"tesseract\.js@(\d+\.\d+\.\d+)", vendor))
    # 只取"当前/现用"语境，排除 "5.1.1 → 6.0.1" 这类历史迁移陈述
    current_ver = set(re.findall(r"(?:当前|现用|升级到|已升级)[^。\n]{0,30}?tesseract\.js\s*(\d+\.\d+\.\d+)", readme))
    if vendor_ver and current_ver and vendor_ver != current_ver:
        problems.append(f"README 当前引擎版本 {sorted(current_ver)} ≠ vendor 下载版本 {sorted(vendor_ver)}")
    else:
        print(f"  OK  OCR 引擎版本       当前态与 vendor 一致（{'/'.join(sorted(vendor_ver)) or '未标注'}）")

    print()
    if problems:
        print(f"文档一致性 FAILED：{len(problems)} 项（修文档，不要改代码迁就文档）")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("文档一致性 ALL GREEN · 关键当前态数字与代码/产物对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())
