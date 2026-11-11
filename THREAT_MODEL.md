# 知债：星穹学途 · 威胁模型（活文档）

本文件记录**当前代码实际具备**的防线，以及它们**能证明什么、不能证明什么**。它不是设计愿景：
每一行「当前防线」都必须指向一个真实存在的文件或门禁；判定「已覆盖」的前提是**有检查在跑**，
而不是「有数据存在」。

维护契约：改动验证逻辑、门禁脚本、密钥/授权/脱敏链路、AI 路由、产物构建流程时，必须在**同一次
改动**里更新本文件对应的行与 §6 变更记录表。`scripts/verify_threat_model.py` 会检查文档结构、
证据路径是否存在、变更记录是否有日期。Conflicting conventions 时以 `scripts/` 下实际执行的门禁
脚本为准，其次 `AGENTS.md`，再次 `README.md`。

状态图例（用文字标记，遵循本仓库文档口径，不使用表情符号）：

| 标记 | 含义 |
|---|---|
| 已覆盖 | 有实现且**有门禁或测试实际执行** |
| 部分 | 实现存在，但缺少自动校验或只覆盖部分入口 |
| 未覆盖 | 已识别风险，当前没有实现 |
| 不可证 | 超出本软件可证明范围，只能依赖外部事实或信任 |
| 非本软件责任 | 攻击面真实存在，但需由运行环境或用户侧承担 |

## 1. 范围与非目标

范围：Web 单体版、Windows 壳、鸿蒙端、原生安卓端，以及它们共用的 `shared/` 逻辑、
`contracts/golden/` 金样与 `scripts/` 门禁。

非目标：不覆盖宿主操作系统被完全控制、浏览器/运行时被替换、供应链上游（npm/NuGet/Gradle
仓库）被投毒、以及用户主动把设备交给他人操作后的本地数据篡改。这些属于「不可证」，
列在表里是为了明确边界，不是待办清单。

## 2. 资产

| 资产 | 说明 | 失败后果 |
|---|---|---|
| 学习者作答与掌握度 | 存于本机分片状态（`shared/store.js`） | 画像被篡改，诊断结论失真 |
| 教材原文与 OCR 结果 | 用户导入的资料，本机解析 | 资料内容外泄或被替换为恶意 HTML |
| 模型密钥 | 自定义密钥经 AES-GCM 加密落盘；内置演示密钥为密文分片 | 密钥泄露导致额度被滥用 |
| 聚合学情 | 教师视图的 k-匿名聚合，不含个体明细 | 反推到具体学生 |
| 诊断数字 | 分数、影响分、红边、计划由本地公式计算 | AI 或前端编造数字误导学习者 |
| 发布产物 | 三端同源 HTML、单文件产物、安装包 | 端上行为不一致或产物被静默替换 |

## 3. 参与者与信任边界

| 角色 | 能力 | 本模型假设 |
|---|---|---|
| 本机使用者 | 可读浏览器 localStorage / IndexedDB、可替换前端文件 | **不完全可信**：本地状态可改，本软件不提供防篡改保证 |
| 学生 | 只看自己的诊断与任务 | 聚合视图不得暴露个体明细 |
| 教师 | 看聚合学情 | 授权默认关闭（fail-closed），样本不足即抑制 |
| 云模型（用户主动启用） | 收到提示词上下文，返回文本 | 半可信：输出按不可信文本处理，数字不得采信 |
| 内容来源 | 教材 PDF / 图片 / 模型输出，都会进 DOM | 一律按不可信输入处理 |
| 打包与 CI | 生成三端镜像、单文件产物、安装包 | 由 md5 基线与门禁交叉约束 |

## 4. 攻击面

### 4.1 注入与 DOM

| ID | 攻击 | 当前防线 | 状态 |
|---|---|---|---|
| T1 | 教材标题/模型输出携带 `onerror`、`<script>` 等注入 DOM | `shared/safe-dom.js:35` `esc()` 自包含转义；`:46` `safeRich()` 只放行无属性标签，带属性整段转义；`:78` `sanitizeUrl()` 限定协议与站内相对路径 | 已覆盖 |
| T2 | 新的直插点绕过 `esc()` | `scripts/verify_xss.py` + `contracts/golden/xss-cases.json` 黄金用例；`scripts/verify_inline_js.py` 对手写内联 JS 行数与直插点哨兵做棘轮 | 已覆盖 |
| T3 | 恶意 `javascript:` / `data:` URL 进入链接属性 | `shared/safe-dom.js:78` `sanitizeUrl()` 白名单（http/https/mailto 与站内相对路径），其余回落 `about:blank` | 已覆盖 |
| T4 | 第三方依赖在运行时注入脚本 | 单文件产物内联全部资源（`scripts/build-single.py`），运行时无外部脚本请求；但**依赖自身的构建期完整性未做签名校验** | 部分 |

