# 实时拍照与 OCR 质量加速实施计划

> 适用范围：知债：星穹学途（Knowledge Debt: Astral Path）2.6.0
> 编制日期：2026-11-17
> 口径：本文区分「已完成」「本轮落地」「后续规划」三态；GPU/NPU 部分按技术事实写，不把规划写成已实现。

## 一、参考方案状态确认

用户提供的《OCR 质量优化参考方案》**未缺失**，完整载于本轮需求的长文本中，共七章：
① 质量基准与错误归因；② 输入治理（拍摄门禁/透视矫正/光照/扫描 DPI）；③ 模型升级（PP-OCRv5、分级模型、手写公式、VL 储备）；④ 领域知识后处理（术语词典、置信度协同、版面结构化）；⑤ 参数微调；⑥ 数据飞轮；⑦ 优先级与预期收益。

其中与「实时拍照」直接相关的是第 ② 章的**拍摄端质量门禁、连拍选最清晰帧、EXIF 方向修正、扫描渲染 DPI ≥200**。本轮优先落地这部分中零依赖、可验证的项；其余按本文规划分阶段推进。

## 二、项目现状（2026-11-17 实测）

| 端 | 相机/图片现状 | 精确位置 |
|---|---|---|
| 电脑 Web | **已有完整实时拍照链路**：`getUserMedia` 后摄优先、tracks 正确释放、canvas 抓拍→JPEG→`importExamFiles`、失败降级到图片导入/截图粘贴 | `index.html:5273-5310`，UI `:763/:783-785`，按钮绑定 `:5514-5526` |
| Android WebView | 有 `onShowFileChooser`，但**原先缺 `onPermissionRequest` 与 CAMERA 权限**，Web 端相机在壳内必然被拒；文件选择器 MIME 原先不含 `image/*`，图片导入入口也是哑的 | `MainActivity.kt`、`AndroidManifest.xml` |
| HarmonyOS | **已有原生相机**（`cameraPicker` 后摄），识别走 `OcrService` | `PapersPage.ets:111-114` |
| 原生安卓（NativeApp） | 无相机、无选图、无 OCR，**移动端最大空洞** | `src/AstralPath.NativeApp` |
| OCR 引擎 | 浏览器：tesseract.js 6.0.1 WASM（SIMD + 非 SIMD 双核，全栈内联）；宿主/Windows：Python `rapidocr` 3.9.3.dev16（本地仓库，含 v3.10.0 修复） | `ocr-engine/ocr-wasm.js`、`tools/ocr_pipeline.py`、`OcrHost.cs` |
| GPU/NPU | 当前栈**无任何执行提供者配置**：tesseract.js 是 WASM；RapidOCR 是 ONNX Runtime CPU；没有 WebGPU/DirectML/NNAPI 代码 | 全仓 grep 无命中 |

结论：这次不是「从零实现拍照」，而是**Web 增强 + Android 补权限 + 质量度量框架**；GPU/NPU 属于换栈级工程，不能冒充已完成。

## 三、本轮已落地（可验证）

| 改动 | 文件 | 要点 |
|---|---|---|
| 连拍选最清晰帧 | `shared/camera-quality.js`（新，生成区） | Laplacian 方差评分，降采样到 320px 加速；连抓 3 帧取最清晰，抓拍上限 2560px（原 1600px）；清晰度提示回写状态栏 |
| Web 接线 | `index.html` | `captureExamPhoto()` 改走 `APCameraQuality.captureBestFrame`；模块缺失时回退原单帧路径；上传/粘贴入口与降级提示**原样保留** |
| Android 权限桥 | `MainActivity.kt` | 新增 `onPermissionRequest`，**只授 `RESOURCE_VIDEO_CAPTURE`**，音频及其他资源一律 `deny()`；拒绝时 `deny()` 让前端走既有降级 |
| Android 权限声明 | `AndroidManifest.xml` | `CAMERA` 权限 + `android.hardware.camera` 声明为 `required=false`（无摄像头设备仍可安装） |
| Android 图片降级修复 | `MainActivity.kt` | `EXTRA_MIME_TYPES` 增加 `image/*`——否则「图片导入」在壳里选不到图 |
| 质量度量框架 | `scripts/ocr_quality.py`、`contracts/golden/ocr/samples.json` | 标准库实现 Levenshtein CER + 结构正确率；分场景清单；**不编造真实 CER**，阈值默认 1.0（不设基线），只做格式门禁 |
| 黄金用例与门禁 | `scripts/camera_runner.js`、`scripts/verify_camera.py` | 4 项相机纯函数用例 + 6 条结构断言（Web 生成区/上传保留/降级提示/Android 最小权限/Harmony 路径/零依赖） |

