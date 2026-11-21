# 跨项目优秀实践迁移汇总报告（knowledge-spaces → AstralPath）

> 源项目：`C:\Users\18948\Documents\GitHub\knowledge-spaces`（Knowledge Space Theory Skill Suite，**MIT**）
> 目标项目：`C:\Users\18948\Documents\GitHub\Knowledge-Debt-Astral-Path`（Apache-2.0）
> 迁移日期：2026-11-22
> 基线：目标 HEAD `c01edfc`（上一轮 ReciteHelper 迁移后）

## 〇、项目形态与许可证

源项目 706KB / 30 文件，**不是应用代码项目**，而是一套 KST（知识空间理论）Agent Skills：
- `scripts/kst_utils.py`（749 行纯标准库）：downset 枚举、fringe、学习路径、BLIM 贝叶斯更新、熵选题、三级图校验、班级分析
- 10 个 SKILL.md（2389 行）+ 6 个 shared references + JSON Schema + 60+ 条教育学 bibliography

**MIT → Apache-2.0 兼容**。但依然遵循上一轮确立的原则：**迁移实践模式，不复制代码字面**——所有落地内容按目标项目风格重新实现，零源码搬运。

## 一、从源项目参考的全部优点条目

两路独立深读（算法与数据规范 / Skill 规范与教学流程）覆盖全部 30 个文件，10 维度梳理：

### A. 算法与数学内核
| # | 优点条目 | 源证据 |
|---|---|---|
| A1 | downset 枚举生成可行知识状态，BFS + `max_states=10000` 上限 + 超限 stderr 告警返回部分结果 | `kst_utils.py:151-186` |
| A2 | inner/outer fringe 计算：可移除/可加入且仍为合法状态的知识点 | `kst_utils.py:189-212` |
| A3 | 三种学习路径策略（breadth-first 少覆盖主题优先 / depth-first 同主题延续 / max-unlock 解锁最多） | `kst_utils.py:219-309` |
| A4 | BLIM 贝叶斯状态更新，lucky_guess / careless_error 双参数，归一化概率分布 | `kst_utils.py:316-351` |
| A5 | 最大区分度选题（选 P(掌握)≈0.5 的题）+ 香农熵 | `kst_utils.py:354-386` |
| A6 | `validate_graph` FAIL/WARN/PASS 三级校验：数学硬约束 + 教学合理性 | `kst_utils.py:393-530` |
| A7 | class_analytics：掌握率、outer fringe 频次、杠杆值、学生聚类 | `kst_utils.py:537-624` |
| A8 | 知识图谱 JSON Schema（metadata/items/surmise_relations/competences/knowledge_states/…） | `schemas/knowledge-graph.schema.json` |

### B. Skill 工程规范
| # | 优点条目 | 源证据 |
|---|---|---|
| B1 | 10 个 Skill 统一结构：front matter / 触发条件 / 分步 workflow / 输入输出契约 / 校验清单 | 各 `SKILL.md` |
| B2 | 共享 references 单一来源 + 各 skill 按需引用 | `.claude/skills/shared-references/` |
| B3 | name 小写连字符、argument-hint、触发词自然融入 description、跨 skill 引用全局同步 | `08e7aef` 提交 |
| B4 | 四阶段 pipeline 明确阶段边界与交接物 | `README.md:98-136` |
| B5 | 持久化纪律："Skills always read/write the graph file — never hold state in conversation only" | `CLAUDE.md:55` |
| B6 | 反模式声明与学术边界（bibliography、模型假设、局限说明） | `references/bibliography.md` 等 |

### C. 教学论方法
| # | 优点条目 | 源证据 |
|---|---|---|
| C1 | UDL 三原则 + 五层脚手架 + Bloom 材料类型映射 | `references/udl-scaffolding.md` |
| C2 | Tomlinson 差异化策略 + ZPD 同伴配对 | `references/differentiation-strategies.md` |
| C3 | ECD 证据规格模板、DOK/SOLO/Fink 分类法 | `references/ecd-framework.md`, `taxonomy-frameworks.md` |

## 二、目标项目适配基线

- 技术栈：.NET 10 + Web 单文件前端，Core 纯函数域逻辑（金样 1e-6 锁定），61 步门禁
- 已有等价体系（两路 Agent 一致确认）：`RemoveCyclesTopo` 环裁剪、`verify_graph_quality.py` 五条二元退化门禁、CAT Fisher 信息选题（js、`cat-diagnosis.js`）、BKT 逐 kp 状态、图谱质量报告、AGENTS.md 事实源优先级、THREAT_MODEL.md 活文档
- **关键判断**：源项目的 BLIM/downset 是"精确但规模不匹配"——目标图谱 120 节点，状态空间 2^120，源项目自己标注 40+ 项因规模不适用；目标的 CAT/BKT 是更务实的选择。**不迁移数学内核**

## 三、落地清单（3 项，全部门禁/报告层增量）

