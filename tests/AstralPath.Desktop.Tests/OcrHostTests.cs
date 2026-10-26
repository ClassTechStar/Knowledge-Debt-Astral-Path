using AstralPath.Infrastructure;
using Xunit;

namespace AstralPath.Desktop.Tests;

/// <summary>
/// OcrHost 路径解析的冒烟用例：开发态要能从测试输出目录往上找到仓库的 tools\ocr_pipeline.py；
/// 解析结果里不能再出现写死的机器路径；Python 路径永远有回退值，不能抛异常。
/// </summary>
public class OcrHostTests
{
    [Fact]
    public void ResolveScript_Finds_Repo_Pipeline_Via_WalkUp()
    {
        var script = OcrHost.ResolveScript();
        Assert.NotNull(script);
        Assert.True(File.Exists(script), $"应存在：{script}");
        Assert.EndsWith("ocr_pipeline.py", script!, StringComparison.Ordinal);
    }

    [Fact]
    public void ResolveScript_Never_Uses_Hardcoded_Machine_Fallbacks()
    {
        // 说明：回溯出来的仓库路径本来就在用户目录下（C:\Users\<user>\Documents\...），带用户名是正常的。
        // 这里守的是代码里别再写死机器路径：以前写死的 MiMo 工程目录不能再出现在解析结果里。
        var script = OcrHost.ResolveScript() ?? "";
        Assert.DoesNotContain("XiaomiMiMo", script);
        Assert.DoesNotContain("Knowledge Debt Astral Path", script);
    }

    [Fact]
    public void ResolvePython_Always_Returns_Fallback()
    {
        var python = OcrHost.ResolvePython();
        Assert.False(string.IsNullOrWhiteSpace(python));
    }

    [Fact]
    public void ResolveTessdata_Returns_Null_Or_Existing_Directory()
    {
        var dir = OcrHost.ResolveTessdata();
        Assert.True(dir is null || Directory.Exists(dir));
    }
}
