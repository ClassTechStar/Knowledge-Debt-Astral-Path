using AstralPath.Core.Updates;
using Xunit;

namespace AstralPath.Core.Tests;

/// <summary>
/// 更新比较纯函数的 sanity 用例（与 shared/updater.js 金样 UP-01…UP-08 同口径）：
/// 版本比较（相等/补丁/跨次段/v 前缀/非法段）、资产挑选、校验和清单解析。
/// </summary>
public class UpdateComparerTests
{
    [Theory]
    [InlineData("2.6.0", "2.6.0", 0)]
    [InlineData("2.6.1", "2.6.0", 1)]
    [InlineData("2.6.0", "2.6.1", -1)]
    [InlineData("2.10.0", "2.9.9", 1)]
    [InlineData("v2.7.0", "2.6.0", 1)]
    [InlineData("abc", "0.0.0", 0)]
    public void CompareVersions_逐段数字比较(string a, string b, int expected)
        => Assert.Equal(expected, UpdateComparer.CompareVersions(a, b));

    [Theory]
    [InlineData("v2.7.0", "2.6.0", true)]
    [InlineData("v2.6.0", "2.6.0", false)]
    [InlineData("v2.5.9", "2.6.0", false)]
    public void IsNewer_按Tag判断是否更新(string latestTag, string current, bool expected)
        => Assert.Equal(expected, UpdateComparer.IsNewer(latestTag, current));

    [Fact]
    public void PickAsset_平台前缀匹配且忽略大小写()
    {
        var names = new[] { "checksums.sha256", "astralpath-monolith-setup-2.7.0.exe", "AstralPath-Android-2.7.0-Store.apk", "manifest.json" };
        Assert.Equal("astralpath-monolith-setup-2.7.0.exe", UpdateComparer.PickAsset(names, "astralpath-monolith-setup"));
        Assert.Equal("AstralPath-Android-2.7.0-Store.apk", UpdateComparer.PickAsset(names, "AstralPath-Android"));
        Assert.Null(UpdateComparer.PickAsset(names, "linux-deb"));
        Assert.Null(UpdateComparer.PickAsset(null, "x"));
    }

    [Fact]
    public void FindChecksum_按文件名取哈希()
    {
        const string text = "abc123  AstralPath-Monolith-Setup-2.7.0.exe\ndef456 *AstralPath-Android-2.7.0-Store.apk\n";
        Assert.Equal("abc123", UpdateComparer.FindChecksum(text, "AstralPath-Monolith-Setup-2.7.0.exe"));
        Assert.Equal("def456", UpdateComparer.FindChecksum(text, "astralpath-android-2.7.0-store.apk")); // 大小写不敏感 + * 前缀剥离
        Assert.Null(UpdateComparer.FindChecksum(text, "missing.exe"));
        Assert.Null(UpdateComparer.FindChecksum("", "x"));
    }
}
