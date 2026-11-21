#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图谱结构校验：FAIL/WARN/PASS 三级报告（迁移自 knowledge-spaces 的 validate_graph 分层法）。

与 verify_graph_quality.py 的职责边界（不重叠）：
  - verify_graph_quality.py：kg-deep-test 产物（思维导图 .json/.md）的**二元退化门禁**，
    5 条硬门槛，退化即 FAIL，已在 verify_all 登记；
  - 本脚本：graph-packs/ 下的**正式知识包**（nodes.json + edges.json），
    做数学一致性 + 教学合理性的三级体检，WARN 不阻塞，只产出可审查报告。

迁移适配说明（源 → 目标）：
  - 源 validate_graph 的 fail/warn/pass 三级分类法 → 保留；
  - 源的 Bloom 层级倒挂检查 → **不采纳**（目标节点无 bloom_level 字段，强加会污染数据契约）；
  - 源的并集闭包采样检查 → **不采纳**（目标不枚举知识空间状态，无 knowledge_states 数据）；
  - 源的孤儿节点 / 直接先修负荷告警 → 采纳，字段映射 from/to；
  - 新增目标特有的边类型白名单校验（prerequisite / transfer_gap）。

用法：
    python scripts/verify_graph_structure.py            # 写报告
    python scripts/verify_graph_structure.py --check    # 只校验（WARN 不算失败）
退出码：0 = 无数学硬错误；1 = 存在 FAIL（引用完整性/重复边/自环/环）
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / "graph-packs"
REPORT = ROOT / "eval" / "graph-structure-report.md"
ALLOWED_EDGE_TYPES = {"prerequisite", "transfer_gap"}
MAX_DIRECT_PREREQ = 7  # 源项目认知负荷阈值，目标会计样例最大远低于此


def load_pack(pack_dir: Path):
    """支持两种布局：① nodes.json + edges.json 分文件；② graph_pack.json 单文件。"""
    nodes_p, edges_p = pack_dir / "nodes.json", pack_dir / "edges.json"
    if nodes_p.exists() and edges_p.exists():
        return json.loads(nodes_p.read_text(encoding="utf-8")), json.loads(edges_p.read_text(encoding="utf-8"))
    single = pack_dir / "graph_pack.json"
    if single.exists():
        d = json.loads(single.read_text(encoding="utf-8"))
        nodes, edges = d.get("nodes", []), d.get("edges", [])
        # 单文件包用 kp_id / from_kp / to_kp / edge_type，归一到分文件口径
        for n in nodes:
            if "id" not in n and "kp_id" in n:
                n["id"] = n["kp_id"]
        for e in edges:
            if "from" not in e and "from_kp" in e:
                e["from"] = e["from_kp"]
            if "to" not in e and "to_kp" in e:
                e["to"] = e["to_kp"]
            if "edgeType" not in e and "edge_type" in e:
                e["edgeType"] = e["edge_type"]
        return nodes, edges
    return None, None


