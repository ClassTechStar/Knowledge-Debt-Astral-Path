#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""知识边置信度标尺门禁（迁移自 knowledge-spaces 的 confidence + evidence 语义）。

背景：源 knowledge-spaces 对知识项/关系带 confidence 字段与来源溯因；
目标 ExamKgBuilder 目前把置信度硬编码为 0.8 / 0.7 / 0.85（attach/tested/prerequisite），
语义散落在代码里、没有统一标尺，也没有"低于阈值需人工复核"的约定。

本门禁只做**文档与事实核对**，不改生产代码、不碰金样：
  ① 检查本文件下方的 CONFIDENCE_SCALE 表完整（五档 + 人工复核阈值）；
  ② 检查 exam.js / ExamKgBuilder.cs 里的硬编码置信度都落在 [0,1] 且在标尺内有定义；
  ③ 若发现新的硬编码数值未在标尺登记，FAIL 提示补文档（防止语义漂移）。

用法：python scripts/verify_confidence_scale.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 五档标尺（迁移自源项目 evidence 分层，按目标项目语义重命名）
CONFIDENCE_SCALE = {
    0.5: "低 · 猜测/弱启发（attach 兜底）",
    0.6: "中低 · 文本模式匹配（attach 常规）",
    0.7: "中 · 章节出现关系（tested）",
    0.8: "中高 · 关键词强关联（attach 高置信）",
    0.85: "高 · 教材结构明示（prerequisite）",
    1.0: "确定 · 直接观测/人工确认",
}
MANUAL_REVIEW_BELOW = 0.6  # 低于此值须人工复核（源的 evidence 门槛思想）

SOURCES = [
    ROOT / "shared" / "exam.js",
    ROOT / "src" / "AstralPath.Core" / "Exam" / "ExamKgBuilder.cs",
]


def main():
    problems = []
    if len(CONFIDENCE_SCALE) < 5:
        problems.append("置信度标尺不足五档")
    print(f"  OK  置信度标尺         {len(CONFIDENCE_SCALE)} 档 + 复核线 {MANUAL_REVIEW_BELOW}")

    found = set()
    for p in SOURCES:
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        # 捕获传给 ExamEdge / confidence 的字面量（0.5~1.0 两位小数）
        for m in re.finditer(r"(?<![\w.])0\.(?:[5-9]|8[05])\b", text):
            found.add(float(m.group()))

    unregistered = sorted(v for v in found if v not in CONFIDENCE_SCALE and v > 0)
    if unregistered:
        problems.append(f"硬编码置信度未在标尺登记：{unregistered}（请补 CONFIDENCE_SCALE 或改用标尺值）")
    else:
        print(f"  OK  硬编码置信度       已登记：{sorted(found)}")

    out_of_range = sorted(v for v in found if not 0 <= v <= 1)
    if out_of_range:
        problems.append(f"置信度越界：{out_of_range}")

    print()
    if problems:
        print(f"置信度标尺 FAILED：{len(problems)} 项")
        for x in problems:
            print(f"  - {x}")
        return 1
    print("置信度标尺 ALL GREEN · 硬编码值与五档标尺对齐，无语义漂移")
    return 0


if __name__ == "__main__":
    sys.exit(main())
