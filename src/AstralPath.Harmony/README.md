# AstralPath.Harmony —— 知债：星穹学途 HarmonyOS 版

用 ArkTS + ArkUI 实现的第四端，与现有 Windows EXE、Android APK、单文件 Web 同源：
同一套公式常量、同一套数据分片、同一套模型接口，界面与交互对齐单文件版。

目标设备：**HUAWEI Mate 90 系列、Mate X7 折叠屏**（HarmonyOS 7.0.0 / API 26）。

---

## 1. 工程结构

```
src/AstralPath.Harmony/
├── AppScope/                          # 应用级（bundleName / 版本 / 图标）
│   ├── app.json5
│   └── resources/base/{element/string.json, media/app_icon.png}
├── entry/                             # 主模块（phone / tablet / 2in1）
│   ├── build-profile.json5            # 模块构建配置
│   ├── hvigorfile.ts                  # 模块构建脚本（hapTasks）
│   ├── oh-package.json5               # 模块依赖（hypium / hamock 仅测试用）
│   └── src/main/
│       ├── module.json5               # abilities / pages / deviceTypes / 权限
│       └── ets/
│           ├── entryability/EntryAbility.ets   # 入口：初始化存储 + 监听窗口尺寸
│           ├── pages/
│           │   ├── Index.ets          # 主壳：顶部栏 + 导航 + 内容区（折叠自适应）
│           │   ├── HomePage.ets       # 起点
│           │   ├── MaterialsPage.ets  # 藏书阁
│           │   ├── GraphPage.ets      # 识网
│           │   ├── PapersPage.ets     # 试卷作业
│           │   ├── DebtPage.ets       # 知债（红边 / 计划 / 销账）
│           │   ├── TodayPage.ets      # 今日（任务 + 答题）
│           │   ├── AgentPage.ets      # 智能体（流式对话）
│           │   ├── ProfilePage.ets    # 画像
│           │   ├── TeacherPage.ets    # 教师（k-匿名聚合）
│           │   └── AccountPage.ets    # 账户（密钥 / 授权 / 清数据）
│           ├── model/
│           │   ├── Models.ets         # Book / KNode / KEdge / Question / Plan / Debt ...
│           │   ├── FormulaConstants.ets  # 公式常量（与 C# / JS 同源）
│           │   └── DemoData.ets       # 示例教材（对齐 Web 版「导入示例教材」）
│           ├── service/
│           │   ├── FormulaService.ets # score-v2 / impact-v2 / sale-v2（逐行移植）
│           │   ├── StoreService.ets   # 五分片存储（preferences）
│           │   └── AiService.ets      # OpenAI 兼容接口 + SSE 流式
│           ├── common/Breakpoint.ets  # 断点 / 栅格 / 页面清单
│           └── components/            # （预留）DebtCard / QuizCard 等复用组件
│       └── resources/base/
│           ├── element/{string.json, color.json}
│           ├── media/app_icon.png
│           └── profile/main_pages.json
├── build-profile.json5                # 工程级：app.products（API 26）+ modules
├── hvigorfile.ts                      # 工程级构建脚本（appTasks）
├── hvigor/hvigor-config.json5
└── oh-package.json5
```

## 2. 关键配置要点

| 文件 | 关键项 |
|---|---|
| `AppScope/app.json5` | `bundleName: com.astralpath.harmony`，`versionName 2.6.0`，`targetAPIVersion 26` |
| `build-profile.json5`（根） | `app.products[0].compatibleSdkVersion/targetSdkVersion = "26.0.0"`、`runtimeOS: HarmonyOS` |
| `entry/src/main/module.json5` | `deviceTypes: [phone, tablet, 2in1]`；权限：`INTERNET`、`GET_NETWORK_INFO`；启动页 `pages/Index` |
| `hvigor/hvigor-config.json5` | **不要**声明 `@ohos/hvigor` / `@ohos/hvigor-ohos-plugin`（IDE 提供，写了会报 00302013）；但 `dependencies` 字段必须存在 |

签名：仓库不含签名材料。调试/模拟器用未签名包即可；真机与上架需在 DevEco Studio →
File → Project Structure → Signing Configs 生成证书，写回 `build-profile.json5` 的
`app.signingConfigs`（该文件已预留空数组）。

## 3. 可复用 / 需重写 / 迁移风险

