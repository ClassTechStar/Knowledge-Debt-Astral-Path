# -*- coding: utf-8 -*-
"""实时拍照链路门禁（Web + Android WebView + HarmonyOS）。

锁死四件事：
  ① Web 端生成区存在且抓拍走 APCameraQuality（连拍选最清晰帧）
  ② 原有上传方式完整保留（不因新增拍照而删掉 file input / 导入按钮）
  ③ 失败降级提示仍在（相机不可用时引导改用图片导入/截图粘贴）
  ④ Android 有 CAMERA 权限与 WebView onPermissionRequest，且只授 VIDEO_CAPTURE；
     HarmonyOS 原生 cameraPicker 路径未被破坏

用法：python scripts/verify_camera.py      退出码 0=全绿 1=有缺口
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "deploy" / "monolith-web" / "index.html"
MODULE = ROOT / "shared" / "camera-quality.js"
MANIFEST = ROOT / "src" / "AstralPath.Native" / "app" / "src" / "main" / "AndroidManifest.xml"
ACTIVITY = ROOT / "src" / "AstralPath.Native" / "app" / "src" / "main" / "java" / "com" / "astralpath" / "app" / "MainActivity.kt"
PAPERS = ROOT / "src" / "AstralPath.Harmony" / "entry" / "src" / "main" / "ets" / "pages" / "PapersPage.ets"
problems = []


def fail(msg):
    problems.append(msg)


def read(p):
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


def main():
    html = read(INDEX)
    mod = read(MODULE)
    if not html or not mod:
        print("FAILED：缺 index.html 或 shared/camera-quality.js")
        return 1

    # ① Web 生成区 + 抓拍接线
    if "AP:BEGIN shared/camera-quality.js" not in html:
        fail("index.html 缺 camera-quality.js 生成区")
    if ("APCameraQuality.captureBestFrame" not in html and "Q.captureBestFrame" not in html):
        fail("captureExamPhoto 未走连拍选帧（新增拍照未生效）")
    if "navigator.mediaDevices.getUserMedia" not in html:
        fail("Web 端 getUserMedia 链路丢失")
    print("  OK  Web 链路           生成区 + 选帧 + getUserMedia 齐备")

    # ② 上传方式保留
    for needle in ['id="fileInput"', 'id="examImgInput"', 'id="examFileInput"',
                   'id="btnExamImg"', 'id="btnExamFile"']:
        if needle not in html:
            fail(f"原有上传入口丢失：{needle}（新增拍照不得替换旧方式）")
    print("  OK  上传保留           文件/图片/粘贴入口均在")

    # ③ 降级提示保留
    if "可改用「图片导入」或「截图粘贴」" not in html:
        fail("相机失败时的降级提示丢失")
    print("  OK  失败降级           改用图片导入/截图粘贴提示在位")

    # ④ Android 权限桥
    mf = read(MANIFEST)
    if "android.permission.CAMERA" not in mf:
        fail("AndroidManifest 缺 CAMERA 权限")
    if 'android:name="android.hardware.camera"' not in mf or 'android:required="false"' not in mf:
        fail("缺 camera 非必需硬件声明（无摄像头设备应仍可安装）")
    act = read(ACTIVITY)
    if "override fun onPermissionRequest" not in act:
        fail("Android WebView 缺 onPermissionRequest（getUserMedia 会被直接拒绝）")
    if "RESOURCE_VIDEO_CAPTURE" not in act:
        fail("未授予 VIDEO_CAPTURE")
    if "RESOURCE_AUDIO_CAPTURE" in act:
        fail("不应授予音频权限（页面 audio:false，违反最小权限）")
    print("  OK  Android            CAMERA 权限 + 仅授 VIDEO_CAPTURE")

    # ⑤ HarmonyOS 原生相机保留
    hp = read(PAPERS)
    if "cameraPicker" not in hp or "CAMERA_POSITION_BACK" not in hp:
        fail("HarmonyOS 原生 cameraPicker 路径被破坏")
    print("  OK  HarmonyOS          原生 cameraPicker 后摄路径在位")

    # ⑥ 模块不引入新依赖
    # 注释里提到的 require()/import 不算依赖，只看真实代码行
    code_lines = [ln for ln in mod.splitlines()
                  if not ln.lstrip().startswith(("*", "//", "/*"))]
    if re.search(r"\brequire\s*\(|\bimport\s+.+\s+from\b", "\n".join(code_lines)):
        fail("camera-quality.js 引入了外部依赖（应保持零依赖）")
    print("  OK  依赖约束           camera-quality.js 零依赖")

    print()
    if problems:
        print(f"实时拍照链路 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("实时拍照链路 ALL GREEN · 三端路径齐备、上传保留、最小权限")
    return 0


if __name__ == "__main__":
    sys.exit(main())
