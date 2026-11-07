# -*- coding: utf-8 -*-
"""C# 分层架构门禁（思想来自 DeepTutor 的 import-linter 契约：分层规则写成测试，不许烂）。

三条契约：
  ① Core 纯净：src/AstralPath.Core 不允许引用表现层/宿主/持久化框架
     （AspNetCore / WinForms / WebView2 / Avalonia / EFCore / JsonDB），也不允许引用 Api*。
  ② Api 不下探宿主：src/AstralPath.Api / Api.Core 不引用 WinForms / WebView2 / Avalonia。
  ③ 壳不做业务：src/AstralPath.Desktop / Monolith / Native 的 C# 文件不允许出现
     score/impact/sale 公式计算与计划排程（业务只许调 Core）。

扫描两个层面：csproj 的 ProjectReference 图 + .cs 源码的 using 命名空间。
用法：python scripts/verify_architecture.py        退出码 0=全绿 1=违约
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# 契约①：Core 禁止的引用（csproj 项目名 / using 命名空间前缀）
CORE_FORBID_PROJ = ["Api", "Api.Core", "Desktop", "Monolith", "Native", "Shared", "Persistence", "Infrastructure", "Graph"]
CORE_FORBID_NS = ["Microsoft.AspNetCore", "System.Windows.Forms", "Microsoft.Web.WebView2", "Avalonia",
                  "Microsoft.EntityFrameworkCore", "Npgsql", "Microsoft.Data.Sqlite"]
# 契约②：API 层禁止的宿主命名空间
API_FORBID_NS = ["System.Windows.Forms", "Microsoft.Web.WebView2", "Avalonia"]
# 契约③：壳内禁止出现的业务计算痕迹（公式/排程关键词，壳里只许调 Core）
SHELL_BIZ_PATTERNS = ["impactV2", "scoreV2", "saleStep", "saleStreak", "checkPlanK", "reliefDays", "spacingOffsets"]

problems = []


def fail(msg):
    problems.append(msg)


def scan_csproj(proj: Path, forbid_proj: list, tag: str):
    text = proj.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r'<ProjectReference Include="([^"]+)"', text):
        ref = Path(m.group(1)).name.replace(".csproj", "")
        if any(ref == f or ref == f"AstralPath.{f}" for f in forbid_proj):
            fail(f"[{tag}] {proj.relative_to(ROOT)} 引用了 {ref}（ProjectReference）")


def scan_usings(cs: Path, forbid_ns: list, tag: str):
    text = cs.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r"using\s+([A-Za-z_.]+)\s*;", text):
        ns = m.group(1)
        for f in forbid_ns:
            if ns == f or ns.startswith(f + "."):
                fail(f"[{tag}] {cs.relative_to(ROOT)}:{text[:m.start()].count(chr(10)) + 1} using {ns}")
                break


def scan_biz(cs: Path, tag: str):
    text = cs.read_text(encoding="utf-8", errors="replace")
    for pat in SHELL_BIZ_PATTERNS:
        for m in re.finditer(re.escape(pat), text):
            fail(f"[{tag}] {cs.relative_to(ROOT)}:{text[:m.start()].count(chr(10)) + 1} 疑似壳内业务计算：{pat}")


def main() -> int:
    if not SRC.exists():
        print("[ARCH] src/ 不存在")
        return 1
    # ① Core 纯净
    core = SRC / "AstralPath.Core"
    if core.exists():
        scan_csproj(core / "AstralPath.Core.csproj", CORE_FORBID_PROJ, "契约①")
        for cs in core.rglob("*.cs"):
            scan_usings(cs, CORE_FORBID_NS, "契约①")
    # ② API 不下探宿主
    for name in ["AstralPath.Api", "AstralPath.Api.Core"]:
        d = SRC / name
        if d.exists():
            for cs in d.rglob("*.cs"):
                scan_usings(cs, API_FORBID_NS, "契约②")
    # ③ 壳不做业务（Kotlin/ArkTS 宿主不在本门禁范围；Native 侧仅扫 *.cs 即无文件时自然通过）
    for name in ["AstralPath.Desktop", "AstralPath.Monolith", "AstralPath.Native"]:
        d = SRC / name
        if d.exists():
            for cs in d.rglob("*.cs"):
                scan_biz(cs, "契约③")

    if problems:
        print("[ARCH]")
        for p in problems:
            print("  - " + p)
        print(f"FAILED: 分层架构违约 {len(problems)} 处")
        return 1
    print("ALL GREEN · 分层架构三契约（Core 纯净 / API 不下探宿主 / 壳不做业务）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