### 4.2 数据与隐私

| ID | 攻击 | 当前防线 | 状态 |
|---|---|---|---|
| T5 | 未授权时教师侧看到学生学情 | `src/AstralPath.Harmony/entry/src/main/ets/pages/AccountPage.ets:121` 授权开关默认不可见；`shared/agent-router.js:92` 撤销优先于授予；`src/AstralPath.Harmony/entry/src/main/ets/pages/TeacherPage.ets:23` k=5、样本少于 3 人只显示「样本不足」 | 已覆盖 |
| T6 | 从聚合结果反推个体 | 教师视图只消费聚合行，不产出个体明细、不排名（`src/AstralPath.Harmony/entry/src/main/ets/pages/TeacherPage.ets` 文件头红线）；但**服务端聚合口径不在本仓库**，客户端只做展示与抑制 | 部分 |
| T7 | 自定义密钥明文落盘 | `deploy/monolith-web/index.html:7314` 起：明文只在输入框内存，落盘前 AES-GCM-256 加密，解密用 IndexedDB 中不可导出的 CryptoKey | 已覆盖 |
| T8 | 密钥信封被盗/误发后无法吊销；内置演示密钥被解出滥用 | 吊销清单**可离线更新**：`shared/app-glue.js` 的 `APRevoked` 把内置 `__AP_REVOKED__` 与用户导入清单（localStorage）合并，账户页「密钥吊销清单」粘贴 JSON 即生效，无需重新构建；`index.html` 的 `__apEnvRevoked` 按 `env.kid` 命中后删除信封并回退。须明确：内置演示密钥与解密材料都在客户端，**任何人都可还原**，它不是保密资产，仅用于免配置体验 | 部分（吊销已可离线更新；演示密钥可还原属不可证） |
| T9 | 本机 localStorage 被直接改写以伪造掌握度 | `shared/store.js:43` 分片 schema 版本、`scripts/verify_store.py` 与 `scripts/store_runner.js` 校验迁移与残缺分片合并；但**无签名/无防篡改**，本机操作者可任意改写 | 不可证 |
| T10 | 资料在用户未同意时被上传到云模型 / 危机词或禁用词被送出设备 | 危机词、禁用词拦截下沉到**唯一网络出口**：`shared/integrations/p0-ai-integration.js:121` 的 `complete()` 调用 `__AP_EGRESS_GUARD__` 拒绝出网；守卫在 `shared/app-glue.js` 装配，词表取自 `shared/core.js` 生成区（CRISIS/BANNED）。**授权粒度**：守卫先查 `__AP_CLOUD_OPTIN__`（默认 false，fail-closed），账户页「云端调用授权」显式开启才出网，「配了密钥」不等于「同意出网」；`scripts/verify_cloud_consent.py` 六条断言锁死 | 已覆盖 |

### 4.3 AI 输出与数字可信度

| ID | 攻击 | 当前防线 | 状态 |
|---|---|---|---|
| T11 | 模型编造分数、影响分或诊断结论 | `shared/integrations/p2-ai-integration.js:583` 系统提示「数字与诊断结论只引用系统上下文，不要编造」；`:596` 本地话术兜底不编造数字；公式真源在 `shared/core.js` 与 `src/AstralPath.Core`，由 `scripts/verify_constants.py`、`scripts/verify_formulas.py` 与金样 runner 对拍 | 已覆盖 |
| T12 | 模型输出夹带敏感词或越界话术 | `shared/integrations/p2-ai-integration.js:554` `sanitizeOutput()` 输出侧脱敏；`shared/core.js:86` 危机词表、`shared/agent-router.js:74` 危机最高优先级；`shared/notify.js:44` 危机卡常驻且免打扰下仍显示 | 已覆盖 |
| T13 | 提示词注入让智能体执行越权意图 | 双层：① **输入侧** `shared/agent-router.js` 意图白名单 + 危机/负例拦截 + 授权前置，`tools/agent-intents.json` 由 `scripts/verify_agent_intents.py` 六方对拍；② **输出侧** `shared/integrations/p2-ai-integration.js` 的 `sanitizeOutput` 拦注入形态（伪造系统指令 / 覆写规则 / 角色伪装 / 模板标记泄漏），并**保持架构不变量：模型返回只作展示、不回喂 `routeWithML`**（执行路径不受模型输出影响）；`scripts/verify_output_guard.py` 四条断言锁死 | 已覆盖 |
| T14 | 危机求助被免打扰设置吞掉 | `shared/notify.js:4` 危机最高级、`shared/app-glue.js:175` 免打扰仍保留危机提醒 | 已覆盖 |

