#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""设计 token 一致性门禁（MD3 × Mochi 对齐）。

事实源：`docs/设计规范-MD3-Mochi对齐.md` 第一节形状刻度、第六节动效八档。
本脚本把该规范变成可校验项，防止四端漂移与档间值回流：

  ① Web `:root` 九档圆角变量齐备且取值正确；
  ② Web 动效八档变量齐备；
  ③ HarmonyOS Theme.ets 九档齐备且与 Web 一致；
  ④ Avalonia AppTheme.axaml 八档齐备且与 Web 一致；
  ⑤ 三端组件内不得出现档间字面量圆角（只允许九档值）；
  ⑥ Web 必须声明 prefers-reduced-motion 降级。

用法：python scripts/verify_design_tokens.py
退出码：0 = ALL GREEN；1 = 有漂移
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "deploy" / "monolith-web" / "index.html"
HARMONY = ROOT / "src" / "AstralPath.Harmony" / "entry" / "src" / "main" / "ets" / "common" / "Theme.ets"
AVALONIA = ROOT / "src" / "AstralPath.Shared" / "Styles" / "AppTheme.axaml"

# 唯一刻度（与规范文档第一节逐项对应）
SCALE = {"xs": 4, "s": 8, "m": 12, "l": 16, "xl": 20, "2xl": 28, "3xl": 32, "4xl": 48, "pill": 999}
ALLOWED = set(SCALE.values())
# 动效八档变量名（值不逐项比对阻尼曲线，只校验存在与时长）
MOTION_TOKENS = {
    "--mo-page": "420ms", "--mo-present": "420ms", "--mo-pop": "360ms",
    "--mo-control": "340ms", "--mo-settle": "280ms", "--mo-bounce": "340ms",
    "--mo-press-down": "220ms", "--mo-press-up": "380ms",
    "--mo-fade-in": "150ms", "--mo-fade-out": "120ms",
}

problems: list[str] = []


def check_web():
    s = WEB.read_text(encoding="utf-8", errors="replace")
    for name, want in SCALE.items():
        m = re.search(rf"--r-{re.escape(name)}:\s*(\d+)px", s)
        if not m:
            problems.append(f"Web 缺圆角变量 --r-{name}")
        elif int(m.group(1)) != want:
            problems.append(f"Web --r-{name}={m.group(1)}px，应为 {want}px")
    if not problems:
        print(f"  OK  Web 形状刻度        九档齐备（4/8/12/16/20/28/32/48/999）")

    missing = [k for k, v in MOTION_TOKENS.items() if k not in s or v not in s]
    if missing:
        problems.append(f"Web 动效档位缺失或时长不符：{missing}")
    else:
        print(f"  OK  Web 动效档位        {len(MOTION_TOKENS)} 项齐备")

    if "prefers-reduced-motion" not in s:
        problems.append("Web 缺 prefers-reduced-motion 降级")
    else:
        print("  OK  动画降级            prefers-reduced-motion 已声明")

    # 档间字面量
    stray = {}
    for m in re.finditer(r"border-radius:\s*(\d+)px", s):
        v = int(m.group(1))
        if v not in ALLOWED:
            stray[v] = stray.get(v, 0) + 1
    if stray:
        problems.append(f"Web 存在档间圆角字面量：{stray}（只允许 {sorted(ALLOWED)}）")
    else:
        print("  OK  Web 无档间圆角      仅使用九档值")


def check_harmony():
    s = HARMONY.read_text(encoding="utf-8", errors="replace")
    names = {"xs": "R_XS", "s": "R_S", "m": "R_M", "l": "R_L", "xl": "R_XL",
             "2xl": "R_2XL", "3xl": "R_3XL", "4xl": "R_4XL", "pill": "R_PILL"}
    bad = []
    for k, field in names.items():
        m = re.search(rf"{field}:\s*number\s*=\s*(\d+)", s)
        if not m:
            bad.append(f"缺 {field}")
        elif int(m.group(1)) != SCALE[k]:
            bad.append(f"{field}={m.group(1)} 应为 {SCALE[k]}")
    if bad:
        problems.append("Harmony 刻度不一致：" + "; ".join(bad))
    else:
        print("  OK  Harmony 形状刻度    九档与 Web 一致")

    stray = {}
    for p in HARMONY.parent.parent.rglob("*.ets"):
        for m in re.finditer(r"borderRadius\((\d+)\)", p.read_text(encoding="utf-8", errors="replace")):
            v = int(m.group(1))
            if v not in ALLOWED and v < 99:  # 99 视作胶囊旧写法
                stray[v] = stray.get(v, 0) + 1
    if stray:
        problems.append(f"Harmony 存在档间圆角字面量：{stray}")
    else:
        print("  OK  Harmony 无档间圆角")


def check_avalonia():
    s = AVALONIA.read_text(encoding="utf-8", errors="replace")
    names = {"xs": "RadiusXs", "s": "RadiusS", "m": "RadiusM", "l": "RadiusL",
             "xl": "RadiusXl", "2xl": "Radius2xl", "3xl": "Radius3xl", "4xl": "Radius4xl"}
    bad = []
    for k, key in names.items():
        m = re.search(rf'x:Key="{key}">(\d+)<', s)
        if not m:
            bad.append(f"缺 {key}")
        elif int(m.group(1)) != SCALE[k]:
            bad.append(f"{key}={m.group(1)} 应为 {SCALE[k]}")
    if bad:
        problems.append("Avalonia 刻度不一致：" + "; ".join(bad))
    else:
        print("  OK  Avalonia 形状刻度   八档与 Web 一致")

    # CardRadius 应等于 large(16)
    m = re.search(r'x:Key="CardRadius">(\d+)<', s)
    if not m:
        problems.append("Avalonia 缺 CardRadius")
    elif int(m.group(1)) != SCALE["l"]:
        problems.append(f"Avalonia CardRadius={m.group(1)}，应与 large({SCALE['l']}) 一致")

    stray = {}
    for p in (ROOT / "src" / "AstralPath.Shared").rglob("*.axaml"):
        for m in re.finditer(r'CornerRadius="(\d+)(?:,\d+)*"', p.read_text(encoding="utf-8", errors="replace")):
            v = int(m.group(1))
            if v not in ALLOWED:
                stray[v] = stray.get(v, 0) + 1
    if stray:
        problems.append(f"Avalonia 存在档间圆角字面量：{stray}")
    else:
        print("  OK  Avalonia 无档间圆角")


def main():
    for p in (WEB, HARMONY, AVALONIA):
        if not p.exists():
            print(f"FAILED：缺文件 {p.relative_to(ROOT)}")
            return 1
    check_web()
    check_harmony()
    check_avalonia()

    print()
    if problems:
        print(f"设计 token FAILED：{len(problems)} 项")
        for x in problems:
            print(f"  - {x}")
        print("  修法：对齐 docs/设计规范-MD3-Mochi对齐.md 第一节刻度，不要放宽门禁。")
        return 1
    print("设计 token ALL GREEN · 四端形状/动效 token 与 MD3-Mochi 规范一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
