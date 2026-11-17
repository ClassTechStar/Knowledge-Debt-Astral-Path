# -*- coding: utf-8 -*-
"""OCR 质量度量工具：行级 CER + 结构正确率 + 错误分桶入口。

设计原则（与项目红线一致）：
  - 只用标准库，零依赖、确定性、可进 CI；
  - 不凭空编造 CER 数字——没有标注语料时只校验框架与格式，
    阈值默认 1.0（即"不设基线"），等真实金样积累后再下调；
  - 度量分两层：行级 CER 评 OCR 本身，结构正确率评题号/题干归属
    （识别对但切错题 = 白识别，这是本项目的最终产物形态决定的）。

用法：
  python scripts/ocr_quality.py --check                    # 校验金样清单格式
  python scripts/ocr_quality.py --report                   # 输出当前 CER/结构报告
  python scripts/ocr_quality.py --pair REF_FILE HYP_FILE   # 单对文本算 CER
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "contracts" / "golden" / "ocr" / "samples.json"


def normalize(text):
    """统一空白、全半角标点，避免格式差异被误算成识别错误。"""
    t = str(text or "").replace("\r\n", "\n").replace("\r", "\n")
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()


def edit_distance(a, b):
    """Levenshtein 距离（滚动数组，O(min(n,m)) 空间）。"""
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
        prev = cur
    return prev[len(b)]


def cer(ref, hyp):
    """字符错误率 = 编辑距离 / 参考长度；参考为空时按 0/1 处理。"""
    r, h = normalize(ref), normalize(hyp)
    if not r:
        return 0.0 if not h else 1.0
    return round(edit_distance(r, h) / len(r), 6)


def structure_accuracy(ref_items, hyp_items):
    """结构正确率：题号对齐 + 题干归属；两边都是 [{no, stem}, ...]。"""
    if not ref_items:
        return 0.0
    rmap = {str(x.get("no", "")).strip(): str(x.get("stem", "")).strip() for x in ref_items}
    hmap = {str(x.get("no", "")).strip(): str(x.get("stem", "")).strip() for x in hyp_items}
    hit = 0
    for no, stem in rmap.items():
        if no in hmap and normalize(hmap[no]) == normalize(stem):
            hit += 1
    return round(hit / len(rmap), 6)


def load_samples():
    if not GOLDEN.exists():
        return None, f"缺金样清单：{GOLDEN.relative_to(ROOT).as_posix()}"
    try:
        data = json.loads(GOLDEN.read_text(encoding="utf-8"))
    except Exception as e:
        return None, f"金样解析失败：{e}"
    if not isinstance(data, dict) or not isinstance(data.get("samples"), list):
        return None, "金样清单应为 {\"schemaVersion\":1, \"samples\":[...]}"
    for i, s in enumerate(data["samples"]):
        for k in ("id", "scene", "refText"):
            if k not in s:
                return None, f"第 {i+1} 条样本缺字段 {k}"
    return data, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--pair", nargs=2, metavar=("REF", "HYP"))
    args = ap.parse_args()

    if args.pair:
        ref, hyp = [Path(p).read_text(encoding="utf-8", errors="replace") for p in args.pair]
        print(f"CER = {cer(ref, hyp):.6f}")
        return 0

    data, err = load_samples()
    if err:
        print(f"FAILED: {err}")
        return 1
    samples = data["samples"]
    print(f"金样清单：{len(samples)} 条，schemaVersion={data.get('schemaVersion')}")

    if args.check:
        bad = [s["id"] for s in samples if not str(s.get("refText", "")).strip()]
        if bad:
            print(f"FAILED: refText 为空的样本：{bad}")
            return 1
        print("格式校验 ALL GREEN（注意：格式正确不等于语料充足，目标 50~100 条四类场景）")
        return 0

    if args.report:
        rows = []
        for s in samples:
            hyp = s.get("hypText")
            if hyp is None:
                rows.append((s["id"], s["scene"], None, None))
                continue
            rows.append((s["id"], s["scene"], cer(s["refText"], hyp),
                         structure_accuracy(s.get("refItems", []), s.get("hypItems", []))))
        for sid, scene, c, sa in rows:
            cs = "未测" if c is None else f"{c:.4f}"
            sas = "未测" if sa is None else f"{sa:.4f}"
            print(f"  {sid:12s} {scene:16s} CER={cs:7s} 结构={sas}")
        tested = [r for r in rows if r[2] is not None]
        if not tested:
            print("\n尚无 hypText 实测值——框架就位，不编造质量数字。")
            print("按参考方案下一步：标注 50~100 张四类场景语料，填入 refText/hypText 后重跑。")
        else:
            avg = sum(r[2] for r in tested) / len(tested)
            limit = float(data.get("cerLimit", 1.0))
            print(f"\n平均 CER={avg:.6f}，阈值={limit}（{'通过' if avg <= limit else '回退'}）")
            return 0 if avg <= limit else 1
        return 0

    print("请指定 --check / --report / --pair REF HYP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
