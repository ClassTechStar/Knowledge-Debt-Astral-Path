using AstralPath.Core.Algorithms;
using Xunit;

namespace AstralPath.Eval.Tests;

/// <summary>
/// A1 模拟学习者离线评测管线（仿真骨架见 SimHarness.cs）。
/// 为什么：公式常数此前全部手设，没有任何实验证明「这组数有效」。本管线用
/// 独立认知模型构造合成学习者（latent level + 简化 ACT-R 稳定性棘轮），
/// 与应用侧估计（score-v2 + impact-v2 + sale-v2）分离，对比四种调度策略的
/// 销账效率与留存，外加「集中突击」对照组。全部固定种子，指标可复现。
///
/// 策略：impact-v2 + 间隔复习（项目策略）vs 随机选题 vs 纯 SM-2 式定隔 vs BKT 追踪。
/// </summary>
public class SimulatedLearnerEvalTests
{
    private static Metrics Simulate(string strategy, int seed)
        => new SimWorld(SimWorld.LoadGraph(), strategy, seed, ProdFormulas.Instance).Run();

    [Fact]
    public void Sim_Deterministic_SameSeedSameMetrics()
    {
        var a = Simulate("impact", 42);
        var b = Simulate("impact", 42);
        Assert.Equal(a, b); // 记录相等：指标可复现，实验结论可回放
    }

    [Fact]
    public void Sim_ImpactV2_BeatsRandom_OnDebtRepair()
    {
        // 三个种子分别跑，避免单种子偶然性；项目策略的欠债销账数与效率都不得差于随机
        var debtImpact = 0; var debtRandom = 0;
        double costImpact = 0, costRandom = 0;
        foreach (var seed in new[] { 7, 42, 2026 })
        {
            var mi = Simulate("impact", seed);
            var mr = Simulate("random", seed);
            debtImpact += mi.DebtCleared; debtRandom += mr.DebtCleared;
            costImpact += double.IsNaN(mi.AvgAttemptsPerClear) ? SimWorld.TotalAttempts : mi.AvgAttemptsPerClear;
            costRandom += double.IsNaN(mr.AvgAttemptsPerClear) ? SimWorld.TotalAttempts : mr.AvgAttemptsPerClear;
        }
        Assert.True(debtImpact >= debtRandom,
            $"欠债销账：impact-v2={debtImpact} 应不差于 random={debtRandom}");
        Assert.True(costImpact <= costRandom + 0.5,
            $"销账效率：impact-v2 每清一债 {costImpact / 3:F2} 次作答不应高于 random {costRandom / 3:F2}");
    }

    [Fact]
    public void Sim_SpacingEffect_SpreadRetention_BeatsMassed()
    {
        // 留存对比（隔离变量）：同一批 14 个知识点、同样每点 3 次作答，
        // massed 一天连做 3 题 vs spread 摊在不同日子——30 天后留存应体现间隔效应
        double massed30 = 0, spread30 = 0;
        foreach (var seed in new[] { 7, 42, 2026 })
        {
            massed30 += Simulate("massed", seed).Retention30;
            spread30 += Simulate("spread", seed).Retention30;
        }
        Assert.True(spread30 > massed30,
            $"30 天留存：间隔 {spread30 / 3:F3} 应高于集中 {massed30 / 3:F3}");
    }

    [Fact]
    public void Sim_AllStrategies_LearnAndRetain()
    {
        foreach (var strategy in new[] { "impact", "random", "sm2", "bkt", "cram" })
        {
            var m = Simulate(strategy, 42);
            Assert.True(m.Retention14 > 0.05, $"{strategy} 14 天后应仍有基本掌握（{m.Retention14:F3}）");
            Assert.True(m.Retention30 > 0 && m.Retention30 < m.Retention14 + 1e-9,
                $"{strategy} 30 天留存应不高于 14 天（遗忘曲线）");
        }
    }

    [Fact]
    public void Sim_SaleStateMachine_Guard_NoEarlyClear()
    {
        // 销账红线在仿真里同样成立：不足 3 次作答绝不清账
        var state = SaleStateMachine.Create();
        state = SaleStateMachine.Transition(state, new SaleAttempt(true, 1.0, 5));
        state = SaleStateMachine.Transition(state, new SaleAttempt(true, 1.0, 5));
        Assert.NotEqual(SaleStatus.Cleared, state.Status); // 连续 2 次达标但只有 2 次作答
        state = SaleStateMachine.Transition(state, new SaleAttempt(true, 1.0, 5));
        Assert.Equal(SaleStatus.Cleared, state.Status);
    }
}
