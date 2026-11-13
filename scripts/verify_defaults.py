# -*- coding: utf-8 -*-
"""默认配置单一来源门禁（借鉴 SidebarDiagnostics 的「默认值并集合并」迁移）。

检查：
  ① shared/store.js 导出 DEFAULTS 与 withDefaults
  ② 页面 defaultState() 与 migrate() 都走 APStore.withDefaults（不手列默认值）
  ③ 页面不再出现逐字段默认值清单（防回潮；activeBookId 之类业务回填不算）
  ④ DEFAULTS 覆盖页面直接消费的关键键

用法：python scripts/verify_defaults.py      退出码 0=全绿 1=有缺口
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "shared" / "store.js"
PAGE = ROOT / "deploy" / "monolith-web" / "index.html"
problems = []

# 曾经手列的默认值清单特征（这些字段现在都归 DEFAULTS 管）
LEGACY_DEFAULT_FIELDS = [
    "mastery", "sale", "logs", "debtExplain", "papers",
    "chatLog", "kgMode", "onboard", "planOverrides", "autoLast", "dnd",
]


def fail(msg):
    problems.append(msg)


def main():
    if not STORE.exists() or not PAGE.exists():
        print("FAILED：缺 shared/store.js 或 index.html")
        return 1
    st = STORE.read_text(encoding="utf-8", errors="replace")
    pg = PAGE.read_text(encoding="utf-8", errors="replace")

    # ① 单一表 + 合并函数 + 导出
    if "var DEFAULTS = {" not in st:
        fail("shared/store.js 缺 DEFAULTS 单一默认值表")
    if "function withDefaults(raw)" not in st:
        fail("shared/store.js 缺 withDefaults 并集合并函数")
    if "DEFAULTS: DEFAULTS" not in st or "withDefaults: withDefaults" not in st:
        fail("DEFAULTS / withDefaults 未导出（页面无法使用）")
    print("  OK  单一表与导出       DEFAULTS / withDefaults 齐备")

    # ② 页面两处都走单一来源
    if not re.search(r"function defaultState\(\)[\s\S]{0,400}APStore\.withDefaults\(", pg):
        fail("页面 defaultState() 未走 APStore.withDefaults")
    if not re.search(r"function migrate\([\s\S]{0,700}APStore\.withDefaults\(raw\)", pg):
        fail("页面 migrate() 未走 APStore.withDefaults")
    print("  OK  页面接线           defaultState 与 migrate 均引用 withDefaults")

    # ③ 防回潮：只针对曾经的默认值字段清单，不误伤 activeBookId 等业务回填
    legacy = [f for f in LEGACY_DEFAULT_FIELDS
              if re.search(r"if\(!raw\." + f + r"\)raw\." + f + r"\s*=", pg)]
    if legacy:
        fail(f"页面残留手写逐字段默认值清单：{legacy}（新增字段请改 DEFAULTS）")
    else:
        print("  OK  防回潮             无手写默认值清单")

    # ④ 关键键抽样（页面逻辑直接消费，必须有默认值）
    keys = ["consent", "optOut", "day", "dnd", "kgMode", "onboard", "autoLast", "papers", "chatLog"]
    missing = [k for k in keys if not re.search(r"\b" + k + r"\s*:", st)]
    if missing:
        fail(f"DEFAULTS 缺关键键：{missing}")
    else:
        print(f"  OK  关键键覆盖          {len(keys)} 个抽样键齐备")

    print()
    if problems:
        print(f"默认配置单一来源 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("默认配置单一来源 ALL GREEN · DEFAULTS 是唯一出处，新增字段零迁移脚本")
    return 0


if __name__ == "__main__":
    sys.exit(main())
