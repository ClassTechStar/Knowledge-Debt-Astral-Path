namespace AstralPath.Core.Agent;

/// <summary>
/// 故障冷却的分类。只有传输/网络类错误（HTTP 状态、网络失败、超时、中断）才冷却；
/// 模型内容问题（比如 JSON 解析失败）不冷却，下次照常试。冷却默认 8 秒，以前 30 秒太影响体验。
/// </summary>
public static class FaultCooldown
{
    public static readonly TimeSpan DefaultCooldown = TimeSpan.FromSeconds(8);

    private static readonly string[] TransportMarkers =
    {
        "HTTP ", "Failed to fetch", "NetworkError", "network error",
        "abort", "timeout", "超时", "load failed", "connection", "socket",
        "Name or service not known", "No such host", "Connection refused"
    };

    /// <summary>判断这个异常算不算传输类故障，算才触发冷却。</summary>
    public static bool IsTransportError(Exception e)
        => IsTransportMessage(e?.Message ?? "") || e is HttpRequestException or TaskCanceledException or TimeoutException;

    public static bool IsTransportMessage(string message)
    {
        var m = message ?? "";
        return TransportMarkers.Any(k => m.Contains(k, StringComparison.OrdinalIgnoreCase));
    }
}
