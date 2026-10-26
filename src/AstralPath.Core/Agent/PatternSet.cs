using System.Text;
using System.Text.RegularExpressions;

namespace AstralPath.Core.Agent;

/// <summary>
/// 一组模式的匹配器，归一化后做 Contains，带括号或竖线的模式当正则用。
/// 命中任意一个就算命中，危机词、禁词、锚点都走它。
/// </summary>
public sealed class PatternSet
{
    private readonly string[] _patterns;
    private readonly bool[] _isRegex;
    private readonly Regex[] _regexes;
    public string Name { get; }
    public int Count => _patterns.Length;

    public PatternSet(string name, IEnumerable<string> patterns)
    {
        Name = name;
        var list = patterns.Where(p => !string.IsNullOrWhiteSpace(p)).ToList();
        _patterns = list.ToArray();
        _isRegex = new bool[_patterns.Length];
        _regexes = new Regex[_patterns.Length];
        for (var i = 0; i < _patterns.Length; i++)
        {
            var p = _patterns[i];
            var looksRegex = p.Contains('(') || p.Contains('[') || p.Contains('|') || p.Contains('*') || p.Contains('+');
            _isRegex[i] = looksRegex;
            if (looksRegex)
            {
                _regexes[i] = new Regex(p, RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            }
        }
    }

    /// <summary>文本归一化：全角转半角、空白并成空格、统一小写，匹配前都先过这。</summary>
    public static string Normalize(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var sb = new StringBuilder(text.Length);
        foreach (var ch in text)
        {
            var c = ch;
            // 全角 → 半角
            if (c >= 0xFF01 && c <= 0xFF5E) c = (char)(c - 0xFEE0);
            if (c == 0x3000) c = ' ';
            if (char.IsWhiteSpace(c) || c == '　') c = ' ';
            sb.Append(char.ToLowerInvariant(c));
        }
        return sb.ToString();
    }

    public bool ContainsAny(string? raw)
    {
        var norm = Normalize(raw);
        if (norm.Length == 0) return false;
        for (var i = 0; i < _patterns.Length; i++)
        {
            if (_isRegex[i])
            {
                if (_regexes[i].IsMatch(norm) || _regexes[i].IsMatch(raw ?? "")) return true;
            }
            else
            {
                var p = Normalize(_patterns[i]);
                if (p.Length > 0 && norm.Contains(p, StringComparison.Ordinal)) return true;
            }
        }
        return false;
    }

    public (bool Hit, string? Pattern, int Index) MatchFirst(string? raw)
    {
        var norm = Normalize(raw);
        for (var i = 0; i < _patterns.Length; i++)
        {
            if (_isRegex[i])
            {
                if (_regexes[i].IsMatch(norm) || _regexes[i].IsMatch(raw ?? ""))
                    return (true, _patterns[i], i);
            }
            else
            {
                var p = Normalize(_patterns[i]);
                if (p.Length > 0 && norm.Contains(p, StringComparison.Ordinal))
                    return (true, _patterns[i], i);
            }
        }
        return (false, null, -1);
    }

    /// <summary>返回命中的最长模式有多长，用来判断整句是不是就是这句客套话。</summary>
    public int LongestMatchLength(string? raw)
    {
        var norm = Normalize(raw);
        if (norm.Length == 0) return 0;
        var best = 0;
        for (var i = 0; i < _patterns.Length; i++)
        {
            var p = Normalize(_patterns[i]);
            if (p.Length == 0) continue;
            if (_isRegex[i])
            {
                if (_regexes[i].IsMatch(norm)) best = Math.Max(best, norm.Length);
            }
            else if (norm.Contains(p, StringComparison.Ordinal))
            {
                best = Math.Max(best, p.Length);
            }
        }
        return best;
    }
}