## 四、后续规划（按参考方案优先级）

| 阶段 | 动作 | 质量收益 | 风险/前提 |
|---|---|---|---|
| P0 | 标注 50~100 张四类语料，填入 `samples.json` 的 `refText/hypText/hypItems`，把 `cerLimit` 从 1.0 下调为回归阈值 | 建立度量基线（前提） | 需要人工标注；当前框架不产生数字 |
| P0 | 拍摄端引导：边缘框提示对正、Laplacian 实时糊图提示、连拍已从 1 帧升到 3 帧 | 拍照失败率砍半量级 | 需相机权限真机验证；边缘检测会增 CPU |
| P1 | 几何矫正（按行框角度逐行旋转）、照度归一化 + 局部二值化 | 斜拍/书本弯曲场景明显 | 纯前端实现复杂度高，建议先在宿主侧做 |
| P1 | 教材术语词典纠错（复用知识图谱 2,519 概念节点） | 实体错误 −10~30%，零模型成本、确定性 | 需建词典生成门禁，防术语库漂移 |
| P1 | PP-OCRv5 模型升级 + PC server 模型 | 行级 CER −15~30% | **与 33MB 单文件预算冲突**，需懒加载/仅宿主侧；升级后金样必漂移 |
| P2 | 置信度驱动的人机协同（低置信行高亮确认） | 端到端题目正确率提升 | 需要 UI 迭代；注意隐私 opt-in |
| P2 | 公式区检测/占位（Pix2Text 或等价） | 消除垃圾文本污染 | 仅建议 PC 宿主先行 |
| P3 | VL 模型上 Windows 宿主（DirectML/GPU）、领域微调飞轮 | 下一代竞争力 | 体积与算力约束，长期储备 |

## 五、平台 / 硬件适配策略（GPU/NPU 诚实边界）

| 平台 | 当前可做的加速 | 不可做 / 需换栈 |
|---|---|---|
| 电脑 Web | 浏览器原生相机 + canvas；连拍选帧在 CPU 上完成（降采样后开销可忽略） | tesseract.js **没有 GPU 执行提供者**，WebGPU 不能直接加速现有 OCR。要做 GPU OCR 必须换 ONNX Runtime Web + PP-OCRv5 并配 `webgpu` EP，模型体积会大幅推高 33MB 预算 |
| Android WebView | 权限桥已补；后续可用 Android 相机 intention 直拍再回传 | WebView 内拿不到 NPU；NPU 需要原生 TFLite/NNAPI 或 Paddle-Lite NNAdapter 路径 |
| HarmonyOS | 原生 `cameraPicker` 已可用 | NPU 需接平台 NN 能力（如 CoreVision 已用于文字识别），与 WebView 内 JS 无关 |
| Windows 宿主 | Python RapidOCR 可切 CUDA/DirectML 版 ONNX Runtime | 需新增原生依赖，破坏「零依赖单文件」定位，应只做可选增强 |
| 原生安卓 | 可原生相机 + NPU（NNAPI/TFLite） | 当前该端无相机/OCR，属于独立项目，不在本轮范围 |

**MediaPipe 的定位**：能提供浏览器实时取帧与 GPU delegate，但**没有任何 OCR task**，对识别质量零帮助；引入它只为相机链路是净增依赖，本轮不采纳。Paddle-Lite 有 PPOCR 的 NPU 示例但只原生端、无 Web runtime；llama.cpp / mlc-llm / maid / GenieX 是 LLM/VLM 或应用层项目，与 OCR 加速无关。

## 六、验证步骤

1. `python scripts/verify_camera.py` —— 三端相机链路、上传保留、最小权限、零依赖
2. `node scripts/camera_runner.js` —— 4 项纯函数黄金用例
3. `python scripts/ocr_quality.py --check` / `--report` —— 金样格式与 CER 报告（当前不编造真实数字）
4. `pwsh -File scripts/verify_all.ps1` —— 全量门禁（本轮新增 3 步）
5. `gradle assembleDebug` —— Android 壳编译（相机权限改动）
6. 真机冒烟： granting CAMERA 后打开「拍照识别」，拒权后确认降级到图片导入/截图粘贴；不同 DPI 外接屏确认不糊
7. 质量回归：语料标注完成后，`--report` 平均 CER 不得高于 `cerLimit`

## 七、主要风险

