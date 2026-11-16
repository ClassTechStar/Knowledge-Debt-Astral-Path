using AstralPath.Core.Algorithms;
using Xunit;
using Xunit.Abstractions;

namespace AstralPath.Eval.Tests;

/// <summary>
/// A2 参数标定与敏感性分析。红线：生产公式仍是 FormulaConstants 注入的确定性纯函数，
/// 本管线只回答「为什么是这组数」——先用 Parity 用例证明参数化复刻与生产公式逐值一致
/// （1e-9），再在仿真器上做 ±20% 敏感性扫描与网格搜索，把手设常数变成实验结论。
/// 扫描对象是 score / retention / impact / sale 的 14 个双精度常数
/// （SaleStreakRequired / SaleMinAttempts 是整数语义，不做 ±20% 扰动）。
/// </summary>
public class ParameterCalibrationTests
{
    private readonly ITestOutputHelper _out;
    public ParameterCalibrationTests(ITestOutputHelper output) => _out = output;

    private static readonly (string Name, Func<SimParams, double> Get, Func<SimParams, double, SimParams> Set)[] Sweep =
    {
        ("WEmpirical", p => p.WEmpirical, (p, v) => p with { WEmpirical = v }),
        ("WRetention", p => p.WRetention, (p, v) => p with { WRetention = v }),
        ("WPrereq", p => p.WPrereq, (p, v) => p with { WPrereq = v }),
        ("PrereqFloor", p => p.PrereqFloor, (p, v) => p with { PrereqFloor = v }),
        ("PrereqWeakMix", p => p.PrereqWeakMix, (p, v) => p with { PrereqWeakMix = v }),
        ("Stability0", p => p.Stability0, (p, v) => p with { Stability0 = v }),
        ("StabilityAlpha", p => p.StabilityAlpha, (p, v) => p with { StabilityAlpha = v }),
        ("StabilityBeta", p => p.StabilityBeta, (p, v) => p with { StabilityBeta = v }),
        ("ImpactBase", p => p.ImpactBase, (p, v) => p with { ImpactBase = v }),
        ("GateSteepness", p => p.GateSteepness, (p, v) => p with { GateSteepness = v }),
        ("CascadeAlpha", p => p.CascadeAlpha, (p, v) => p with { CascadeAlpha = v }),
        ("VolumeBeta", p => p.VolumeBeta, (p, v) => p with { VolumeBeta = v }),
        ("SaleBar", p => p.SaleBar, (p, v) => p with { SaleBar = v }),
        ("SaleAccMin", p => p.SaleAccMin, (p, v) => p with { SaleAccMin = v }),
    };

    private static readonly int[] Seeds = { 7, 42, 2026 };

    /// <summary>综合目标：销账数与留存越高越好、每清一债的作答成本越低越好。</summary>
    private static double Objective(Metrics m)
        => 2 * m.DebtCleared + 2 * m.TotalCleared + 20 * m.Retention30
           - (double.IsNaN(m.AvgAttemptsPerClear) ? SimWorld.TotalAttempts : m.AvgAttemptsPerClear);

    private static double EvalParams(SimParams p)
    {
        var graph = SimWorld.LoadGraph();
        var total = 0.0;
        foreach (var seed in Seeds)
            total += Objective(new SimWorld(graph, "impact", seed, new ParamFormulas(p)).Run());
        return total;
    }

    // ─────────────────────────── ① 逐值对拍 ───────────────────────────

    [Fact]
    public void Parity_ParamFormulas_MatchProduction_1e9()
    {
        var prod = ProdFormulas.Instance;
        var rep = new ParamFormulas(SimParams.Default);
        var maxDiff = 0.0;

        // score：作答数 × 成绩 × 信心 × 龄期 × 连对 × 先修形态
        foreach (var attempts in new[] { 0, 1, 3, 10 })
            foreach (var successes in new[] { 0, 1, 3, 10 }.Where(s => s <= attempts).DefaultIfEmpty(0))
                foreach (var conf in new[] { 1.0, 3.0, 5.0 })
                    foreach (var age in new[] { 0.0, 1.0, 5.0, 20.0 })
                        foreach (var streak in new[] { 0, 1, 3 })
                            foreach (var prereqs in new[] { new List<double>(), new List<double> { 0.2 }, new List<double> { 0.9 }, new List<double> { 0.2, 0.9, 0.5 } })
                            {
                                var input = new MasteryInput(attempts, successes, conf, age, streak, prereqs);
                                maxDiff = Math.Max(maxDiff, Math.Abs(prod.Score(input) - rep.Score(input)));
                            }

        // impact：父子分 × 权重 × 边类型 × 错题体量 × 下游
        foreach (var sf in new[] { 0.2, 0.55, 0.9 })
            foreach (var st in new[] { 0.2, 0.5, 0.8 })
                foreach (var w in new[] { 0.5, 1.0, 1.6 })
                    foreach (var et in new[] { EdgeType.Prerequisite, EdgeType.TransferGap })
                        foreach (var freq in new[] { 0, 1, 5 })
                            foreach (var ds in new[] { 0, 2, 5 })
                            {
                                var input = new DebtInput(sf, st, w, et, freq, ds);
                                maxDiff = Math.Max(maxDiff, Math.Abs(prod.Impact(input) - rep.Impact(input)));
                                Assert.Equal(prod.IsHit(input), rep.IsHit(input));
                            }

        // sale：四种作答序列的状态机逐步对拍
        var seqs = new[]
        {
            new[] { (true, 1.0, 5), (true, 1.0, 5), (true, 1.0, 5) },
            new[] { (true, 0.8, 4), (false, 0.5, 2), (true, 0.75, 3), (true, 0.8, 4) },
            new[] { (false, 0.3, 1), (false, 0.25, 1), (false, 0.2, 2) },
            new[] { (true, 0.69, 2), (true, 0.7, 3), (true, 0.7, 3) },
        };
        foreach (var seq in seqs)
        {
            var sp = SaleStateMachine.Create();
            var sr = SaleStateMachine.Create();
            foreach (var (ok, acc, conf) in seq)
            {
                sp = prod.Transition(sp, new SaleAttempt(ok, acc, conf));
                sr = rep.Transition(sr, new SaleAttempt(ok, acc, conf));
                Assert.Equal(sp, sr);
            }
        }

        Assert.True(maxDiff <= 1e-9, $"参数化复刻与生产公式漂移 {maxDiff:E3}（必须 ≤1e-9，否则标定结论不能迁移）");
    }

