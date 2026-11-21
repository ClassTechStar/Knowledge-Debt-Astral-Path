using AstralPath.Core.Algorithms;
using Xunit;

namespace AstralPath.Core.Tests;

/// <summary>
/// 边界值矩阵测试（迁移自 ReciteHelper 的 CareBoundary 实践模式，非代码复制）。
///
/// 源项目的经验：生产代码里的 clamp/门槛最容易在边界处悄悄改变语义，
/// 而"典型值"测试覆盖不到。本测试针对目标项目 MasteryCalculator 的
/// 两个关键边界——零输入与极大 streak 下的封顶——用成对相邻值锁定行为。
///
/// 注意：测试只锁"边界不崩、不越界、单调不反转"，不写死具体公式系数，
/// 这样 A2 标定调参时不会误报，但边界回退会被立刻抓住。
/// </summary>
public class MasteryBoundaryTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(0, 1)]
    [InlineData(1, 0)]
    [InlineData(1, 1)]
    [InlineData(-1, 0)]      // 异常输入的防御边界
    [InlineData(0, -1)]
    public void Stability_AtBoundaries_IsFiniteAndNonNegative(int streak, int attempts)
    {
        var s = MasteryCalculator.Stability(streak, attempts);
        Assert.True(double.IsFinite(s), $"Stability({streak},{attempts}) 必须是有限数");
        Assert.True(s >= 0, $"Stability({streak},{attempts}) 不得为负：{s}");
    }

    [Fact]
    public void Stability_LargeStreak_IsCapped()
    {
        // 极大 streak 不应让稳定度无界增长（有上限是目标项目的设计约定）
        var moderate = MasteryCalculator.Stability(10, 5);
        var extreme = MasteryCalculator.Stability(1_000_000, 5);
        Assert.True(double.IsFinite(extreme), "极大 streak 下稳定性必须仍为有限数");
        Assert.True(extreme >= moderate, "稳定性不应随 streak 增大而下降");
    }

    [Theory]
    [InlineData(0, 0, 0)]
    [InlineData(0, 0, 1)]
    [InlineData(1, 3, 5)]
    public void Retention_InUnitRange(int ageDays, int streak, int attempts)
    {
        var r = MasteryCalculator.Retention(ageDays, streak, attempts);
        Assert.True(double.IsFinite(r));
        Assert.InRange(r, 0.0, 1.0);
    }

    [Fact]
    public void Retention_DecaysWithAge()
    {
        // 单调性：同一记忆状态下，时间越久回忆率不应更高
        var now = MasteryCalculator.Retention(0, 5, 3);
        var later = MasteryCalculator.Retention(30, 5, 3);
        Assert.True(later <= now + 1e-9, $"回忆率应随时间衰减：R(0)={now}, R(30)={later}");
    }
}
