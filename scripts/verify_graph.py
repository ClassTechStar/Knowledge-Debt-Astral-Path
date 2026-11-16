# -*- coding: utf-8 -*-
"""图数据校验（P3 交付物补位：verify_all 一直挂着的 SKIP 从此关掉）。
对单个 graph_pack.json 断言：
  ① 结构：nodes/edges 数组、节点 id 唯一、标题与 why 非空；
  ② 边：端点存在、无重复边（from,to,type）、edge_type 合法、weight > 0、why 非空；
  ③ 拓扑：全图无环（含 transfer_gap——环会让「先修路径」自相矛盾）。
用法：python scripts/verify_graph.py <graph_pack.json>
退出码：0 = 全绿；1 = 有缺口
"""
import json
import sys
from collections import defaultdict, deque
from pathlib import Path

VALID_TYPES = {"prerequisite", "transfer_gap"}
MIN_NODES = 3


def main() -> int:
    if len(sys.argv) < 2:
        print("用法：python scripts/verify_graph.py <graph_pack.json>")
        return 1
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"[GRAPH] 文件不存在：{path}")
        return 1
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"[GRAPH] 不是合法 JSON：{e}")
        return 1

    problems = []
    nodes = data.get("nodes") or []
    edges = data.get("edges") or []
    if len(nodes) < MIN_NODES:
        problems.append(f"节点过少：{len(nodes)} < {MIN_NODES}")
    if not edges:
        problems.append("没有任何边")

    ids = {}
    for n in nodes:
        nid = n.get("kp_id")
        if not nid:
            problems.append(f"节点缺 kp_id：{n}")
            continue
        if nid in ids:
            problems.append(f"节点 id 重复：{nid}")
        ids[nid] = n
        if not str(n.get("title") or "").strip():
            problems.append(f"节点 {nid} 标题为空")
        if not str(n.get("why") or "").strip():
            problems.append(f"节点 {nid} 缺 why（可溯源）")

    seen = set()
    adj = defaultdict(list)
    indeg = defaultdict(int)
    for e in edges:
        f, t = e.get("from_kp"), e.get("to_kp")
        key = (f, t, e.get("edge_type"))
        if f not in ids or t not in ids:
            problems.append(f"悬空边：{f} -> {t}")
            continue
        if f == t:
            problems.append(f"自环：{f}")
        if key in seen:
            problems.append(f"重复边：{f} -> {t} ({e.get('edge_type')})")
        seen.add(key)
        if e.get("edge_type") not in VALID_TYPES:
            problems.append(f"edge_type 非法：{e.get('edge_type')}（{f}->{t}）")
        if not (e.get("weight") or 0) > 0:
            problems.append(f"weight 非正：{f}->{t} = {e.get('weight')}")
        if not str(e.get("why") or "").strip():
            problems.append(f"边缺 why（可溯源）：{f}->{t}")
        adj[f].append(t)
        indeg[t] += 1

    # ③ 拓扑：Kahn 拓扑排序，剩下没消化的就是环上的节点
    q = deque([n for n in ids if indeg[n] == 0])
    seen_n = 0
    while q:
        u = q.popleft()
        seen_n += 1
        for v in adj[u]:
            indeg[v] -= 1
            if indeg[v] == 0:
                q.append(v)
    if seen_n != len(ids):
        cyclic = sorted(n for n in ids if indeg[n] > 0)
        problems.append(f"图中有环，涉及节点：{cyclic[:8]}")

    if problems:
        print("[GRAPH]")
        for p in problems:
            print("  - " + p)
        print(f"FAILED: {path.name} 校验未过（{len(problems)} 项）")
        return 1
    print(f"ALL GREEN · {path.name}：{len(ids)} 节点 {len(edges)} 边，无环 / 无悬空 / 无重复 / 可溯源")
    return 0


if __name__ == "__main__":
    sys.exit(main())