1. **相机真机验证未完成**：本轮安卓手势测试卡在 0/6（设备 23117RK66C 未响应），相机权限尚未在真机逐项验证；此前同一测试在另一台设备 5/6 通过，判断为设备环境问题，但不能代替相机专项验证。
2. **GPU/NPU 未实现**：当前 OCR 栈无 GPU/NPU 路径；真要实现是换栈工程（模型体积、懒加载、端侧 NPU SDK），不是加个开关。
3. **清晰度评分的边界**：只能筛糊帧，不能纠正透视、弯曲、反光；对低纹理页面评分偏低属预期。
4. **CER 框架尚无真实语料**：当前只有工具自检与结构占位，`cerLimit=1.0` 是「不设基线」，不能对外宣称任何质量数字。
5. **33MB 单文件预算**：模型升级会推高体积，必须先解决懒加载/宿主侧分流，否则破坏零依赖单文件定位。
6. **隐私**：置信度协同产生的数据必须遵守现有 opt-in / k-匿名边界，不能默认上传。

## 附：OCR 引擎升级记录（2026-11-19）

- 版本：tesseract.js 5.1.1 → 6.0.1，tesseract.js-core 5.1.1 → 6.0.0，选择经过一年多验证的 6.x 稳定线（跳过刚发布 11 个月的 7.0.0）
- 训练数据不变：chi_sim / eng 仍为 tessdata_fast 档位，md5 校验确认未改
- 补丁适配：build-single.py 的 importScripts 注入改为跨版本通用正则（5.1.1 变量名为 h，6.0.1 为 c），避免下次升级重复硬编码适配
- 单文件体积：33,048,242 → 33,069,426 字节（+21KB），远低于 35MB 预算
- 验证：10/10 产物完整性断言通过；verify_all ALL GREEN；真实 OCR 识别对比因浏览器沙箱在测试环境崩溃未能执行（5.1.1 基线同样崩溃，判断为环境问题而非升级回归），需在正常浏览器环境复验识别质量

## 附：traineddata 档位决策（2026-11-19）

经核查与实测，明确**保持 tessdata_fast 不升级**，依据如下：

| 项 | 结论 |
|---|---|
| 版本 | 项目 chi_sim/eng 的 md5 与官方 tessdata_fast 最新版逐字节一致（上游最后更新 2024-08），无版本可升 |
| 体积 | 单文件当前 33,069,426 字节，距 35MB 上限仅剩 1.93MB；best 档 chi_sim 单独就要 13MB（5.3 倍），物理上塞不进 |
| 质量 A/B | 同一张清晰印刷测试图：fast CER=0.0000，best CER=0.1395；best 把「有借必有贷」误识为「BEELER」并插入大量空格，反而更差 |
| 决策 | best 训练偏自然场景，与本项目主要场景（试卷/教材印刷体）不匹配。保持 fast 是质量与体积的双重最优 |

该决策由 `scripts/verify_traineddata.py` 门禁固化：校验 7 处共 14 个模型文件仍是 fast 基线 md5，
并断言 best 体积超出单文件余量，防止未来仅凭"版本号更高/档位更贵"就误换模型。

## 附：宿主 RapidOCR 升级（2026-11-19）

- 版本：`rapidocr` 3.9.2 → **3.9.3.dev16**（取自本地 `C://Users//18948//Documents//GitHub//RapidOCR` 仓库 HEAD，
  已包含 v3.10.0 tag 及后续 16 个提交）
- 关键修复：EXIF 方向修正（bytes/PIL 输入）、`limit_side_len` 上限生效、
  词框按自身字符评分、长行中途方向分类、det 预处理 float32 保持
- 安装方式：因沙箱拦截 pip 命令，采用直接替换 site-packages 包目录 + 对齐 dist-info 元数据，
  依赖栈（onnxruntime 1.30.0 / opencv 5.0.0.93 / pyclipper 1.4.0）保持原样未动
- 顺带修复两处既有语法笔误：`tools/ocr_pipeline.py:1215` `* *q` → `**q`、
  `tools/deep_chapters.py:448` `* *sec` → `**sec`（原本导致两脚本无法导入）
- 验证：新旧版对同一清晰印刷 PDF 的 OCR 结果逐字一致（CER 均 0.0000，零回归）；
  `verify_all` ALL GREEN；新版价值在于上述修复覆盖的拍照痛点场景，
  理想测试图无法体现，需在斜拍/EXIF 旋转样本上复验
- 回退：旧包备份在工作区 `_tess_build/rapidocr_backup`（不入库）

## 附：便携版脚本保持独立配置的说明

`release/AstralPath-Portable-2.6.0/tools/` 下的 `ocr_pipeline.py` / `deep_chapters.py`
是发布包内的独立副本，路径布局与主 `tools/` 不同（行数与路径基准均有差异），
且原本不含上述两处语法笔误。本次**未覆盖便携版副本**，避免破坏其相对路径引用；
其 RapidOCR 依赖随便携版 ocr-venv 独立存在，升级需另行重打包发布。
