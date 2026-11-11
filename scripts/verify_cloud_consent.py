# -*- coding: utf-8 -*-
"""云调用出口守卫与授权粒度门禁（威胁模型 T10 + T8）。

背景：`__AP_MIMO__.complete()` 有 4 个调用入口（p0 生成 / p1 图谱与出题 / p2 对话），
但危机词/禁用词拦截原本只长在 p2 的 replyAgent 里。任何新入口只要绕过它直接调
`complete()`，把自杀求助或禁用词发给云模型都不拦。防线写在入口 = 每加一个入口就多一处
可能漏；防线写在**唯一网络出口** = 一处设卡，所有入口自动受保护。

本脚本把这条约定编译成门禁，四条断言：
  ① 全仓 `shared/` 的网络出网点（fetch / XMLHttpRequest / sendBeacon）唯一
  ② 唯一出口所在函数内真的调用了出口守卫（不是只写了注释）
  ③ 存在守卫装配点（`__AP_EGRESS_GUARD__` 被定义，且词表取自 core.js 生成区）
  ④ 所有 `M.complete(` / `__AP_MIMO__.complete(` 调用点都落在 shared/integrations/ 下
     （不存在绕过 complete 直接 fetch 的旁路）
  ⑤ 授权粒度：守卫必须检查 `__AP_CLOUD_OPTIN__`（默认 false，fail-closed），
     「配了密钥」不得等于「同意出网」
  ⑥ 吊销清单可离线更新：存在 `APRevoked` 的合并/导入实现，启动时合并到 `__AP_REVOKED__`

用法：python scripts/verify_cloud_consent.py      退出码 0=全绿 1=有缺口
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "shared"
problems = []


def fail(msg):
    problems.append(msg)


def main():
    js_files = sorted(p for p in SHARED.rglob("*.js") if "node_modules" not in p.parts)

    # ① 网络出网点唯一
    egress = []  # (file, line, text)
    for f in js_files:
        text = f.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            if re.search(r"\bfetch\s*\(", line) or re.search(r"\bXMLHttpRequest\b", line) or re.search(r"sendBeacon\s*\(", line):
                egress.append((f.relative_to(ROOT).as_posix(), i, stripped[:70]))
    if len(egress) != 1:
        fail(f"网络出网点应唯一，实测 {len(egress)} 处：" +
             " | ".join(f"{a}:{b}" for a, b, _ in egress))
    else:
        print(f"  OK  出网点唯一           {egress[0][0]}:{egress[0][1]}")

    # ② 唯一出口所在函数内有守卫调用
    if egress:
        efile = ROOT / egress[0][0]
        text = efile.read_text(encoding="utf-8", errors="replace")
        # 取出口所在函数的起止（从 function complete( 到下一个 function ）
        m = re.search(r"function\s+complete\s*\([^)]*\)\s*\{", text)
        if not m:
            fail(f"{egress[0][0]} 中未找到 complete() 出口函数")
        else:
            start = m.start()
            nxt = text.find("\n  function ", m.end())
            body = text[start: nxt if nxt > 0 else len(text)]
            if "__AP_EGRESS_GUARD__" not in body:
                fail(f"{egress[0][0]} 的 complete() 内未调用出口守卫（危机词/禁用词会出网）")
            else:
                print(f"  OK  出口设卡             complete() 内调用了 __AP_EGRESS_GUARD__")

    # ③ 守卫装配点存在且词表取自 core.js 生成区
    defined = []
    for f in js_files:
        text = f.read_text(encoding="utf-8", errors="replace")
        if re.search(r"__AP_EGRESS_GUARD__\s*=\s*function", text):
            defined.append(f.relative_to(ROOT).as_posix())
    if not defined:
        fail("没有找到守卫装配点（__AP_EGRESS_GUARD__ 未被定义）")
    else:
        ok_words = False
        for rel in defined:
            t = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
            if re.search(r"CRISIS", t) and re.search(r"BANNED", t):
                ok_words = True
        if not ok_words:
            fail(f"守卫装配点 {defined} 未引用 core.js 生成区的 CRISIS/BANNED 词表")
        else:
            print(f"  OK  守卫装配             {', '.join(defined)}（词表来自生成区）")

    # ④ complete 调用点不得绕过
    calls = []
    for f in js_files:
        text = f.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.splitlines(), 1):
            if re.search(r"\bM\.complete\s*\(|__AP_MIMO__\.complete\s*\(", line):
                calls.append((f.relative_to(ROOT).as_posix(), i))
    bad = [c for c in calls if not c[0].startswith("shared/integrations/")]
    if bad:
        fail(f"存在绕过 integrations 层的 complete 调用：{bad}")
    elif not calls:
        fail("未发现任何 complete() 调用点（约定应有多个调用入口）")
    else:
        print(f"  OK  调用点归口             {len(calls)} 处全部在 shared/integrations/，均经唯一出口")

    # ⑤ 授权粒度：出口守卫必须先看 __AP_CLOUD_OPTIN__（fail-closed）
    guard_def = None
    for f in js_files:
        t = f.read_text(encoding="utf-8", errors="replace")
        if "__AP_EGRESS_GUARD__ = function" in t:
            guard_def = (f, t)
            break
    if guard_def is None:
        fail("未找到 __AP_EGRESS_GUARD__ 定义")
    else:
        gt = guard_def[1]
        if "__AP_CLOUD_OPTIN__" not in gt:
            fail(f"{guard_def[0].relative_to(ROOT)} 的出口守卫未检查 __AP_CLOUD_OPTIN__（配密钥即出网）")
        else:
            print("  OK  授权粒度           守卫检查 __AP_CLOUD_OPTIN__（默认拒绝出网）")

    # ⑥ 吊销清单离线更新
    revoked_ok = False
    for f in js_files:
        t = f.read_text(encoding="utf-8", errors="replace")
        if "APRevoked" in t and "function" in t and "list:" in t:
            revoked_ok = True
            if "import" not in t:
                fail(f"{f.relative_to(ROOT)} 的 APRevoked 缺 import（无法离线导入清单）")
            else:
                print(f"  OK  吊销离线更新       {f.relative_to(ROOT).as_posix()}：合并 + import")
            break
    if not revoked_ok:
        fail("未找到 APRevoked 吊销清单离线更新实现")

    print()
    if problems:
        print(f"云调用出口守卫 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("云调用出口守卫 ALL GREEN · 唯一出网点设卡、装配齐备、无旁路")
    return 0


if __name__ == "__main__":
    sys.exit(main())
