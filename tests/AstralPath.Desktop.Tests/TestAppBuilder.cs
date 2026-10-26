using AstralPath.Shared.Services;
using Avalonia;
using Avalonia.Headless;

[assembly: AvaloniaTestApplication(typeof(AstralPath.Desktop.Tests.TestAppBuilder))]

namespace AstralPath.Desktop.Tests;

/// <summary>
/// Headless UI 测试宿主。跑的是 <see cref="ShellWindow"/> 加真实的 Shell 组合根（<see cref="Composition"/>）
/// 和 <c>AstralPath.Shared</c> 的真实视图，所以测试通过就等于应用能跑。
/// 壳放在这里而不引用 <c>AstralPath.Desktop</c>，是因为生产桌面壳已改成 WinForms + WebView2，
/// 不再编译 Avalonia 窗口，而 Headless 测试需要跨平台可跑的 net10.0 宿主。
/// </summary>
public static class TestAppBuilder
{
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<TestApp>()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = true });
}
