/**
 * plan_scheduler_runner.js —— shared/plan-scheduler.js 用例（verify_all / CI 调用）
 * 覆盖：K1–K5 合约、逐日容量调度、先修感知重排、超预算减压、移动下限。
 */
"use strict";
const path = require("path");
const plan = require(path.resolve(__dirname, "..", "shared", "plan-scheduler.js"));

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
  { id: "A", title: "会计基础", kind: "chapter" },
  { id: "B", title: "借贷记账法", kind: "chapter" },
  { id: "C", title: "财务报表", kind: "chapter" },
];
const EDGES = [{ from: "A", to: "B", tg: false, w: 0.9 }, { from: "B", to: "C", tg: false, w: 0.8 }];
const TITLES = { A: "会计基础", B: "借贷记账法", C: "财务报表" };
const titleOf = (id) => TITLES[id] || id;
const label = (d, kind, r) => (kind === "core" ? "巩固：" : "练习：") + (kind === "core" ? d.fromName : d.toName) + "·" + r;
const why = (d, kind, r, min) => "先垫「" + d.fromName + "」，再练「" + d.toName + "」（" + min + " 分钟，第 " + (r + 1) + " 轮）";
const ctx = {
  edges: EDGES, nodes: NODES, titleOf,
  courseOf: () => "会计",
  prereqs: (id) => EDGES.filter((e) => e.to === id && !e.tg).map((e) => e.from),
  label, why, spacingOffsets: [0, 2, 6],
};
function debt(from, to, imp) {
  return { from, to, fromName: titleOf(from), toName: titleOf(to), imp: imp || 0.2, sf: 0.4, st: 0.3, freq: 2 };
}
const DS = [debt("A", "B", 0.3), debt("B", "C", 0.2)];

check("PL-01", "goldenScore 公式", () => {
  eq(plan.goldenScore(0.8, 0.2, 4), 80, "分数");
  eq(plan.goldenScore(1.5, -1, 9), 100, "饱和钳制");
  return "80 / 100";
});

check("PL-02", "K1/K3/K4/K2 违规可检出", () => {
  const bad = [
    { day: 1, kp: "A", fromKp: "A", min: 30, why: "" },
    { day: 1, kp: "A", fromKp: "A", min: 30, why: "会计基础" },
    { day: 1, kp: "B", fromKp: "A", min: 10, why: "会计基础" },
  ];
  const v = plan.checkPlanK(bad, 40, {}, ctx);
  const all = v.join(" | ");
  if (!/K1/.test(all)) throw new Error("缺 K1：" + all);
  if (!/K3/.test(all)) throw new Error("缺 K3：" + all);
  if (!/K4/.test(all)) throw new Error("缺 K4：" + all);
  return v.length + " 条违规";
});

check("PL-03", "K2 先修顺序违规可检出", () => {
  const bad = [
    { day: 2, kp: "A", fromKp: "A", min: 10, why: "会计基础" },
    { day: 1, kp: "B", fromKp: "B", min: 10, why: "借贷记账法" },
  ];
  const v = plan.checkPlanK(bad, 40, {}, ctx).join(" | ");
  if (!/K2/.test(v)) throw new Error("缺 K2：" + v);
  return v;
});

check("PL-04", "调度：日预算、先修顺序、K 合约全通过", () => {
  const sch = plan.schedule(DS, 40, { course: "会计" }, ctx);
  if (!sch.items.length) throw new Error("未排入任务");
  const byDay = {};
  sch.items.forEach((p) => { byDay[p.day] = (byDay[p.day] || 0) + p.min; });
  Object.keys(byDay).forEach((d) => {
    if (byDay[d] > 40) throw new Error("D" + d + " 超预算 " + byDay[d]);
  });
  const v = plan.checkPlanK(sch.items, 40, { debts: DS, deferred: sch.deferred }, ctx);
  if (v.length) throw new Error("合约违规：" + v.join(" | "));
  return sch.items.length + " 项 / " + Object.keys(byDay).length + " 天 / 延期 " + sch.deferred.length;
});

check("PL-05", "小预算：超额债边显式延期", () => {
  const many = [debt("A", "B"), debt("B", "C"), debt("A", "C"), debt("C", "A"), debt("B", "A")];
  const sch = plan.schedule(many, 20, {}, ctx);
  const byDay = {};
  sch.items.forEach((p) => { byDay[p.day] = (byDay[p.day] || 0) + p.min; });
  Object.keys(byDay).forEach((d) => {
    if (byDay[d] > 20) throw new Error("D" + d + " 超预算 " + byDay[d]);
  });
  if (!sch.deferred.length) throw new Error("未产生延期说明");
  return sch.items.length + " 项 / 延期 " + sch.deferred.length;
});

check("PL-06", "超预算减压：压缩/顺延后不超预算", () => {
  const items = [
    { day: 1, kp: "A", min: 30 },
    { day: 1, kp: "B", min: 30 },
    { day: 2, kp: "C", min: 10 },
  ];
  const repairs = [];
  plan.reliefDays(items, 40, repairs);
  const byDay = {};
  items.forEach((p) => { byDay[p.day] = (byDay[p.day] || 0) + p.min; });
  Object.keys(byDay).forEach((d) => {
    if (byDay[d] > 40) throw new Error("D" + d + " 仍超预算 " + byDay[d]);
  });
  if (!repairs.length) throw new Error("无修复记录");
  return repairs.join("；");
});

check("PL-07", "移动下限：复习间隔不足时拒绝", () => {
  const items = [{ day: 7, kp: "A", min: 10, rd: 2 }];
  const bins = { 7: { min: 10, n: 1, kps: { A: 1 } } };
  eq(plan.moveNode(items, bins, 40, "A", -1, false, [0, 2, 6]), false, "rd=2 下限 7");
  const items2 = [{ day: 3, kp: "A", min: 10, rd: 0 }];
  const bins2 = { 3: { min: 10, n: 1, kps: { A: 1 } } };
  eq(plan.moveNode(items2, bins2, 40, "A", -1, false, [0, 2, 6]), true, "rd=0 可前移");
  return "拒绝 / 允许";
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
