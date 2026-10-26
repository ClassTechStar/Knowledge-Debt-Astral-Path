using System.Security.Cryptography;
using System.Text;

namespace AstralPath.Core.Agent;

/// <summary>
/// 密钥信封：API key 先用 AES-256-GCM 加密再落盘，加密用的数据密钥（DEK）由宿主单独保管、不可导出。
/// 信封和 DEK 分开存，单泄一个拿不到明文。桌面端 DEK 走 DPAPI/Keychain，Web 端放 IndexedDB 的不可导出 CryptoKey。
/// </summary>
/// <param name="CiphertextB64">密文（ciphertext ‖ tag，和 Web Crypto 的格式一致）。</param>
/// <param name="IvB64">12 字节随机 IV。</param>
/// <param name="Base">网关 base URL，也放信封里，不落明文。</param>
/// <param name="Model">模型名，同样在信封里。</param>
/// <param name="UpdatedAt">写入时间（Unix ms）。</param>
/// <param name="Version">
/// 信封格式版本，Seal 时写入 <see cref="KeyEnvelopeCrypto.CurrentVersion"/>。
/// 旧版本照样能解开，这个字段只用来排障和判断要不要迁移，不参与解密。
/// </param>
/// <param name="KeyId">
/// 信封指纹：密文 SHA-256 的前 8 字节 hex。给吊销清单精确匹配用——
/// 运维下发一个 keyId 黑名单就能作废泄露的信封，不用碰用户本机的 DEK。
/// </param>
public sealed record KeyEnvelope(
    string CiphertextB64,
    string IvB64,
    string? Base,
    string? Model,
    long UpdatedAt,
    int Version = 1,
    string? KeyId = null);

/// <summary>信封失效的原因。以前静默回退用户没感觉，现在能报出来。</summary>
public enum EnvelopeIssue
{
    /// <summary>无问题（未配置自定义密钥，或解密成功）。</summary>
    None = 0,
    /// <summary>本机拿不到 DEK（换浏览器 / 清理过 IndexedDB / 换机器）。</summary>
    DekMissing = 1,
    /// <summary>信封命中吊销清单（运维判定泄露）。</summary>
    Revoked = 2,
    /// <summary>密文损坏或 DEK 不匹配，GCM 校验失败。</summary>
    Unreadable = 3,
}

public static class KeyEnvelopeCrypto
{
    /// <summary>当前信封格式版本，2 起带 keyId 指纹。</summary>
    public const int CurrentVersion = 2;

    public static KeyEnvelope Seal(string plaintextKey, byte[] dek, string? baseUri, string? model)
    {
        var iv = RandomNumberGenerator.GetBytes(12);
        var pt = Encoding.UTF8.GetBytes(plaintextKey ?? "");
        var ct = new byte[pt.Length];
        var tag = new byte[16];
        using var gcm = new AesGcm(dek, 16);
        gcm.Encrypt(iv, pt, ct, tag);
        // 密文 = ciphertext || tag（16 字节尾部），与 Web Crypto 密文格式一致
        var sealedBytes = new byte[ct.Length + tag.Length];
        Buffer.BlockCopy(ct, 0, sealedBytes, 0, ct.Length);
        Buffer.BlockCopy(tag, 0, sealedBytes, ct.Length, tag.Length);
        var ctB64 = Convert.ToBase64String(sealedBytes);
        return new KeyEnvelope(
            ctB64,
            Convert.ToBase64String(iv),
            baseUri,
            model,
            DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            CurrentVersion,
            Fingerprint(ctB64));
    }

    /// <summary>信封指纹：密文 SHA-256 前 8 字节的 hex（16 字符）。不含任何密钥材料。</summary>
    public static string Fingerprint(string ciphertextB64)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(ciphertextB64 ?? ""));
        return Convert.ToHexString(bytes, 0, 8).ToLowerInvariant();
    }

    /// <summary>
    /// 轮换：用新 DEK 把同一明文重新加密成新信封（版本和指纹都按当前格式重算），旧信封作废。
    /// 换机器或者怀疑泄露时走这个，别原地改 IV 糊弄。
    /// </summary>
    public static KeyEnvelope? Rotate(KeyEnvelope env, byte[] oldDek, byte[] newDek)
    {
        var key = Open(env, oldDek);
        if (key is null) return null; // 旧信封已不可解，无法轮换（调用方应让用户重配）
        return Seal(key, newDek, env.Base, env.Model);
    }

    public static string? Open(KeyEnvelope env, byte[] dek)
    {
        try
        {
            var sealedBytes = Convert.FromBase64String(env.CiphertextB64);
            if (sealedBytes.Length < 16) return null;
            var iv = Convert.FromBase64String(env.IvB64);
            var ctLen = sealedBytes.Length - 16;
            var ct = new byte[ctLen];
            var tag = new byte[16];
            Buffer.BlockCopy(sealedBytes, 0, ct, 0, ctLen);
            Buffer.BlockCopy(sealedBytes, ctLen, tag, 0, 16);
            var pt = new byte[ctLen];
            using var gcm = new AesGcm(dek, 16);
            gcm.Decrypt(iv, ct, tag, pt);
            return Encoding.UTF8.GetString(pt);
        }
        catch (Exception ex)
        {
            // 密钥环不匹配（换机器/清了 DEK）：信封作废，返回 null 触发调用方清理
            Diagnostics.Diag.Recover(ex, "envelope.open");
            return null;
        }
    }
}

/// <summary>信封吊销清单：只认 <see cref="KeyEnvelope.KeyId"/>，不用碰用户的 DEK。</summary>
public interface IKeyRevocationList
{
    bool IsRevoked(KeyEnvelope env);
}

/// <summary>内存吊销清单（测试与单机场景用；服务端可换成持久化实现）。</summary>
public sealed class InMemoryKeyRevocationList : IKeyRevocationList
{
    private readonly HashSet<string> _ids = new(StringComparer.OrdinalIgnoreCase);

    public InMemoryKeyRevocationList(IEnumerable<string>? revokedKeyIds = null)
    {
        if (revokedKeyIds is null) return;
        foreach (var id in revokedKeyIds)
        {
            if (!string.IsNullOrWhiteSpace(id)) _ids.Add(id.Trim());
        }
    }

    public int Count => _ids.Count;

    public void Revoke(string keyId)
    {
        if (!string.IsNullOrWhiteSpace(keyId)) _ids.Add(keyId.Trim());
    }

    public bool IsRevoked(KeyEnvelope env)
    {
        if (env.KeyId is null) return false; // 旧信封无指纹，吊销清单管不到（可先轮换再吊销）
        return _ids.Contains(env.KeyId);
    }
}
