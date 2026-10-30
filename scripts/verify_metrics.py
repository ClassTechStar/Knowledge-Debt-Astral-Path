# README 里的数字只维护一份：意图 / 危机词 / 测试数都从代码统计出来，自动和 README 比对
# 早先这些数字是手填的，改几轮代码后就和实际对不上了，所以改成机器统计。
# 意图 / 危机词来自 tools/agent-intents.json，测试数用 dotnet test --list-tests 枚举。
# README 中被盯住的数字用成对注释标记包起来：
#   <!-- metrics:key -->值<!-- /metrics:key -->
# 用法：python scripts/verify_metrics.py          # 统计 + 回写 README + 写 eval/metrics.json
#       python scripts/verify_metrics.py --check  # 只校验（CI / verify_all 用）
# 退出码：0 = ALL GREEN；1 = 数字对不上
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INTENTS_JSON = ROOT / "tools" / "agent-intents.json"
README = ROOT / "README.md"
METRICS_OUT = ROOT / "eval" / "metrics.json"
TESTS_DIR = ROOT / "tests"

# 测试项目 → README 标记 key（保持与 README §7 表格一致）
PROJECTS = [
    ("Core", "tests-Core"),
    ("Persistence", "tests-Persistence"),
    ("Desktop", "tests-Desktop"),
    ("Api", "tests-Api"),
    ("Eval", "tests-Eval"),
]

FACT_RE = re.compile(r"\[(?:Avalonia)?Fact\]")
THEORY_RE = re.compile(r"\[(?:Avalonia)?Theory\]")
INLINE_DATA_RE = re.compile(r"\[InlineData")
LIST_LINE_RE = re.compile(r"^\s{4,}\S")


def count_project_tests(csproj_dir: Path) -> int:
    """用 dotnet test --list-tests 精确枚举用例数（含 Theory 数据展开）。

    不用静态数 InlineData：MemberData 这类自定义数据源根本数不准，迟早又对不上。
    要求先构建过（--no-build）。
    """
    proc = subprocess.run(
        ["dotnet", "test", str(csproj_dir), "-c", "Release", "--no-build", "--list-tests"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600,
    )
    if proc.returncode != 0:
        print(f"[ERROR] dotnet test --list-tests 失败（{csproj_dir.name}）：请先 dotnet build")
        print(proc.stdout[-500:] if proc.stdout else "", proc.stderr[-300:] if proc.stderr else "")
        sys.exit(1)
    return sum(1 for ln in proc.stdout.splitlines() if LIST_LINE_RE.match(ln))


def collect() -> dict:
    intents = json.loads(INTENTS_JSON.read_text(encoding="utf-8"))
    n_intents = len(intents["intents"])
    n_crisis = len(intents["crisis"])
    per_project = {}
    for name, key in PROJECTS:
        d = TESTS_DIR / f"AstralPath.{name}.Tests"
        per_project[key] = count_project_tests(d) if d.exists() else 0
    metrics = {
        "agentIntents": n_intents,
        "crisisWords": n_crisis,
        "tests": per_project,
        "testsTotal": sum(per_project.values()),
    }
    return metrics


def rewrite_readme(metrics: dict, check_only: bool) -> list:
    """校验/回写 README 中带 metrics 标记的数字，返回漂移列表。"""
    text = README.read_text(encoding="utf-8")
    values = dict(metrics["tests"])
    values["tests-Total"] = metrics["testsTotal"]
    values["agent-intents"] = metrics["agentIntents"]
    values["crisis-words"] = metrics["crisisWords"]
    drift = []
    pattern = re.compile(r"(<!-- metrics:([a-zA-Z0-9-]+) -->)(\d+)(<!-- /metrics:\2 -->)")

    def sub(m):
        key = m.group(2)
        if key not in values:
            drift.append(f"README 出现未知标记 metrics:{key}")
            return m.group(0)
        want = str(values[key])
        if m.group(3) != want:
            drift.append(f"metrics:{key} README={m.group(3)} 实际={want}")
            return f"{m.group(1)}{want}{m.group(4)}" if not check_only else m.group(0)
        return m.group(0)

    new_text = pattern.sub(sub, text)
    if drift and not check_only:
        README.write_text(new_text, encoding="utf-8")
    return drift


def main() -> int:
    check_only = "--check" in sys.argv
    metrics = collect()
    METRICS_OUT.write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    drift = rewrite_readme(metrics, check_only)
    # 这里别写嵌套 f-string：PEP 701 要 Python 3.12+，而 CI 跑的是 3.11
    test_parts = " / ".join(
        "%s=%s" % (k.split("-")[-1], v) for k, v in metrics["tests"].items()
    )
    print(
        f"[metrics] 意图 {metrics['agentIntents']} · 危机词 {metrics['crisisWords']} · "
        f"测试 {metrics['testsTotal']}（{test_parts}）"
    )
    missing = [k for k, _ in [("tests-Total", 0)] if f"<!-- metrics:{k} -->" not in README.read_text(encoding="utf-8")]
    if missing:
        print(f"[DRIFT] README 缺少 metrics 标记：{missing}")
        return 1
    if drift:
        print("[DRIFT] " + "；".join(drift))
        print("FAILED: README 数字与代码不一致" + ("（--check 模式不回写）" if check_only else "（已回写，请提交）"))
        return 1
    print("ALL GREEN · README 数字与代码一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
