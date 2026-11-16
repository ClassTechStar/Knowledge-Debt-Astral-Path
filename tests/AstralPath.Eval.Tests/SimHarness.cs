using AstralPath.Core.Algorithms;
using AstralPath.Graph;

namespace AstralPath.Eval.Tests;

/// <summary>
/// 可调参数集：与 FormulaConstants 一一对应，**只供离线评测/标定使用**。
/// 生产公式仍是 FormulaConstants 注入的确定性纯函数（红线不变）；
/// 本参数集的价值是把「为什么是这组数」从手设变成实验结论。
/// </summary>
internal sealed record SimParams(
    double WEmpirical = 0.50, double WRetention = 0.30, double WPrereq = 0.20,
    double PrereqFloor = 0.55, double PrereqWeakMix = 0.65,
    double Stability0 = 2.5, double StabilityAlpha = 0.45, double StabilityBeta = 0.25,
    double ImpactBase = 0.55, double GateSteepness = 8.0,
    double CascadeAlpha = 0.12, double VolumeBeta = 0.08,
    double SaleBar = 0.65, double SaleAccMin = 0.7)
{
    public static readonly SimParams Default = new();
}

/// <summary>公式集抽象：生产实现 ↔ 参数化复刻，仿真器只依赖此接口。</summary>
internal interface IFormulaSet
{
    double Score(MasteryInput input);
    double Impact(DebtInput input);
    bool IsHit(DebtInput input);
    SaleState Transition(SaleState state, SaleAttempt attempt);
}

/// <summary>生产公式直通（A1 用）。</summary>
internal sealed class ProdFormulas : IFormulaSet
{
    public static readonly ProdFormulas Instance = new();
    public double Score(MasteryInput input) => MasteryCalculator.ComputeScore(input);
    public double Impact(DebtInput input) => DebtScanner.ComputeImpact(input);
    public bool IsHit(DebtInput input) => DebtScanner.IsHit(input);
    public SaleState Transition(SaleState state, SaleAttempt attempt) => SaleStateMachine.Transition(state, attempt);
}

/// <summary>
/// 参数化复刻（A2 用）：逐项镜像 MasteryCalculator / DebtScanner / SaleStateMachine，
/// 但常数取自 SimParams。与生产实现的逐值对拍由 ParameterCalibrationTests 的
/// Parity 用例锁死（1e-9）——对拍通过，敏感性/标定结论才能迁回生产公式。
/// 未纳入扫描的常数（Jeffreys 先验 0.5、know 混合 0.85/0.15、门限中心 0.55/0.50、
/// transfer_gap 1.15、conf 比 0.7/0.3、conf 刻度 5、命中线 0.08）按真源字面镜像。
/// </summary>
internal sealed class ParamFormulas : IFormulaSet
{
    private readonly SimParams _p;
    public ParamFormulas(SimParams p) => _p = p;

    private static double Clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    private static double Sigmoid(double x) => 1.0 / (1.0 + Math.Exp(-x));

    public double Score(MasteryInput i)
    {
        var s = Math.Clamp(i.Successes, 0, Math.Max(i.Attempts, 0));
        var f = Math.Max(i.Attempts, 0) - s;
        var emp = (s + 0.5) / (s + f + 1.0); // Jeffreys 先验 0.5/0.5
        var confNorm = Math.Clamp(i.MeanSelfConf / 5.0, 0, 1);
        var know = 0.85 * emp + 0.15 * confNorm;

        var st = Math.Max(i.Streak, 0);
        var n = Math.Max(i.Attempts, 1);
        var stab = _p.Stability0 * (1.0 + _p.StabilityAlpha * st) * (1.0 + _p.StabilityBeta * Math.Log(1.0 + n));
        var ret = Math.Exp(-Math.Max(i.AgeDays, 0) / stab);

        double pre;
        if (i.PrereqScores is not { Count: > 0 }) pre = 0.5;
        else pre = (1 - _p.PrereqWeakMix) * i.PrereqScores.Average() + _p.PrereqWeakMix * i.PrereqScores.Min();

        var raw = _p.WEmpirical * know + _p.WRetention * ret + _p.WPrereq * pre;
        var ceil = i.PrereqScores is not { Count: > 0 } ? 1.0 : _p.PrereqFloor + (1 - _p.PrereqFloor) * i.PrereqScores.Min();
        return Clamp01(Math.Min(raw, ceil));
    }

