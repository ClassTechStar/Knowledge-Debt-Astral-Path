# -*- coding: utf-8 -*-
"""发布清单校验门禁（威胁模型 T19：发布包被替换后无校验）。

校验四件事：
  ① 清单存在且格式正确（manifest.json + checksums.sha256 互相一致）
  ② 清单里每个产物实际存在、sha256 与文件内容匹配（防「单个产物被替换」）
  ③ release/ 下的发布产物都在清单里（防「漏登记一个包」）
  ④ 清单签名（若 signed=true）HMAC-SHA256 有效；未签名则如实标注，不冒充已签名

版本口径与 scripts/verify_release_version.py 呼应：manifest.version 必须等于
Directory.Build.props 的 <Version>。

用法：python scripts/verify_release_manifest.py      退出码 0=全绿 1=有缺口
"""
import hashlib
import hmac
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "release"
SKIP_NAMES = {"checksums.sha256", "manifest.json", "manifest.sig"}
ARTIFACT_RE = re.compile(r"\.(exe|apk|zip|msi|dmg|AppImage|hap)$", re.I)
problems = []


def fail(msg):
    problems.append(msg)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if not RELEASE.exists():
        print("FAILED：缺 release/ 目录")
        return 1

    # ① 清单存在且一致
    mpath = RELEASE / "manifest.json"
    cpath = RELEASE / "checksums.sha256"
    if not mpath.exists():
        fail("缺 release/manifest.json（跑 scripts/gen_release_manifest.py 生成）")
        return 1
    if not cpath.exists():
        fail("缺 release/checksums.sha256")
        return 1

    try:
        manifest = json.loads(mpath.read_text(encoding="utf-8"))
    except Exception as e:
        fail(f"manifest.json 解析失败：{e}")
        return 1

    arts = manifest.get("artifacts") or []
    if not arts:
        fail("manifest.json 里没有 artifacts")
        return 1

    # ② 逐个产物验哈希
    ok_count = 0
    for it in arts:
        name = it.get("name", "")
        want = str(it.get("sha256", "")).lower()
        p = RELEASE / name
        if not p.exists():
            fail(f"清单里的产物不存在：{name}")
            continue
        got = sha256_of(p)
        if got != want:
            fail(f"哈希不符（疑似被替换）：{name} 期望 {want[:16]}… 实际 {got[:16]}…")
        else:
            ok_count += 1
        if p.stat().st_size != it.get("bytes"):
            fail(f"大小不符：{name} 清单 {it.get('bytes')} 实际 {p.stat().st_size}")
    print(f"  OK  哈希校验             {ok_count}/{len(arts)} 个产物 sha256 匹配")

    # ③ 防遗漏：release/ 下的发布产物都要在清单里
    listed = {it.get("name") for it in arts}
    on_disk = [p.name for p in RELEASE.iterdir()
               if p.is_file() and p.name not in SKIP_NAMES and ARTIFACT_RE.search(p.name)]
    missing = [n for n in on_disk if n not in listed]
    if missing:
        fail(f"release/ 下有产物未登记进清单：{missing}")
    else:
        print(f"  OK  防遗漏               {len(on_disk)} 个产物均已登记")

    # ④ checksums.sha256 与 manifest 一致
    lines = [ln for ln in cpath.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
    if len(lines) != len(arts):
        fail(f"checksums.sha256 行数 {len(lines)} 与 manifest 产物数 {len(arts)} 不一致")
    else:
        bad = []
        for ln, it in zip(lines, arts):
            parts = ln.split()
            if len(parts) < 2 or parts[0].lower() != str(it.get("sha256", "")).lower() or parts[1] != it.get("name"):
                bad.append(ln[:60])
        if bad:
            fail(f"checksums.sha256 与 manifest 不一致：{bad[:3]}")
        else:
            print(f"  OK  双清单一致           checksums.sha256 与 manifest.json 对齐")

    # ⑤ 签名
    if manifest.get("signed"):
        sig_path = RELEASE / "manifest.sig"
        if not sig_path.exists():
            fail("signed=true 但缺 manifest.sig")
        else:
            key = os.environ.get("ASTRALPATH_MANIFEST_KEY", "")
            if not key:
                print("  WARN 清单声称已签名，但未设 ASTRALPATH_MANIFEST_KEY，无法本地验签")
            else:
                body = json.dumps({k: v for k, v in manifest.items() if k != "signed"},
                                  ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                want = hmac.new(key.encode("utf-8"), body.encode("utf-8"), hashlib.sha256).hexdigest()
                got = sig_path.read_text(encoding="utf-8").strip()
                if not hmac.compare_digest(want, got):
                    fail("清单签名校验失败（清单可能被改）")
                else:
                    print("  OK  清单签名             HMAC-SHA256 校验通过")
    else:
        print("  WARN 清单未签名：哈希可防单文件替换，但清单本身可被改"
              "（设 ASTRALPATH_MANIFEST_KEY 可启用签名）")

    # ⑥ 版本口径
    props = (ROOT / "Directory.Build.props").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"<Version>\s*([0-9]+\.[0-9]+\.[0-9]+)\s*</Version>", props)
    if m and manifest.get("version") != m.group(1):
        fail(f"清单版本 {manifest.get('version')} ≠ 基线 {m.group(1)}")
    else:
        print(f"  OK  版本口径             manifest.version = {manifest.get('version')}")

    print()
    if problems:
        print(f"发布清单校验 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("发布清单 ALL GREEN · 产物哈希一致、无遗漏、版本对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())
