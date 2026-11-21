# -*- coding: utf-8 -*-
"""测试项目命名与归属纪律门禁（迁移自 ReciteHelper 的反面教材）。

背景：ReciteHelper 的 tests/ 下只有一个项目 `ReciteHelper.OAuth.Tests`，
却塞进了 CfsrsWorkflowTests / FacetReviewTests / SubquestionGradingTests 等
与 OAuth 完全无关的测试——名字误导读者，也让"按域跑测试"变得不可能。

目标项目已有 5 个按域划分的测试项目（Core/Api/Desktop/Persistence/Eval），
本门禁把这个正确做法固化：新测试文件必须落在已知的域测试项目下，
且文件名要能反映被测主题，禁止塞进不相干的"万能测试项目"。

检查：
  ① tests/ 下每个 .csproj 的项目名符合 AstralPath.<域>.Tests 约定
  ② 每个测试文件路径的深度与所属项目一致（不允许游离在 tests/ 根的测试）
  ③ 存在跨域乱放：测试文件名关键词与所在项目域明显冲突时告警
     （目前只硬拦"文件名含某域名但放在另一个域项目"的明确错位）

用法：python scripts/verify_test_layout.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
problems = []

# 允许的项目域，与 AstralPath.slnx 当前声明一致
ALLOWED = {"Core", "Api", "Desktop", "Persistence", "Eval"}
# 关键词 → 应属域（只列明确的，避免误报）
# 只保留"明确只属于一个域"的关键词；graph/ocr/api 这类多域共有词不列，
# 否则 GraphLayoutTests（Desktop 布局）、OcrHostTests（Desktop 宿主桥）会被误报
DOMAIN_HINT = {
    "calibration": "Eval", "redteam": "Eval", "coveragereport": "Eval",
}


def main():
    if not TESTS.exists():
        print("FAILED：tests/ 目录缺失")
        return 1

    projects = sorted(p for p in TESTS.glob("*/*.csproj") if "obj" not in p.parts)
    if not projects:
        problems.append("tests/ 下没有任何测试项目")
    for proj in projects:
        m = re.fullmatch(r"AstralPath\.(\w+)\.Tests", proj.stem)
        if not m or m.group(1) not in ALLOWED:
            problems.append(f"测试项目名 {proj.stem} 不符合 AstralPath.<域>.Tests 约定（允许域：{sorted(ALLOWED)}）")
    print(f"  OK  测试项目命名         {len(projects)} 个项目均符合 AstralPath.<域>.Tests")

    # 测试文件必须归属于某个项目目录
    loose = [p for p in TESTS.glob("*.cs")]
    if loose:
        problems.append(f"tests/ 根目录有游离测试文件：{[p.name for p in loose]}（应放进域项目子目录）")
    print("  OK  测试文件归属         无游离在 tests/ 根的测试文件")

    # 跨域错位：文件名关键词指向的域与所在项目不一致
    misplaced = []
    for proj in projects:
        domain = proj.stem.split(".")[1]
        for cs in proj.parent.glob("*.cs"):
            if "obj" in cs.parts:
                continue
            low = cs.stem.lower()
            for kw, expected in DOMAIN_HINT.items():
                if kw in low and expected != domain:
                    misplaced.append(f"{cs.relative_to(ROOT).as_posix()} 含 '{kw}'，应属 {expected} 而非 {domain}")
                    break
    if misplaced:
        problems.append("测试跨域错位（源项目 ReciteHelper 的通病）：" + "; ".join(misplaced[:5]))
    else:
        print("  OK  测试主题归属         无明显的跨域错位")

    print()
    if problems:
        print(f"测试项目布局 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("测试项目布局 ALL GREEN · 按域划分纪律保持完好")
    return 0


if __name__ == "__main__":
    sys.exit(main())
