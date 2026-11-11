# -*- coding: utf-8 -*-
"""发布版本一致性门禁（借鉴 VeriRandom「发布前校验版本元数据」的 channel gate 思路，
适配为本仓库的单一事实源 + 门禁脚本形态，不引入签名密钥或新依赖）。

为什么需要：版本号曾散落在 csproj / iss / gradle / 打包脚本里，rebase 会把旧值
悄悄带回来（实测发现 1.3.0 / 1.5.0 / 2.2.0 与 2.6.0 并存），而 verify_metrics.py
只管公开数字、verify_architecture.py 只管分层，都没有盯版本。

事实源：Directory.Build.props 的 <Version>（MSBuild 会把同一份值注入所有项目）。
校验：安装包脚本、Gradle 产物、打包脚本中的产物名、README 变更记录的最新版；
      并禁止任何 src/ 下的 csproj 重新写死 <Version>（防回潮）。

明确排除（不是漏检，是有意）：
  - attic/：停用代码档案馆，不参与构建
  - obj/、build/、bin/：构建产物
  - deploy/win-install/setup.iss、setup-desktop.iss：历史安装包脚本，
    活跃链路只用 src/AstralPath.Monolith/setup-monolith.iss（build-release.ps1:88）
  - deploy/monolith-web/ocr-engine/ocr-wasm.js 的 VERSION：OCR 引擎组件自身版本，
    与应用发布版本是两条独立的版本线

用法：python scripts/verify_release_version.py      退出码 0=全绿 1=漂移
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
problems = []


def fail(msg):
    problems.append(msg)


def read(rel):
    p = ROOT / rel
    if not p.exists():
        fail(f"缺少文件：{rel}")
        return None
    return p.read_text(encoding="utf-8", errors="replace")


def expect(rel, pattern, label, version, flags=0):
    """在文件里找到 pattern 的第 1 个捕获组，要求等于基线版本。"""
    text = read(rel)
    if text is None:
        return
    m = re.search(pattern, text, flags)
    if not m:
        fail(f"[{label}] {rel} 中未找到版本声明（正则 {pattern[:36]}…）")
        return
    got = m.group(1)
    if got != version:
        fail(f"[{label}] {rel} 版本 {got} ≠ 基线 {version}")
    else:
        print(f"  OK  {label:14s} {rel} = {got}")


def main():
    baseline_text = read("Directory.Build.props")
    if baseline_text is None:
        return 1
    m = re.search(r"<Version>\s*([0-9]+\.[0-9]+\.[0-9]+)\s*</Version>", baseline_text)
    if not m:
        fail("Directory.Build.props 缺少 <Version>X.Y.Z</Version>")
        return 1
    version = m.group(1)
    print(f"版本基线（单一事实源）：Directory.Build.props = {version}")

    # ① Windows 安装包（活跃链路）
    expect("src/AstralPath.Monolith/setup-monolith.iss",
           r'#define\s+MyAppVersion\s+"([^"]+)"', "Inno Setup", version)

    # ② 两个安卓端的 versionName
    expect("src/AstralPath.Native/app/build.gradle.kts",
           r'versionName\s*=\s*"([^"]+)"', "Android(WebView)", version)
    expect("src/AstralPath.NativeApp/app/build.gradle.kts",
           r'versionName\s*=\s*"([^"]+)"', "Android(原生)", version)

    # ③ 便携版与发布脚本
    expect("release/build-portable.ps1",
           r'\$version\s*=\s*"([^"]+)"', "便携版", version)

    rel_text = read("release/build-release.ps1")
    if rel_text is not None:
        found = set()
        for mm in re.finditer(r"AstralPath-[A-Za-z0-9-]*?([0-9]+\.[0-9]+\.[0-9]+)", rel_text):
            # 跳过纯注释行里的说明，只看产物名/复制路径
            line = rel_text[rel_text.rfind("\n", 0, mm.start()) + 1: rel_text.find("\n", mm.end())]
            if line.lstrip().startswith("#"):
                continue
            found.add(mm.group(1))
        bad = sorted(v for v in found if v != version)
        if bad:
            fail(f"[发布脚本] release/build-release.ps1 产物名含旧版本 {bad}（应为 {version}）")
        elif found:
            print(f"  OK  {'发布脚本':14s} release/build-release.ps1 产物名 = {', '.join(sorted(found))}")
        else:
            fail("[发布脚本] release/build-release.ps1 未找到任何带版本号的产物名")

    # ④ 防回潮：src/ 下任何 csproj 都不许重新写死 <Version>
    for proj in sorted((ROOT / "src").rglob("*.csproj")):
        rel = proj.relative_to(ROOT).as_posix()
        if "/obj/" in rel or "/bin/" in rel:
            continue
        text = proj.read_text(encoding="utf-8", errors="replace")
        for mm in re.finditer(r"<Version>\s*([^<]+)\s*</Version>", text):
            if mm.group(1).strip() != version:
                fail(f"[防回潮] {rel} 写死了 <Version>{mm.group(1).strip()}</Version>，"
                     f"请删除该行让 Directory.Build.props 接管")
    print(f"  OK  {'防回潮':14s} src/ 下 csproj 无独立版本声明")

    # ⑤ README 变更记录里必须能看到当前基线（文档口径同步）
    readme = read("README.md")
    if readme is not None and "## 11. 变更记录" in readme:
        section = readme.split("## 11. 变更记录", 1)[1]
        if version not in section:
            fail(f"[文档口径] README §11 变更记录未出现当前版本 {version}")
        else:
            print(f"  OK  {'文档口径':14s} README §11 含 {version}")

    print()
    if problems:
        print(f"版本一致性 FAILED：{len(problems)} 处漂移")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"版本一致性 ALL GREEN · 全链路锁定 {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