**可直接复用（语义层，改动很小）**
- 公式常量与算法：`score-v2` / `impact-v2` / `sale-v2`、先修支撑与天花板、记忆稳定性。
  已逐行移植到 `FormulaService.ets` + `FormulaConstants.ets`，与 C# `FormulaConstants.cs`、
  JS 常量块 `K` 同源（`scripts/verify_constants.py` 负责 C#↔JS，ArkTS 侧建议加一条同样的对拍）。
- 数据模型与分片布局：`ap:meta / books / answers / plan / papers` 五分片，字段名沿用原实现，
  三端可互相导入导出。
- 试卷结构化规则：题头 / 选项 / 答案 / `1.A 2.B` 批量分发，与 `shared/exam.js` 同一套正则。
- 业务红线：危机词不作答、k-匿名（样本 <3 抑制）、fail-closed、可关闭个性化。

**需要重写（平台相关）**
| 能力 | 原实现 | 鸿蒙实现 |
|---|---|---|
| 渲染 | HTML/CSS + SVG 力导向图 | ArkUI 声明式组件；图谱改为「列表 + 详情双栏」 |
| 导航 | `nav.pills` + `main#p-*` 显隐 | `Index.ets` 单页壳 + 内部状态切换（折叠态胶囊 / 展开态侧栏） |
| 存储 | localStorage / IndexedDB | `@kit.ArkData` preferences（分片）；大文本走文件 |
| 网络 | fetch / EventSource | `@kit.NetworkKit` http（含 `requestInStream` 做 SSE） |
| OCR | tesseract.js / pdf.js（WASM） | 未接入：扫描版 PDF 走不了；文本类（TXT/MD）已由 `KgService` 接上 |
| 权限 | 无 | `INTERNET`、`GET_NETWORK_INFO`（已在 module.json5 声明并写明用途） |
| 推送/后台 | 无 | 未使用；如需再加 `ohos.permission.KEEP_BACKGROUND_RUNNING` |

**主要风险与应对**
1. **算法漂移**：三方（JS/C#/ArkTS）各存一份常量，容易各改各的。
   应对：把 `FormulaConstants.ets` 纳入对拍门禁（新增一条 ArkTS↔C# 校验，与
   `verify_constants.py` 同口径），任何一端改数值都必须同步。
2. **ArkTS 严格语法**：不支持结构化类型、内联对象类型、`any/unknown`、展开非数组。
   本次已按规则改写（显式接口 + 显式类型循环）；后续新增代码需遵守，否则编译不过。
3. **图谱渲染降级**：SVG 力导向图在 ArkUI 无直接对应。当前用列表 + 先修/后续面板表达，
   功能等价但视觉不同；若要 1:1 需用 Canvas 自绘。
4. **OCR 未接入**：包里没有 OCR 引擎与字库（这是 HAP 只有数百 KB 的主因，见第 8 节）。
   文本类资料（TXT / Markdown）已可解析建图谱；扫描版 PDF 需要后续接引擎。
5. **数据迁移**：Web 版导出 JSON 可直接读取（字段一致）；反向导入需注意
   `Record<string, Mastery>` 在 ArkTS 中的类型显式化。

## 4. 折叠屏自适应（Mate X7）

- 断点（`common/Breakpoint.ets`）：`SM < 600vp` / `MD 600–840vp` / `LG ≥ 840vp`。
- 形态：折叠态（SM/MD）顶部胶囊导航 + 单栏；展开态（LG）左侧固定导航（140vp）+ 右侧内容，
  内容区最大宽度 960vp 居中；`GraphPage` 在展开态直接是双栏（左列表 / 右详情）。
- 状态监听：`EntryAbility` 里 `win.on('windowSizeChange')` → 换算 vp → 写入 `AppStorage('layoutSize')`，
  页面用 `@StorageLink` 响应式跟随；折叠/展开、分屏、自由窗口都会触发。
- 多窗口：已声明 `continuable: true`，配合 `2in1` 设备类型；分屏时宽度变小会自动回落到 SM/MD 单栏。

## 5. 环境（已按实际存在性核对）

