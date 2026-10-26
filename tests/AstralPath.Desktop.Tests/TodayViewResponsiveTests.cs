using AstralPath.Contracts;
using AstralPath.Shared;
using AstralPath.Shared.Navigation;
using AstralPath.Shared.Services;
using AstralPath.Shared.ViewModels;
using AstralPath.Shared.Views;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;

using Xunit;

namespace AstralPath.Desktop.Tests;

/// <summary>
/// 双端布局与响应式断点的用例。
/// 触达下限按 Shared 主题的 44px 断言；移动端在 <c>Mobile/App.axaml</c> 里覆盖成 48px。
/// </summary>
public sealed class TodayViewResponsiveTests
{
    private const double DesktopWidth = 1440;
    private const double DesktopHeight = 900;
    private const double MobileWidth = 390;
    private const double MobileHeight = 844;
    private const double SharedTouchFloor = 44;

    [AvaloniaTheory]
    [InlineData(DesktopWidth, DesktopHeight)]
    [InlineData(MobileWidth, MobileHeight)]
    public void 今日页在两种尺寸下都能渲染出任务卡且触达达标(double width, double height)
    {
        AppSettings.Current.Reset();

        var (shell, _) = Composition.CreateShell(touchTarget: 44);
        var window = new ShellWindow { DataContext = shell, Width = width, Height = height };
        window.Show();
        Dispatcher.UIThread.RunJobs();
        window.UpdateLayout();

        var today = window.GetVisualDescendants().OfType<TodayView>().FirstOrDefault();
        Assert.NotNull(today);

        var list = today!.FindControl<ItemsControl>("TaskList");
        Assert.NotNull(list);
        Assert.True(list!.ItemCount > 0, $"{width}x{height} 下今日任务不应为空");

        // 只检查真正渲染出来的按钮：空态卡在 HasTasks=true 时是折叠的，其子元素高度为 0 属正常
        var buttons = today.GetVisualDescendants().OfType<Button>()
            .Where(b => b.IsEffectivelyVisible)
            .ToList();
        Assert.NotEmpty(buttons);
        Assert.All(buttons, b => Assert.True(
            b.Bounds.Height >= SharedTouchFloor - 0.5,
            $"{width}x{height} 下按钮高度 {b.Bounds.Height} 小于触达下限 {SharedTouchFloor}"));

        window.Close();
    }

    [AvaloniaFact]
    public void 窄屏判定与断点一致()
    {
        AppSettings.Current.Reset();
        var (shell, _) = Composition.CreateShell(44);
        var window = new ShellWindow { DataContext = shell, Width = MobileWidth, Height = MobileHeight };
        window.Show();
        Dispatcher.UIThread.RunJobs();
        window.UpdateLayout();

        Assert.True(shell.IsNarrow);
        Assert.False(shell.IsWide);
        Assert.False(window.FindControl<Border>("LeftNav")!.IsVisible);

        window.Close();
    }

    // 原来「移动端外壳渲染出五个底部Tab」的用例随 AstralPath.Mobile 一起归档了，
    // 它断言的是没发布的 Avalonia 移动壳 MobileShell，见 attic/README.md

    [AvaloniaFact]
    public void 今日页包含预算胶囊与免责声明且无评价性措辞()
    {
        AppSettings.Current.Reset();
        var (shell, _) = Composition.CreateShell(44);
        var window = new ShellWindow { DataContext = shell, Width = DesktopWidth, Height = DesktopHeight };
        window.Show();
        Dispatcher.UIThread.RunJobs();
        window.UpdateLayout();

        var today = window.GetVisualDescendants().OfType<TodayView>().Single();
        var texts = today.GetVisualDescendants().OfType<TextBlock>()
            .Select(t => t.Text ?? string.Empty).ToList();

        Assert.Contains(texts, t => t.Contains("预算", StringComparison.Ordinal));
        Assert.Contains(texts, t => t.Contains("不构成处分依据", StringComparison.Ordinal));

        // 不能出现排名、惩罚性措辞。
        // 「处分」只出现在免责声明「不构成处分依据」里，先把那句排除再检查。
        var withoutDisclaimer = texts
            .Where(t => !t.Contains("不构成处分依据", StringComparison.Ordinal))
            .ToList();
        foreach (var word in new[] { "排名", "处分", "惩罚", "倒数" })
        {
            Assert.DoesNotContain(withoutDisclaimer, t => t.Contains(word, StringComparison.Ordinal));
        }

        window.Close();
    }

    [AvaloniaFact]
    public void 今日页任务来自真实规划器且可作答更新掌握度()
    {
        AppSettings.Current.Reset();
        var data = new OfflineDemoDataSource();
        var today = new TodayViewModel(data, new NavigationService());
        today.Load(PageContext.ForStudent(DemoMeta.StudentAId, "演示学生 A"));

        Assert.NotEmpty(today.Tasks);
        Assert.True(today.TotalMinutes > 0);
        Assert.False(today.IsEmpty);
        Assert.Equal("今日", today.Title);

        var first = today.Tasks[0];
        var before = data.GetMastery(DemoMeta.StudentAId).First(m => m.KpId == first.Dto.KpId).RecentAcc;

        var attempt = data.SubmitAttempt(new CreateAttemptRequest(
            DemoMeta.StudentAId,
            first.Dto.PlanItemId,
            first.Dto.KpId,
            first.QuestionId,
            Correct: true,
            SelfConf: 4));

        Assert.True(attempt.Correct);
        var after = data.GetMastery(DemoMeta.StudentAId).First(m => m.KpId == first.Dto.KpId).RecentAcc;
        Assert.True(after >= before, "答对后近期正确率不应下降");
    }
}