def check_pack(pack_dir: Path):
    nodes, edges = load_pack(pack_dir)
    result = {"pack": pack_dir.name, "fail": [], "warn": [], "pass": [], "stats": {}}
    if nodes is None:
        result["fail"].append("缺 nodes.json 或 edges.json")
        return result

    ids = [n["id"] for n in nodes if isinstance(n, dict) and "id" in n]
    id_set = set(ids)
    result["stats"] = {"nodes": len(ids), "edges": len(edges)}

    # --- 数学硬约束（FAIL）---
    if len(ids) != len(id_set):
        result["fail"].append(f"节点 ID 重复：{len(ids) - len(id_set)} 个")
    else:
        result["pass"].append("节点 ID 唯一")

    bad_refs = [e for e in edges if e.get("from") not in id_set or e.get("to") not in id_set]
    if bad_refs:
        result["fail"].append(f"悬空边（引用不存在节点）：{len(bad_refs)} 条")
    else:
        result["pass"].append("引用完整性：所有边端点有效")

    seen, dupes = set(), 0
    for e in edges:
        key = (e.get("from"), e.get("to"), e.get("edgeType"))
        if key in seen:
            dupes += 1
        seen.add(key)
    if dupes:
        result["fail"].append(f"重复边：{dupes} 条")
    else:
        result["pass"].append("无重复边")

    self_loops = [e for e in edges if e.get("from") == e.get("to")]
    if self_loops:
        result["fail"].append(f"自环：{len(self_loops)} 条")
    else:
        result["pass"].append("无自环")

    bad_types = sorted({e.get("edgeType") for e in edges} - ALLOWED_EDGE_TYPES)
    if bad_types:
        result["fail"].append(f"未知边类型：{bad_types}")
    else:
        result["pass"].append("边类型在白名单内")

    # 环检测（prerequisite 子图，DFS 三色）
    adj = defaultdict(list)
    for e in edges:
        if e.get("edgeType") == "prerequisite":
            adj[e["from"]].append(e["to"])
    color = {}
    cyclic = []

    def dfs(u):
        color[u] = 1
        for v in adj.get(u, []):
            if color.get(v, 0) == 1:
                cyclic.append((u, v))
            elif color.get(v, 0) == 0:
                dfs(v)
        color[u] = 2

    for n in id_set:
        if color.get(n, 0) == 0:
            dfs(n)
    if cyclic:
        result["fail"].append(f"先修环：{len(cyclic)} 处（示例 {cyclic[:3]}）")
    else:
        result["pass"].append("先修子图无环")

    # --- 教学合理性（WARN，不阻塞）---
    indeg = defaultdict(int)
    linked = set()
    for e in edges:
        if e.get("edgeType") == "prerequisite":
            indeg[e["to"]] += 1
        linked.add(e.get("from"))
        linked.add(e.get("to"))
    heavy = {k: v for k, v in indeg.items() if v > MAX_DIRECT_PREREQ}
    if heavy:
        result["warn"].append(f"直接先修 >{MAX_DIRECT_PREREQ} 的认知负荷节点：{dict(list(heavy.items())[:5])}")
    orphans = sorted(id_set - linked)
    if orphans and len(id_set) > 1:
        result["warn"].append(f"孤儿节点（无任何边）：{len(orphans)} 个（示例 {orphans[:5]}）")
    if not heavy and not orphans:
        result["pass"].append("教学合理性：无过重先修、无孤儿节点")
    return result


def main():
    if not PACKS.exists():
        print("FAILED: graph-packs/ 缺失")
        return 1
    results = [check_pack(d) for d in sorted(PACKS.iterdir()) if d.is_dir() and not d.name.startswith(".")]
    results = [r for r in results if r["stats"] or r["fail"]]

    lines = [
        "# 图谱结构三级校验报告",
        "",
        "> 迁移自 knowledge-spaces 的 `validate_graph` 分层思想；与 `verify_graph_quality.py`",
        "> （kg-deep-test 产物的二元退化门禁）职责不重叠：本报告只覆盖 `graph-packs/` 正式知识包。",
        "> WARN 不阻塞发布，供人工复核；FAIL 表示数学硬错误。",
        "",
        "| 知识包 | 节点 | 边 | FAIL | WARN | PASS | 结论 |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    total_fail = 0
    for r in results:
        n, w, p = len(r["fail"]), len(r["warn"]), len(r["pass"])
        total_fail += n
        lines.append(f"| {r['pack']} | {r['stats'].get('nodes', 0)} | {r['stats'].get('edges', 0)} "
                     f"| {n} | {w} | {p} | {'FAIL' if n else ('WARN' if w else 'PASS')} |")

    lines += ["", "## 明细", ""]
    for r in results:
        lines += [f"### {r['pack']}", ""]
        for level in ("fail", "warn", "pass"):
            if r[level]:
                lines.append(f"**{level.upper()}**")
                lines += [f"- {x}" for x in r[level]]
                lines.append("")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    check_only = "--check" in sys.argv
    if not check_only:
        REPORT.write_text("\n".join(lines), encoding="utf-8")
    print(f"图谱结构校验：{len(results)} 个知识包 | FAIL {total_fail} | "
          + ("--check 模式（不写报告）" if check_only else f"报告 {REPORT.relative_to(ROOT)}"))
    for r in results:
        print(f"  {r['pack']}: FAIL={len(r['fail'])} WARN={len(r['warn'])} PASS={len(r['pass'])}")
    return 1 if total_fail else 0


if __name__ == "__main__":
    sys.exit(main())