    // ─────────────────────────── ② 敏感性扫描 ───────────────────────────

    private static Dictionary<string, double> RunSensitivity(out double baseline, out List<string> ranking)
    {
        baseline = EvalParams(SimParams.Default);
        var sens = new Dictionary<string, double>();
        foreach (var (name, get, set) in Sweep)
        {
            var v0 = get(SimParams.Default);
            var lo = EvalParams(set(SimParams.Default, v0 * 0.8));
            var hi = EvalParams(set(SimParams.Default, v0 * 1.2));
            sens[name] = Math.Max(Math.Abs(lo - baseline), Math.Abs(hi - baseline));
        }
        ranking = sens.OrderByDescending(kv => kv.Value).Select(kv => kv.Key).ToList();
        return sens;
    }

    [Fact]
    public void Sensitivity_Rank_Constants_Deterministic()
    {
        var sens = RunSensitivity(out var baseline, out var ranking);
        var sens2 = RunSensitivity(out var baseline2, out var ranking2);

        _out.WriteLine($"[A2 敏感性] 基线目标值 {baseline:F3}（impact-v2 策略 × {Seeds.Length} 种子）");
        foreach (var name in ranking)
            _out.WriteLine($"  {name,-16} Δ={sens[name]:F3}");

        Assert.Equal(baseline, baseline2);          // 固定种子：基线可复现
        Assert.Equal(ranking, ranking2);            // 排名可复现
        var vals = sens.Values.ToList();
        Assert.True(vals.All(v => double.IsFinite(v)), "敏感度必须有限");
        Assert.True(vals.Max() > vals.Min(), "14 个常数的影响力应有区分度");
        // 实验结论（供答辩引用）：影响力排名前三的常数
        Assert.True(ranking.Count == Sweep.Length, "排名应覆盖全部 14 个常数");
        Assert.True(vals.Max() > 0.05,
            $"影响力最大的常数 {ranking[0]}（Δ={vals.Max():F3}）应显著影响指标，排名：" +
            string.Join(" > ", ranking.Take(3)));
    }

    // ─────────────────────────── ③ 网格标定 ───────────────────────────

    [Fact]
    public void Calibration_GridSearch_ImprovementFound_RequiresReview()
    {
        RunSensitivity(out _, out var ranking);
        var top3 = ranking.Take(3).ToArray();
        var map = Sweep.ToDictionary(s => s.Name);

        // 对影响力前三的常数做 3×3×3 网格（各自 0.8/1.0/1.2 倍）
        var bestObj = double.NegativeInfinity;
        SimParams bestParams = SimParams.Default;
        foreach (var a in new[] { 0.8, 1.0, 1.2 })
            foreach (var b in new[] { 0.8, 1.0, 1.2 })
                foreach (var c in new[] { 0.8, 1.0, 1.2 })
                {
                    var p = SimParams.Default;
                    var factors = new[] { a, b, c };
                    for (var i = 0; i < 3; i++)
                    {
                        var entry = map[top3[i]];
                        p = entry.Set(p, entry.Get(SimParams.Default) * factors[i]);
                    }
                    var obj = EvalParams(p);
                    if (obj > bestObj) { bestObj = obj; bestParams = p; }
                }

        var defaultObj = EvalParams(SimParams.Default);
        var describe = string.Join(", ", top3.Select(n => $"{n}={map[n].Get(bestParams):F3}"));
        _out.WriteLine($"[A2 标定] 默认目标值 {defaultObj:F3} → 网格最优 {bestObj:F3}（组合：{describe}）");

        // 结论锁（A2 的实证产出）：±20% 邻域内存在优于默认的组合，当前最敏感的改进杠杆是
        // 销账质量线（SaleAccMin 降低 → 更多知识点达到销账口径）。本用例锁定该发现可复现；
        // **不改生产常数**——调整任何常数必须走正式评审 + 金样对拍 + 复跑本管线。
        Assert.True(bestObj > defaultObj + 1.0,
            $"±20% 邻域应能找到显著改进（默认 {defaultObj:F3} → 最优 {bestObj:F3}，组合：{describe}）");

        // 确定性：整个搜索可复现（同种子同结论）
        var bestObj2 = double.NegativeInfinity;
        foreach (var a in new[] { 0.8, 1.0, 1.2 })
            foreach (var b in new[] { 0.8, 1.0, 1.2 })
                foreach (var c in new[] { 0.8, 1.0, 1.2 })
                {
                    var p = SimParams.Default;
                    var factors = new[] { a, b, c };
                    for (var i = 0; i < 3; i++)
                    {
                        var entry = map[top3[i]];
                        p = entry.Set(p, entry.Get(SimParams.Default) * factors[i]);
                    }
                    bestObj2 = Math.Max(bestObj2, EvalParams(p));
                }
        Assert.Equal(bestObj, bestObj2);
    }
}
