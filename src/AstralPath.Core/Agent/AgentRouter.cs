namespace AstralPath.Core.Agent;

/// <summary>
/// 受约束智能体路由器 v3。相比 v2 修了几个老毛病：阈值常量以前定义了却没用上（实际硬编码 0.5），
/// 现在真的走 TauExec / TauClarify / MaxClarify，还加了「和次优差距太小算歧义」的判断；
/// 打分改成主锚点加分、其余锚点饱和累加，多个锚点同时命中算更强的证据，另外按覆盖率压住
/// 长句里偶然碰中一个短词就 execute 的误判；负例要占整句够长才判死，不然"好的，帮我生成计划"
/// 会被整句干掉；槽位分支会抽已填槽位、槽位齐了就 execute，追问到 MaxClarify 就不再纠缠，
/// 也允许中途换话题；角色过滤换成预建 HashSet，去掉 32 个意图的位图上限；最后支持 prevIntent，
/// "再解释一下"这种省略指代能接上上文。
/// </summary>
public sealed class AgentRouter
{
    public const double TauExec = 0.75;
    public const double TauClarify = 0.60;
    public const int MaxClarify = 2;

    private readonly PatternSet _crisis;
    private readonly PatternSet _banned;
    private readonly PatternSet _negative;
    private readonly IReadOnlyList<AgentIntent> _intents;
    private readonly Dictionary<string, HashSet<string>> _roleIntents;

    public PatternSet Banned => _banned;
    public PatternSet Crisis => _crisis;
    public IReadOnlyList<AgentIntent> Intents => _intents;

