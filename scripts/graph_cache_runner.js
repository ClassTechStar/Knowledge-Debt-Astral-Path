/**
 * graph_cache_runner.js —— shared/graph-cache.js 用例（verify_all 的 graph-cache-golden 步骤直接调用）。
 * 覆盖：标题查表（命中/回退）、先修表（顺序 + tg 引导边排除）、下游 BFS 量（含 tg）、
 * 递归得分（注入 computeScore 的链式传播 + 环检测终止）、跨调用缓存 O(V+E)、失效语义。
 * 退出码：0 = 全过；1 = 有失败。
 */
"use strict";
const path = require("path");
const APGraphCache = require(path.resolve(__dirname, "..", "shared", "graph-cache.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: detail || "" });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String((e && e.message) || e) });
  }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function eq(a, b, msg) { if (a !== b) throw new Error(`${msg}（实际 ${a} ≠ 期望 ${b}）`); }
function near(a, b, msg) { if (Math.abs(a - b) > 1e-9) throw new Error(`${msg}（实际 ${a} ≠ 期望 ${b}）`); }

const NODES = [
  { id: "A", title: "极限" },
  { id: "B", title: "连续" },
  { id: "C", title: "导数" },
  { id: "D", title: "积分" },
];

check("GC-01", "标题查表：命中返回标题，未知 id 回退为 id 本身", () => {
  APGraphCache.invalidate();
  eq(APGraphCache.title("B", [], NODES), "连续", "hit");
  eq(APGraphCache.title("ZZZ", [], NODES), "ZZZ", "miss-fallback");
  return "title";
});

check("GC-02", "先修表：保序 + tg 引导边排除", () => {
  APGraphCache.invalidate();
  const edges = [
    { from: "B", to: "C" },
    { from: "C", to: "D", tg: 1 },  // 引导边：进下游、不进先修
    { from: "A", to: "C" },
    { from: "B", to: "C" },          // 重复边：与旧实现一致，不去重
  ];
  const pre = APGraphCache.prereqs("C", edges);
  eq(pre.length, 3, "tg-excluded");   // B、A、B：重复边与旧实现一致不去重
  eq(pre[0], "B", "order-0");
  eq(pre[1], "A", "order-1");
  eq(pre[2], "B", "order-2");
  eq(APGraphCache.prereqs("A", edges).length, 0, "no-pre");
  return "prereqs";
});

check("GC-03", "下游 BFS 量：tg 边计入下游；无出边记 0；与旧实现同为逐层计数", () => {
  APGraphCache.invalidate();
  const edges = [
    { from: "A", to: "B" },
    { from: "A", to: "C", tg: 1 },  // 引导边计入下游量
    { from: "B", to: "D" },
  ];
  eq(APGraphCache.downMass("A", edges), 3, "down-A");
  eq(APGraphCache.downMass("D", edges), 0, "leaf");
  eq(APGraphCache.downMass("ZZZ", edges), 0, "unknown");
  return "downmass";
});

check("GC-04", "递归得分：computeScore 注入的链式传播；环检测终止", () => {
  APGraphCache.invalidate();
  const edges = [{ from: "A", to: "B" }, { from: "B", to: "C" }];
  const mastery = { A: { n: 4, s: 3, c: 3, age: 0, st: 1 } };
  // 简化公式：有信号节点 0.8，否则 0.2；有先修时与先修均值折半——确定性可对拍
  const cs = (m, pre) => {
    const base = m.s > 0 ? 0.8 : 0.2;
    return pre.length ? (base + pre.reduce((x, y) => x + y, 0) / pre.length) / 2 : base;
  };
  near(APGraphCache.scoreOf("A", edges, NODES, mastery, cs), 0.8, "A");
  near(APGraphCache.scoreOf("B", edges, NODES, mastery, cs), 0.5, "B");
  near(APGraphCache.scoreOf("C", edges, NODES, mastery, cs), 0.35, "C");
  // 环：A↔B 互相先修——必须终止且落在 [0,1]
  APGraphCache.invalidate();
  const cyc = [{ from: "A", to: "B" }, { from: "B", to: "A" }];
  const v = APGraphCache.scoreOf("A", cyc, NODES, mastery, cs);
  assert(v >= 0 && v <= 1, "cycle-in-range");
  return "score";
});

check("GC-05", "跨调用缓存：5 节点逐个查询，公式只算 5 次（O(V+E) 证明）", () => {
  APGraphCache.invalidate();
  const edges = [{ from: "A", to: "B" }, { from: "B", to: "C" }, { from: "A", to: "D" }, { from: "D", to: "E" }];
  const nodes = NODES.concat([{ id: "E", title: "级数" }]);
  let calls = 0;
  const cs = (m, pre) => { calls++; return 0.5; };
  ["A", "B", "C", "D", "E"].forEach((id) => APGraphCache.scoreOf(id, edges, nodes, {}, cs));
  eq(calls, 5, "compute-once");
  return "o(v+e)";
});

check("GC-06", "失效语义：invalidate 后按新边集重算，不残留旧邻接", () => {
  APGraphCache.invalidate();
  const e1 = [{ from: "A", to: "B" }, { from: "B", to: "C" }];
  eq(APGraphCache.downMass("A", e1), 2, "before");
  const e2 = [{ from: "A", to: "B" }]; // 删掉 B→C
  APGraphCache.invalidate();
  eq(APGraphCache.downMass("A", e2), 1, "after");
  return "invalidate";
});

check("GC-07", "downMass 先行不污染标题表（邻接与标题分离缓存）", () => {
  APGraphCache.invalidate();
  const edges = [{ from: "A", to: "B" }];
  eq(APGraphCache.downMass("A", edges), 1, "down-first");
  eq(APGraphCache.title("A", edges, NODES), "极限", "title-after-down");
  return "split-cache";
});

check("GC-08", "scanDebts：错答计数进 freq，imp>0 过滤并按影响度降序", () => {
  APGraphCache.invalidate();
  const edges = [{ from: "A", to: "B", w: 1 }, { from: "B", to: "C", w: 1 }];
  const mastery = { A: { n: 4, s: 3, c: 3, age: 0, st: 1 }, B: { n: 4, s: 3, c: 3, age: 0, st: 1 }, C: { n: 4, s: 3, c: 3, age: 0, st: 1 } };
  const logs = [{ kp: "B", ok: false, ts: 1 }, { kp: "B", ok: false, ts: 2 }, { kp: "C", ok: true, ts: 3 }];
  const scoreV2 = () => 0.8;
  const impactV2 = (sf, st, w, tg, fr) => 0.2 + fr * 0.1;
  const K = { hit: 0.5 };
  const list = APGraphCache.scanDebts(edges, NODES, mastery, logs, scoreV2, impactV2, K);
  eq(list.length, 2, "all-positive");
  eq(list[0].from, "A", "top-from");
  eq(list[0].freq, 2, "wrong-count");
  eq(list[0].imp, 0.4, "top-imp");
  eq(list[0].toName, "连续", "title-injected");
  eq(list[1].imp, 0.2, "second-imp");
  return "scan";
});

check("GC-09", "scanDebts：imp=0 的边被过滤、status 按 K.hit 判定", () => {
  APGraphCache.invalidate();
  const edges = [{ from: "A", to: "B", w: 1 }];
  const impactV2 = () => 0;
  const K = { hit: 0.5 };
  eq(APGraphCache.scanDebts(edges, NODES, {}, [], () => 0.5, impactV2, K).length, 0, "filtered-zero");
  const list2 = APGraphCache.scanDebts(edges, NODES, {}, [], () => 0.5, () => 0.6, K);
  eq(list2.length, 1, "kept");
  eq(list2[0].status, "open", "open-status");
  const list3 = APGraphCache.scanDebts(edges, NODES, {}, [], () => 0.5, () => 0.3, K);
  eq(list3[0].status, "cleared", "cleared-status");
  return "filter-status";
});

let fail = 0;
for (const r of results) {
  console.log(`${r.ok ? "PASS" : "FAIL"} ${r.id} ${r.name}${r.ok ? " · " + r.detail : " · " + r.detail}`);
  if (!r.ok) fail++;
}
console.log(`graph_cache_runner: ${results.length - fail}/${results.length} 通过`);
process.exit(fail ? 1 : 0);