| 来源条目 | 目标项目具体改动 | 适配说明 |
|---|---|---|
| **A6 FAIL/WARN/PASS 三级校验** | 新增 `scripts/verify_graph_structure.py`：对 `graph-packs/` 三个正式知识包做引用完整性/重复边/自环/边类型白名单/先修环（FAIL）+ 认知负荷>7/孤儿节点（WARN），产出 `eval/graph-structure-report.md`；注册为 verify_all 第 60 步 | 与现有 `verify_graph_quality.py`（kg-deep-test 产物的二元退化门禁）**职责不重叠**；WARN 不阻塞。自动适配目标两种图谱格式（分文件 + 单文件 `graph_pack.json`，后者字段 kp_id/from_kp/to_kp/edge_type） |
| **A8 + 源 confidence 语义 → 置信度标尺** | 新增 `scripts/verify_confidence_scale.py`：把 ExamKgBuilder 散落的硬编码 0.5/0.6/0.7/0.8/0.85 登记为六档标尺 + 0.6 人工复核线，发现未登记硬编码即 FAIL；注册为第 61 步 | 不碰生产代码、不碰金样。第一次运行就抓到 0.8（attach 高置信）未登记——正是要防的"语义漂移" |
| **B4/B5 文档纪律的延续** | 修正 README 步数 59→61（新门禁注册后的同提交更新） | 上一轮迁移的 `verify_docs_consistency.py` 当场验证自洽——新门禁自己管住了自己的文档 |

**零生产代码改动、零金样公式改动、零第三方依赖。**

## 四、未采纳条目及原因

| 条目 | 不采纳原因 |
|---|---|
| **A1 downset 枚举 / A2 fringe / A4 BLIM / A5 熵选题** | ① 目标图谱 120 节点，状态空间 2^120，源项目自己说 40+ 项因规模不适用；② 目标已有 `cat-diagnosis.js` 的 Fisher 信息选题（比"距 0.5 最近"更精细）+ BKT 逐 kp 更新；③ 引入第二套诊断体系会制造双事实源，违反 AGENTS.md |
| **A3 三种学习路径策略** | 目标 `PlannerBuilder` 已有 0/2/6 三遍间隔 + K1–K5 合约 + `QuestionScheduler.Priority()`；源的三种策略无合约校验，更弱 |
| **A6 的 Bloom 层级倒挂检查** | 目标节点数据无 `bloom_level` 字段（已核实 nodes.json / graph_pack.json），强加会污染数据契约。只采纳同一函数里的孤儿/负荷/三级分类 |
| **A6 的并集闭包采样** | 目标不枚举知识空间状态，无 `knowledge_states` 数据，无从校验 |
| **A7 class_analytics** | 目标已有只读学情看板（薄弱热点、红边清单、近七日趋势）；源的掌握率/杠杆值粒度更粗 |
| **A8 完整 KG Schema** | 目标已有 `graph-packs/*/pack.json` 清单规范 + 既有 edges/nodes 格式，引入第二套 schema 会分裂数据契约 |
| **B1/B2/B3 Skill 规范（argument-hint 等）** | 目标 skill 是 WorkBuddy 格式（name/description/version/compatibility），非 Claude Agent Skill 标准；`name: astralpath-edu` 已符合小写连字符；front matter 已完整。无缺口 |
| **B6 bibliography** | 目标已有毕业论文 + 60+ 篇项目文档 + THREAT_MODEL 证据路径，学术溯源已覆盖 |
| **C1/C2/C3 UDL/Tomlinson/ECD 教学动作库** | 与源的数学内核同属"教学论资产"，但目标 AI 计划官走 K1–K5 本地合约终审，教学动作需与合约联动而非独立动作库；直接搬会成为"悬空文档"。若要引入需单独设计合约映射，超出本次"零破坏性改动"边界 |

## 五、验证执行结果

| 验证项 | 命令 | 结果 |
|---|---|---|
| 全量门禁 | `pwsh scripts/verify_all.ps1` | **ALL GREEN**（61 步：59 Step + 2 SkipStep） |
| .NET 测试 | 全量 | **276 通过 / 0 失败**（Core 136、Persistence 8、Desktop 50、Api 72、Eval 10） |
| 图谱结构校验 | `python scripts/verify_graph_structure.py --check` | **3 包全 PASS**，各 7 项通过、0 FAIL、0 WARN |
| 置信度标尺 | `python scripts/verify_confidence_scale.py` | **ALL GREEN**，5 个硬编码值全部登记 |
| 文档一致性 | `python scripts/verify_docs_consistency.py` | **ALL GREEN**（步数 61 自洽） |
| 构建/格式/覆盖率 | verify_all 内各步骤 | **ALL GREEN** |
| 设备手势回归 | android/harmony | 按设计 **SKIP**（无设备在线，非失败） |

零功能回归、零新增第三方依赖、零生产代码改动。

## 六、潜在风险点

1. **图谱结构校验的格式适配是启发式的**：两种布局靠字段名映射（`kp_id`→`id` 等），若将来新增第三种格式会误报；当前 3 包全通过，风险可控。
2. **置信度标尺是"文档登记"而非"执行约束"**：只检查硬编码值是否登记，不检查其语义是否恰当（比如 0.8 用于 attach 是否合理仍需人工判断）。
3. **WARN 级告警可能被忽略**：认知负荷>7、孤儿节点只写报告不阻塞；若需强制需提升为 FAIL，但会影响现有知识包，需另行评审。
4. **教学论资产（UDL/ECD）未迁移**：这是源项目最有"教育"味道的部分，但与目标 K1–K5 合约的映射需要专门设计；当前 AI 计划官的教学策略仍以合约为准，未吸收 UDL 脚手架。若参赛材料强调教学论，建议单独立项。
5. **BLIM/downset 的"不采纳"是基于当前规模**：若未来知识点压缩到 <20 且需要精确诊断，可重新评估；届时须先解决与目标 CAT 的双事实源问题。
6. **两路 Agent 报告中的数字仍需实测复核**：本报告所有落地判断均以目标项目实际文件与全量门禁结果为准，报告仅作线索。

---

*本报告与迁移改动同提交。所有"未采纳"条目均给出可核查原因，不留待办式空话。*