    public AgentRouter(
        IEnumerable<string> crisisWords,
        IEnumerable<string> bannedWords,
        IEnumerable<string> negativeWords,
        IEnumerable<AgentIntent> intents)
    {
        _crisis = new PatternSet("crisis", crisisWords);
        _banned = new PatternSet("banned", bannedWords);
        _negative = new PatternSet("negative", negativeWords);
        _intents = intents.ToList();
        _roleIntents = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var role in new[] { AgentRoles.Student, AgentRoles.Teacher, AgentRoles.Admin, AgentRoles.Demo })
        {
            var set = new HashSet<string>(StringComparer.Ordinal);
            foreach (var it in _intents)
            {
                if (it.RoleMask.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Contains(role, StringComparer.OrdinalIgnoreCase))
                {
                    set.Add(it.IntentId);
                }
            }
            _roleIntents[role] = set;
        }
    }

    private bool Allows(string role, string intentId)
        => _roleIntents.TryGetValue(role, out var set) && set.Contains(intentId);

    /// <summary>对一句话打分，返回全部候选（按分数降序）。</summary>
    public IReadOnlyList<IntentScore> Score(string? utterance, string role)
    {
        var norm = PatternSet.Normalize(utterance);
        var scores = new List<IntentScore>();
        if (norm.Length == 0) return scores;

        foreach (var it in _intents)
        {
            if (it.IntentId == "crisis.handoff") continue; // 由 R0 单独处理
            if (!Allows(role, it.IntentId)) continue;

            double maxS = 0, sumOthers = 0;
            var bestAnchor = "";
            var matchedLen = 0;
            foreach (var anchor in it.Anchors)
            {
                var a = PatternSet.Normalize(anchor);
                if (a.Length == 0 || !norm.Contains(a, StringComparison.Ordinal)) continue;
                // 越长锚点越特异
                var s = 0.5 + 0.5 * Math.Min(1.0, a.Length / 8.0);
                matchedLen += a.Length;
                if (s > maxS) { sumOthers += maxS; maxS = s; bestAnchor = anchor; }
                else sumOthers += s;
            }

            // 意图描述里的核心词算弱证据
            var desc = PatternSet.Normalize(it.Description);
            if (desc.Length >= 2 && norm.Contains(desc, StringComparison.Ordinal))
                maxS = Math.Max(maxS, 0.5);

            if (maxS <= 0) continue;

            // 多锚点饱和累加 + 覆盖率奖励（抑制长句里的偶然短词命中）
            var score = maxS + 0.5 * Math.Min(sumOthers, 1.0);
            score += 0.15 * Math.Min(1.0, matchedLen / Math.Max(6.0, norm.Length));
            score = Math.Clamp(score, 0.0, 1.0);
            scores.Add(new IntentScore(it.IntentId, Math.Round(score, 6), bestAnchor));
        }
        return scores.OrderByDescending(s => s.Score).ThenBy(s => s.IntentId, StringComparer.Ordinal).ToList();
    }

    /// <summary>
    /// 分类。
    /// </summary>
    /// <param name="awaitingIntent">上一轮正在追问的意图（槽位填充中）。</param>
    /// <param name="prevIntentId">上一轮已执行的意图，用于"再解释一下"这类省略指代。</param>
    public AgentRouteResult Classify(
        string? utterance,
        string role,
        int clarifyCount = 0,
        string? awaitingIntent = null,
        string? prevIntentId = null)
    {
        // R0 危机词最先判，优先级最高
        var crisis = _crisis.MatchFirst(utterance);
        if (crisis.Hit)
            return new AgentRouteResult("crisis.handoff", 1.0, "crisis.handoff", Array.Empty<string>(),
                $"R0:crisis:{crisis.Pattern}");

        var norm = PatternSet.Normalize(utterance);

        // R2.5 负例快落：负例得占整句 60% 以上才认，免得误杀"好的，帮我…"这种
        if (norm.Length > 0 && _negative.ContainsAny(norm))
        {
            var longest = _negative.LongestMatchLength(norm);
            var ratio = norm.Length == 0 ? 0 : (double)longest / norm.Length;
            if (ratio >= 0.6)
                return new AgentRouteResult("meta.help", 0.0, "fallback", Array.Empty<string>(),
                    $"R2.5:negative_lexicon;ratio={ratio:0.00}");
        }

        var ranked = Score(utterance, role);
        var best = ranked.Count > 0 ? ranked[0] : null;
        var second = ranked.Count > 1 ? ranked[1] : null;

        // R1 槽位填充 / 话题切换
        if (!string.IsNullOrWhiteSpace(awaitingIntent))
        {
            var pending = _intents.FirstOrDefault(i => i.IntentId == awaitingIntent);

            // 用户中途换话题：新意图分数够高就切换
            if (best is not null && !string.Equals(best.IntentId, awaitingIntent, StringComparison.Ordinal)
                && best.Score >= TauExec)
            {
                return Decide(best, ranked, pendingSlots: Array.Empty<string>(), tracePrefix: "R1:topic_switch");
            }

            if (pending is not null)
            {
                var filled = ExtractProvidedSlots(pending, norm);
                var remaining = pending.RequiredSlots
                    .Where(s => !filled.Contains(s, StringComparer.OrdinalIgnoreCase))
                    .ToArray();

                if (remaining.Length == 0)
                    return new AgentRouteResult(pending.IntentId, 1.0, "execute", Array.Empty<string>(),
                        "R1:slots_complete");

                // 追问次数用完 → 不再纠缠，按已有信息执行
                if (clarifyCount >= MaxClarify)
                    return new AgentRouteResult(pending.IntentId, 0.6, "execute", remaining,
                        $"R1:max_clarify_reached({MaxClarify})");

                return new AgentRouteResult(pending.IntentId, 0.8, "clarify", remaining,
                    "R1:awaiting_slot:" + string.Join(",", remaining));
            }
        }

        // R3 锚点路由
        if (best is not null)
        {
            var intent = _intents.FirstOrDefault(i => i.IntentId == best.IntentId);
            var filled = intent is null ? Array.Empty<string>() : ExtractProvidedSlots(intent, norm);
            var missing = intent?.RequiredSlots
                .Where(s => !filled.Contains(s, StringComparer.OrdinalIgnoreCase))
                .ToArray() ?? Array.Empty<string>();

            // 分数够高，或上文意图延续（"再解释一下"）
            var inherits = prevIntentId is not null
                           && string.Equals(best.IntentId, prevIntentId, StringComparison.Ordinal);
            var threshold = inherits ? TauClarify : TauExec;

            // 歧义：与次优差距过小 → 先问一句
            var ambiguous = second is not null && best.Score - second.Score < 0.08;

            if (best.Score >= threshold && !ambiguous)
                return Decide(best, ranked, missing, "R3:anchor");

            if (best.Score >= TauClarify)
                return new AgentRouteResult(best.IntentId, best.Score,
                    missing.Length > 0 || ambiguous ? "clarify" : "execute",
                    missing, $"R3:mid_confidence;score={best.Score:0.00};ambiguous={ambiguous}");

            // 低分：沿用上文意图兜底（避免每句话都掉回 help）
            if (inherits)
                return new AgentRouteResult(prevIntentId!, best.Score, "execute", missing,
                    $"R3:anaphora;score={best.Score:0.00}");
        }

        // R6 兜底
        var help = _intents.FirstOrDefault(i => i.IntentId == "meta.help");
        return new AgentRouteResult(help?.IntentId ?? "meta.help", 0.0, "fallback", Array.Empty<string>(), "R6:fallback");
    }

    private AgentRouteResult Decide(IntentScore best, IReadOnlyList<IntentScore> ranked, string[] pendingSlots, string tracePrefix)
    {
        var decision = pendingSlots.Length == 0 ? "execute" : "clarify";
        var near = ranked.Count > 1 ? ranked[1] : null;
        return new AgentRouteResult(best.IntentId, best.Score, decision, pendingSlots,
            $"{tracePrefix}:{best.Anchor};score={best.Score:0.00};second={(near?.IntentId ?? "-")}");
    }

    /// <summary>口语填充词：去掉后仍有内容才算"提供了槽位值"。</summary>
    private static readonly string[] SlotFillers =
    {
        "帮我", "请", "麻烦", "我想", "我要", "给我", "我的", "能不能", "可以", "一下", "一个",
        "帮", "查", "找", "看", "要", "给", "的", "是", "了", "吗", "呢", "把", "个"
    };

    private const string SlotPunct = "，,。.！!？?：:；;、\"'“”‘’（）()【】[]";

    /// <summary>
    /// 从用户话里抽已提供的槽位，两级启发式（纯函数、好测；真上生产建议换 NER/模板抽槽）：
    /// 槽位名直接出现就算填了（"书名是会计基础"）；
    /// 再不然走残余法，把命中锚点和口语填充词剔掉还剩实质内容、且只剩一个槽位没填，剩下的就是它的值（"检索 会计基础"）。
    /// 少了残余法会出现"用户明明给了值，系统还在追问"的死循环。
    /// </summary>
    public static IReadOnlyList<string> ExtractProvidedSlots(AgentIntent intent, string normalizedUtterance)
    {
        if (intent.RequiredSlots.Length == 0) return Array.Empty<string>();
        var norm = PatternSet.Normalize(normalizedUtterance);
        if (norm.Length == 0) return Array.Empty<string>();

        var filled = new List<string>();
        foreach (var s in intent.RequiredSlots)
            if (norm.Contains(PatternSet.Normalize(s), StringComparison.Ordinal)) filled.Add(s);
        if (filled.Count == intent.RequiredSlots.Length) return filled;

        var residual = norm;
        foreach (var a in intent.Anchors)
        {
            var na = PatternSet.Normalize(a);
            if (na.Length > 0) residual = residual.Replace(na, "", StringComparison.Ordinal);
        }
        foreach (var f in SlotFillers)
            residual = residual.Replace(f, "", StringComparison.Ordinal);
        residual = new string(residual.Where(c => !char.IsWhiteSpace(c) && !SlotPunct.Contains(c)).ToArray());

        var unfilled = intent.RequiredSlots.Where(s => !filled.Contains(s, StringComparer.OrdinalIgnoreCase)).ToList();
        if (residual.Length >= 2 && unfilled.Count == 1) filled.Add(unfilled[0]);

        return filled;
    }

    public bool IsBanned(string? text) => _banned.ContainsAny(text);

    public static AgentRouter CreateDefault() => new(
        crisisWords: new[] { "自杀", "不想活", "轻生", "结束生命", "自残", "伤害自己", "跳楼", "上吊", "suicide", "kill myself", "活不下去" },
        bannedWords: Formula.FormulaWeights.BannedWords,
        negativeWords: new[] { "哈哈", "呵呵", "随便", "没事了", "thanks", "thank you", "ok", "好的" },
        intents: DefaultAgentIntents.Table);

    /// <summary>
    /// [P5-1 合并] 原先这里内联着第二张 22 意图运行时表，与登记表
    /// DefaultAgentIntents.Table（15 意图）长期漂移。现在统一委托登记表，
    /// 登记表即运行时表；内容必须与 tools/agent-intents.json 逐字一致，
    /// 由 scripts/verify_agent_intents.py 对拍。
    /// </summary>
    public static IReadOnlyList<AgentIntent> DefaultIntents() => DefaultAgentIntents.Table;
}
