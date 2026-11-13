# AGENTS · 仓库结构与协作约定

面向在本仓库工作的开发者与 AI 助手。改代码前先读这一页，能避开绝大多数返工。

## 维护契约与事实源优先级

- **事实源优先级**：冲突时按 `scripts/` 下实际执行的门禁脚本 > 本文件 > `README.md`。
  门禁脚本是「代码说了算」的那一层，文档与之矛盾时改文档、别去削弱门禁。
- **同提交更新**：改动仓库结构、目标框架、生成区、门禁脚本、公开数字口径、
  安全/验证链路（密钥、授权、脱敏、AI 路由、产物构建）时，必须在**同一次提交**里
  更新本文件与 `THREAT_MODEL.md` 对应条目。「改了代码、文档回头再说」= 未完成的改动。
- **嵌套规则**：子树级约定写进该子树的 `AGENTS.md`（`src/AstralPath.Harmony/`、
  `src/AstralPath.NativeApp/` 各一份）。根规则全库适用，子树规则只加增量。
- **新增文档前先问**：有没有旧文档可改。本仓库承重文档在根目录，`docs/` 当前为空。

## 仓库形状（Repo Shape）

| 目录 | 内容 | 约束 |
|---|---|---|
| `src/AstralPath.Core` | 纯函数域逻辑：公式 / 图 / OCR / 画像 / 销账 / 计划 / 智能体 | 不碰 DOM、不碰 IO；行为由金样（1e-6）锁定 |
| `src/AstralPath.Api`、`Api.Core` | ASP.NET Core（Web 与 Windows 共用） | — |
| `src/AstralPath.Desktop`、`Monolith` | Windows 壳（WebView2） | 壳只做宿主：窗口 / 托盘 / OCR 桥，业务逻辑不进壳 |
| `src/AstralPath.Native` | Android 壳（Kotlin + WebView） | 同上 |
| `src/AstralPath.Shared` | Avalonia 视图层（Desktop.Tests 覆盖） | — |
| `shared/` | 前端共享逻辑源（唯一编辑点） | 见下「前端改动铁律」 |
| `deploy/monolith-web` | `index.html`（页面源）+ 单文件构建产物 | — |
| `contracts/`、`eval/` | OpenAPI 与金样 / 评测资产 | 金样文件不要手改，跑生成器 |
| `graph-packs/` | 内容包（`pack.json` 清单规范见包内 README） | — |
| `scripts/`、`tools/` | 门禁与构建脚本 / Python 工具链 | — |
| `attic/` | 停用代码档案馆 | 不参与构建；复活用 `git mv` 回原位 |
| `THREAT_MODEL.md` | 威胁模型（活文档，改验证逻辑必须同提交更新） | 由 `scripts/verify_threat_model.py` 校验 |

## 前端改动铁律

1. **唯一编辑点**：改 `shared/*.js` 或 `deploy/monolith-web/index.html`，然后跑
   `powershell -File scripts/sync-monolith-html.ps1` 同步到 Windows / Android 两份镜像。
   手改镜像 = 门禁必红。
2. **生成区**：`shared/` 经 `scripts/gen_frontend_regions.py` 内联进页面
   `/* AP:BEGIN … DO NOT EDIT */` 标记内。标记内不要手改；新增共享模块时在
   `gen_frontend_regions.py` 的 REGIONS 登记，并在页面插入标记对后跑一次生成器。
3. **棘轮**：`scripts/verify_inline_js.py` 限制手写内联 JS 行数（只许降不许涨）。
   新逻辑一律进 `shared/`，页面里只留最少量胶水；每搬完一段就手动下调上限。
4. **XSS**：页面动态插值用 `esc()`；新 DOM 构建优先 `textContent/createElement`。

## 数字与文案

- 意图数 / 危机词 / 测试数等公开数字由 `scripts/verify_metrics.py` 从代码与
  `tools/agent-intents.json` 自动对拍（README 中 `<!-- metrics:* -->` 标记）。
  改了表或测试数后：先跑一次不带 `--check` 的 `verify_metrics.py` 回写 README，再提交。
- 用户可见文案不出现内部术语（版本号、接口地址、存储实现等）；工程排查信息进
  `?debug=1` 调试面板。

## 门禁与验证

