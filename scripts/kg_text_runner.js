/**
 * kg_text_runner.js —— shared/kg-text.js 用例（verify_all / CI 调用）
 * 覆盖：大纲抽取（Markdown/第X章）、无标题兜底分章、标题有效性过滤、
 *       TextRank 确定性、加权术语（停用词与目录噪声剔除）。
 * 输出 JSON：{passed, failed, results:[{id,name,ok,detail}]}
 */
"use strict";
const path = require("path");
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

const MD = [
  "## 会计基础",
  "资产与负债是会计要素的核心。借贷记账法建立在会计等式之上。",
  "## 借贷记账法",
  "借贷记账法需要先掌握会计等式与会计要素，再理解复式记账。",
  "## 财务报表",
  "财务报表汇总资产、负债与所有者权益，是会计要素的最终呈现。",
].join("\n");

// 词之间用空格分隔，保证分词器切出完整术语（教材正文里术语常由标点/空白隔开）
const TERMS_TEXT = [
  "会计等式 资产 负债 所有者权益 会计要素",
  "借贷记账法 复式记账 会计等式 资产 负债",
  "财务报表 会计要素 资产 负债 所有者权益",
].join("\n\n").repeat(2);

check("KG-01", "Markdown 大纲：三章且标题保真", () => {
  const chs = kg.extractOutlineV2(MD, 10);
  eq(chs.length, 3, "章节数");
  eq(chs.map((c) => c.title), ["会计基础", "借贷记账法", "财务报表"], "标题");
  return "3 章";
});

check("KG-02", "无标题正文：句子聚合兜底分章", () => {
  const chs = kg.kgChunkChapters(TERMS_TEXT, 6);
  if (chs.length < 2) throw new Error("兜底分章少于 2：" + chs.length);
  if (!chs.every((c) => c.body && c.title)) throw new Error("章节缺 body/title");
  return chs.length + " 章";
});

check("KG-03", "标题过滤：页码/长数字/碎片拒绝，术语保留", () => {
  eq(kg.kgValidTitle("123456"), "", "长数字串");
  eq(kg.kgValidTitle("（ ）"), "", "括号残片");
  eq(kg.kgValidTitle("会计等式"), "会计等式", "中文术语");
  return "过滤正常";
});

check("KG-04", "TextRank：确定性排序与统计", () => {
  const toks = kg.tokenize(TERMS_TEXT);
  const a = kg.textRank(toks, 5, 12, 0.85);
  const b = kg.textRank(toks, 5, 12, 0.85);
  if (!a.stats || a.stats.n < 2 || a.stats.edges < 1) throw new Error("统计异常");
  eq(Object.keys(a.out), Object.keys(b.out), "两次词表顺序");
  const top = Object.keys(a.out).sort((x, y) => a.out[y] - a.out[x])[0];
  if (!top) throw new Error("无 Top 词");
  return `Top=${top} · n=${a.stats.n} · edges=${a.stats.edges}`;
});

check("KG-05", "加权术语：领域词入选且停用词/目录噪声剔除", () => {
  const terms = kg.extractTermsWeighted(TERMS_TEXT, [{ title: "会计基础", body: TERMS_TEXT }], 12);
  if (!terms.length) throw new Error("无术语");
  const words = terms.map((t) => t.t);
  if (!words.includes("会计等式")) throw new Error("缺领域词：会计等式（" + words.join(",") + "）");
  if (words.some((w) => w === "第" || /^\d+$/.test(w))) throw new Error("目录噪声入榜");
  return `${terms.length} 词 · ${words.slice(0, 3).join("/")}`;
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
