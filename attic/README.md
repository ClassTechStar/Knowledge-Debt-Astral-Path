# attic · 停用代码档案馆

本目录存放**已停用但暂不销毁**的项目与基础设施，统一原则：

1. **不参与构建**：`AstralPath.slnx`、CI、verify_all 均不触及本目录。
2. **保留复活能力**：git 历史可完整找回；如需复活，`git mv` 回原位并恢复引用即可。
3. **二进制产物不进馆**：旧 APK / 安装包已直接 `git rm`（git 历史与 Git LFS 仍可找回）。

## 目录清单（2026-10-25 归档）

| 目录 | 原位置 | 停用原因 |
|---|---|---|
| `AstralPath.Android/` | `src/` | 遗留 Java WebView 壳（aapt2/d8 手工打包路线），被 AstralPath.Native（Kotlin，已上架 2.6.0）取代 |
| `AstralPath.AndroidApp/` | `src/` | .NET Android 试验壳，从未进入任何解决方案 |
| `AstralPath.Mobile/` | `src/` | Avalonia 跨端壳；Android TFM 因 wasm-tools 工作负载缺失默认禁用，从未发布。其响应式测试已由 Desktop.Tests 改挂 Shared 保留 |
| `AstralPath.Mobile.Offline/` | `src/` | 内嵌一份**陈旧 Core 分叉**（缺 Agent/Graph/Exam 等目录）+ 84 个跑在陈旧分叉上的测试，制造虚假覆盖 |
| `services/` | 根目录 | 10 个 9 行 Program.cs 空壳（自称"非独立领域服务"，复用单体控制器），演示用 |
| `k8s/` `chaos/` `observability/` `docker-compose.microservices.yml` | `deploy/` | 为空壳微服务准备的编排，随 services/ 一并归档 |
| `mobile-app/` | `deploy/` | 旧版 7,987 行 HTML 拷贝（已漂移），被 monolith-web 三份 md5 同步拷贝取代 |
| `scripts/` | `scripts/` | 微服务构建/测试脚本（build-microservices.sh、test-microservices.ps1、test_microservices.py） |

## 存活的交付物（对照）

- **Web**：`deploy/monolith-web/index.html`（源）→ Cloudflare Pages
- **Windows**：`src/AstralPath.Monolith`（WebView2 壳，Setup 2.6.0）
- **Android**：`src/AstralPath.Native`（Kotlin WebView 壳，Store APK 2.6.0）
- **HTML 拷贝同步**：`scripts/sync-monolith-html.ps1`（md5 校验）

相关决策记录见 `docs/adr/`（ADR-0002）。
