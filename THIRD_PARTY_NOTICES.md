# 第三方组件声明（THIRD PARTY NOTICES）

本项目（知债：星穹学途 / Knowledge Debt: Astral Path）在单文件产物与构建工具链中使用了以下第三方组件，按许可要求在此致谢并声明。各组件均以**原包独立使用**，未修改其源码（构建期内联属于打包搬运，注释性适配均已标注出处）。

**核查口径**（本表不是"看一眼写个大概"）：
- 版本线索优先取**实装产物内嵌的版本串**（如 `ocr-engine/pdf.min.js` 内的 `version:"3.32.2"`、
  `ocr-engine/ocr-wasm.js` 内的 `tesseract.js v5`），而非依赖清单声明——本仓库 `requirements.txt`
  只登记门禁脚本依赖且当前为空，Python 侧包版本以各端 `tools/` 下实装环境为准。
- 许可取值按各组件官方 LICENSE 的 SPDX 标识；**发布前需复核许可文本是否随包提供**（Apache-2.0 要求保留 NOTICE）。
- 最近核查：2026-11-11（对 `deploy/monolith-web/` 内联产物逐个读出版本串并回填）。

## 随单文件分发（`deploy/monolith-web/astralpath-monolith.html` 内联）

| 组件 | 版本线索 | 许可 | 用途 | 来源 |
|---|---|---|---|---|
| pdf.js（pdf.min.js / pdf.worker.min.js） | 3.32.2（min 产物内嵌）；包形态 pdfjs-dist 3.11.174 | Apache-2.0 | PDF 渲染与文本层提取（文本层优先管线第一级） | https://github.com/mozilla/pdf.js |
| tesseract.js（tesseract.min.js / worker.min.js） | v5（ocr-wasm.js 内嵌） | Apache-2.0 | 浏览器内 OCR 工作线程调度 | https://github.com/naptha/tesseract.js |
| tesseract-core-simd-lstm.wasm.js / tesseract-core-lstm.wasm.js | Tesseract WASM 内核 | Apache-2.0 | LSTM 识别内核（SIMD/标量双份，按设备能力选择） | https://github.com/naptha/tesseract.js-core |
| chi_sim.traineddata / eng.traineddata | Tesseract 语言包 | Apache-2.0 | 中文简体与英文识别模型（gzip+base64 内嵌） | https://github.com/tesseract-ocr/tessdata |
| onnxruntime-web（ort.min.js / ort-wasm-simd-threaded.wasm） | 1.x | MIT | 轻量意图分类模型的浏览器推理运行时（已内联，运行期零外部请求） | https://github.com/microsoft/onnxruntime |

## 构建与宿主侧（不随单文件分发）

| 组件 | 许可 | 用途 |
|---|---|---|
| RapidOCR（Windows 宿主桥识别后端，pip 包 `rapidocr_onnxruntime`；版本以 `tools/ocr-venv/` 实装为准，非本仓库锁定） | Apache-2.0 | 扫描页宿主侧识别（`tools/ocr_pipeline.py` 阶梯） |
| .NET / ASP.NET Core / WebView2 | 各自许可（MIT / MIT / Microsoft 软件许可） | C# 后端与 Windows 壳运行时 |
| Playwright（e2e 测试） | Apache-2.0 | 浏览器端到端验证 |
| xUnit / Avalonia / CommunityToolkit.Mvvm | Apache-2.0 / MIT / Apache-2.0 | 测试与 Avalonia 视图层 |

## 设计概念致谢（未复制代码，仅借鉴思路）

| 来源 | 借鉴内容 |
|---|---|
| liquid-glass-react | 「液态玻璃」视觉效果的实现思路（账户页可选开关，CSS 自研） |
| DeepTutor（HKUDS，Apache-2.0） | 流式 UI 三项机制的实现思路：自适应打字机（时间限流）、正文内嵌 `<think>` 段分离、用户取消语义（取消保留已产出内容）。均为本项目自主实现，见 `shared/stream-ui.js` 与 `shared/integrations/p0-ai-integration.js` 注释 |
| ClassIsland / Class Widgets 2 | 可靠性机制借鉴：单实例互斥、启动失败恢复模式、通知分级队列、状态翻转驱动提醒（均自主实现） |

## 服务说明

- 小米 MiMo 开放接口（`api.xiaomimimo.com`）为**可选的云端增强服务**，不属于本分发物；未配置密钥时应用以本地规则引擎完整运行，界面如实标注「演示模式」。

以上组件的许可文本副本可在各组件官方仓库获取；如持有者认为本文件的署名方式需要调整，请提交 issue 联系我们。
