# -*- coding: utf-8 -*-
"""发布清单生成器（威胁模型 T19：发布包被替换后无校验）。

产出 release/ 下两份文件：
  checksums.sha256   标准 sha256sum 格式（sha256sum -c 可直接验）
  manifest.json      结构化清单：版本 / 时间 / 每个产物的大小与 sha256 / 签名态

签名分层（诚实标注，不夸大）：
  - 哈希清单：防「单个产物被替换」——替换后 sha256 对不上
  - 清单签名：防「清单本身被改」——用 HMAC-SHA256，密钥取自环境变量
    ASTRALPATH_MANIFEST_KEY；密钥缺失时清单标注 signed=false（不冒充已签名）
  - 局限：HMAC 是对称的，密钥泄露即失效；这是「检测替换」而非「不可否认签名」。
    要不可否认需 Ed25519，那要引入 cryptography 依赖与密钥托管，未纳入本次。

用法：python scripts/gen_release_manifest.py [--out release]
"""
import argparse
import hashlib
import hmac
import json
import os
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# 发布产物白名单：只认安装包/压缩包/可执行发布物，不含脚本与说明文档
ARTIFACT_RE = re.compile(r"\.(exe|apk|zip|msi|dmg|AppImage|hap)$", re.I)
SKIP_NAMES = {"checksums.sha256", "manifest.json", "manifest.sig"}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def baseline_version() -> str:
    props = (ROOT / "Directory.Build.props").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"<Version>\s*([0-9]+\.[0-9]+\.[0-9]+)\s*</Version>", props)
    return m.group(1) if m else "0.0.0"


def collect(out: Path):
    items = []
    for p in sorted(out.iterdir()):
        if not p.is_file():
            continue
        if p.name in SKIP_NAMES:
            continue
        if not ARTIFACT_RE.search(p.name):
            continue
        items.append({
            "name": p.name,
            "bytes": p.stat().st_size,
            "sha256": sha256_of(p),
        })
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "release"))
    args = ap.parse_args()
    out = Path(args.out)
    if not out.exists():
        print(f"FAILED：目录不存在 {out}")
        return 1

    items = collect(out)
    if not items:
        print(f"FAILED：{out} 下没有发布产物（.exe/.apk/.zip 等）")
        return 1

    version = baseline_version()
    manifest = {
        "schemaVersion": 1,
        "product": "AstralPath",
        "version": version,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "hashAlgorithm": "sha256",
        "signatureAlgorithm": "hmac-sha256",
        "signed": False,
        "artifacts": items,
    }

    # 清单签名：HMAC-SHA256，密钥来自环境变量；缺密钥则如实标注未签名
    key = os.environ.get("ASTRALPATH_MANIFEST_KEY", "")
    # 签名体排除 signed 字段：signed 是「结果」不是「被签名内容」，
    # 与 verify_release_manifest.py 的校验口径保持一致
    body = json.dumps({k: v for k, v in manifest.items() if k != "signed"},
                      ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    if key:
        sig = hmac.new(key.encode("utf-8"), body.encode("utf-8"), hashlib.sha256).hexdigest()
        manifest["signed"] = True
        (out / "manifest.sig").write_text(sig + "\n", encoding="utf-8")
    else:
        try:
            (out / "manifest.sig").unlink()
        except FileNotFoundError:
            pass

    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                       encoding="utf-8")
    lines = [f"{it['sha256']}  {it['name']}" for it in items]
    (out / "checksums.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"发布清单已生成：{len(items)} 个产物，版本 {version}")
    for it in items:
        print(f"  {it['sha256'][:16]}…  {it['name']}  ({it['bytes']} bytes)")
    if manifest["signed"]:
        print("清单已签名（HMAC-SHA256）")
    else:
        print("清单未签名（未设 ASTRALPATH_MANIFEST_KEY）——哈希仍可防单文件替换，"
              "但清单本身可被改；要启用签名请设置该环境变量")
    return 0


if __name__ == "__main__":
    sys.exit(main())
