# -*- coding: utf-8 -*-
"""从项目实际字符集生成 MiSans 子集字体（可复现构建）。

用法：
  python scripts/gen_font_subset.py

输入：C:/Users/18948/Downloads/MiSans/MiSans/ttf/MiSans-Normal.ttf（8.2MB 完整字体）
输出：assets/MiSans-subset.ttf（约 309KB，覆盖项目全部汉字 + ASCII + 常用标点）

设计：
  - 单文件版内联此子集（离线可用），完整字体放 deploy/monolith-web/assets/ 作外链兜底；
  - 只收集页面与 shared/ 中实际出现的汉字，避免把 8.2MB 完整字体塞进 35MB 预算；
  - 用 fontTools.pyftsubset，无需 brotli（不用 WOFF2）；
  - 字符变化后重跑本脚本，并重建单文件。
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_FONT = Path(os.environ.get(
    "ASTRALPATH_SRC_FONT",
    str(ROOT / "assets" / "src" / "MiSans-Normal.ttf"),
))
OUT = ROOT / "assets" / "MiSans-subset.ttf"
CHARSET = ROOT / "assets" / "font-charset.txt"

# 字符来源：页面源、共享模块、OCR 适配层
SOURCES = [
    ROOT / "deploy" / "monolith-web" / "index.html",
    ROOT / "deploy" / "monolith-web" / "ocr-engine" / "ocr-wasm.js",
]
SOURCES += sorted((ROOT / "shared").glob("*.js"))


def main():
    if not SRC_FONT.exists():
        print(f"FAILED：完整字体不存在：{SRC_FONT}")
        return 1
    chars = set()
    for p in SOURCES:
        if p.exists():
            chars |= set(re.findall(r"[\u4e00-\u9fff]", p.read_text(encoding="utf-8", errors="replace")))
    chars |= {chr(i) for i in range(32, 127)}
    chars |= set("，。！？、；：“”‘’（）《》【】—…·￥％＋－／＝＃＆＊")
    text = "".join(sorted(chars))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    CHARSET.write_text(text, encoding="utf-8")
    cmd = [sys.executable, "-m", "fontTools.subset", str(SRC_FONT),
           "--text-file=" + str(CHARSET), "--output-file=" + str(OUT),
           "--layout-features=*"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("FAILED：子集化失败：", r.stderr[:300])
        return 1
    print(f"OK：{len(chars):,} 码点 → {OUT.name}（{OUT.stat().st_size:,} 字节）")
    print("下一步：python scripts/build-single.py 重建单文件")
    return 0


if __name__ == "__main__":
    sys.exit(main())
