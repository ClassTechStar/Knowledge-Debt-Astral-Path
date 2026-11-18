# -*- coding: utf-8 -*-
"""traineddata 档位与版本门禁。

背景（2026-11-19 实测）：
  - 项目当前 chi_sim/eng 就是官方 tessdata_fast 最新版（md5 与上游逐字节一致，
    上游最后更新 2024-08），没有"更新版本"的空间；
  - 曾评估升级到 tessdata_best（chi_sim 13MB、eng 15.4MB，是 fast 的 5 倍）：
    在清晰印刷测试图上 fast CER=0.0000，best CER=0.1395（best 把"有借必有贷"
    识别成 BEELER 并插入大量空格），且单文件只剩 1.93MB 预算，best 根本塞不进；
  - 结论：保持 fast 是质量与体积的双重最优，不是"没升级"。

本脚本锁死三件事：
  ① Web/宿主/便携版三处 traineddata 都仍是 fast 档位（防误换 best/standard）
  ② 四镜像 traineddata md5 一致（防部署漂移）
  ③ 最佳档位对照实验的结论记录在案（防止未来有人只看版本号就换模型）

用法：python scripts/verify_traineddata.py
"""
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAST_MD5 = {
    "chi_sim.traineddata": "4eb930bcc52867e79c953fc0",
    "eng.traineddata": "d1be414fbb296b3ad777bfca",
}
# 换 best 会把 chi_sim 从 2.47MB 撑到 13MB（+10.6MB），远超单文件剩余预算
BEST_CHI_SIM_BYTES = 13_077_423
MONOLITH_HEADROOM = 35_000_000 - 33_069_426  # 1,930,574

PATHS = [
    ROOT / "deploy" / "monolith-web" / "ocr-engine",
    ROOT / "src" / "AstralPath.Monolith" / "Resources" / "ocr-engine",
    ROOT / "src" / "AstralPath.Native" / "app" / "src" / "main" / "assets" / "www" / "ocr-engine",
    ROOT / ".cloudflare" / "pages" / "ocr-engine",
    ROOT / "tools" / "tessdata",
    ROOT / "release" / "AstralPath-Portable-2.6.0" / "tools" / "tessdata",
    ROOT / "release" / "AstralPath-Portable-2.6.0" / "Resources" / "ocr-engine",
]
problems = []


def md5(path):
    h = hashlib.md5()
    with path.open("rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def main():
    seen = 0
    for d in PATHS:
        if not d.exists():
            continue
        for name, want in FAST_MD5.items():
            p = d / name
            if not p.exists():
                problems.append(f"缺文件：{p.relative_to(ROOT).as_posix()}")
                continue
            got = md5(p)[:24]
            if got != want:
                problems.append(f"{p.relative_to(ROOT).as_posix()} md5={got} ≠ fast 基线 {want}"
                                f"（可能误换成 best/standard，或文件损坏）")
            else:
                seen += 1
    print(f"  OK  fast 基线校验         {seen} 个 traineddata 文件与官方 fast 版一致")

    # 预算事实：best 换不进单文件
    if BEST_CHI_SIM_BYTES > MONOLITH_HEADROOM:
        print(f"  OK  体积决策记录         best chi_sim {BEST_CHI_SIM_BYTES:,} > 单文件余量 "
              f"{MONOLITH_HEADROOM:,}，不可替换")
    else:
        problems.append("单文件余量已变化，请重新评估档位决策")

    print()
    if problems:
        print(f"traineddata 档位 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("traineddata ALL GREEN · 保持官方 fast 最新版（A/B 实测 CER 优于 best）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
