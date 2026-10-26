/**
 * plan_runtime_runner.js —— shared/plan-runtime.js 用例（verify_all 的 plan-runtime-golden 步骤直接调用）
 * 断言快照状态机：ahead/ontrack/behind/paused、连续未完成、streak、临时调整与内置自动化。
 * 退出码：0 = 全过；1 = 有失败。
 */
"use strict";
const path = require("path");
const APRuntime = require(path.resolve(__dirname, "..", "shared", "plan-runtime.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: detail || "" });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String(e && e.message || e) });
  }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function eq(a, b, msg) { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}（实际 ${JSON.stringify(a)} ≠ 期望 ${JSON.stringify(b)}）`); }

function item(day, kp, st, min) { return { id: kp, day, kp, layer: "core", st: st || "todo", min: min || 10 }; }

check("PR-01", "空计划：ontrack、无提醒", () => {
  const s = APRuntime.computeSnapshot(null, { day: 5 });
  eq(s.status, "ontrack", "状态");
  eq(s.totalItems, 0, "总数");
  return "ontrack";
});

check("PR-02", "今日全部完成且无过期 → ahead", () => {
  const plan = [item(5, "A", "done"), item(5, "B", "done")];
  const s = APRuntime.computeSnapshot(plan, { day: 5 });
  eq(s.status, "ahead", "状态");
  eq(s.todayDone, 2, "今日完成");
  return "ahead";
});

check("PR-03", "有过期未完成 → behind，且能数出连续未完成天数", () => {
  const plan = [item(1, "A", "todo"), item(2, "B", "todo"), item(3, "C", "todo"), item(4, "D", "done"), item(4, "E", "todo")];
  const s = APRuntime.computeSnapshot(plan, { day: 4 });
  eq(s.status, "behind", "状态");
  eq(s.overdueCount, 3, "过期数");
  eq(s.consecutiveIncomplete, 3, "D1–D3 全没做");
  return `behind, overdue=${s.overdueCount}, ci=${s.consecutiveIncomplete}`;
});

check("PR-04", "昨天完成了、前天没完成 → streak=1，连续未完成=0", () => {
  const plan = [item(2, "A", "todo"), item(3, "B", "done"), item(4, "C", "todo")];
  const s = APRuntime.computeSnapshot(plan, { day: 4 });
  eq(s.streak, 1, "streak");
  eq(s.consecutiveIncomplete, 0, "昨天做了就不计连续未完成");
  return `streak=1`;
});

check("PR-05", "请假暂停：覆盖期内 paused，且打断连续未完成计数", () => {
  const plan = [item(1, "A", "todo"), item(2, "B", "todo"), item(4, "D", "todo")];
  const ov = [{ id: "o1", type: "pause", days: 3, startDay: 2 }];
  const s = APRuntime.computeSnapshot(plan, { day: 4, overrides: ov });
  eq(s.status, "paused", "暂停优先于 behind（今日 D4 在覆盖期内）");
  eq(s.consecutiveIncomplete, 0, "D2–D3 在暂停期，不计数");
  const ovShort = [{ id: "o1b", type: "pause", days: 2, startDay: 2 }];
  const s1 = APRuntime.computeSnapshot(plan, { day: 4, overrides: ovShort });
  eq(s1.status, "behind", "覆盖期只盖 D2–D3 时，D1 没做仍算 behind");
  eq(s1.consecutiveIncomplete, 0, "D2–D3 暂停不计入连续未完成");
  const s2 = APRuntime.computeSnapshot([item(4, "D", "todo")], { day: 4, overrides: ov });
  eq(s2.status, "paused", "今日在覆盖期内 → paused");
  return "paused & excused";
});

check("PR-06", "本周减半：未完成任务时长按 0.5 折算", () => {
  const plan = [item(5, "A", "todo", 20), item(5, "B", "done", 20)];
  const ov = [{ id: "o2", type: "relief", days: 7, startDay: 5, ratio: 0.5 }];
  const s = APRuntime.computeSnapshot(plan, { day: 5, overrides: ov });
  eq(s.todayMin, 30, "20×0.5 + 已完成 20");
  return "todayMin=30";
});

check("PR-07", "diffSnapshots 只报告翻转字段", () => {
  const plan = [item(1, "A", "todo")];
  const a = APRuntime.computeSnapshot([], { day: 4 });
  const b = APRuntime.computeSnapshot(plan, { day: 4 });
  const flips = APRuntime.diffSnapshots(a, b);
  const keys = flips.map((f) => f.key).sort();
  eq(keys, ["overdueCount", "status"], "应翻转 status 与 overdueCount");
  return flips.map((f) => f.key).join(",");
});

check("PR-08", "自动化：连续 3 天未完成 → 减负建议，7 天冷却", () => {
  const plan = [item(1, "A"), item(2, "B"), item(3, "C"), item(4, "D")];
  const s = APRuntime.computeSnapshot(plan, { day: 4 });
  const now = 1_700_000_000_000;
  const m1 = APRuntime.evaluateAutomations(s, {}, now);
  assert(m1.some((m) => m.key === "relief" && m.level === "warn"), "应触发减负建议");
  const m2 = APRuntime.evaluateAutomations(s, { relief: now }, now + 1000);
  assert(!m2.some((m) => m.key === "relief"), "冷却期内不应重复提醒");
  const m3 = APRuntime.evaluateAutomations(s, { relief: now - 8 * 24 * 3600 * 1000 }, now);
  assert(m3.some((m) => m.key === "relief"), "冷却过后应再次提醒");
  return "relief + cooldown ok";
});

check("PR-09", "自动化：streak 满 7 里程碑提醒一次，同里程碑不重复", () => {
  const items = [];
  for (let d = 1; d <= 7; d++) items.push(item(d, "K" + d, "done"));
  const plan = items.concat([item(8, "X", "todo")]);
  const s = APRuntime.computeSnapshot(plan, { day: 8 });
  eq(s.streak, 7, "streak");
  const now = 1_700_000_000_000;
  const m1 = APRuntime.evaluateAutomations(s, {}, now);
  assert(m1.some((m) => m.key === "streak7" && m.level === "info"), "应触发里程碑");
  const m2 = APRuntime.evaluateAutomations(s, { streakMilestone: 7 }, now);
  assert(!m2.some((m) => m.key === "streak7"), "同一里程碑不应重复");
  return "streak7 once";
});

check("PR-10", "自动化：暂停期内不弹减负建议", () => {
  const plan = [item(1, "A"), item(2, "B"), item(3, "C"), item(4, "D")];
  const ov = [{ id: "p", type: "pause", days: 3, startDay: 4 }];
  const s = APRuntime.computeSnapshot(plan, { day: 4, overrides: ov });
  const m = APRuntime.evaluateAutomations(s, {}, 1_700_000_000_000);
  assert(!m.some((x) => x.key === "relief"), "暂停中不应催");
  return "quiet during pause";
});

const passed = results.filter((r) => r.ok).length;
process.stdout.write(JSON.stringify({ passed, failed: results.length - passed, results }, null, 2));
if (passed !== results.length) process.exit(1);
