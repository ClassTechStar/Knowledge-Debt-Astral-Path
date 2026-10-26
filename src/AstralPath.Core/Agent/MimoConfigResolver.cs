namespace AstralPath.Core.Agent;

/// <summary>
/// 决定用哪份配置：用户自定义密钥信封（KeyEnvelope + DEK）→ 内置演示密钥（DemoKeyProvider）→ 都没有就 null。
/// 信封失效不再悄悄回退，会带上 <see cref="MimoConfigResolution.Issue"/> 和
/// <see cref="MimoConfigResolution.UserMessage"/>，前端好提示用户重新配 key。
/// 失效分三种：DEK 丢了（换浏览器）、被吊销（运维判泄露）、密文解不开。
/// </summary>
public sealed record MimoConfigResolution(
    MimoConfig? Config,
    bool CustomEnvelopeInvalid,
    EnvelopeIssue Issue = EnvelopeIssue.None,
    string? UserMessage = null);

public interface IKeyEnvelopeStore
{
    /// <summary>读取用户自定义密钥信封；无则返回 null。</summary>
    KeyEnvelope? Load();

    /// <summary>作废（删除）当前信封——DEK 与信封不匹配时调用，避免死循环。</summary>
    void Invalidate();
}

public static class MimoConfigResolver
{
    public static MimoConfigResolution Resolve(
        IKeyEnvelopeStore store,
        Func<byte[]?> getDek,
        IKeyRevocationList? revocation = null)
    {
        ArgumentNullException.ThrowIfNull(store);
        var env = store.Load();
        if (env is null)
            return new MimoConfigResolution(DemoKeyProvider.Resolve(), CustomEnvelopeInvalid: false);

        // 先查吊销：信封本身没坏也可能被运维判废（泄露/离职/换供应商）
        if (revocation?.IsRevoked(env) == true)
        {
            store.Invalidate();
            Diagnostics.Diag.Note($"envelope revoked: keyId={env.KeyId}");
            return new MimoConfigResolution(
                DemoKeyProvider.Resolve(),
                CustomEnvelopeInvalid: true,
                Issue: EnvelopeIssue.Revoked,
                UserMessage: "自定义密钥已被吊销，已回退内置演示密钥。请重新输入 API Key。");
        }

        // DEK 缺失：换过浏览器、清过 IndexedDB 或者换机器都会这样
        var dek = getDek();
        if (dek is null)
        {
            store.Invalidate();
            Diagnostics.Diag.Note($"envelope DEK missing: keyId={env.KeyId}");
            return new MimoConfigResolution(
                DemoKeyProvider.Resolve(),
                CustomEnvelopeInvalid: true,
                Issue: EnvelopeIssue.DekMissing,
                UserMessage: "自定义密钥的加密材料不在本机（可能换过浏览器或清理过存储），已回退内置演示密钥。请重新输入 API Key。");
        }

        // 密文解不开
        var key = KeyEnvelopeCrypto.Open(env, dek);
        if (key is null)
        {
            store.Invalidate();
            return new MimoConfigResolution(
                DemoKeyProvider.Resolve(),
                CustomEnvelopeInvalid: true,
                Issue: EnvelopeIssue.Unreadable,
                UserMessage: "自定义密钥无法解密（密文损坏），已回退内置演示密钥。请重新输入 API Key。");
        }

        return new MimoConfigResolution(
            new MimoConfig(key, (env.Base ?? MimoConfig.DefaultBase).TrimEnd('/'), env.Model ?? MimoConfig.DefaultModel),
            CustomEnvelopeInvalid: false);
    }
}
