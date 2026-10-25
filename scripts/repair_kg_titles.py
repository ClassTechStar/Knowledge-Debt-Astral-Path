#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复 kg-deep-test 思维导图里退化的「段落 N」标题
====================================================
背景：kg_builder 的兜底分章在章节标题识别失败时，用段落首行或「段落 N」充当
章节名，导致思维导图二级节点大面积退化为「段落 1 / 段落 2 / …」（13 份产物
共 1,036 个节点中 383 个退化，其中 267 个还是空壳）。

本脚本做三件事（幂等，可重复运行）：
  1. 有子节点的退化节点：改用「子树最大 + 名称最长」的子节点命名，
     让分组标题反映其下最发育的概念；
  2. 无子节点的退化节点：直接移除（空壳分组不携带任何信息）；
  3. 依据修复后的 JSON 重新生成同名 .md（保证两份产物一致）。

用法：
    python scripts/repair_kg_titles.py            # 修复并重写产物
    python scripts/repair_kg_titles.py --check    # 只检查不写（CI / verify_all 用）
退出码：0 = 无退化残留或已修复；1 = --check 模式下仍有退化
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "kg-deep-test"

DEGRADED = re.compile(r"^(段落\s*\d+|第\s*\d+\s*页)$")


def walk(node):
    yield node
    for c in node.get("children") or []:
        yield from walk(c)


def text_of(node) -> str:
    return str((node.get("data") or {}).get("text", "") or "")


def subtree_size(node) -> int:
    return 1 + sum(subtree_size(c) for c in node.get("children") or [])


def repair(node) -> tuple[int, int]:
    """返回 (重命名数, 移除数)"""
    renamed = removed = 0
    kids = node.get("children") or []
    kept = []
    for c in kids:
        r, m = repair(c)
        renamed += r
        removed += m
        t = text_of(c)
        if DEGRADED.match(t):
            sub = c.get("children") or []
            if sub:
                # 子树最大者优先，其次名称最长（最能代表该分组）
                best = sorted(sub, key=lambda x: (subtree_size(x), len(text_of(x))), reverse=True)[0]
                c["data"]["text"] = text_of(best)
                # 提升为标题后从子节点里移除，避免父子同名
                c["children"] = [x for x in sub if x is not best]
                renamed += 1
            else:
                removed += 1
                continue
        kept.append(c)
    node["children"] = kept
    return renamed, removed


def render_md(root) -> str:
    lines = ["# " + text_of(root)]

    def emit(node, depth):
        for c in node.get("children") or []:
            lines.append("  " * depth + "- " + text_of(c))
            emit(c, depth + 1)

    emit(root, 1)
    return "\n".join(lines) + "\n"


def eol_of(raw: bytes) -> str:
    return "\r\n" if b"\r\n" in raw else "\n"


def main() -> int:
    check = "--check" in sys.argv[1:]
    files = sorted(DIR.glob("*.mindmap.json"))
    if not files:
        print("[KG] 未找到思维导图产物")
        return 1
    total_renamed = total_removed = total_left = 0
    for f in files:
        raw = f.read_bytes()
        nl = eol_of(raw)
        doc = json.loads(raw.decode("utf-8"))
        renamed, removed = repair(doc)
        left = sum(1 for n in walk(doc) if DEGRADED.match(text_of(n)))
        total_renamed += renamed
        total_removed += removed
        total_left += left
        if not check and (renamed or removed or left):
            f.write_bytes(json.dumps(doc, ensure_ascii=False, indent=1).replace("\n", nl).encode("utf-8"))
            md = f.with_suffix(".md")
            if md.exists():
                md.write_bytes(render_md(doc).replace("\n", nl).encode("utf-8"))
            print(f"[KG] {f.name}: 重命名 {renamed} · 移除空壳 {removed} · 残留 {left}")
        elif renamed or removed or left:
            print(f"[KG] {f.name}: 仍存在退化 {left}（重命名 {renamed} · 空壳 {removed} 待修复）")
    if check:
        if total_left:
            print(f"FAILED: 仍有 {total_left} 个退化标题，跑 `python scripts/repair_kg_titles.py` 修复")
            return 1
        print(f"ALL GREEN · {len(files)} 份思维导图无退化标题")
        return 0
    print(f"ALL GREEN · 共重命名 {total_renamed} · 移除空壳 {total_removed} · 残留 {total_left}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