| 项 | 路径 | 核对结果 |
|---|---|---|
| DevEco Studio | `C:\Program Files\Huawei\DevEco Studio\bin\devecostudio64.exe` | ✅ 存在（版本 26.0） |
| OpenHarmony SDK | `C:\Users\18948\AppData\Local\OpenHarmony\Sdk` | ✅ 存在（`26.0.0`，含 ets/native/toolchains） |
| HarmonyOS SDK（系统镜像） | `C:\Users\18948\AppData\Local\Huawei\Sdk` | ✅ 存在（`system-image\HarmonyOS-7.0.0`，`apiVersion 26`） |
| 模拟器 | `C:\Users\18948\AppData\Local\Huawei\Emulator\deployed` | ✅ 已部署 **Mate 90 Pro**、**Mate X7**、MatePad Pro 13、MateBook Pro |
| 命令行工具 | `C:\Users\18948\Downloads\command-line-tools` | ✅ 存在（hvigorw 6.26.8 / ohpm / codelinter / arktsdoc / Emulator.bat） |
| 插件 | `C:\Users\18948\Downloads\codegenie-plugin` | ✅ 存在（codebase_feature_ask / embedding_model / lancedb_server） |
| DevEco Testing | `C:\Program Files\DevEco Testing\bin\DevEco Testing.exe` | ✅ 存在（168 KB）— 你给的第一版路径（与 DevEco 同路径）是错的 |

补充：`@ohos/hvigor` 与 `@ohos/hvigor-ohos-plugin` **不在公共 ohpm 仓库**（404），
只随 DevEco Studio 提供；因此纯命令行构建需把 `hvigor-config.json5` 的 `dependencies`
临时指向 IDE 内置目录（见第 6 节），常规开发用 IDE 打开即可。

## 6. 编译 / 运行 / 验证步骤

### 6.1 命令行编译（本次已验证：BUILD SUCCESSFUL，33 tasks）

```bat
cd /d C:\Users\18948\Documents\GitHub\Knowledge-Debt-Astral-Path\src\AstralPath.Harmony
set OHOS_SDK_HOME=C:\Users\18948\AppData\Local\OpenHarmony\Sdk\26.0.0
set HOS_SDK_HOME=C:\Users\18948\AppData\Local\Huawei\Sdk
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\tools\node

REM 1) 安装三方依赖（hypium / hamock）
"C:\Users\18948\Downloads\command-line-tools\bin\ohpm.bat" install

REM 2) 命令行模式下把 hvigor 指向 IDE 内置目录（仓库里建议保持为注释说明，按需启用）
REM    hvigor/hvigor-config.json5 → dependencies:
REM      "@ohos/hvigor": "file:C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor"
REM      "@ohos/hvigor-ohos-plugin": "file:C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor-ohos-plugin"

REM 3) 打 HAP
"C:\Users\18948\Downloads\command-line-tools\bin\hvigorw.bat" assembleHap --mode module -p product=default --no-daemon
```

产物：`entry\build\default\outputs\default\entry-default-unsigned.hap`（本次约 366 KB）。
未配置签名时会警告 `Will skip sign 'hos_hap'`，属预期。

排错要点（本次实际踩过）：
- `00302013 root node is not yet available`：hvigor-config 里声明了 hvigor 依赖，或有重复副本 → 去掉依赖、删掉 `node_modules/@ohos`。
- `api version parameter is illegal`：API 26 的版本串必须写成 `"26.0.0"`（10–25 才用 `'5.0.0(12)'` 形式）。
- `Schema validate failed`：根 `build-profile.json5` 顶层只能是 `app` 与 `modules`。
- `arkts-no-*` 系列：ArkTS 严格语法，按第 3 节风险 2 改写。

### 6.2 在模拟器上运行（Mate X7 / Mate 90 Pro）

```bat
REM 启动模拟器（折叠屏）
start "" "C:\Users\18948\Downloads\command-line-tools\bin\Emulator.bat" -name "Mate X7"
REM 或直板旗舰
start "" "C:\Users\18948\Downloads\command-line-tools\bin\Emulator.bat" -name "Mate 90 Pro"

set HDC=C:\Users\18948\AppData\Local\OpenHarmony\Sdk\26.0.0\toolchains\hdc.exe
"%HDC%" list targets                       REM 应出现 127.0.0.1:5555 之类
"%HDC%" install entry\build\default\outputs\default\entry-default-unsigned.hap
"%HDC%" shell aa start -a EntryAbility -b com.astralpath.harmony
"%HDC%" shell hilog | findstr /i astralpath   REM 看运行日志
```