    public double Impact(DebtInput i)
    {
        if (i.Freq <= 0) return 0.0;
        var readiness = Sigmoid((i.ScoreFrom - 0.55) * _p.GateSteepness);
        var gap = Sigmoid((0.50 - i.ScoreTo) * _p.GateSteepness);
        var cross = i.EdgeType == EdgeType.TransferGap ? 1.15 : 1.0;
        return _p.ImpactBase * readiness * gap * Math.Max(i.Weight, 0) * cross
               * (1.0 + _p.CascadeAlpha * Math.Log(1.0 + Math.Max(i.DownstreamCount, 0)))
               * (1.0 + _p.VolumeBeta * Math.Log(1.0 + Math.Max(i.Freq, 0)));
    }

    public bool IsHit(DebtInput i) => i.Freq > 0 && Impact(i) >= 0.08;

    private double Weighted(SaleAttempt a)
        => 0.7 * Math.Clamp(a.Accuracy, 0, 1) + 0.3 * Math.Clamp(a.SelfConf / 5.0, 0, 1);

    private bool MeetsBar(SaleAttempt a)
        => Weighted(a) >= _p.SaleBar && a.Accuracy >= _p.SaleAccMin && a.SelfConf >= 3;

    public SaleState Transition(SaleState state, SaleAttempt a)
    {
        if (state.Status == SaleStatus.Cleared) return state;
        var attempts = state.Attempts + 1;
        var streak = MeetsBar(a) ? state.Streak + 1 : 0;
        var pct = (int)Math.Round(Weighted(a) * 100);
        var status = state.Status;
        if (streak >= 2 && attempts >= 3) status = SaleStatus.Cleared;
        else if (streak > 0 || attempts > 0) status = SaleStatus.Repairing;
        return new SaleState(status, streak, attempts, pct);
    }
}

/// <summary>合成学习者的公开指标（A1 策略对比 / A2 敏感性共用）。</summary>
internal sealed record Metrics(
    string Strategy,
    int DebtCleared,
    int DebtTotal,
    int TotalCleared,
    double AvgAttemptsPerClear,
    double Retention14,
    double Retention30);

/// <summary>
/// 仿真世界：图谱 + 合成学习者（latent，简化 ACT-R 稳定性棘轮）+ 应用侧估计
/// （公式集可注入）。策略与用例见 SimulatedLearnerEvalTests / ParameterCalibrationTests。
/// </summary>
internal sealed class SimWorld
{
    public const int PlanDays = 14;
    public const int SessionsPerDay = 3;
    public const int TotalAttempts = PlanDays * SessionsPerDay;

    // 欠债注入：K02/K03 是 K05/K06 的先修，起始掌握低（「会计等式→借贷记账法」红边形态）
    public static readonly Dictionary<string, double> InitialDebt = new()
    {
        ["K02"] = 0.18,
        ["K03"] = 0.22,
    };

    private sealed class Latent
    {
        public double Level;
        public double Stab = 2.5;
        public int Attempts;
        public int Successes;
        public int Streak;
        public int LastDay;
        public int WrongFreq;
    }

    private sealed class BktTrack
    {
        public double Pm = 0.2;
        private const double Learn = 0.12, Guess = 0.2, Slip = 0.1;

        public void Update(bool correct)
        {
            var pKnown = 1.0 - Slip;
            var pUnknown = Guess;
            var pCorrect = Pm * pKnown + (1 - Pm) * pUnknown;
            var pPost = correct ? Pm * pKnown / pCorrect : Pm * (1 - pKnown) / (1 - pCorrect);
            Pm = pPost + (1 - pPost) * Learn;
        }
    }