```powershell
pwsh -NoProfile -File scripts/verify_all.ps1     # 全量（CI 同款，含 release-version 与 threat-model）
node scripts/store_runner.js                      # 单跑某个金样 runner
python scripts/verify_metrics.py                  # 数字回写
python scripts/build-single.py                    # 重建 17MB 单文件产物（会校验基座 md5）
```

约定：新增纯逻辑模块时，同时交付一个 `scripts/<name>_runner.js` 金样用例并在
`verify_all.ps1` 登记；改 C# 壳后至少 `dotnet build src/AstralPath.Monolith` 过一遍。

## 最小有用证据矩阵（改什么，跑什么）

| 改动类型 | 最小证据 |
|---|---|
| JS 常量/词表 | `verify_constants` + `verify_agent_intents`（词表还涉及鸿蒙方对拍） |
| shared/ 模块 | 对应 runner（如 `store_runner.js`）+ `check-js` + `frontend-regions` |
| 页面交互 | `npx playwright test`（演示链路两条） |
| 公式/调度 | `plan_scheduler_runner.js`（金样源在 shared，先改 JS 侧） |
| C# 逻辑 | `dotnet test`（对应套件）+ `dotnet format --verify` |
| C# 壳 | `dotnet build src/AstralPath.Monolith` + 手工冒烟 |
| 样式/HTML | `sync-monolith-html` md5 一致 + 单文件重建基线 |
| 公开数字 | `verify_metrics.py`（先回写 README 再提交） |
| 发布版本号 | `verify_release_version.py`（单一事实源是 `Directory.Build.props`；打包脚本开头也会拦） |
| 威胁模型 / 安全链路 | `verify_threat_model.py` + 同提交更新 `THREAT_MODEL.md` |
| 默认配置 / DPI | `verify_defaults.py`、`verify_dpi.py`（新增状态字段 / 新增 Windows 壳时必跑） |

## 代码风格

- 中文注释，写「为什么」而不是「做了什么」。
- `catch` 不许为空：要么 `Diag.Recover(ex, …)`（C#），要么记录或显式降级（JS/Py）——
  `verify_no_empty_catch.py` 会拦。
- 命名遵循 `scripts/naming_consistency.py`（全称「知债：星穹学途」，代码标识 AstralPath）。

## 代码地图（短而稳定；代码移动时同提交更新本表）

| 关键符号 | 位置 | 角色 |
|---|---|---|
| `Version`（唯一事实源） | `Directory.Build.props` | 全仓版本号；csproj 不许再写死 |
| `esc()` / `safeRich()` / `sanitizeUrl()` | `shared/safe-dom.js` | DOM 注入防线；XSS 黄金用例的对拍对象 |
| `APStore` 分片存储 | `shared/store.js` | 五分片 + schema 版本 + 旧键迁移留底 |
| `DEFAULTS` / `withDefaults()` | `shared/store.js` | 状态默认值**单一来源**；新增状态字段只改此处，不写逐字段迁移脚本 |
| `CRISIS` 词表 / 意图路由 | `shared/core.js`、`shared/agent-router.js` | 危机最高优先级、授权前置、负例拦截 |
| 云调用与输出脱敏 | `shared/integrations/p2-ai-integration.js` | 离线/危机词/禁用词不走云；数字只引用系统上下文 |
| 内置演示密钥 | `deploy/monolith-web/index.html` 的 `__AP_EMBED__` / `__AP_REVOKED__` | AES-GCM 密文分片 + 吊销清单；明文不落文件 |
| 三镜像同步 | `scripts/sync-monolith-html.ps1` | Web/Windows/Android 三端同源 |
| 生成区 | `scripts/gen_frontend_regions.py` | `shared/` → 页面 `AP:BEGIN` 标记，禁手改 |
| 单文件产物基线 | `scripts/build-single.py` 的 `EXPECTED_MD5` | 改基座须重打基线 |
| 公式真源（C#） | `src/AstralPath.Core/` | 与 `shared/core.js` 双端对拍 |
| 分层契约 | `scripts/verify_architecture.py` | Core 纯净 / API 不下探宿主 / 壳不做业务 |
| 威胁模型 | `THREAT_MODEL.md` | 覆盖状态 + 证据路径 + 日期化变更记录 |
| 一键门禁 | `scripts/verify_all.ps1` | 本地与 CI 同款；新门禁必须在此登记 |
