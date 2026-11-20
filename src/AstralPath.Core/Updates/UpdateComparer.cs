using System.Globalization;

namespace AstralPath.Core.Updates;

/// <summary>
/// 更新检查的纯函数部分：版本比较、Release 资产挑选、校验和清单解析。
/// 与 shared/updater.js 的 compareVersions/parseLatest/pickAsset 同构（金样 JS 侧）；
/// Windows 壳的更新器（AstralPath.Monolith.UpdateService）消费这里的结果做下载与核验。
/// 不碰 IO、不碰网络——网络与文件留在壳层。
/// </summary>
public static class UpdateComparer
{
    /// <summary>解析 x.y.z 版本段（v 前缀剥离；非法段按 0，与 JS 侧一致不抛异常）。</summary>
    public static int[] Segments(string version)
    {
        var t = (version ?? "").Trim();
        if (t.StartsWith("v", StringComparison.OrdinalIgnoreCase)) t = t[1..];
        var parts = t.Split('.');
        var outp = new int[3];
        for (var i = 0; i < 3; i++)
        {
            outp[i] = i < parts.Length && int.TryParse(parts[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : 0;
        }
        return outp;
    }

    /// <summary>版本比较：-1/0/1（a 相对 b）。</summary>
    public static int CompareVersions(string a, string b)
    {
        var A = Segments(a);
        var B = Segments(b);
        for (var i = 0; i < 3; i++)
        {
            if (A[i] != B[i]) return A[i] < B[i] ? -1 : 1;
        }
        return 0;
    }

    /// <summary>latestTag（可带 v 前缀）是否比 current 新。</summary>
    public static bool IsNewer(string latestTag, string current)
        => CompareVersions(latestTag, current) > 0;

    /// <summary>在 Release 资产名里挑当前平台的安装包（前缀匹配，忽略大小写；无匹配返回 null）。</summary>
    public static string? PickAsset(IEnumerable<string>? names, string prefix)
    {
        if (names is null) return null;
        var p = (prefix ?? "").ToLowerInvariant();
        foreach (var n in names)
        {
            if (n is null) continue;
            if (n.ToLowerInvariant().StartsWith(p, StringComparison.Ordinal)) return n;
        }
        return null;
    }

    /// <summary>
    /// 从 checksums.sha256 文本（形如「&lt;sha256&gt;  &lt;文件名&gt;」行）里取指定文件的哈希；
    /// 找不到返回 null（清单缺失时更新器如实降级为「不校验哈希、仅 HTTPS」并告知用户）。
    /// </summary>
    public static string? FindChecksum(string checksumsText, string fileName)
    {
        if (string.IsNullOrEmpty(checksumsText) || string.IsNullOrEmpty(fileName)) return null;
        foreach (var raw in checksumsText.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            var parts = line.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2)
            {
                var name = parts[1].Trim().TrimStart('*');
                if (string.Equals(name, fileName, StringComparison.OrdinalIgnoreCase))
                    return parts[0].Trim().ToLowerInvariant();
            }
        }
        return null;
    }
}