也可以直接在 DevEco Studio 里：`Run > Run 'entry'`（或 `Shift+F10`），选择已部署的
Mate X7 模拟器；首次运行 IDE 会自动 Sync 并装包。

### 6.3 验证清单（对齐单文件版）

| 项 | 预期 |
|---|---|
| 首次启动 | 顶部显示「本机数据 · 无需联网」；起点页提示「暂无资料」 |
| 导入示例教材 | 起点/藏书阁出现「Python 从入门到实践（示例）」：14 节点、13 边、14 题 |
| 今日任务 | 按掌握度升序列出 5 条；点「开始练习」出现题干与 4 个选项 |
| 作答 | 提交后写入 answers 分片，并显示该知识点掌握度百分比 |
| 知债诊断 | 出现开放红边（影响分 ≥ 0.08），按 impact 降序 |
| 生成 14 天计划 | 产出计划条目，每天 ≤ 40 分钟，同一知识点间隔 ≥ 1 天 |
| 销账检查 | 连续达标 2 次且累计 ≥ 3 次作答后结清 |
| 教师页 | 样本 < 3 的知识点不出现（k-匿名抑制） |
| 智能体 | 未配密钥时明确标注演示模式；危机词命中时不作答并给出求助提示 |
| 折叠屏 | Mate X7 折叠态：顶部胶囊导航、单栏；展开态：左侧导航 + 右侧双栏；切换时布局实时跟随 |
| 分屏 | 宽度变窄后自动回落到单栏布局 |

### 6.4 用 DevEco Testing

`C:\Program Files\DevEco Testing\bin\DevEco Testing.exe`（注意：不是 DevEco Studio 那个路径）。
可做稳定性/性能/基础质量测试；命令行侧用 `command-line-tools\bin\codelinter.bat`
做静态检查（ArkTS 规范）。

## 7. 参考

- 官方文档中心：<https://developer.huawei.com/consumer/cn/doc/doccenter>
- ArkTS 语法约束：搜索 `arkts-no-structural-typing` / `arkts-no-untyped-obj-literals`
- 折叠屏适配：搜索 `一次开发多端部署` / `响应式布局`

## 8. 已知缺口（对照单文件版逐项列）

**已实现**：10 个页面与导航、公式与债边诊断（含递归先修得分）、14 天计划、销账、
五分片存储、教材列表与切换、TXT/MD 解析建图谱、意图路由（24 个意图的本地答复）、
危机词拦截（11 个，与 `tools/agent-intents.json` 同源）、折叠屏自适应、模型流式对话。

**还没做**（按影响排序）：

| 缺口 | 说明 | 代价 |
|---|---|---|
| OCR（扫描版 PDF） | 无 tesseract/RapidOCR 引擎与字库，扫描件只能走文本层 | 包体积 +10~20 MB，需 Native 或 WASM 移植 |
| PDF/PPT/Word/EPUB 解析 | 目前只认 TXT/MD | 中等（PDF 文本层解析约几百行） |
| 图谱可视化 | 现在是列表 + 先修/后续面板，不是力导向图 | Canvas 自绘，约 200 行 |
| What-if 模拟 | 滑杆调参数看债边变化 | 小（纯本地公式） |
| 债边叙事解读 / 计划复盘 | 需要模型参与，也可本地模板化 | 小~中 |
| 拍照识别试卷 | 相机 + 图像预处理 | 中 |
| 敏感词脱敏 | Web 版在入库前脱敏，鸿蒙版还没做 | 小 |
| 内置演示密钥 | Web/单文件版内置了一份演示密钥，鸿蒙版没有 | 小（但有合规考量，建议不内置） |
| 帮助中心 / 术语词典 | Web 版有引导与词典 | 小 |

**包体积说明**：HAP 现在约 410 KB（debug，含 93 KB sourcemap；release 约 310 KB）。
对比 Android APK 11 MB、单文件 Web 33 MB，差距几乎全部来自「没有内联 OCR 引擎与字库」
（tesseract 核心约 10 MB ×2、中英文字库约 5 MB、pdf.js 与 WASM 若干）。
功能代码本身（ArkTS 字节码 252 KB）并不比其它端少多少。
是否要把 OCR 搬进来，取决于你要不要「拍照/扫描版教材直接解析」这条能力——
要的话包会涨到 10 MB 量级，不要的话当前体积就是合理的。
