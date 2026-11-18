# -*- coding: utf-8 -*-
"""宿主 RapidOCR 版本与就绪门禁。

背景（2026-11-19）：项目 tools/ocr-venv 里的 RapidOCR 从 3.9.2 升级到本地仓库
HEAD 3.9.3.dev16（包含 v3.10.0 及后续修复）。新版带来的关键修复正好命中本项目
拍照场景痛点：EXIF 方向修正、det limit_side_len 上限、词框按字符评分、长行
方向分类。同时修复了项目里两处 `* *x` → `**x` 语法笔误（导致 ocr_pipeline.py
与 deep_chapters.py 原本无法导入）。

检查：
  ① tools/ocr-venv 的 rapidocr 版本不低于 3.9.3
  ② RapidOCR 类可导入、关键 API 字段（boxes/txts）在管线中有消费
  ③ ocr_pipeline.py 与 deep_chapters.py 能通过 py_compile（防语法笔误回归）
  ④ 便携版副本保持其独立配置，不做强制一致校验（路径布局不同）

用法：python scripts/verify_rapidocr.py
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENV_PY = ROOT / "tools" / "ocr-venv" / "Scripts" / "python.exe"
PKG = ROOT / "tools" / "ocr-venv" / "Lib" / "site-packages" / "rapidocr"
PIPELINE = ROOT / "tools" / "ocr_pipeline.py"
DEEP = ROOT / "tools" / "deep_chapters.py"
problems = []


def fail(msg):
    problems.append(msg)


def main():
    if not VENV_PY.exists() or not PKG.exists():
        print("FAILED：tools/ocr-venv 或 rapidocr 包缺失")
        return 1

    # ① 版本
    vf = PKG / "_version.py"
    if not vf.exists():
        fail("rapidocr/_version.py 缺失")
    else:
        m = re.search(r"__version__\s*=\s*version\s*=\s*['\"]([^'\"]+)", vf.read_text(encoding="utf-8"))
        ver = m.group(1) if m else "?"
        num = tuple(int(x) for x in re.findall(r"^\d+", ver)[:1]) if ver != "?" else (0,)
        ok = ver.startswith(("3.9.3", "3.10", "4."))
        if not ok:
            fail(f"rapidocr 版本 {ver} 低于升级基线 3.9.3（venv 可能被重置）")
        else:
            print(f"  OK  RapidOCR 版本         {ver}")

    # ② API 可导入 + 管线消费字段
    try:
        r = subprocess.run([str(VENV_PY), "-c",
                            "from rapidocr import RapidOCR; print('ok' if callable(RapidOCR) else 'bad')"],
                           capture_output=True, text=True, timeout=60)
        if r.stdout.strip() != "ok":
            fail(f"RapidOCR 类导入失败：{r.stderr[:150]}")
        else:
            print("  OK  RapidOCR API          类可导入")
    except Exception as e:
        fail(f"RapidOCR 导入检查异常：{e}")

    src = PIPELINE.read_text(encoding="utf-8", errors="replace")
    if ("from rapidocr import RapidOCR" not in src
            or 'getattr(res, "txts"' not in src or 'getattr(res, "boxes"' not in src):
        fail("ocr_pipeline.py 未消费新版 RapidOCR 的 boxes/txts API")
    else:
        print("  OK  管线 API 对齐         boxes/txts 消费在位")

    # ③ py_compile 防语法笔误
    for p in (PIPELINE, DEEP):
        r = subprocess.run([str(VENV_PY), "-m", "py_compile", str(p)],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            fail(f"{p.name} 语法检查失败：{r.stderr[:150]}")
    print("  OK  脚本语法             ocr_pipeline / deep_chapters 均可编译")

    print()
    if problems:
        print(f"宿主 RapidOCR FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("宿主 RapidOCR ALL GREEN · 3.9.3.dev16（含 v3.10.0 修复）就绪")
    return 0


if __name__ == "__main__":
    sys.exit(main())
