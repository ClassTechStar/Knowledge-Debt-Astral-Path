# 数据来源与版权声明

本仓库只提交**代码、自撰示例数据与合成测试样例**。教材相关的提取产物不入库。

## 不入库的数据（本地保留，按需再生成）

| 目录 / 文件 | 内容 | 为什么不入库 |
|---|---|---|
| `kg-deep-test/` | 教材思维导图产物（JSON + Markdown 大纲） | 由受版权保护的教材目录/正文派生 |
| `ocr-ground-truth/` | 逐页人工校对文本与页清单 | 整书正文提取物，权利属出版方 |
| `ocr-full-compare/`、`ocr-compare/` | 整书 OCR 抽取结果与引擎对比数据 | 同上 |
| `materials/` 下的原始教材 PDF | 扫描/电子书原件 | 同上（`.gitignore` 已排除） |

这些目录仍可存在于维护者本机，用于本地跑工具链；`.gitignore` 已排除，`git status` 不会提示。

## 仓库内置的样例数据（可公开）

| 路径 | 说明 |
|---|---|
| `eval/kg-fixtures/` | 自撰的合成思维导图（示例课程·数据结构基础，25 节点），供 `verify_graph_quality.py`、`repair_kg_titles.py` 与 `tools/mindmap_to_graphpack.py` 金样使用 |
| `graph-packs/astralpath-v2/` | 团队自撰的运行时图包（会计基础 / Python 入门 / 深度学习概论，34 节点 74 边） |
| `graph-packs/mindmap-sample/` | 由上述合成 fixture 自动生成的图包（A4 管线金样） |
| `eval/question_bank.json` | 团队自撰题库（100 题，34 知识点） |

## 如何校验真实教材产物

真实教材产物不入库，但门禁逻辑照样可跑。把环境变量指向本机目录即可：

```powershell
# 校验某一批真实思维导图产物的质量
$env:ASTRALPATH_KG_DIR = "D:\教材产物\kg-deep-test"
python scripts/verify_graph_quality.py --check
python scripts/repair_kg_titles.py --check

# 从任意一本教材的思维导图生成图包（输出到 graph-packs/<id>/）
python tools/mindmap_to_graphpack.py "D:\教材产物\kg-deep-test\某本书.mindmap.json" --pack-id my-pack
```

再生成 OCR 校对数据（需要自备 PDF）：

```powershell
python tools/ocr_ground_truth.py      # 输出到 ocr-ground-truth/（已被 .gitignore 排除）
python tools/ocr_full_compare.py      # 输出到 ocr-full-compare/
```

## 提交前自检

- `git status` 不应出现上述目录下的任何新文件；
- 若误加，`git rm -r --cached <目录>` 后确认 `.gitignore` 已覆盖；
- 新增任何教材派生数据前，先确认其授权（公有领域 / 已获授权 / 自撰）。
