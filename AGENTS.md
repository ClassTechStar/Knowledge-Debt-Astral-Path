# AGENTS · 仓库结构与协作约定

面向在本仓库工作的开发者与 AI 助手。改代码前先读这一页，能避开绝大多数返工。

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
| `docs/` | 13 份承重文档 | 新增文档前先问：有没有旧文档可改 |

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
pwsh -NoProfile -File scripts/verify_all.ps1     # 全量（CI 同款）
node scripts/store_runner.js                      # 单跑某个金样 runner
python scripts/verify_metrics.py                  # 数字回写
python scripts/build-single.py                    # 重建 17MB 单文件产物（会校验基座 md5）
```

约定：新增纯逻辑模块时，同时交付一个 `scripts/<name>_runner.js` 金样用例并在
`verify_all.ps1` 登记；改 C# 壳后至少 `dotnet build src/AstralPath.Monolith` 过一遍。

## 代码风格

- 中文注释，写「为什么」而不是「做了什么」。
- `catch` 不许为空：要么 `Diag.Recover(ex, …)`（C#），要么记录或显式降级（JS/Py）——
  `verify_no_empty_catch.py` 会拦。
- 命名遵循 `scripts/naming_consistency.py`（全称「知债：星穹学途」，代码标识 AstralPath）。
