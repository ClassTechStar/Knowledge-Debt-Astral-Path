# 图谱结构三级校验报告

> 迁移自 knowledge-spaces 的 `validate_graph` 分层思想；与 `verify_graph_quality.py`
> （kg-deep-test 产物的二元退化门禁）职责不重叠：本报告只覆盖 `graph-packs/` 正式知识包。
> WARN 不阻塞发布，供人工复核；FAIL 表示数学硬错误。

| 知识包 | 节点 | 边 | FAIL | WARN | PASS | 结论 |
|---|---:|---:|---:|---:|---:|---|
| accounting-v1 | 36 | 51 | 0 | 0 | 7 | PASS |
| astralpath-v2 | 34 | 74 | 0 | 0 | 7 | PASS |
| mindmap-kotlin | 32 | 31 | 0 | 0 | 7 | PASS |

## 明细

### accounting-v1

**PASS**
- 节点 ID 唯一
- 引用完整性：所有边端点有效
- 无重复边
- 无自环
- 边类型在白名单内
- 先修子图无环
- 教学合理性：无过重先修、无孤儿节点

### astralpath-v2

**PASS**
- 节点 ID 唯一
- 引用完整性：所有边端点有效
- 无重复边
- 无自环
- 边类型在白名单内
- 先修子图无环
- 教学合理性：无过重先修、无孤儿节点

### mindmap-kotlin

**PASS**
- 节点 ID 唯一
- 引用完整性：所有边端点有效
- 无重复边
- 无自环
- 边类型在白名单内
- 先修子图无环
- 教学合理性：无过重先修、无孤儿节点
