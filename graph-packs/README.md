# graph-packs · 内容包规范

本目录存放随项目交付的知识图谱内容包。每个包是一个**自描述目录**，带 `pack.json` 清单；
第三方可以按本规范产出新包，坏包会被校验门禁拦下、不会污染主数据。

## 目录约定

```
graph-packs/<packId>/
├── pack.json      # 清单（唯一入口，门禁从这里开始校验）
├── meta.json      # 可选：包元信息（兼容历史包）
└── <数据文件>      # 由 entries 声明：图数据 / 节点表 / 边表
```

## pack.json 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `packId` | ✅ | 与目录名一致 |
| `name` | ✅ | 人类可读名称 |
| `schemaVersion` | ✅ | 清单结构版本，当前 `1` |
| `apiVersion` | ✅ | 数据消费方兼容版本（semver），当前 `1.0.0` |
| `courseScope` | ✅ | 覆盖课程名数组 |
| `publishedAt` | ✅ | ISO 8601 时间 |
| `entries[]` | ✅ | 数据文件清单，见下 |

## entries 条目

| kind | 必填字段 | 校验行为 |
|---|---|---|
| `graph` | `file` `nodes` `edges` `nodeKey` `edgeFrom` `edgeTo` | 装载 JSON，断言 nodes/edges 数组长度与声明一致，悬空边报错 |
| `nodes` | `file` `count` `idKey` | 断言数组长度与声明一致 |
| `edges` | `file` `count` `fromKey` `toKey` | 断言数组长度与声明一致，端点可在 nodes 中找到 |

## 校验

```powershell
python scripts/verify_pack_manifest.py            # 校验全部包（verify_all 已接入）
```

规则：缺 `pack.json` 视为历史遗留包，跳过并列出提示（一个版本宽限期）；
清单字段缺失、计数不符、悬空边一律判红。
