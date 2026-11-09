# -*- coding: utf-8 -*-
"""CSS token 完整性门禁（contract ④）：
  ① :root 内不得出现 --x:var(--x) 自引用（rebase/合并曾把整段 token 定义搞成循环引用，
     浏览器视其为非法→整套主题色静默失效，sloplint 的字面量门禁检测不到）；
  ② :root 内不得出现拼接损坏（如 var(--surface)4d6）；
  ③ 页面 :root 里被引用的每个 var(--x) 必须在 :root 有定义（防"用了没定义"）。
用法：python scripts/verify_tokens.py    退出码 0=全绿 1=违约
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "deploy" / "monolith-web" / "index.html"


def main() -> int:
    s = TARGET.read_text(encoding="utf-8")
    m = re.search(r":root\{([^}]*)\}", s)
    if not m:
        print("[TOKEN] 找不到 :root")
        return 1
    body = m.group(1)
    defined = set(re.findall(r"(--[\w-]+)\s*:", body))

    problems = []
    # ① 自引用
    for d in defined:
        if re.search(r"--[\w-]+\s*:\s*var\(\s*" + re.escape(d) + r"\s*\)", body):
            problems.append(f":root 自引用：{d}")
    # ② 拼接损坏：值里出现 var(...) 与其他字符直接相连（如 var(--surface)4d6）
    for v in re.findall(r":\s*([^;\n]+)", body):
        if "var(" in v and re.search(r"var\([^)]*\)[^;\s]", v):
            problems.append(f":root 拼接损坏：{v.strip()}")
    # ③ 引用完整性：页面里用到的 var(--x) 是否都有定义
    used = set(re.findall(r"var\((--[\w-]+)", s))
    undefined = sorted(u for u in used if u not in defined)
    for u in undefined:
        problems.append(f"引用了未定义的 token：{u}")

    if problems:
        print("[TOKEN]")
        for p in problems:
            print("  - " + p)
        print("FAILED: CSS token 完整性违约")
        return 1
    print(f"ALL GREEN · token 完整性（定义 {len(defined)} 个，引用 {len(used)} 个，无自引用/拼接损坏/未定义引用）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
