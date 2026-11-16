# -*- coding: utf-8 -*-
"""教材思维导图 → 运行时图包子集（A4：打通「教材 → 图包」最后一步）。

背景：教材侧已解析十余本教材并产出思维导图（kg-deep-test/*.mindmap.json），
运行时却只有手维护的 astralpath-v2 图包。本工具把「思维导图」一键转成
符合 graph-packs/README.md 规范的自描述内容包，让任何一本教材都能
产出可用图包，再由 verify_graph / verify_pack_manifest 两个门禁把关。

规则（确定性，产出可复现，回归金样逐字对拍）：
  · 节点：一级子节点 = 章节（kind=chapter, difficulty=2）；
          二级子节点 = 关键词（kind=keyword, difficulty=1），过滤后每章最多 8 个。
          过滤：长度≥2、去重（全书先到先得）、剔除 OCR 噪声词与停用词、
          剔除与章节标题重复的词。三级及更深不收（信噪比过低）。
  · 边：章节→其关键词（prerequisite, 0.7，why=章节包含关键词）；
        章节→后继章节（prerequisite, 0.6，why=后继章节）。
        边一律由 DFS 序小指向序大，天然无环。
  · id：按 DFS 序 M001 起；publishedAt 不参与金样对拍（日期会合理漂移）。

用法：
  python tools/mindmap_to_graphpack.py                       # 重生成回归金样包
  python tools/mindmap_to_graphpack.py --check               # 金样对拍（verify_all / CI）
  python tools/mindmap_to_graphpack.py <mindmap.json> --pack-id <id>   # 任意教材一键产包
退出码：0 = 成功/一致；1 = 失败/漂移
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 回归金样：源思维导图 → 产出目录（改这里就换金样）
GOLDEN = {
    "kg-deep-test/Kotlin编程实践.mindmap.json": "graph-packs/mindmap-kotlin",
}

# OCR 噪声词与停用词：只作用于关键词层，章节标题不过滤
NOISE = {
    "如图", "所示", "例如", "其中", "使用", "访问", "创建", "训练", "对象",
    "资源包", "综合练习", "编程训练", "语句", "方法", "注意", "说明", "总结",
    "the", "and", "of", "for", "in", "to", "a", "an", "is", "are", "with",
}
MAX_KEYWORDS_PER_CHAPTER = 8

PACK_TEMPLATE = {
    "schemaVersion": 1,
    "apiVersion": "1.0.0",
    "publishedAt": "2026-11-17T00:00:00Z",  # 金样对拍忽略此字段
}


def flatten(node, depth, out, book):
    """DFS 展平：记录 (深度, 标题, 父下标)；下标即 DFS 序。"""
    idx = len(out)
    out.append({"depth": depth, "title": str((node.get("data") or {}).get("text") or "").strip(), "parent": None})
    for child in node.get("children") or []:
        cidx = flatten(child, depth + 1, out, book)
        out[cidx]["parent"] = idx
    return idx


def is_noise(title, chapter_title):
    if len(title) < 2:
        return True
    if not re.search(r"[A-Za-z0-9\u4e00-\u9fff]", title):
        return True
    if title.lower() in NOISE or title in NOISE:
        return True
    if chapter_title and title in chapter_title:  # 与章节标题重复，信息量为零
        return True
    return False


def build(mindmap_path: Path):
    data = json.loads(mindmap_path.read_text(encoding="utf-8"))
    book = str((data.get("data") or {}).get("text") or mindmap_path.stem).strip()
    flat = []
    flatten(data, 0, flat, book)

    nodes, edges = [], []
    used_kw = set()
    chapter_ids = []
    for i, item in enumerate(flat):
        depth, title = item["depth"], item["title"]
        if not title or depth > 2:
            continue
        if depth == 1:
            nid = f"M{i:03d}"
            nodes.append({
                "kp_id": nid, "title": title, "course": book, "difficulty": 2,
                "kind": "chapter", "why": f"《{book}》思维导图章节", "ord": len(nodes) + 1,
            })
            chapter_ids.append((nid, i, title))
        elif depth == 2:
            parent = item["parent"]
            # 关键词挂在所属章节下：最近的、DFS 序更小的一级节点
            parent_chapter_id = None
            parent_chapter_title = ""
            for cid, cidx, ctitle in reversed(chapter_ids):
                if cidx < i:
                    parent_chapter_id, parent_chapter_title = cid, ctitle
                    break
            if parent_chapter_id is None or parent is None:
                continue
            if is_noise(title, parent_chapter_title):
                continue
            if title in used_kw:
                continue
            chapter_entry = next(n for n in nodes if n["kp_id"] == parent_chapter_id)
            same_chapter_kw = sum(
                1 for e in edges
                if e["from_kp"] == parent_chapter_id and e["why"] == "章节包含关键词"
            )
            if same_chapter_kw >= MAX_KEYWORDS_PER_CHAPTER:
                continue
            used_kw.add(title)
            nid = f"M{i:03d}"
            nodes.append({
                "kp_id": nid, "title": title, "course": book, "difficulty": 1,
                "kind": "keyword", "why": f"《{chapter_entry['title']}》关键词", "ord": len(nodes) + 1,
            })
            edges.append({
                "from_kp": parent_chapter_id, "to_kp": nid, "edge_type": "prerequisite",
                "weight": 0.7, "why": "章节包含关键词",
            })

    # 后继章节：按章节在 DFS 序上的先后连成链
    for (a, ia, _), (b, ib, _) in zip(chapter_ids, chapter_ids[1:]):
        if any(n["kp_id"] == a for n in nodes) and any(n["kp_id"] == b for n in nodes):
            edges.append({
                "from_kp": a, "to_kp": b, "edge_type": "prerequisite",
                "weight": 0.6, "why": "后继章节",
            })

    graph = {"packId": None, "courses": [book], "nodes": nodes, "edges": edges}
    return graph


def pack_manifest(pack_id, name, course, graph):
    m = dict(PACK_TEMPLATE)
    m.update({
        "packId": pack_id,
        "name": name,
        "courseScope": [course],
        "entries": [{
            "file": "graph_pack.json", "kind": "graph",
            "nodes": len(graph["nodes"]), "edges": len(graph["edges"]),
            "nodeKey": "kp_id", "edgeFrom": "from_kp", "edgeTo": "to_kp",
        }],
    })
    return m


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, indent=2) + "\n"


def generate(mindmap_path: Path, pack_id: str, out_dir: Path, write: bool):
    graph = build(mindmap_path)
    graph["packId"] = pack_id
    course = graph["courses"][0]
    manifest = pack_manifest(pack_id, f"《{course}》思维导图自动图包", course, graph)
    files = {"pack.json": manifest, "graph_pack.json": graph}
    if write:
        out_dir.mkdir(parents=True, exist_ok=True)
        for fname, obj in files.items():
            (out_dir / fname).write_text(dump(obj), encoding="utf-8")
    return files


def check_golden() -> int:
    drift = []
    for src, out in GOLDEN.items():
        src_path = ROOT / src
        out_dir = ROOT / out
        if not src_path.exists():
            drift.append(f"{src} 源文件缺失")
            continue
        fresh = generate(src_path, out_dir.name, out_dir, write=False)
        for fname, obj in fresh.items():
            committed_path = out_dir / fname
            if not committed_path.exists():
                drift.append(f"{out}/{fname} 未提交（先跑生成模式）")
                continue
            committed = json.loads(committed_path.read_text(encoding="utf-8"))
            if fname == "pack.json":
                committed.pop("publishedAt", None)
                obj = dict(obj)
                obj.pop("publishedAt", None)
            if committed != obj:
                drift.append(f"{out}/{fname} 与源不同步（跑 `python tools/mindmap_to_graphpack.py` 重生成）")
    if drift:
        print("[MINDMAP-PACK]")
        for d in drift:
            print("  - " + d)
        print("FAILED: 教材→图包金样漂移")
        return 1
    print(f"ALL GREEN · 教材→图包金样与 {len(GOLDEN)} 个源思维导图逐字一致")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if "--check" in args:
        return check_golden()
    if not args:
        # 无参 = 重生成全部金样包
        for src, out in GOLDEN.items():
            files = generate(ROOT / src, Path(out).name, ROOT / out, write=True)
            g = files["graph_pack.json"]
            print(f"generated · {out}（{len(g['nodes'])} 节点 {len(g['edges'])} 边）")
        return 0
    src = Path(args[0])
    if not src.exists():
        print(f"[MINDMAP-PACK] 源文件不存在：{src}")
        return 1
    pack_id = None
    if "--pack-id" in args:
        pack_id = args[args.index("--pack-id") + 1]
    else:
        pack_id = "mindmap-" + re.sub(r"[^a-z0-9]+", "-", src.stem.lower()).strip("-")[:24]
    out_dir = ROOT / "graph-packs" / pack_id
    files = generate(src, pack_id, out_dir, write=True)
    g = files["graph_pack.json"]
    print(f"generated · graph-packs/{pack_id}（{len(g['nodes'])} 节点 {len(g['edges'])} 边）")
    print("下一步：python scripts/verify_graph.py " + str(out_dir / "graph_pack.json").replace(str(ROOT) + "\\", "")
          + " && python scripts/verify_pack_manifest.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
