# -*- coding: utf-8 -*-
"""模型输出守卫门禁（威胁模型 T13：提示词注入不得执行越权意图）。

背景：模型返回的文本只作展示、从不被当指令执行——这个不变量是安全的前提。
但返回内容本身可能携带注入形态（伪造系统指令 / 覆写规则 / 角色伪装 / 模板标记泄漏），
误导用户或伪装成系统消息。原有 sanitizeOutput 只过滤敏感词，不拦注入。

三条断言：
  ① 输出守卫存在且真的拦注入（sanitizeOutput 调用 hasInjection，不只是写了注释）
  ② 注入模式覆盖关键形态（伪造系统指令 / 覆写规则 / 角色伪装 / 模板标记泄漏）
  ③ 架构不变量：模型返回不回喂路由执行（routeWithML 的入参不得来自 res.text）
  ④ Web 单体版（index.html）的 __AP_MIMO__.complete 出口也设了卡——
     它是独立实现，不加载 shared/integrations/，只改 p2 会漏掉 Web 端

用法：python scripts/verify_output_guard.py      退出码 0=全绿 1=有缺口
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P2 = ROOT / "shared" / "integrations" / "p2-ai-integration.js"
problems = []


def fail(msg):
    problems.append(msg)


def main():
    if not P2.exists():
        print("FAILED：缺 shared/integrations/p2-ai-integration.js")
        return 1
    text = P2.read_text(encoding="utf-8", errors="replace")

    # ① 输出守卫真的拦注入
    m = re.search(r"function\s+sanitizeOutput\s*\([^)]*\)\s*\{", text)
    if not m:
        fail("未找到 sanitizeOutput")
    else:
        start = m.start()
        nxt = text.find("\n  function ", m.end())
        body = text[start: nxt if nxt > 0 else len(text)]
        if "hasInjection" not in body:
            fail("sanitizeOutput 未调用 hasInjection（注入形态会直接放行）")
        else:
            print("  OK  输出守卫             sanitizeOutput 调用 hasInjection")

    # ② 注入模式覆盖关键形态
    if "INJECT_PATTERNS" not in text:
        fail("未找到 INJECT_PATTERNS 注入模式表")
    else:
        # 检测的是「源码里有没有写这个模式」，不是「运行时能不能匹配」——
        # 所以搜字面量（含正则转义形态），别用运行时正则去匹配正则源码
        required = [
            ("伪造系统指令", ("system\\s*prompt", "系统提示", "系统指令")),
            ("覆写规则", ("ignore", "忽略", "disregard")),
            ("角色伪装", ("you\\s+are\\s+now", "你现在")),
            ("模板标记泄漏", ("im_start", "INST", "SYS")),
        ]
        missing = []
        for label, lits in required:
            if not any(lit in text for lit in lits):
                missing.append(label)
        if missing:
            fail(f"INJECT_PATTERNS 缺少关键形态：{', '.join(missing)}")
        else:
            print("  OK  模式覆盖             伪造指令 / 覆写规则 / 角色伪装 / 模板标记泄漏")

    # ③ 架构不变量：模型返回不回喂路由执行
    #    routeWithML( 的入参必须是用户文本，不得来自 res.text / 返回内容
    call_re = re.compile(r"routeWithML\s*\(([^)]*)\)")
    bad_calls = []
    for cm in call_re.finditer(text):
        arg = cm.group(1)
        if re.search(r"res\.text|response\.text|completion|out\b|generated", arg):
            line = text[: cm.start()].count("\n") + 1
            bad_calls.append(f"{P2.name}:{line} → routeWithML({arg.strip()})")
    if bad_calls:
        fail(f"模型返回被回喂路由执行（架构不变量被破坏）：{bad_calls}")
    else:
        print("  OK  架构不变量           模型返回未回喂 routeWithML（执行路径不受模型输出影响）")

    # ④ Web 单体版出口设卡（独立实现，容易被漏改）
    idx = ROOT / "deploy" / "monolith-web" / "index.html"
    if not idx.exists():
        fail("缺 deploy/monolith-web/index.html")
    else:
        itext = idx.read_text(encoding="utf-8", errors="replace")
        if "__AP_OUTPUT_GUARD__" not in itext:
            fail("Web 端 index.html 未在 __AP_MIMO__.complete 出口调用输出守卫（8 个调用点会漏）")
        elif "window.__AP_OUTPUT_GUARD__(out)" not in itext and "window.__AP_OUTPUT_GUARD__(text)" not in itext:
            fail("index.html 提到 __AP_OUTPUT_GUARD__ 但未在 complete 出口实际调用")
        else:
            print("  OK  Web 端出口设卡       index.html 的 complete 出口调用输出守卫")

    # ⑤ 守卫实现存在（app-glue 提供）
    glue = ROOT / "shared" / "app-glue.js"
    if not glue.exists() or "__AP_OUTPUT_GUARD__ = function" not in glue.read_text(encoding="utf-8", errors="replace"):
        fail("shared/app-glue.js 未定义 __AP_OUTPUT_GUARD__（Web 端守卫无实现）")
    else:
        print("  OK  守卫实现             shared/app-glue.js 定义 __AP_OUTPUT_GUARD__")

    # ⑥ hasInjection 已导出（便于测试与排障）
    if not re.search(r"hasInjection\s*:\s*hasInjection", text):
        fail("hasInjection 未导出（__AP_ROUTER__ 应暴露它供测试）")
    else:
        print("  OK  接口导出             __AP_ROUTER__.hasInjection 可用")

    print()
    if problems:
        print(f"模型输出守卫 FAILED：{len(problems)} 项")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("模型输出守卫 ALL GREEN · 注入拦截在位、模式覆盖、执行路径不受模型输出影响")
    return 0


if __name__ == "__main__":
    sys.exit(main())
