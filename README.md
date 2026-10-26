# 知债：星穹学途（Knowledge Debt: Astral Path）

上多门课的时候，卡住你的往往不是「这一章没听懂」，而是前面某门课的概念没打好，欠下的这笔账越滚越大。我们管它叫知识债。

这个项目做的事其实就四步：把你欠的先修概念找出来，排一张 14 天内做得完的补课表，陪着你练，练熟了把这条债销掉。分数、影响分、销账这些数字都是本地公式算的，大模型不许改。作为学生作业和竞赛作品，它也能提醒别人：AI 不该随便给学生下判断，这条线得由代码来守。

> 2026 iCAN AI / DuMate 竞赛作品，版本 2.6.0（contract-v2.2.0-algo-v2），支持 Windows 10/11 与 Android 8.0 以上。
>
> 名字的事说清楚：全称「知债：星穹学途（Knowledge Debt: Astral Path）」，中文简称「知债：星穹学途」，代码标识 AstralPath。以前用过「知债图 / ZhiZhaiTu」，已经废弃，不要再用。

---

## 目录

1. [产品简介](#1-产品简介)
2. [交付物](#2-交付物)
3. [快速开始](#3-快速开始)
4. [功能模块](#4-功能模块)
5. [核心公式](#5-核心公式)
6. [系统架构](#6-系统架构)
7. [测试与门禁](#7-测试与门禁)
8. [开发者指南](#8-开发者指南)
9. [四人分工](#9-四人分工)
10. [演示账号与伦理](#10-演示账号与伦理)
11. [变更记录](#11-变更记录)

---

## 1. 产品简介

拿会计举例：借贷记账法听不懂，多半是「会计等式」没打牢。系统能顺着教材的先修关系把这种债找出来，按影响大小排序，再生成一张补得完的课表。

| 步骤 | 说明 | 类比 |
|---|---|---|
| 诊断 | 找出「会计等式到借贷记账法」这类断掉的先修边 | 体检找病灶 |
| 计划 | 14 天补课表，每天不超过 40 分钟，按 0/2/6 天间隔复习 | 开药方 |
| 练习 | 做真题，自己报信心（1 到 5 分），系统按你的状态挑题 | 吃药复查 |
| 销账 | 连续 2 次达标且累计作答不少于 3 次，这条债就算结清 | 痊愈出院 |

Web、Windows、Android 三个端用的是同一套页面和同一套设计，功能没有差别。单文件版完全离线，数据只留在你自己的机器上。

## 2. 交付物

| 产物 | 路径 | 说明 |
|---|---|---|
| Web 单体版 | `deploy/monolith-web/index.html` | 一个 HTML，浏览器直接打开就能用，功能完整 |
| 自包含单文件 | `deploy/monolith-web/astralpath-monolith.html` | 约 31 MB，OCR 和 ONNX 运行时都塞进去了，断网可用 |
| Windows 安装包 | `release/AstralPath-Monolith-Setup-2.6.0.exe` | WebView2 壳加载同一份 HTML，本机装过一遍 |
| Windows 便携版 | `release/AstralPath-Portable-2.6.0/`（及同名 zip） | 解压即用，.NET 10 自带运行时 |
| Android APK | `release/AstralPath-Android-2.6.0-Store.apk` | WebView 同构加离线核心，versionCode 36，商店签名 |
| 题库 | `eval/question_bank.json` | 100 题，覆盖 34 个知识点，难度 1:21 / 2:51 / 3:28 |
| 图包 | `graph-packs/astralpath-v2/graph_pack.json` | 34 节点 74 边（先修 50 条 + 跨课迁移 24 条），无环，横跨三门课 |
| 教材思维导图 | `kg-deep-test/*.mindmap.{json,md}` | 13 本教材 6,720 页，2,519 节点 2,662 边 |
| 工具链 | `tools/*.py` | OCR、章节、构图、思维导图全链路 |
| 架构决策 | `docs/adr/` | ADR-0002：单文件零外部依赖与构建期常量注入 |

## 3. 快速开始

### 3.1 单体版（零依赖，推荐）

```powershell
# Web：双击打开
deploy\monolith-web\index.html

# Windows：安装包或便携版
release\AstralPath-Monolith-Setup-2.6.0.exe
# 或者解压 release\AstralPath-Portable-2.6.0.zip 后运行 AstralPath.Monolith.exe
```

起点、藏书阁、识网、知债、今日、智能体、画像、账户这些页面的计算全在本机完成，数据存在浏览器里，可以导出 JSON 带走。

### 3.2 Android

安装 `release/AstralPath-Android-2.6.0-Store.apk`。没电脑、没 adb 也能离线用核心功能。

### 3.3 源码构建

```powershell
# 环境：.NET 10 · Android workload · JDK 17 · Gradle
dotnet test tests/AstralPath.Core.Tests -c Release
dotnet test tests/AstralPath.Persistence.Tests -c Release
dotnet test tests/AstralPath.Desktop.Tests -c Release
dotnet test tests/AstralPath.Api.Tests -c Release
dotnet test tests/AstralPath.Eval.Tests -c Release
```

注意 `dotnet test` 一次只能接一个项目，所以这里是分开跑的。

## 4. 功能模块

| 模块 | 做什么 |
|---|---|
| 起点 | 总览、快捷入口、资料数与开放债边统计 |
| 藏书阁 | PDF 与文本本机解析，转章节、关键词并出题；扫描版走离线 OCR |
| 识网 | 知识图谱（TextRank、PMI、依赖句式），看瓶颈与关键路径，分层布局 |
| 知债 | 找出影响分最高的红边，能试算「如果补上会怎样」，生成 14 天计划 |
| 今日 | 每天不超过 3 项任务，做题、报信心（1 至 5）、判分 |
| 智能体 | 听懂你想干什么，危机词命中立刻转人工，敏感词脱敏，读的是真实学情 |
| 试卷作业 | 拍照、截图、粘贴图片或导入文件，识别后自动结构化并生成知识点层级图谱 |
| 画像 | 信心校准（Brier）、学习风格五轴、k-匿名，可随时关闭 |
| 教师 | 只读学情视图，需学生授权，含薄弱热点、红边清单与近七日趋势 |
| 账户 | 登录、授权、导出与重置 |

## 5. 核心公式

```text
score = min( 0.50·know + 0.30·retention + 0.20·prereqSupport , 0.55+0.45·min(prereq) )
know   = 0.85·Beta(成功,失败) + 0.15·(conf/5)
retention = exp(-age/S);  S = 2.5·(1+0.45·streak) · (1+0.25·ln(1+reps))

impact = 0.55 · σ((sf-0.55)·8) · σ((0.50-st)·8) · w · cross · (1+0.12·ln(1+下游)) · (1+0.08·ln(1+freq))
cross  = 1.0 | 1.15 (transfer_gap)；命中 freq>0 ∧ impact≥0.08

销账 ⇔ 近期连续 2 次达标 ∧ 累计 ≥3 次；Weighted=0.7·acc+0.3·(conf/5)≥0.65
```

代码在 `src/AstralPath.Core/`，全是纯函数，和金标准结果逐位比对（误差 1e-6 以内）。这几个数字只能由公式算出来，LLM 不许改写；`cleared` 只有 `SaleStateMachine` 能写。

## 6. 系统架构

```text
AstralPath.Core/          纯函数：公式 / 图 / OCR / 画像 / 销账 / 计划
AstralPath.Api/           ASP.NET Core（Web 与 Windows 共用）
AstralPath.Desktop/       WebView2 壳
AstralPath.Native/        Android WebView 壳（已上架）
AstralPath.Monolith/      无微服务 Windows 壳（Setup-2.6.0）
AstralPath.Persistence/   Postgres（默认）+ memory 回退
tests/                    Core 114 · Persistence 8 · Desktop 50 · Api 70 · Eval 2（合计见 §7，由 scripts/verify_metrics.py 自动对拍）
```

以前做过的旧方案（Java 壳、Avalonia 壳、微服务空壳等）都收在 `attic/`，不参与构建，想看可以翻 `attic/README.md`。

持久化默认走 PostgreSQL 加 pgvector（`Persistence:Mode=postgres`），连接串可用 `Persistence__ConnectionString` 覆盖；连不上且 `AllowMemoryFallback=true` 时降级到内存实现，不会挡着你用。

## 7. 测试与门禁

| 套件 | 通过 | 说明 |
|---|---|---|
| Core.Tests | <!-- metrics:tests-Core -->114<!-- /metrics:tests-Core -->/114 | score、impact、sale、计划、图谱、金标准对拍（1e-6）与画像、智能体 v3 回归 |
| Persistence.Tests | <!-- metrics:tests-Persistence -->8<!-- /metrics:tests-Persistence -->/8 | Postgres 与 InMemory 双模式 |
| Desktop.Tests | <!-- metrics:tests-Desktop -->50<!-- /metrics:tests-Desktop -->/50 | Avalonia 原生 UI 绑定与导航 |
| Api.Tests | <!-- metrics:tests-Api -->70<!-- /metrics:tests-Api -->/70 | 上传、解析、诊断、计划、agent 与 P0/P1 回归 |
| Eval.Tests | <!-- metrics:tests-Eval -->2<!-- /metrics:tests-Eval -->/2 | 合成数据回归 |
| 合计 | <!-- metrics:tests-Total -->244<!-- /metrics:tests-Total -->/244 | 零回归（原 MobileCore 84 例跑的是过时的 Core 分叉，已随档移除） |

表里的数字由 `scripts/verify_metrics.py` 从代码和登记表自动核对（`<!-- metrics:* -->` 标记），对不上 CI 会失败，不用人盯。

一键验收：

```powershell
pwsh -NoProfile -File scripts\verify_all.ps1     # 31 步全部通过
```

这个脚本会依次查：常量是否对齐、公式常量生成区（`K` 由 `FormulaConstants.cs` 生成）、意图表多方核对（<!-- metrics:agent-intents -->26<!-- /metrics:agent-intents --> 个意图，危机词 <!-- metrics:crisis-words -->11<!-- /metrics:crisis-words --> 个）、公式跨语言对拍、前端脚本语法、XSS 用例（14 例）、共享内核行为等价、生成区一致性（9 区）、状态分片用例（10 例）、试卷/教材文本/智能体路由/计划调度用例（29 例）、空 catch（151 个 .cs 文件里不允许有）、命名规范、三端 HTML 是否一致、图谱性能预算、覆盖率阈值，以及 `dotnet format` 和 eslint。

持续集成在 `.github/workflows/ci.yml`，push 和 PR 都会跑构建、测试和上面这些检查；覆盖率是硬指标（行 ≥50%、分支 ≥40%，不到就红）。另外有两个独立作业：Android 打包验证、Playwright 浏览器冒烟。CI 刚搭起来时红过三处，都修了：OcrHost 的 tessdata 兜底路径没查存在性、Windows runner 控制台默认 cp1252 导致中文输出崩掉、生成块比对没归一换行。

## 8. 开发者指南

```powershell
# 环境
dotnet --version        # ≥ 10
dotnet workload list    # android
java -version           # 17（打包 APK）

# 跑 API（可选全功能模式）
dotnet run --project src/AstralPath.Api --urls http://127.0.0.1:5190

# 打 Android APK（路径必须纯 ASCII，否则 AAPT2265）
$env:JAVA_HOME="C:\Temp\jdk-17"
& "C:\Gradle\bin\gradle.bat" -p src/AstralPath.Native assembleRelease

# 打 Windows 单体安装包
dotnet publish src/AstralPath.Monolith -c Release -r win-x64 --self-contained -o src/AstralPath.Monolith/publish
& "C:\Program Files\Inno Setup 7\ISCC.exe" src/AstralPath.Monolith/setup-monolith.iss
```

NuGet 报 `path1=null` 的话，把 `PROGRAMDATA`、`PROGRAMFILES(X86)`、`ALLUSERSPROFILE` 三个环境变量补齐，再设 `CheckEolWorkloads=false`。

前端共享代码只在 `shared/` 里维护一份，页面里的副本由 `python scripts/gen_frontend_regions.py` 刷进 `deploy/monolith-web/index.html` 的生成区，`--check` 用在 CI 里。改完生成区记得跑 `scripts/sync-monolith-html.ps1` 同步三端镜像，并把 `scripts/build-single.py` 里的 `EXPECTED_MD5` 重算一遍（小写）。

单文件构建还需要 `deploy/monolith-web/ort-runtime/` 下的 `ort.min.js` 和 `ort-wasm-simd-threaded.wasm`（走 LFS），构建时会内联进产物，所以产物里没有任何外部 `src`/`href`。调试信息都收在 `?debug=1` 的隐藏面板里，平时界面上看不到工程术语。

前端检查用 `npm ci` 后 `npm run lint`（eslint）；C# 侧用 `dotnet format whitespace AstralPath.slnx --verify-no-changes`。

## 9. 四人分工

| 角色 | 负责 |
|---|---|
| P1 | 文案、禁词、危机词、隐私、演示脚本 |
| P2 | 公式、Core、API、金标准用例 |
| P3 | 图包、题库、金标准用例、工具链、验收脚本 |
| P4 | 单文件 UI、安卓壳、Windows 安装包 |

分工边界和交接方式在团队内部维护；仓库里只留能跑的代码和门禁，一次性文档不进仓库。

## 10. 演示账号与伦理

演示账号 `demo@astralpath.local` / `demo123456`，另有 `demo-student-a`。

三条红线：数字只能由公式算出来，AI 不许改分；不发明先修边；`cleared` 只由状态机写入。

隐私方面：教师侧做 k-匿名，样本少于 3 人一律不显示；危机域和敏感域不进画像；用户随时可以 opt-out。危机词命中时只做安抚和转人工，不评价学生。

## 11. 变更记录

| 版本 | 日期 | 要点 |
|---|---|---|
| 2.6.0 第三轮工程整改 | 2026-10-25 至 26 | 单文件不再依赖外部 CDN（ORT 运行时内联）；公式常量改成从 C# 生成；覆盖率变成硬指标；图谱性能预算、`dotnet format` 和 eslint 进 CI；教材文本、智能体路由、计划调度搬进 `shared/` 并补了用例；首页工程信息收进 `?debug=1` 面板 |
| 2.6.0 | 2026-10-17 | 版本号统一（前端、C# 程序集、gradle、iss、文档）；双端安装包发到 GitHub Release v2.6.0；打包链加了签名环境自动加载与 tessdata 自动保障，打包基本不用管 |
| 2.6.0 第一轮工程整改 | 2026-10-18 | 搭 CI 与静态检查（脚本解析检查、XSS 用例、禁止空 catch）；前端共享代码收进 `shared/`；意图表从三方核对扩到六方，26 个意图一致 |
| 2.6.0 第二轮工程整改 | 2026-10-18 至 19 | 密钥信封 v2（轮换与吊销）；本地状态分五片存，旧数据自动迁移并留备份；意图路由器从 479 行减到 281 行；加运行期诊断与 `/health/ready`；前端构建合并成一键 |
| 2.6.0 纯前端同步 | 2026-10-19 | 主仓库的前端改动反向同步到纯前端源目录，两边 `index.html` 与单文件产物逐字节一致 |
| 2.6.0 CI 修复 | 2026-10-19 | 修 OcrHost tessdata 兜底存在性检查、Windows runner 强制 Python UTF-8、生成块比对归一换行 |
| 2.5.0 | 2026-10-10 至 15 | AI 计划官与债务解读，K1 至 K5 合约引擎；试卷作业错题直拍识别与多格式导入；教师只读学情视图与作业单互传；内置演示密钥；思维链流式呈现与垫题秒出 |
| 2.2.0 | 2026-09-25 至 28 | RapidOCR 接入生产，三端抽样验收 12 本 PDF 通过，算法 v3 与画像、智能体 v3 落地，修了一批审计问题，测试 235 项 |
| 2.0.0-algo-v2 | 2026-09-24 | score-v2、impact-v2、sale-v2，图谱 v2，OCR v2，画像 v2，100 题库与 34 节点 74 边图包，Postgres 默认持久化，Avalonia 原生 UI，无微服务单体版 |
| 1.4.x 至 1.5.0 | 2026-09 | 智能体接真实学情，启动预热，上传分片，WebView 同构壳，商店签名 |

---

© 2026 知债：星穹学途四人团队
