using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using AstralPath.Core.Diagnostics;
using AstralPath.Core.Updates;

namespace AstralPath.Monolith;

/// <summary>
/// Windows 壳更新器：检查源默认 GitHub Release（releases/latest），发现新版本后
/// 应用内下载 Setup 安装包，用同一 Release 的 checksums.sha256 核验哈希（T19 清单），
/// 用户确认后才运行安装器。设计约束：
///  - 只向 api.github.com 发匿名查询（限流 60 次/小时），启动后静默查一次、失败不重试；
///  - 取消/离线/限流一律静默，不打扰课堂使用；手动「检查更新」才给明确反馈；
///  - 哈希核验依赖 Release 附带的 checksums.sha256（T19）：缺失时如实提示「未校验哈希」，
///    由用户决定是否继续，不静默放行。
/// </summary>
internal static class UpdateService
{
    private const string Repo = "ClassTechStar/Knowledge-Debt-Astral-Path";
    private const string LatestApi = "https://api.github.com/repos/" + Repo + "/releases/latest";
    private const string ReleasePage = "https://github.com/" + Repo + "/releases/latest";
    private const string SetupPrefix = "astralpath-monolith-setup-";

    public sealed record UpdateCheck(string Version, string HtmlUrl, string? SetupAsset, string? ChecksumsText);

    private static HttpClient? _http;
    /// <summary>托盘菜单项的运行态文本（检查到新版本后更新）。</summary>
    public static string PendingVersion { get; private set; } = "";

    private static HttpClient Http => _http ??= new HttpClient() { Timeout = TimeSpan.FromSeconds(15) };

    internal static string CurrentVersion()
    {
        // FileVersion 来自 Directory.Build.props（单一事实源）；取前三段与 tag 对齐
        var v = Application.ProductVersion ?? "";
        var plus = v.IndexOf('+');
        if (plus >= 0) v = v[..plus];
        var parts = v.Split('.');
        return parts.Length >= 3 ? $"{parts[0]}.{parts[1]}.{parts[2]}" : "0.0.0";
    }

    /// <summary>静默检查（启动路径）：任何失败返回 null，不抛、不打扰。</summary>
    public static async Task<UpdateCheck?> CheckSilentlyAsync()
    {
        try { return await CheckAsync(); }
        catch (Exception ex) { Diag.Recover(ex, "UpdateCheck"); return null; }
    }

    /// <summary>手动检查：失败抛出，由调用方给用户反馈。</summary>
    public static async Task<UpdateCheck> CheckAsync()
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, LatestApi);
        req.Headers.Add("Accept", "application/vnd.github+json");
        req.Headers.UserAgent.ParseAdd("AstralPath-Updater/" + CurrentVersion());
        using var resp = await Http.SendAsync(req);
        resp.EnsureSuccessStatusCode();
        var json = await resp.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        var htmlUrl = root.TryGetProperty("html_url", out var hu) ? hu.GetString() ?? ReleasePage : ReleasePage;
        var assets = new List<string>();
        if (root.TryGetProperty("assets", out var arr))
        {
            foreach (var a in arr.EnumerateArray())
            {
                var n = a.TryGetProperty("name", out var an) ? an.GetString() : null;
                if (n is not null) assets.Add(n);
            }
        }
        var setup = UpdateComparer.PickAsset(assets, SetupPrefix) ?? "";
        // 校验和清单：同 Release 的 checksums.sha256 资产（T19），无则 null（调用方如实提示）
        var checksums = UpdateComparer.PickAsset(assets, "checksums.sha256");
        string? checksumsText = null;
        if (!string.IsNullOrEmpty(checksums))
        {
            using var cReq = new HttpRequestMessage(HttpMethod.Get,
                $"https://github.com/{Repo}/releases/download/{tag}/{checksums}");
            cReq.Headers.UserAgent.ParseAdd("AstralPath-Updater/" + CurrentVersion());
            using var cResp = await Http.SendAsync(cReq);
            if (cResp.IsSuccessStatusCode) checksumsText = await cResp.Content.ReadAsStringAsync();
        }
        PendingVersion = UpdateComparer.IsNewer(tag, CurrentVersion()) ? tag.TrimStart('v') : "";
        return new UpdateCheck(tag.TrimStart('v'), htmlUrl,
            string.IsNullOrEmpty(setup) ? null : setup, checksumsText);
    }

    /// <summary>下载 Setup 到临时目录并核验 SHA256；返回本地文件路径。失败抛出。</summary>
    public static async Task<string> DownloadVerifiedAsync(UpdateCheck check, IProgress<int> progress)
    {
        var tag = "v" + check.Version;
        var fileName = check.SetupAsset ?? $"AstralPath-Monolith-Setup-{check.Version}.exe";
        var url = $"https://github.com/{Repo}/releases/download/{tag}/{Uri.EscapeDataString(fileName)}";
        var dir = Path.Combine(Path.GetTempPath(), "AstralPathUpdate");
        Directory.CreateDirectory(dir);
        var target = Path.Combine(dir, fileName);

        using var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        resp.EnsureSuccessStatusCode();
        var total = resp.Content.Headers.ContentLength ?? -1;
        await using var src = await resp.Content.ReadAsStreamAsync();
        await using var dst = new FileStream(target, FileMode.Create, FileAccess.Write);
        var buf = new byte[81920];
        long readTotal = 0;
        int r;
        while ((r = await src.ReadAsync(buf)) > 0)
        {
            await dst.WriteAsync(buf.AsMemory(0, r));
            readTotal += r;
            if (total > 0 && progress is not null)
            {
                var pct = (int)(readTotal * 100 / total);
                progress.Report(Math.Min(100, Math.Max(0, pct)));
            }
        }

        // T19 供应链：下载完成先验哈希；清单缺失时如实返回未校验标记（调用方提示用户）
        var expected = UpdateComparer.FindChecksum(check.ChecksumsText ?? "", fileName);
        if (expected is not null)
        {
            using var fs = File.OpenRead(target);
            using var sha = System.Security.Cryptography.SHA256.Create();
            var actual = Convert.ToHexString(sha.ComputeHash(fs)).ToLowerInvariant();
            if (actual != expected)
            {
                File.Delete(target);
                throw new InvalidOperationException("SHA256 校验不一致，已删除下载文件（更新源可能被替换）");
            }
            return target;
        }
        return target + "|unverified";
    }
}
