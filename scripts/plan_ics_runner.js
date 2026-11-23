/**
 * plan_ics_runner.js —— shared/plan-ics.js 用例（verify_all / CI 调用）
 * 覆盖：日历骨架、项数映射、日期推进、时长、文本转义、行折叠（≤75 字节）、
 *       确定性、脏数据跳过、空计划边界。
 */
"use strict";
const path = require("path");
const ics = require(path.resolve(__dirname, "..", "shared", "plan-ics.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: String(detail == null ? "ok" : detail) });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String((e && e.message) || e) });
  }
}
function must(cond, msg) { if (!cond) throw new Error(msg); }

const ITEMS = [
  { id: "p1", day: 1, kp: "K01", min: 20, label: "巩固「会计要素」", why: "先修：会计对象" },
  { id: "p2", day: 2, kp: "K02", min: 30, label: "练习：会计等式", why: "红边 K01→K02" },
  { id: "p3", day: 14, kp: "K03", min: 15, label: "挑战：借贷记账法", why: "" },
];
const OPTS = { startDate: "2026-11-17", hour: 19, minute: 0, stamp: new Date(Date.UTC(2026, 10, 17, 2, 0, 0)) };

check("ICS-01", "日历骨架与事件数", () => {
  const s = ics.build(ITEMS, OPTS);
  must(s.startsWith("BEGIN:VCALENDAR\r\n"), "缺 VCALENDAR 头");
  must(s.trimEnd().endsWith("END:VCALENDAR"), "缺 VCALENDAR 尾");
  must(s.includes("VERSION:2.0"), "缺 VERSION");
  must(s.includes("PRODID:-//AstralPath"), "缺 PRODID");
  const n = (s.match(/BEGIN:VEVENT/g) || []).length;
  must(n === 3, `事件数 ${n} ≠ 3`);
  must((s.match(/END:VEVENT/g) || []).length === 3, "VEVENT 未成对");
  return "3 个事件";
});

check("ICS-02", "日期推进：day-1 偏移 + 本地浮动时间", () => {
  const s = ics.build(ITEMS, OPTS);
  must(s.includes("DTSTART:20261117T190000"), "D1 应为 11-17 19:00");
  must(s.includes("DTSTART:20261118T190000"), "D2 应为 11-18 19:00");
  must(s.includes("DTSTART:20261130T190000"), "D14 应为 11-30 19:00");
  must(!/DTSTART:\d{8}T\d{6}Z/.test(s), "浮动时间不应带 Z");
  return "D1/D2/D14 正确";
});

check("ICS-03", "时长与 UID 稳定", () => {
  const s = ics.build(ITEMS, OPTS);
  must(s.includes("DURATION:PT20M"), "缺 20 分钟");
  must(s.includes("DURATION:PT30M"), "缺 30 分钟");
  must(s.includes("UID:astralpath-p1@astralpath.local"), "UID 未按 id 生成");
  return "PT20M / PT30M / UID 正确";
});

check("ICS-04", "文本转义：分号、逗号、反斜杠、换行", () => {
  const s = ics.build([
    { id: "x", day: 1, kp: "K;1", min: 10, label: "A, B; C\\D", why: "第一行\n第二行" },
  ], OPTS);
  must(s.includes("SUMMARY:D1 · A\\, B\\; C\\\\D"), "SUMMARY 未正确转义：" + s.split("\r\n").filter(l => l.startsWith("SUMMARY"))[0]);
  must(s.includes("第一行\\n第二行"), "换行未转义为 \\n");
  return "转义通过";
});

check("ICS-05", "行折叠：每个物理行 ≤75 字节", () => {
  const long = "很长的标题".repeat(40);
  const s = ics.build([{ id: "l", day: 1, kp: "K1", min: 10, label: long, why: long }], OPTS);
  const bad = s.split("\r\n").filter((l) => Buffer.byteLength(l, "utf8") > 75);
  must(bad.length === 0, `有 ${bad.length} 行超 75 字节，例如 ${bad[0]}`);
  const cont = s.split("\r\n").filter((l) => l.startsWith(" "));
  must(cont.length > 0, "长行未产生续行");
  return `${cont.length} 个续行，全部 ≤75 字节`;
});

check("ICS-06", "确定性：同输入同字节输出", () => {
  const a = ics.build(ITEMS, OPTS);
  const b = ics.build(ITEMS, OPTS);
  must(a === b, "两次输出不一致");
  const c = ics.build(ITEMS, Object.assign({}, OPTS, { startDate: "2026-11-18" }));
  must(a !== c, "换起始日应改变 DTSTART");
  return "可复现";
});

check("ICS-07", "脏数据跳过 + 空计划边界", () => {
  const s = ics.build([
    null, {}, { day: 0, kp: "K" }, { day: "x" }, { day: 3, kp: "K9", min: 0 },
  ], OPTS);
  must((s.match(/BEGIN:VEVENT/g) || []).length === 1, "只应保留唯一合法项（min 缺失按 20 兜底）");
  must(s.includes("DURATION:PT20M"), "缺失时长应兜底 20 分钟");

  const empty = ics.build([], OPTS);
  must(empty.startsWith("BEGIN:VCALENDAR"), "空计划也应是合法日历");
  must(!empty.includes("BEGIN:VEVENT"), "空计划不应有事件");
  return "跳过 4 条脏数据，空计划合法";
});

check("ICS-08", "CRLF 行尾", () => {
  const s = ics.build(ITEMS, OPTS);
  const lfOnly = s.split("\r\n").join("").includes("\n");
  must(!lfOnly, "存在裸 LF 行尾");
  return "全部 CRLF";
});

check("ICS-09", "download 胶水：注入假 DOM 也能产出 Blob 与文件名", () => {
  const created = [];
  const revoked = [];
  const fakeDoc = {
    body: { appendChild: () => {} },
    createElement: () => {
      const a = { href: "", download: "", click: () => created.push(a.download), remove: () => {} };
      return a;
    },
  };
  const fakeURL = {
    createObjectURL: () => "blob:fake",
    revokeObjectURL: (u) => revoked.push(u),
  };
  class FakeBlob { constructor(parts, opts) { this.parts = parts; this.opts = opts; } }

  const r = ics.download(ITEMS, { startDate: "2026-11-17" }, { Blob: FakeBlob, URL: fakeURL, document: fakeDoc, Date });
  must(r.ok === true, "应报告成功");
  must(r.count === 3, "应导出 3 项");
  must(r.filename === "astralpath-plan-2026-11-17.ics", "文件名不对：" + r.filename);
  must(created[0] === r.filename, "未触发下载");
  const empty = ics.download([], {}, { Blob: FakeBlob, URL: fakeURL, document: fakeDoc, Date });
  must(empty.ok === false && /先生成/.test(empty.message), "空计划应给出提示");
  const noDom = ics.download(ITEMS, {}, { Blob: null, URL: null, document: null, Date });
  must(noDom.ok === false, "无 DOM 环境应安全失败");
  return "假 DOM 导出通过，空/无 DOM 安全失败";
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
