# AstralPath.NativeApp · 原生安卓端（Kotlin + Jetpack View 体系）

无 WebView 的**原生实现**：公式内核、计划调度器、意图路由、分片存储均为
`shared/`（Web 事实源）与鸿蒙版（ArkTS）的同构 Kotlin 移植。与 `src/AstralPath.Native`
（Kotlin WebView 壳，加载单文件产物）并存，二者互补：壳版功能最全（浏览器内 OCR），
本模块纯原生、启动快、无 33MB 资产。

## 构建与安装

```bash
# 前置：JDK 17+、Android SDK（API 35）、Gradle 9.x（本机验证组合：Gradle 9.7.1 + AGP 9.0.0）
cd src/AstralPath.NativeApp
echo 'sdk.dir=C\:\\path\\to\\Android\\Sdk' > local.properties   # 本机路径，不入库
C:/Gradle/bin/gradle.bat assembleDebug testDebugUnitTest --no-daemon
# 产物：app/build/outputs/apk/debug/app-debug.apk（debug 签名，可直接安装）
```

发布 APK 统一复制到仓库 `release/AstralPath-NativeApp-<version>.apk`。
release 构建默认回退 debug 签名；正式上架时配置 `ASTRALPATH_KEYSTORE` 四件套环境变量
（与 Native 壳共用同一密钥，见 `release/build-release.ps1`）。

## 功能清单（v2.6.0 · 与四端对齐）

| 模块 | 说明 |
|---|---|
| 起点页 | 导入示例教材（14 节点/13 边/14 题 + 演示学情，红边可复现） |
| 藏书阁 | TXT/MD/HTML/DOCX/PPTX/EPUB 导入 → KgService 分章建图（PDF 文本层抽取见下方限制） |
| 识网 | 自绘力导向图谱（GraphView：斥力+弹簧+向心力 220 轮），红边红色描粗、点选看先修/后续 |
| 知债 | impact-v2 诊断、债务解读、What-if 滑杆、销账检查、计划复盘 |
| 14 天计划 | 完整 PlanScheduler 移植：逐日容量/三遍复习/K1–K5 合约/fixK2 重排/延期明示 |
| 今日 | 掌握度最低优先任务、答题信心滑条（进销账与掌握度） |
| 智能体 | 25 意图锚点路由 + 11 危机词转介（常驻对话框）+ MiMo 流式（可停止、取消保留半文） |
| 画像/教师 | 掌握分布、opt-out、k-匿名聚合视图（fail-closed） |
| 账户 | 密钥本机存储、免打扰开关、授权、演示数据/全量重置 |

## 与其他端的差异（如实声明）

- **PDF**：原生端不做文本层抽取（Android 平台无对应 API）；扫描页 OCR 亦未接入。
  这两类输入请用 Web 单文件版（pdf.js + WASM OCR）或 Windows 壳。
- **拍照识别试卷**：同上，用 WebView 壳版；原生 v1 支持粘贴文本结构化（ExamService）。
- 词表（危机词/意图锚点）与 Web 登记表逐条一致，已由 `verify_agent_intents.py`
  第七方对拍覆盖（鸿蒙侧同批）；安卓侧词表与鸿蒙侧为同一份人工同步，改动需双端联动。

## 已验证

- `assembleDebug testDebugUnitTest` BUILD SUCCESSFUL；JVM 测试 5 项（公式阈值/调度合约/销账步进/先修天花板）
- 模拟器（API 35）实机走查：安装 → 导入示例 → 识网红边 3 条 → 知债诊断（影响分 0.422/0.372）
  → 生成 18 条计划且 K1–K5 徽标通过 → 计划条目含 label/why，全程零崩溃
