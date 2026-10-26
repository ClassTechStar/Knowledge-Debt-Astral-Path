# -*- coding: utf-8 -*-
"""XSS 注入点检查，分两部分：
  1) 用例：contracts/golden/xss-cases.json → shared/safe-dom.js 的 safeRich/esc
     必须挡下事件注入、协议注入、mutation XSS，同时不误伤白名单富文本。
  2) 源码扫描：主 HTML 与 shared/integrations 的 innerHTML 直插点，RHS 出现
     「模型输出 / 用户内容」变量又没包 esc()/safeRich()/setHTML() 就判红。

用法：python scripts/verify_xss.py
退出码：0 = ALL GREEN；1 = 还有没管住的注入点
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = ROOT / "contracts" / "golden" / "xss-cases.json"
RUNNER = ROOT / "scripts" / "xss_runner.js"

SCAN_TARGETS = [
    ROOT / "deploy" / "monolith-web" / "index.html",
    ROOT / "shared" / "integrations" / "p0-ai-integration.js",
    ROOT / "shared" / "integrations" / "p1-ai-integration.js",
    ROOT / "shared" / "integrations" / "p2-ai-integration.js",
]

# 承载「模型输出 / 用户内容」的属性/变量。只取属性引用，不然 acc/logs 这类
# 数值变量会造出一堆假红；流式 acc 的写入点由下面的 GUARD 兜住
SINK = re.compile(
    r"(\.stem|\.explain|\.text|\.title|\.name|\.label|\.fromName|\.toName"
    r"|reply|aiText|_aiExplain)"
)
# 已经包了转义的出口
GUARD = re.compile(r"(esc\(|safeRich\(|setHTML\(|setText\(|sanitizeText\(|APSafe\.)")

# 回归哨兵，和 sync-monolith-html.ps1 里那个同款，专抓没转义的 .map(title)
C3_SENTINEL = re.compile(r"\.map\(title\)")

# 拼接标记字符串的证据（'<div' / "<span" 之类字面量）
MARKUP = re.compile(r"['\"]<[a-zA-Z/!]")

failed = []


def check_cases():
    if not CASES.exists():
        failed.append(f"缺少黄金用例 {CASES}")
        return 0
    if not RUNNER.exists():
        failed.append(f"缺少驱动 {RUNNER}")
        return 0
    proc = subprocess.run(
        ["node", str(RUNNER), str(CASES)],
        capture_output=True, text=True, encoding="utf-8", cwd=str(ROOT),
    )
    if proc.returncode != 0:
        failed.append(f"xss_runner 执行失败：{proc.stderr.strip()[:200]}")
        return 0
    results = json.loads(proc.stdout)
    doc = json.loads(CASES.read_text(encoding="utf-8"))
    by_id = {c["id"]: c for c in doc["cases"]}
    for r in results:
        c = by_id[r["id"]]
        out = r["safeRich"]
        low = out.lower()
        for bad in c.get("must_not_contain", []):
            if bad.lower() in low:
                failed.append(f"{r['id']} {r['name']}：safeRich 输出仍含 {bad!r} → {out!r}")
        for good in c.get("must_contain", []):
            if good not in out:
                failed.append(f"{r['id']} {r['name']}：safeRich 输出缺少 {good!r} → {out!r}")
        # 协议级：显式声明的用例必须被 sanitizeUrl 拦下
        bad_proto = c.get("url_must_not_start_with")
        if bad_proto and r["url"].lower().startswith(bad_proto.lower()):
            failed.append(f"{r['id']} {r['name']}：sanitizeUrl 未拦截 {bad_proto} → {r['url']!r}")
    return len(results)


JS_KEYWORDS = {
    "if", "for", "while", "function", "return", "var", "let", "const", "new",
    "String", "Number", "Math", "Object", "Array", "JSON", "Date", "true",
    "false", "null", "undefined", "document", "window", "this", "type", "of",
    "in", "do", "else", "try", "catch", "throw", "typeof", "instanceof", "class",
}


def js_identifiers(expr):
    return {m for m in re.findall(r"[A-Za-z_$][\w$]*", expr) if m not in JS_KEYWORDS}


def assignment_block(lines, start_idx, ident):
    """从 start_idx 行起，截取 `ident = …` 这条语句（按括号深度与分号结束）。"""
    depth = 0
    buf = []
    for j in range(start_idx, min(start_idx + 60, len(lines))):
        ln = lines[j]
        buf.append((j + 1, ln))
        depth += ln.count("(") + ln.count("[") + ln.count("{")
        depth -= ln.count(")") + ln.count("]") + ln.count("}")
        if depth <= 0 and ln.rstrip().endswith((";", "}", ",")):
            break
    return buf


def check_sources():
    """两层扫描：先看行内直插（单语句），再做变量赋值回溯（跨行构造再插入）。"""
    hits = 0
    for f in SCAN_TARGETS:
        if not f.exists():
            continue
        src = f.read_text(encoding="utf-8")
        lines = src.split("\n")
        rel = f.relative_to(ROOT).as_posix()

        # 变量 → 赋值语句行号区间
        assigns = {}
        for i, ln in enumerate(lines):
            m = re.search(r"(?:var|let|const)?\s*([A-Za-z_$][\w$]*)\s*=\s*", ln)
            if m and not ln.strip().startswith("//"):
                assigns.setdefault(m.group(1), []).append(i)

        reported = set()
        for i, ln in enumerate(lines, 1):
            if C3_SENTINEL.search(ln):
                failed.append(f"{rel} L{i}: C3 回归哨兵命中（未转义的 .map(title)）")
                hits += 1
                continue
            m = re.search(r"\.(innerHTML|insertAdjacentHTML)\s*(\+?=|\()([^\n]*)", ln)
            if not m:
                continue
            rhs = m.group(3)
            if GUARD.search(ln):
                continue
            # 行内：RHS 直接出现没转义的动态内容
            if SINK.search(rhs):
                failed.append(f"{rel} L{i}: innerHTML 直插疑似未转义的动态内容 → {ln.strip()[:160]}")
                hits += 1
                continue
            # 回溯：RHS 引用的变量，看它邻近的赋值语句是不是在拼标记字符串时
            # 混进了没转义的动态内容。三个条件都要满足，避免跨作用域跟到同名变量
            # （i/b/n/data 这种通用名一跟全文件就是一堆假红）：
            #   a) 赋值点在该 innerHTML 行上方 WINDOW 行内（同一个局部作用域）
            #   b) 赋值块确实在拼标记（出现 '<tag' 字面量）
            #   c) 块里出现承载模型/用户内容的属性，且本行没有转义出口
            WINDOW = 25
            for ident in js_identifiers(rhs):
                for st in assigns.get(ident, []):
                    if not (i - 1 - WINDOW) <= st < (i - 1):
                        continue
                    block = assignment_block(lines, st, ident)
                    if not any(MARKUP.search(bl) for _l, bl in block):
                        continue
                    for (lno, bl) in block:
                        if not SINK.search(bl) or GUARD.search(bl):
                            continue
                        key = (rel, lno)
                        if key in reported:
                            continue
                        reported.add(key)
                        failed.append(
                            f"{rel} L{lno}: 变量 {ident} 的标记拼接未转义动态内容（经 L{i} 的 innerHTML 插入）→ {bl.strip()[:150]}"
                        )
                        hits += 1
    return hits


def main():
    n_cases = check_cases()
    n_hits = check_sources()
    if failed:
        print("[XSS-DRIFT]")
        for m in failed:
            print("  - " + m)
        print(f"FAILED: xss 门禁未收口（{len(failed)} 项）")
        sys.exit(1)
    print(f"ALL GREEN · xss-cases {n_cases} 例全通过，直插点哨兵 {len(SCAN_TARGETS)} 文件无未转义注入")


if __name__ == "__main__":
    main()
