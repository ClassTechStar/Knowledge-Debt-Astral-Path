# -*- coding: utf-8 -*-
"""威胁模型活文档门禁（借鉴 VeriRandom「威胁模型随代码同提交演进」的契约，
适配为可自动校验的形式：文档不是写完就烂，而是有门禁盯着）。

为什么需要：威胁模型最常见的死法是「写得漂亮，然后和代码各走各的」。本脚本
只校验三件机器可判的事，其余交给 review：
  ① 状态图例齐全（五个标记，且不用表情符号——本仓库文档口径）
  ② 攻击面表格里引用的文件路径真实存在（防线写错位置等于没有防线）
  ③ 变更记录带日期，且条目有「影响条目」列

用法：python scripts/verify_threat_model.py      退出码 0=全绿 1=不可用
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "THREAT_MODEL.md"
problems = []
LEGENDS = ["已覆盖", "部分", "未覆盖", "不可证", "非本软件责任"]


def fail(msg):
    problems.append(msg)


def main():
    if not DOC.exists():
        print("FAILED：缺少 THREAT_MODEL.md")
        return 1
    text = DOC.read_text(encoding="utf-8", errors="replace")

    # ① 状态图例五个标记齐全，且不在表格里使用表情符号（项目文档口径「去 AI 味」）
    for legend in LEGENDS:
        if legend not in text:
            fail(f"状态图例缺少「{legend}」")
    # 表情符号哨兵：出现 ✅ 🟡 ❌ ⛔ ⚪ 之类说明图例被改回了 emoji 风格
    if re.search(r"[\u2705\u274C\u26AA\u2B1C\u26D4]", text):
        fail("威胁模型出现了表情符号状态标记；本仓库文档口径要求用文字标记（已覆盖/部分/未覆盖/不可证/非本软件责任）")
    print(f"  OK  状态图例           五档齐全且为文字标记")

    # ② 攻击面表格里「当前防线」列引用的文件路径必须真实存在
    #    形如 `shared/safe-dom.js:35`、`src/.../Foo.cs`、`scripts/verify_xss.py`
    refs = set()
    for m in re.finditer(r"`([A-Za-z0-9_./-]+\.(?:js|ts|ets|kt|cs|py|ps1|json|yml|yaml|props|csproj|md|iss))(?::\d+)?`", text):
        refs.add(m.group(1))
    missing = []
    for r in sorted(refs):
        # 门禁脚本、源码、配置都按相对仓库根解析
        if not (ROOT / r).exists():
            missing.append(r)
    if missing:
        for r in missing:
            fail(f"威胁模型引用了不存在的路径：{r}（防线位置必须真实）")
    else:
        print(f"  OK  证据路径           {len(refs)} 处引用全部存在")

    # ③ 变更记录必须带日期，且每行三列（日期/变更/影响条目）
    if "## 6. 变更记录" not in text:
        fail("缺少 §6 变更记录")
    else:
        section = text.split("## 6. 变更记录", 1)[1]
        rows = [ln for ln in section.splitlines() if ln.startswith("| 20")]
        if not rows:
            fail("§6 变更记录没有带日期的行（格式：| 2026-11-11 | 变更 | 影响条目 |）")
        else:
            bad = [ln for ln in rows if not re.match(r"^\|\s*20\d\d-\d\d-\d\d\s*\|.*\|.*\|", ln)]
            if bad:
                fail(f"§6 变更记录有 {len(bad)} 行缺列（需 日期 | 变更 | 影响条目 三列）")
            else:
                print(f"  OK  变更记录           {len(rows)} 条均带日期与影响条目")

    # ④ 维护契约必须在场（改验证逻辑同提交更新的约束）
    if "同一次" not in text and "同提交" not in text:
        fail("缺少「同一次改动/同提交更新」的维护契约表述")
    else:
        print(f"  OK  维护契约           同提交更新约束在场")

    print()
    if problems:
        print(f"威胁模型文档 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("威胁模型文档 ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
