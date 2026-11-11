<!-- 一个 PR 只做一件事。描述请写「为什么改」，改动内容看 diff 即可。 -->

## 为什么改

<!-- 问题/需求一句话；若修复缺陷，写清现象与根因。 -->

## 关联

<!-- Closes #123 -->

## 验证方式（必填）

<!-- 勾选你**实际跑过**的项，没跑的写原因。编译通过不能替代运行验证。 -->

- [ ] `pwsh -NoProfile -File scripts/verify_all.ps1` 全绿
- [ ] `dotnet test`（对应测试项目）
- [ ] 前端改动：`scripts/sync-monolith-html.ps1` 同步三镜像 + `node scripts/<name>_runner.js`
- [ ] 移动端改动：真机 / 模拟器实际操作过（说明做了什么）
- [ ] 界面改动附截图（改动前后）

## 是否触及以下红线（勾选，无则不勾）

- [ ] `shared/` 生成区或 `deploy/monolith-web/index.html`（记得跑 sync + 重打 `EXPECTED_MD5`）
- [ ] 公开数字（意图数 / 危机词 / 测试数）→ 先跑 `python scripts/verify_metrics.py` 回写 README
- [ ] 发布版本号 → 版本单一事实源是 `Directory.Build.props`，别在 csproj 里写死
- [ ] 密钥 / 授权 / 脱敏 / AI 路由 / 产物构建 → **必须同提交更新 `THREAT_MODEL.md`**
- [ ] 仓库结构 / 目标框架 / 门禁脚本 / 公开边界 → **必须同提交更新 `AGENTS.md`**

## 兼容性影响

<!-- 是否影响既有数据迁移、三端行为一致性、已发布的安装包？无则写「无」。 -->

## 提交说明

- 一行中文讲清「为什么改」。
- 行为变化附验证方式（测试 / 真机 / 截图）。
- 不提交 `bin/` `obj/` `artifacts/` 等构建产物。
