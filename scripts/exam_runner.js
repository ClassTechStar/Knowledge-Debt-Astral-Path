/**
 * exam_runner.js —— shared/exam.js 黄金用例（供 verify_all / CI 调用）
 * ===========================================================
 * 覆盖：四类题型（选择/填空/判断/解答）、答案批量分发、题号连续、空输入、
 *       单卷上限。输出 JSON：{passed, failed, results:[{id,name,ok,detail}]}
 */
"use strict";
const path = require("path");
const ex = require(path.resolve(__dirname, "..", "shared", "exam.js"));

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

const CHOICE = "一、单项选择题\n1. 下列关于 Cache 的说法正确的是（ ）\nA. 全相联映射冲突多\nB. 直接映射实现简单\nC. 组相联不支持\nD. 以上都不对\n答案：B";
const JUDGE = "二、判断题\n1. 直接映射的冲突率高于全相联映射。（ ）\n答案：错误";
const BLANK = "三、填空题\n1. 组相联映射的每组包含 ___ 个 Cache 行。\n答案：2";
const SOLVE = "四、简答题\n1. 简述 Cache 映射的三种方式。\n答案：直接映射、全相联、组相联";
const BATCH = "一、单选题\n1. 甲（ ）\nA. 1\nB. 2\n2. 乙（ ）\nA. 3\nB. 4\n答案：1.A 2.B";

check("EX-01", "单选题：题头/四个选项/答案", () => {
  const r = ex.structureExamText(CHOICE, "exam");
  eq(r.items.length, 1, "题目数");
  eq(r.items[0].options.length, 4, "选项数");
  eq(r.items[0].answer, "B", "答案");
  eq(r.items[0].qtype, "choice", "题型");
  return "1 题 / 4 选项 / 答案 B";
});

check("EX-02", "判断题：题型与答案保留", () => {
  const r = ex.structureExamText(JUDGE, "exam");
  eq(r.items.length, 1, "题目数");
  eq(r.items[0].qtype, "judge", "题型");
  eq(r.items[0].answer, "错误", "答案");
  return "judge / 错误";
});

check("EX-03", "填空题：空缺占位与答案", () => {
  const r = ex.structureExamText(BLANK, "exam");
  eq(r.items[0].qtype, "blank", "题型");
  eq(r.items[0].answer, "2", "答案");
  return "blank / 2";
});

check("EX-04", "简答题：题型与整段答案", () => {
  const r = ex.structureExamText(SOLVE, "exam");
  eq(r.items[0].qtype, "solve", "题型");
  eq(r.items[0].answer, "直接映射、全相联、组相联", "答案");
  return "solve / 三方式";
});

check("EX-05", "答案批量分发（1.A 2.B 映射回对应题）", () => {
  const r = ex.structureExamText(BATCH, "exam");
  eq(r.items.length, 2, "题目数");
  eq(r.items.map((i) => i.answer), ["A", "B"], "答案序列");
  return "A/B";
});

check("EX-06", "空输入不抛异常、题目为 0", () => {
  const r = ex.structureExamText("", "exam");
  eq(r.items.length, 0, "题目数");
  return "0 题";
});

check("EX-07", "题号连续（从 1 递增）", () => {
  const r = ex.structureExamText(BATCH, "exam");
  eq(r.items.map((i) => i.no), [1, 2], "题号");
  return "1,2";
});

check("EX-08", "单卷上限 300 题", () => {
  const many = Array.from({ length: 350 }, (_, i) => `${i + 1}. 题目 ${i + 1}（ ）\nA. 甲\nB. 乙\nC. 丙\nD. 丁\n答案：A`).join("\n");
  const r = ex.structureExamText(many, "exam");
  if (r.items.length > 300) throw new Error("超过上限：" + r.items.length);
  return "截断至 " + r.items.length + " 题";
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