    private readonly KnowledgeGraph _graph;
    private readonly IFormulaSet _f;
    private readonly Dictionary<string, Latent> _latent = new();
    private readonly Dictionary<string, SaleState> _sale = new();
    private readonly Dictionary<string, BktTrack> _bkt = new();
    private readonly Dictionary<string, int> _nextReview = new();
    private readonly Random _rng;
    private readonly string _strategy;
    private int _day;
    private int _slot;

    public SimWorld(KnowledgeGraph graph, string strategy, int seed, IFormulaSet formulas)
    {
        _graph = graph;
        _strategy = strategy;
        _f = formulas;
        _rng = new Random(seed);
        foreach (var n in graph.Nodes)
        {
            var level = InitialDebt.TryGetValue(n.Id, out var debt) ? debt : 0.55 + 0.2 * ((_rng.NextDouble() + n.Id.Length) % 1);
            _latent[n.Id] = new Latent { Level = Math.Clamp(level, 0.05, 0.95) };
            _sale[n.Id] = SaleStateMachine.Create();
            _bkt[n.Id] = new BktTrack();
            _nextReview[n.Id] = 1;
        }
    }

    /// <summary>真实掌握度（含遗忘）：level × exp(-age/Stab)，ACT-R 式稳定性棘轮在 Attempt 内增长。</summary>
    public double Effective(string kp)
    {
        var l = _latent[kp];
        var age = Math.Max(_day - l.LastDay, 0);
        return l.Level * Math.Exp(-age / l.Stab);
    }

    /// <summary>应用侧估计：注入的公式集（生产或参数化）。</summary>
    public double Estimate(string kp)
    {
        var l = _latent[kp];
        var prereqs = _graph.Edges
            .Where(e => e.To == kp && e.EdgeType != "transfer_gap")
            .Select(e => EstimateFrom(e.From))
            .ToList();
        return _f.Score(new MasteryInput(
            l.Attempts, l.Successes, MeanConf(kp),
            Math.Max(_day - l.LastDay, 0), l.Streak, prereqs));
    }

    private readonly Dictionary<string, double> _estCache = new();
    private double EstimateFrom(string kp)
    {
        if (_estCache.TryGetValue(kp, out var v)) return v;
        v = Estimate(kp); // 图无环，递归安全
        _estCache[kp] = v;
        return v;
    }

    private double MeanConf(string kp)
    {
        var l = _latent[kp];
        return l.Attempts == 0 ? 3.0 : 2.0 + 2.0 * l.Successes / l.Attempts;
    }

    private void NewDay(int day)
    {
        _day = day;
        _estCache.Clear();
    }

    private List<(string Target, double Impact)> OpenDebts()
    {
        var debts = new List<(string, double)>();
        foreach (var e in _graph.Edges)
        {
            var child = _latent[e.To];
            var input = new DebtInput(
                EstimateFrom(e.From), EstimateFrom(e.To), e.Weight,
                e.EdgeType == "transfer_gap" ? EdgeType.TransferGap : EdgeType.Prerequisite,
                child.WrongFreq, _graph.OutNeighbors(e.From).Count);
            if (_f.IsHit(input)) debts.Add((e.To, _f.Impact(input)));
        }
        return debts;
    }

    private string PickKp()
    {
        var kps = _graph.Nodes.Select(n => n.Id).ToList();
        switch (_strategy)
        {
            case "random":
                return kps[_rng.Next(kps.Count)];

            case "sm2":
                {
                    var pick = kps.OrderBy(k => _nextReview[k]).ThenBy(k => k, StringComparer.Ordinal).First();
                    var l = _latent[pick];
                    var intervals = new[] { 1, 2, 4, 8 };
                    _nextReview[pick] = _day + intervals[Math.Min(l.Streak, 3)];
                    return pick;
                }

            case "bkt":
                return kps.OrderBy(k => _bkt[k].Pm).ThenBy(k => k, StringComparer.Ordinal).First();

            case "cram":
                {
                    var block = (_day - 1) % kps.Count;
                    return kps[block];
                }

            case "massed":
                return kps[Math.Min(_slot / 3, kps.Count - 1)];

            case "spread":
                return kps[_slot % 14];

            default: // impact-v2 + 间隔复习（项目策略）
                {
                    var debts = OpenDebts();
                    var candidates = (debts.Count > 0
                            ? debts.Select(d => d.Target).Distinct()
                            : kps)
                        .Where(k => _day - _latent[k].LastDay >= 2 || _latent[k].LastDay == 0)
                        .ToList();
                    if (candidates.Count == 0) candidates = kps;
                    var pool = candidates.Select(k => new QuestionCandidate(
                        k, k,
                        QuestionScheduler.TargetDifficulty(EstimateFrom(k)),
                        EstimateFrom(k),
                        debts.Where(d => d.Target == k).Select(d => d.Impact).DefaultIfEmpty(0).Max(),
                        Math.Max(_day - _latent[k].LastDay, 0))).ToList();
                    return QuestionScheduler.Pick(pool)!.KpId;
                }
        }
    }

