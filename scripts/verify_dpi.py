# -*- coding: utf-8 -*-
"""Windows 壳 DPI 一致性门禁（借鉴 SidebarDiagnostics 的「显式 DPI 声明」原则）。

背景：SidebarDiagnostics 把多显示器/DPI 支持作为核心特性，DPI 换算收口在
Windows.cs 的 Monitor.ScaleX/InverseScaleX（DPI/96），且通过清单显式声明感知级别。
本仓库的 Desktop 壳已有 PerMonitorV2 声明，但主交付的 Monolith 单体版曾缺失——
外接不同缩放的屏幕时 WebView2 内容会模糊。Win32 贴边换算不迁移（侧边栏特需），
只保留「每个 Windows 壳都必须显式声明、且各端一致」这条可校验约束。

检查：
  ① 所有 net10.0-windows 的 WinExe 项目都要挂载 app.manifest
  ② manifest 内声明 PerMonitorV2（dpiAware true/pm 也是必需的兼容项）
  ③ 入口代码调用 Application.SetHighDpiMode(HighDpiMode.PerMonitorV2)
  ④ 各端声明一致，不允许一端降级为 SystemAware

用法：python scripts/verify_dpi.py      退出码 0=全绿 1=有缺口
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
problems = []


def fail(msg):
    problems.append(msg)


def main():
    # 找 Windows 壳：TargetFramework 含 windows 且 OutputType 为 WinExe
    shells = []
    for proj in sorted(SRC.rglob("*.csproj")):
        if "/obj/" in proj.as_posix() or "/bin/" in proj.as_posix():
            continue
        text = proj.read_text(encoding="utf-8", errors="replace")
        if "net10.0-windows" not in text or "<OutputType>WinExe</OutputType>" not in text:
            continue
        shells.append((proj, text))

    if not shells:
        print("FAILED：未找到 Windows 壳项目")
        return 1

    for proj, text in shells:
        name = proj.parent.name
        rel = proj.relative_to(ROOT).as_posix()

        # ① csproj 挂载 manifest
        mm = re.search(r"<ApplicationManifest>\s*([^<]+)\s*</ApplicationManifest>", text)
        if not mm:
            fail(f"[{name}] {rel} 未挂载 <ApplicationManifest>")
            continue
        manifest = proj.parent / mm.group(1).strip().replace("\\", "/")
        if not manifest.exists():
            fail(f"[{name}] 清单文件不存在：{manifest.relative_to(ROOT).as_posix()}")
            continue
        mt = manifest.read_text(encoding="utf-8", errors="replace")

        # ② manifest 声明 PerMonitorV2 + dpiAware true/pm
        if "PerMonitorV2" not in mt:
            fail(f"[{name}] {manifest.name} 未声明 PerMonitorV2")
        if not re.search(r"<dpiAware[^>]*>\s*true/pm\s*</dpiAware>", mt):
            fail(f"[{name}] {manifest.name} 缺 dpiAware true/pm（Win8.1 兼容项）")

        # ③ 入口代码显式设置
        entries = list(proj.parent.glob("Program.cs"))
        called = any(
            "SetHighDpiMode(HighDpiMode.PerMonitorV2)" in e.read_text(encoding="utf-8", errors="replace")
            for e in entries
        )
        if not called:
            fail(f"[{name}] Program.cs 未调用 SetHighDpiMode(PerMonitorV2)")
        else:
            print(f"  OK  {name:22s} manifest 与入口均为 PerMonitorV2")

    # ④ 降级哨兵：任一 Windows 壳不得显式设为 SystemAware/DpiUnaware
    for proj, text in shells:
        for entry in proj.parent.glob("Program.cs"):
            t = entry.read_text(encoding="utf-8", errors="replace")
            if re.search(r"SetHighDpiMode\(HighDpiMode\.(SystemAware|DpiUnaware|DpiUnawareGdiScaled)\b", t):
                fail(f"[{proj.parent.name}] 入口显式降级了 DPI 模式")

    print()
    if problems:
        print(f"DPI 一致性 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"DPI 一致性 ALL GREEN · {len(shells)} 个 Windows 壳均为 PerMonitorV2")
    return 0


if __name__ == "__main__":
    sys.exit(main())
