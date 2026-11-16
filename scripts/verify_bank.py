# -*- coding: utf-8 -*-
"""题库校验（P3 交付物补位：verify_all 一直挂着的 SKIP 从此关掉）。
对题库 JSON 数组断言：
  ① 规模：题数 ≥ --min（销账要求累计 ≥3 次作答，题库太小会反复曝光同一题）；
  ② 结构：id 唯一、kp_id/stem 非空、difficulty ∈ {1,2,3}；
  ③ 判分：choice 题 options ≥2 且 correct_index 落在选项内（判分红线不能靠运气）；
  ④ 可溯源：source 与 why 非空。
用法：python scripts/verify_bank.py <question_bank.json> [--min 100]
退出码：0 = 全绿；1 = 有缺口
"""
import json
import sys
from collections import Counter
from pathlib import Path


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("用法：python scripts/verify_bank.py <question_bank.json> [--min 100]")
        return 1
    path = Path(args[0])
    min_count = 100
    if "--min" in args:
        min_count = int(args[args.index("--min") + 1])
    if not path.exists():
        print(f"[BANK] 文件不存在：{path}")
        return 1
    try:
        qs = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"[BANK] 不是合法 JSON：{e}")
        return 1
    if not isinstance(qs, list):
        print("[BANK] 题库应为 JSON 数组")
        return 1

    problems = []
    if len(qs) < min_count:
        problems.append(f"题量不足：{len(qs)} < {min_count}")

    ids = set()
    kps = Counter()
    diffs = Counter()
    for i, q in enumerate(qs):
        tag = q.get("id") or f"#{i}"
        qid = q.get("id")
        if not qid:
            problems.append(f"{tag} 缺 id")
        elif qid in ids:
            problems.append(f"{tag} id 重复")
        ids.add(qid)
        if not str(q.get("kp_id") or "").strip():
            problems.append(f"{tag} 缺 kp_id")
        else:
            kps[q["kp_id"]] += 1
        if not str(q.get("stem") or "").strip():
            problems.append(f"{tag} 题干为空")
        d = q.get("difficulty")
        if d not in (1, 2, 3):
            problems.append(f"{tag} difficulty 非法：{d}")
        else:
            diffs[d] += 1
        if q.get("answer_kind") == "choice":
            opts = q.get("options") or []
            ci = q.get("correct_index")
            if len(opts) < 2:
                problems.append(f"{tag} 选项不足 2 个")
            if not isinstance(ci, int) or not (0 <= ci < len(opts)):
                problems.append(f"{tag} correct_index 越界：{ci}（选项 {len(opts)} 个）")
        if not str(q.get("source") or "").strip() or not str(q.get("why") or "").strip():
            problems.append(f"{tag} 缺 source/why（不可溯源）")

    if problems:
        print("[BANK]")
        for p in problems[:20]:
            print("  - " + p)
        if len(problems) > 20:
            print(f"  … 共 {len(problems)} 项")
        print(f"FAILED: {path.name} 校验未过（{len(problems)} 项）")
        return 1
    per_kp = sorted(kps.values())
    print(
        f"ALL GREEN · {path.name}：{len(qs)} 题 / {len(kps)} 知识点"
        f"（每点 {per_kp[0]}~{per_kp[-1]} 题），难度 "
        + " / ".join(f"{d}:{diffs[d]}" for d in sorted(diffs))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
