# 知债：星穹学途 · 一键验收（ALL GREEN / FAILED）
# 用法：powershell -File scripts\verify_all.ps1
#       powershell -File scripts\verify_all.ps1 -Json   # 机器可读结果（CI 断言用）
# 退出码：0 = ALL GREEN；非 0 = FAILED
param(
    [switch]$Json
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failed = @()
$results = New-Object System.Collections.ArrayList

# 统一输出编码，并把 dotnet CLI 切英文，避免控制台中文乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:DOTNET_CLI_UI_LANGUAGE = "en"
$env:DOTNET_NOLOGO = "1"

function Step($name, $cmd) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) {
        $script:failed += $name
        [void]$script:results.Add([pscustomobject]@{ name = $name; status = "failed"; exit = $LASTEXITCODE })
    } else {
        [void]$script:results.Add([pscustomobject]@{ name = $name; status = "passed"; exit = 0 })
    }
}

# 1) 常量对齐：JS 的 K 对象 ↔ C# 的 FormulaConstants.cs
Step "constants-K-vs-FormulaConstants" { python scripts/verify_constants.py }

# 1b) 公式常量生成区：index.html 的 K 必须由 C# 源生成，禁止两侧手工同步
if (Test-Path scripts/gen_formula_constants.py) {
    Step "formula-constants-generated" { python scripts/gen_formula_constants.py --check }
}

# 1b) 智能体意图登记表多方比对：tools/agent-intents.json ↔ index.html ↔ AgentRouter.cs
if (Test-Path scripts/verify_agent_intents.py) {
    Step "agent-intents-three-way" { python scripts/verify_agent_intents.py }
} else {
    Write-Host "[SKIP] scripts/verify_agent_intents.py 尚未生成" -ForegroundColor Yellow
}

# 2) 知识图包：无环 / 无悬空边 / 无重复边 / why 非空
if (Test-Path scripts/verify_graph.py) {
    Step "graph-pack" { python scripts/verify_graph.py graph-packs/astralpath-v2/graph_pack.json }
} else {
    Write-Host "[SKIP] scripts/verify_graph.py 尚未生成（P3 交付物）" -ForegroundColor Yellow
}

# 3) 题库：≥100 题 / correct_index 合法 / 可溯源
if (Test-Path scripts/verify_bank.py) {
    Step "question-bank" { python scripts/verify_bank.py eval/question_bank.json --min 100 }
} else {
    Write-Host "[SKIP] scripts/verify_bank.py 尚未生成（P3 交付物）" -ForegroundColor Yellow
}

# 4) .NET 测试（逐个项目，dotnet test 一次只能接一个）
#    Core 顺带采集覆盖率，供后面的阈值检查用
Step "test-Core"        { dotnet test tests/AstralPath.Core.Tests -c Release --collect:"XPlat Code Coverage" --results-directory ./artifacts/coverage }
Step "test-Persistence" { dotnet test tests/AstralPath.Persistence.Tests -c Release }
Step "test-Desktop"     { dotnet test tests/AstralPath.Desktop.Tests -c Release }
Step "test-Api"         { dotnet test tests/AstralPath.Api.Tests -c Release }
Step "test-Eval"        { dotnet test tests/AstralPath.Eval.Tests -c Release }
# （原 test-MobileCore 已随 Mobile.Offline 归档移除：其 84 个测试跑的是陈旧 Core 分叉，见 attic/）

# 4a) 覆盖率阈值：低于行/分支阈值就判红
if (Test-Path scripts/verify_coverage.py) {
    Step "coverage-gate" { python scripts/verify_coverage.py }
}

# 4b) README 数字只维护一份：意图/危机词/测试数 ↔ README 标记自动比对
Step "metrics-readme"   { python scripts/verify_metrics.py --check }

# 4c) 图谱质量：退化标题/空标题/父子同名/节点规模/md 一致性
if (Test-Path scripts/verify_graph_quality.py) {
    Step "graph-quality" { python scripts/verify_graph_quality.py --check }
    Step "kg-titles-clean" { python scripts/repair_kg_titles.py --check }
}

