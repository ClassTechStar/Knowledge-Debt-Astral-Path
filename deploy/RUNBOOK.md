# 部署与 Runbook（竞赛轨）

## 本地启动

在**仓库根目录**执行（路径全部相对仓库，不写死机器位置）：

```powershell
# 可选：NuGet 缓存位置（默认 %USERPROFILE%\.nuget\packages，一般不用改）
# $env:NUGET_PACKAGES = "$env:TEMP\ngp"

# 图包目录：默认就是仓库内的 graph-packs/accounting-v1，一般无需设置
# $env:ASTRALPATH_GRAPH_PACK = "$PWD\graph-packs\accounting-v1"

dotnet run --project src/AstralPath.Api -c Release --urls http://127.0.0.1:5190
```

> 从其他目录启动时，先把 `ASTRALPATH_GRAPH_PACK` 指到 `<仓库根>/graph-packs/accounting-v1`。

## 健康检查

`GET /health/ready` → `{ status: "ready", checks: { graph, students, packId, graphVersion } }`

## 演示日检查单

- [ ] `dotnet test` 全绿（金样 + 召回 + E2E）
- [ ] `/v1/graphs/accounting-v1/validate` ok=true，无环
- [ ] Student A diagnose ≥3 红边；Student B = 0
- [ ] 计划 201 且 constraintsChecked=true，任一天 ≤35
- [ ] consent revoke 后教师热点收缩/空态文案正确
- [ ] Demo +1 天到 D7：cleared≥1
- [ ] 页脚免责与非处分定位可见
- [ ] 录屏/备用设备就绪

## 故障分级

| 级别 | 现象 | 动作 |
|---|---|---|
| P0 | 诊断/销账不可用 | 切录屏 + 本地公式旁注 |
| P1 | consent 服务异常 | fail-closed 空态，强调设计意图 |
| P2 | 叙事降级模板 | 正常演示，说明内容安全门禁 |
