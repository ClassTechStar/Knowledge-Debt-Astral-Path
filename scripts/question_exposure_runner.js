/**
 * question_exposure_runner.js —— shared/question-exposure.js 用例（verify_all / CI 调用）
 * 覆盖：降温权重单调性、冷却防重复、全冷却兜底、曝光少者优先、recent 截断、
 *       形状归一、修剪上限、空候选边界。随机源全部注入定序序列，结果可复现。
 */
"use strict";
const path = require("path");
const exp = require(path.resolve(__dirname, "..", "shared", "question-exposure.js"));

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
/** 定序随机源：依次吐出给定序列，耗尽后恒 0（落在第一段权重内） */
function seq(values) {
  let i = 0;
  return () => (i < values.length ? values[i++] : 0);
}

check("QX-01", "降温权重随曝光单调递减且永不归零", () => {
  let prev = exp.weightOf(0);
  eq(prev, 1, "零曝光权重");
  for (let n = 1; n <= 20; n++) {
    const w = exp.weightOf(n);
    if (!(w < prev)) throw new Error(`第 ${n} 次曝光权重未下降：${prev} → ${w}`);
    if (!(w > 0)) throw new Error(`第 ${n} 次曝光权重归零`);
    prev = w;
  }
  return "weightOf(0)=1 单调递减";
});

check("QX-02", "冷却生效：相邻两次绝不重复（3 候选必进兜底也不连发）", () => {
  const state = {};
  const ids = ["q1", "q2", "q3"];
  const out = [];
  for (let i = 0; i < 6; i++) out.push(exp.pick(ids, state, seq([0.99]))); // 定序：每次都想选末位
  for (let i = 1; i < out.length; i++) {
    if (out[i] === out[i - 1]) throw new Error(`相邻重复：${out.join(",")}`);
  }
  return "6 连选无相邻重复：" + out.join(",");
});

check("QX-03", "候选多于冷却窗口时窗口内零重复", () => {
  const state = {};
  const ids = [];
  for (let i = 0; i < 10; i++) ids.push("q" + i);
  const out = [];
  for (let i = 0; i < 6; i++) out.push(exp.pick(ids, state, seq([0.5])));
  eq(new Set(out).size, 6, "6 次选取的去重数");
  return "10 候选取 6 次全部不同";
});

check("QX-04", "全冷却兜底：不放空，放开窗口照常出题", () => {
  const state = {};
  const ids = ["a", "b"];
  exp.record(state, "a");
  exp.record(state, "b"); // recent=[a,b]，两个候选全在冷却
  const q = exp.pick(ids, state, seq([0.0]));
  if (!q) throw new Error("兜底返回了空");
  return "全冷却仍出题：" + q;
});

check("QX-05", "降温真实生效：同样抽 300 次，曝光多的题显著少出", () => {
  // 均匀扫过 [0,1) 的定序随机：统计分布应反映权重（cold 权重是 hot 的 2 倍）
  let cold = 0, hot = 0;
  for (let i = 0; i < 300; i++) {
    const st = { exposure: { shown: { hot: 3, cold: 1 }, recent: [] } };
    const q = exp.pick(["hot", "cold"], st, seq([(i + 0.5) / 300]));
    if (q === "cold") cold++; else hot++;
  }
  if (!(cold > hot * 1.4)) throw new Error(`降温失效：cold=${cold} hot=${hot}`);
  return `cold=${cold} > hot=${hot}`;
});

check("QX-06", "recent 环形截断不超过上限", () => {
  const state = {};
  for (let i = 0; i < 20; i++) exp.record(state, "q" + i);
  const e = exp.ensure(state);
  if (e.recent.length > exp.RECENT_CAP) throw new Error(`recent 超上限：${e.recent.length}`);
  eq(e.recent[e.recent.length - 1], "q19", "recent 末位是最新曝光");
  eq(e.shown.q0, 1, "计数保留");
  return `recent=${e.recent.length}/${exp.RECENT_CAP}`;
});

check("QX-07", "形状归一：历史脏数据升级为 {shown,recent}", () => {
  const s1 = {};
  exp.ensure(s1);
  eq(Object.keys(s1.exposure).sort(), ["recent", "shown"], "空状态新建");
  const s2 = { exposure: { legacy: true } };
  exp.ensure(s2);
  eq(s2.exposure.shown, {}, "脏对象被替换");
  exp.ensure(null); // 不抛错
  return "归一通过";
});

check("QX-08", "修剪：条目超上限先丢曝光最少者", () => {
  const e = { shown: {}, recent: [] };
  for (let i = 0; i < exp.PRUNE_CAP + 50; i++) e.shown["q" + i] = i < 50 ? 1 : 100 + i;
  exp.prune(e);
  const n = Object.keys(e.shown).length;
  if (n > exp.PRUNE_CAP) throw new Error(`修剪后仍有 ${n} 条`);
  if (e.shown.q0 !== undefined) throw new Error("最低频条目未被丢弃");
  if (e.shown["q" + (exp.PRUNE_CAP + 49)] === undefined) throw new Error("高频条目被误删");
  return `修剪到 ${n} 条`;
});

check("QX-09", "空候选返回 null，单候选恒返回它", () => {
  eq(exp.pick([], {}, seq([0.5])), null, "空候选");
  const state = {};
  eq(exp.pick(["only"], state, seq([0.9])), "only", "单候选");
  eq(exp.pick(["only"], state, seq([0.9])), "only", "冷却兜底仍返回");
  return "边界通过";
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