# 4d) 图谱性能预算：固定语料跑分章→构图，掉出预算就判红
if (Test-Path scripts/bench_kg.py) {
    Step "kg-perf" { python scripts/bench_kg.py --check }
}

# 5) 三端 HTML 同源 + XSS 回归哨兵（统一由同步脚本提供）
Step "monolith-html-sync" { powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-monolith-html.ps1 -Check }

# 6b) 前端 JS 语法检查（独立脚本 + HTML 内联块）
if (Test-Path tools/check-js.js) {
    Step "check-js" { node tools/check-js.js }
}

# 6c) XSS 用例 + 直插点哨兵
if (Test-Path scripts/verify_xss.py) {
    Step "xss-cases" { python scripts/verify_xss.py }
}

# 6d) 共享内核：常量块与 JSON 一致 + 和旧实现双跑比对行为等价
if (Test-Path scripts/gen-shared-core.js) {
    Step "shared-core-generated" { node scripts/gen-shared-core.js --check }
}
if (Test-Path scripts/verify_core.py) {
    Step "shared-core-equivalence" { python scripts/verify_core.py }
}

# 6d-2) 前端构建合并：index.html 的 AP 生成区与 shared/ 逐字一致
if (Test-Path scripts/gen_frontend_regions.py) {
    Step "frontend-regions" { python scripts/gen_frontend_regions.py --check }
}

# 6d-3) state 分片存储：用例 + 页面接入校验
if (Test-Path scripts/verify_store.py) {
    Step "store-shards" { python scripts/verify_store.py }
}

# 6f) 试卷结构化用例（第一个抽出去的边界：shared/exam.js）
if (Test-Path scripts/exam_runner.js) {
    Step "exam-golden" { node scripts/exam_runner.js }
}

# 6h) 教材文本/章节/关键词用例（第二个抽出去的边界：shared/kg-text.js）
if (Test-Path scripts/kg_text_runner.js) {
    Step "kg-text-golden" { node scripts/kg_text_runner.js }
}

# 6i) 智能体规则路由用例（第三个边界：shared/agent-router.js）
if (Test-Path scripts/agent_router_runner.js) {
    Step "agent-router-golden" { node scripts/agent_router_runner.js }
}

# 6j) 计划调度与 K1–K5 合约用例（第四个边界：shared/plan-scheduler.js）
if (Test-Path scripts/plan_scheduler_runner.js) {
    Step "plan-scheduler-golden" { node scripts/plan_scheduler_runner.js }
}

# 6g) 单文件内联 JS 规模上限（手写行数与页面副本数）
if (Test-Path scripts/verify_inline_js.py) {
    Step "inline-js" { python scripts/verify_inline_js.py --check }
}

# 6e) 空 catch 检查：每个 catch 必须有记录或降级动作
if (Test-Path scripts/verify_no_empty_catch.py) {
    Step "no-empty-catch" { python scripts/verify_no_empty_catch.py }
}

# 7) 命名规范扫描（含旧名残留；脚本内置「政策声明语境」判定，
#    "禁止再使用旧名…"这种声明句不会误报，别再用朴素 Select-String 手写一遍）
if (Test-Path scripts/naming_consistency.py) {
    Step "naming" { python scripts/naming_consistency.py --check }
}

# 8) 代码风格检查：C# 走 dotnet format 的空白/换行检查，前端走 eslint
Step "dotnet-format" { dotnet format whitespace AstralPath.slnx --verify-no-changes --no-restore }
if (Test-Path node_modules/eslint) {
    Step "eslint" { npx --no-install eslint . }
} else {
    Write-Host "[SKIP] 未安装 eslint（npm ci 后可用）" -ForegroundColor Yellow
}

# 结论
Write-Host "`n" ("=" * 60)
if ($Json) {
    $summary = [pscustomobject]@{
        total  = $results.Count
        passed = @($results | Where-Object { $_.status -eq "passed" }).Count
        failed = $failed
        items  = $results
    }
    $summary | ConvertTo-Json -Depth 4
}
if ($failed.Count -eq 0) {
    Write-Host "ALL GREEN" -ForegroundColor Green
    exit 0
} else {
    Write-Host ("FAILED: " + ($failed -join ", ")) -ForegroundColor Red
    exit 1
}
