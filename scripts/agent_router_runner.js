/**
 * agent_router_runner.js —— shared/agent-router.js 用例（verify_all / CI 调用）
 * 覆盖：危机拦截、负例占比、授权/撤销前置、章节阅读、图谱关系特判、
 *       锚点打分、模糊锚点二次确认、敏感词脱敏。
 */
"use strict";
const path = require("path");
const agent = require(path.resolve(__dirname, "..", "shared", "agent-router.js"));
const core = require(path.resolve(__dirname, "..", "shared", "core.js"));
const kg = require(path.resolve(__dirname, "..", "shared", "kg-text.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: String(detail == null ? "ok" : detail) });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String((e && e.message) || e) });
  }
}
function eq(a, b, what) {
  const sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error(`${what}: 期望 ${sb}，实际 ${sa}`);
}

const NODES = [
  { id: "C01", title: "会计基础", kind: "chapter" },
  { id: "C02", title: "借贷记账法", kind: "chapter" },
  { id: "T01", title: "会计等式", kind: "term" },
];
const CHAPTERS = [{ id: "C01", title: "会计基础" }, { id: "C02", title: "借贷记账法" }];
function route(t, extra) {
  return agent.route(t, Object.assign({
    nodes: NODES, chapters: CHAPTERS,
    intents: core.INTENTS, crisis: core.CRISIS, negative: core.NEGATIVE, banned: core.BANNED,
    kgCn2Num: kg.kgCn2Num,
  }, extra || {}));
}

check("AR-01", "危机词优先转人工", () => {
  const r = route("我不想活了");
  eq(r.id, "crisis.handoff", "意图");
  eq(r.decision, "crisis.handoff", "决策");
  return r.trace;
});

check("AR-02", "负例占比：纯客套兜底，带任务不吞", () => {
  eq(route("好的").id, "meta.help", "纯客套");
  const r = route("好的，帮我生成计划");
  eq(r.id, "plan.create", "带任务");
  return "meta.help / plan.create";
});

check("AR-03", "授权前置：撤销优先于授予", () => {
  eq(route("撤销授权").id, "consent.revoke", "撤销");
  eq(route("同意授权").id, "consent.grant", "授予");
  return "revoke / grant";
});

check("AR-04", "章节阅读优先于通用搜索", () => {
  const r = route("第三章讲了什么");
  eq(r.id, "chapter.read", "意图");
  return r.trace;
});

check("AR-05", "图谱关系：第一章和第二章有什么关系", () => {
  const r = route("第一章和第二章有什么关系");
  eq(r.id, "graph.path", "意图");
  return r.trace;
});

check("AR-06", "无图谱依据时不误判关系查询", () => {
  const r = route("我和你说个事", { nodes: [], chapters: [] });
  if (r.id === "graph.path") throw new Error("误判 graph.path");
  return r.id;
});

check("AR-07", "锚点打分：14 天复习计划", () => {
  const r = route("帮我做一个14天复习计划");
  eq(r.id, "plan.create", "意图");
  if (r.score < 0.5) throw new Error("分数过低：" + r.score);
  return r.trace;
});

check("AR-08", "模糊锚点二次确认", () => {
  const s = agent.fuzzyAnchorConfirm("plan.create", "复习计划", core.INTENTS);
  if (!s || s.indexOf("复习计划") < 0) throw new Error("未确认：" + s);
  return s;
});

check("AR-09", "敏感词脱敏", () => {
  const s = agent.sanitize("我的银行卡密码是 123456", core.BANNED);
  if (s.indexOf("银行卡密码") >= 0) throw new Error("未脱敏：" + s);
  return s.slice(0, 24) + "…";
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