    private void Attempt(string kp)
    {
        _slot++;
        var l = _latent[kp];
        var eff = Effective(kp);
        // 难度固定基线档（0.25）：隔离纯间隔效应，避免遗忘后回练被难度放大
        var pCorrect = Math.Clamp(0.08 + 0.84 * MasteryCalculator.Sigmoid((eff - 0.25) * 6), 0.05, 0.95);
        var correct = _rng.NextDouble() < pCorrect;

        var gap = l.LastDay == 0 ? 0 : Math.Max(_day - l.LastDay, 0);
        if (correct)
        {
            l.Level = Math.Clamp(l.Level + (1 - l.Level) * 0.30, 0, 1);
            l.Stab += 2.0 + 0.8 * Math.Min(gap, 10);
            l.Successes++; l.Streak++;
        }
        else
        {
            l.Level = Math.Clamp(l.Level + (1 - l.Level) * 0.12, 0, 1);
            l.Stab += 0.3;
            l.Streak = 0; l.WrongFreq++;
        }
        l.Attempts++;
        l.LastDay = _day;

        _bkt[kp].Update(correct);

        var acc = (double)l.Successes / l.Attempts;
        var conf = correct ? 4 : 2;
        _sale[kp] = _f.Transition(_sale[kp], new SaleAttempt(correct, acc, conf));
    }

    public Metrics Run()
    {
        for (var day = 1; day <= PlanDays; day++)
        {
            NewDay(day);
            for (var s = 0; s < SessionsPerDay; s++) Attempt(PickKp());
        }

        var debtKps = InitialDebt.Keys.ToHashSet();
        var clearedDebt = debtKps.Count(k => _sale[k].Status == SaleStatus.Cleared);
        var clearedAll = _sale.Count(kv => kv.Value.Status == SaleStatus.Cleared);
        var clearedKps = _sale.Where(kv => kv.Value.Status == SaleStatus.Cleared).Select(kv => kv.Key).ToHashSet();
        var attemptsOnCleared = clearedKps.Sum(k => _latent[k].Attempts);

        NewDay(14);
        var practiced = _graph.Nodes.Select(n => n.Id).Where(k => _latent[k].Attempts > 0).ToList();
        if (practiced.Count == 0) practiced = _graph.Nodes.Select(n => n.Id).ToList();
        var retention14 = practiced.Average(Effective);
        NewDay(30);
        var retention30 = practiced.Average(Effective);

        return new Metrics(
            _strategy,
            clearedDebt, debtKps.Count, clearedAll,
            clearedAll == 0 ? double.NaN : (double)attemptsOnCleared / clearedAll,
            retention14, retention30);
    }

    /// <summary>加载 accounting-v1 图包（从测试输出目录或仓库根向上遍历）。</summary>
    public static KnowledgeGraph LoadGraph()
    {
        var dir = Directory.Exists(Path.Combine(Directory.GetCurrentDirectory(), "graph-packs", "accounting-v1"))
            ? Path.Combine(Directory.GetCurrentDirectory(), "graph-packs", "accounting-v1")
            : FindPackUpwards();
        return new KnowledgeGraph(KnowledgeGraph.LoadFromDirectory(dir));
    }

    private static string FindPackUpwards()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "graph-packs", "accounting-v1");
            if (Directory.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("找不到 graph-packs/accounting-v1（从测试目录向上遍历失败）");
    }
}
