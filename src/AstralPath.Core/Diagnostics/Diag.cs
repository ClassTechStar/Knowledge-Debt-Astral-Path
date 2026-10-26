using System.Collections.Concurrent;
using System.Runtime.CompilerServices;

namespace AstralPath.Core.Diagnostics;

/// <summary>
/// 一条诊断记录（最近 50 条环形缓冲的元素）。
/// </summary>
/// <param name="At">发生时间（UTC）。</param>
/// <param name="Scope">调用点（成员名:行号），由编译器注入，不写死字符串。</param>
/// <param name="Kind">严重度：<c>recover</c>=已降级继续 / <c>fail</c>=不可恢复 / <c>note</c>=说明。</param>
/// <param name="Message">异常消息或备注。</param>
public sealed record DiagEntry(DateTimeOffset At, string Scope, string Kind, string Message)
{
    /// <summary>导出为单行文本（前端/日志文件可直接消费）。</summary>
    public override string ToString() =>
        $"{At:yyyy-MM-ddTHH:mm:ss.fffZ} [{Kind}] {Scope} :: {Message}";
}

/// <summary>
/// 轻量诊断器：把被吞掉的错误变成能看见的记录。以前全仓有 40 处空 catch，线上出问题只能猜，
/// 所以弄了这个零依赖、不抛异常、内存有界的出口。环形缓冲固定 50 条，跑再久也不涨内存；
/// 调用点靠 <see cref="CallerMemberNameAttribute"/> / <see cref="CallerLineNumberAttribute"/> 自动注入，
/// catch 里写一行 <c>Diag.Recover(ex)</c> 就行，不用手抄 scope 字符串。纯内存，不写文件不发网络，
/// 符合本地优先的隐私要求。
/// 用法：可恢复走 <see cref="Recover"/>（记完继续降级路径），不可恢复走 <see cref="Fail"/>
/// （记完交给上层出 ProblemDetails / 提示），纯说明走 <see cref="Note"/>。
/// </summary>
public static class Diag
{
    /// <summary>环形缓冲容量（与前端 error ring 保持一致）。</summary>
    public const int Capacity = 50;

    private static readonly ConcurrentQueue<DiagEntry> Ring = new();
    private static long _total;

    /// <summary>累计记录条数（含已被挤出缓冲的），用于判断「发生过多少次」而非「最近几次」。</summary>
    public static long Total => Interlocked.Read(ref _total);

    /// <summary>可恢复错误：记一笔然后继续走降级路径，不往外抛异常。</summary>
    public static void Recover(
        Exception? ex = null,
        string? note = null,
        [CallerMemberName] string member = "",
        [CallerLineNumber] int line = 0)
        => Record("recover", member, line, ex, note);

    /// <summary>不可恢复错误：记录后由上层转换为用户可见提示（ProblemDetails / toast）。</summary>
    public static void Fail(
        Exception? ex = null,
        string? note = null,
        [CallerMemberName] string member = "",
        [CallerLineNumber] int line = 0)
        => Record("fail", member, line, ex, note);

    /// <summary>说明性记录（非异常），例如「演示密钥信封失效，已回落内置」。</summary>
    public static void Note(
        string message,
        [CallerMemberName] string member = "",
        [CallerLineNumber] int line = 0)
        => Record("note", member, line, null, message);

    /// <summary>取最近 <see cref="Capacity"/> 条（新→旧）。</summary>
    public static IReadOnlyList<DiagEntry> Snapshot()
    {
        var list = Ring.ToArray();
        Array.Reverse(list); // ConcurrentQueue 是 FIFO，反转后最新在前
        return list;
    }

    /// <summary>清空缓冲（不影响 <see cref="Total"/>）。</summary>
    public static void Clear()
    {
        while (Ring.TryDequeue(out _)) { }
    }

    private static void Record(string kind, string member, int line, Exception? ex, string? note)
    {
        try
        {
            var msg = ex is null
                ? (note ?? "")
                : (note is null ? $"{ex.GetType().Name}: {ex.Message}" : $"{note} | {ex.GetType().Name}: {ex.Message}");
            var entry = new DiagEntry(DateTimeOffset.UtcNow, $"{member}:{line}", kind, Truncate(msg, 300));
            Ring.Enqueue(entry);
            while (Ring.Count > Capacity && Ring.TryDequeue(out _)) { }
            Interlocked.Increment(ref _total);
            System.Diagnostics.Debug.WriteLine("[diag] " + entry);
        }
        catch
        {
            // 诊断器自己不能再把主流程搞挂，这里只能吞掉，它已经是最后一道防线了。
        }
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max] + "…";
}
