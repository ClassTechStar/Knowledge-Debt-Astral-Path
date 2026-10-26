# -*- coding: utf-8 -*-
"""内容包清单校验（规范见 graph-packs/README.md）。
每个 graph-packs/<id>/ 目录若带 pack.json，则校验：
  必填字段 / apiVersion 形如 semver / 目录名一致 /
  entries 声明的文件存在、计数一致、图数据无悬空边。
不带 pack.json 的目录视为历史遗留包：跳过并列出提示（版本宽限期，不判红）。
用法：python scripts/verify_pack_manifest.py
退出码：0 = 全绿；1 = 有包校验失败
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / "graph-packs"
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
REQUIRED = ["packId", "name", "schemaVersion", "apiVersion", "courseScope", "publishedAt", "entries"]


def fail(msgs, pack, msg):
    msgs.append(f"[{pack}] {msg}")


def load_json(path, msgs, pack):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        fail(msgs, pack, f"{path.name} 不是合法 JSON：{e}")
        return None


def check_entry(pack_dir, pack_id, entry, msgs):
    kind = entry.get("kind")
    f = entry.get("file")
    if not f or kind not in ("graph", "nodes", "edges"):
        fail(msgs, pack_id, f"entry 缺 file/kind 或 kind 非法：{entry}")
        return
    data = load_json(pack_dir / f, msgs, pack_id)
    if data is None:
        return
    if not isinstance(data, list) and kind != "graph":
        fail(msgs, pack_id, f"{f} 应为数组")
        return
    if kind == "graph":
        if not isinstance(data, dict):
            fail(msgs, pack_id, f"{f} 应为对象（含 nodes/edges）")
            return
        nodes, edges = data.get("nodes") or [], data.get("edges") or []
        if len(nodes) != entry.get("nodes"):
            fail(msgs, pack_id, f"{f} 节点数 {len(nodes)} ≠ 声明 {entry.get('nodes')}")
        if len(edges) != entry.get("edges"):
            fail(msgs, pack_id, f"{f} 边数 {len(edges)} ≠ 声明 {entry.get('edges')}")
        nk = entry.get("nodeKey") or "kp_id"
        ids = {n.get(nk) for n in nodes}
        ek_from, ek_to = entry.get("edgeFrom") or "from_kp", entry.get("edgeTo") or "to_kp"
        dangling = [e for e in edges if e.get(ek_from) not in ids or e.get(ek_to) not in ids]
        if dangling:
            fail(msgs, pack_id, f"{f} 有 {len(dangling)} 条悬空边，如 {dangling[0]}")
    elif kind == "nodes":
        if len(data) != entry.get("count"):
            fail(msgs, pack_id, f"{f} 节点数 {len(data)} ≠ 声明 {entry.get('count')}")
    elif kind == "edges":
        if len(data) != entry.get("count"):
            fail(msgs, pack_id, f"{f} 边数 {len(data)} ≠ 声明 {entry.get('count')}")


def main() -> int:
    if not PACKS.exists():
        print("[PACK] graph-packs/ 不存在")
        return 1
    problems, legacy = [], []
    for d in sorted(p for p in PACKS.iterdir() if p.is_dir()):
        manifest = d / "pack.json"
        if not manifest.exists():
            legacy.append(d.name)
            continue
        m = load_json(manifest, problems, d.name)
        if m is None:
            continue
        for k in REQUIRED:
            if k not in m:
                fail(problems, d.name, f"缺必填字段 {k}")
        if m.get("packId") != d.name:
            fail(problems, d.name, f"packId={m.get('packId')} 与目录名不一致")
        if not SEMVER.match(str(m.get("apiVersion", ""))):
            fail(problems, d.name, f"apiVersion 非法：{m.get('apiVersion')}")
        for e in m.get("entries") or []:
            check_entry(d, d.name, e, problems)

    if legacy:
        print("[PACK] 历史遗留包（无 pack.json，宽限期内跳过）：" + "、".join(legacy))
    if problems:
        print("[PACK]")
        for p in problems:
            print("  - " + p)
        print(f"FAILED: 内容包校验未过")
        return 1
    print("ALL GREEN · 内容包清单与数据一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
