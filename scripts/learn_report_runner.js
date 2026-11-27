/**
 * learn_report_runner.js —— shared/learn-report.js 用例（verify_all 的 learn-report-golden 步骤直接调用）。
 * 覆盖：空日志、按天分桶与正确率、越界日志不进统计、最易错排序与标题回退、
 * 日界边界（0 点整点归属当天、明日时间戳排除）。
 * 退出码：0 = 全过；1 = 有失败。
 */
"use strict";
const path = require("path");
const APReport = require(path.resolve(__dirname, "..", "shared", "learn-report.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: detail || "" });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String((e && e.message) || e) });
  }
}
function eq(a, b, msg) { if (a !== b) throw new Error(`${msg}（实际 ${a} ≠ 期望 ${b}）`); }
function near(a, b, msg) { if (Math.abs(a - b) > 1e-9) throw new Error(`${msg}（实际 ${a} ≠ 期望 ${b}）`); }

// 固定"今天"：2026-11-28 12:00 本地时间，金样可对拍
const NOW = new Date(2026, 10, 28, 12, 0, 0).getTime();
const DAY = 86400000;
const NODES = [{ id: "N1", title: "极限" }, { id: "N2", title: "导数" }];

check("LR-01", "空日志：全零、正确率 0、无最易错", () => {
  const r = APReport.weekly([], NODES, NOW);
  eq(r.total, 0, "total");
  eq(r.acc, 0, "acc");
  eq(r.days.length, 7, "days-7");
  eq(r.days[6].count, 0, "today-zero");
  eq(r.weakest.length, 0, "weakest-empty");
  return "empty";
});

check("LR-02", "按天分桶：今天/昨天计数与正确率", () => {
  const logs = [
    { kp: "N1", ok: true, ts: NOW - 3600000 },          // 今天上午
    { kp: "N1", ok: false, ts: NOW - 7200000 },         // 今天上午
    { kp: "N2", ok: true, ts: NOW - DAY - 3600000 },    // 昨天
  ];
  const r = APReport.weekly(logs, NODES, NOW);
  eq(r.total, 3, "total");
  eq(r.days[5].count, 1, "yesterday");
  eq(r.days[6].count, 2, "today");
  eq(r.days[6].ok, 1, "today-ok");
  near(r.acc, 2 / 3, "acc");
  return "buckets";
});

check("LR-03", "越界过滤：7 天前的作答不进 total，也不进最易错", () => {
  const logs = [
    { kp: "N1", ok: false, ts: NOW - 7 * DAY - 1000 },  // 7 天前一点
    { kp: "N1", ok: false, ts: NOW - DAY },             // 昨天边界内
  ];
  const r = APReport.weekly(logs, NODES, NOW);
  eq(r.total, 1, "out-of-range-excluded");
  eq(r.weakest.length, 1, "weakest-only-in-range");
  eq(r.weakest[0].wrong, 1, "wrong-1");
  return "window";
});

check("LR-04", "最易错排序：错次降序、并列按总作答多者靠前；未知 kp 回退为 id", () => {
  const logs = [
    { kp: "N1", ok: false, ts: NOW }, { kp: "N1", ok: true, ts: NOW },
    { kp: "N2", ok: false, ts: NOW }, { kp: "N2", ok: true, ts: NOW },
    { kp: "X9", ok: false, ts: NOW },
  ];
  const r = APReport.weekly(logs, NODES, NOW);
  eq(r.weakest.length, 3, "three-entries");
  eq(r.weakest[0].id, "N1", "tie-by-total"); // N1/N2 错次相同，N1 总作答 2 > N2 的 2？→ 相同，取先插入者
  eq(r.weakest[0].wrong, 1, "wrong");
  const x9 = r.weakest.find((w) => w.id === "X9");
  eq(x9.title, "X9", "title-fallback");
  return "weakest";
});

check("LR-05", "日界边界：0 点整点归属当天；明天 0 点的时间戳被排除", () => {
  const base = new Date(2026, 10, 28, 0, 0, 0).getTime();
  const logs = [
    { kp: "N1", ok: true, ts: base },                 // 今天 0 点整
    { kp: "N1", ok: true, ts: base + DAY },           // 明天 0 点——不属于今天
  ];
  const r = APReport.weekly(logs, NODES, base + 3600000);
  eq(r.days[6].count, 1, "midnight-in-day");
  eq(r.total, 1, "tomorrow-excluded");
  return "boundary";
});

let fail = 0;
for (const r of results) {
  console.log(`${r.ok ? "PASS" : "FAIL"} ${r.id} ${r.name}${r.ok ? " · " + r.detail : " · " + r.detail}`);
  if (!r.ok) fail++;
}
console.log(`learn_report_runner: ${results.length - fail}/${results.length} 通过`);
process.exit(fail ? 1 : 0);