### 4.4 产物一致性与供应链

| ID | 攻击 | 当前防线 | 状态 |
|---|---|---|---|
| T15 | 三端镜像被单独手改导致行为分叉 | `scripts/sync-monolith-html.ps1` 同步三端；`scripts/gen_frontend_regions.py --check` 生成区对拍；`scripts/build-single.py` 的 `EXPECTED_MD5` 基线 | 已覆盖 |
| T16 | 版本号被 rebase 带回旧值，产物与文档口径不一 | `scripts/verify_release_version.py`：以 `Directory.Build.props` 为唯一事实源，校验 iss / gradle / 打包脚本 / README，并禁止 csproj 重新写死版本；`release/build-release.ps1:28` 打包前先跑该门禁 | 已覆盖 |
| T17 | 壳层偷偷实现业务公式导致多端口径不一致 | `scripts/verify_architecture.py` 三契约（Core 纯净 / API 不下探宿主 / 壳不做业务） | 已覆盖 |
| T18 | 空 catch 吞掉异常，故障无声 | `scripts/verify_no_empty_catch.py` 全量扫描 C#；`src/AstralPath.Core/Diagnostics/Diag.cs` 环形缓冲 | 已覆盖 |
| T19 | 发布包被替换后无校验 | **哈希清单**：`release/manifest.json` + `checksums.sha256` 记录每个产物的 sha256，`scripts/verify_release_manifest.py` 校验哈希一致 + 防遗漏 + 版本对齐；`release/build-release.ps1` 打包后自动生成。**清单签名**：HMAC-SHA256（`ASTRALPATH_MANIFEST_KEY`），防清单本身被改；密钥缺失时如实标注未签名。局限：HMAC 是对称的，属「检测替换」而非「不可否认签名」；要不可否认需 Ed25519 + 密钥托管 | 部分（哈希已覆盖替换检测；清单签名需密钥，默认未启用） |
| T20 | 宿主运行时、浏览器扩展或操作系统被替换 | 无 | 不可证 |

## 5. 门禁与证据对应

| 门禁 | 覆盖的攻击编号 |
|---|---|
| `scripts/verify_xss.py`、`scripts/verify_inline_js.py` | T1、T2 |
| `scripts/verify_store.py`、`scripts/store_runner.js` | T9（仅数据完整性，不防篡改） |
| `scripts/verify_constants.py`、`scripts/verify_formulas.py`、`scripts/verify_agent_intents.py` | T11、T13 |
| `scripts/verify_architecture.py`、`scripts/verify_no_empty_catch.py` | T17、T18 |
| `scripts/gen_frontend_regions.py --check`、`scripts/sync-monolith-html.ps1 -Check`、`scripts/build-single.py` | T15 |
| `scripts/verify_release_version.py` | T16 |
| `scripts/verify_cloud_consent.py` | T10 |
| `scripts/verify_output_guard.py` | T13 |
| `scripts/verify_release_manifest.py`、`scripts/gen_release_manifest.py` | T19 |
| `scripts/verify_threat_model.py` | 本文件自身的结构与证据路径 |

## 6. 变更记录

| 日期 | 变更 | 影响条目 |
|---|---|---|
| 2026-11-11 | 建立威胁模型活文档，按当前代码逐项核对防线与证据路径；同步新增 `scripts/verify_threat_model.py` 门禁 | 全文 |
| 2026-11-11 | 版本口径收敛到 `Directory.Build.props` 单一事实源，新增发布前版本门禁（借鉴 VeriRandom channel gate） | T16 |
| 2026-11-11 | T10 从「部分」升「已覆盖」：危机词/禁用词拦截从 replyAgent 单入口下沉到 p0 唯一网络出口 `complete()`，守卫由 app-glue 装配；新增 `scripts/verify_cloud_consent.py` 门禁锁死出网点唯一与装配齐备 | T10 |
| 2026-11-11 | T10 补授权粒度：新增 `__AP_CLOUD_OPTIN__` 显式同意开关（默认关，fail-closed），账户页可开关；「配了密钥」不再等于「同意出网」 | T10 |
| 2026-11-11 | T8 吊销清单改为可离线更新：`APRevoked` 合并内置清单与本地导入，账户页粘贴 JSON 即生效；演示密钥可还原仍属不可证 | T8 |
| 2026-11-11 | T13 从「部分」升「已覆盖」：输出侧加注入形态拦截（伪造指令/覆写规则/角色伪装/模板标记），并用门禁锁死「模型返回不回喂执行路径」的架构不变量 | T13 |
| 2026-11-11 | T19 从「未覆盖」升「部分」：发布哈希清单 + 校验门禁生效，HMAC 清单签名可选启用；Ed25519 不可否认签名未纳入（需密钥托管） | T19 |
