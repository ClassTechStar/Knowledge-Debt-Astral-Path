/**
 * gen-shared-core.js —— 由 tools/agent-intents.json 生成 shared/core.js 的常量块
 * 意图表只维护一份。以前 p2-ai-integration.js 自己另存了一份 INTENTS，22→26
 * 扩容时漏了同步（kb.search 少 13 个锚点等 17 处）。这里把共享内核的常量改成
 * 构建期产物，打上 DO NOT EDIT 标记，平行副本就没地方藏了。
 *
 * 用法：node scripts/gen-shared-core.js [--check]
 *       --check  只校验生成块是否与 JSON 一致，不写文件（CI 用）
 * 退出码：0 = 一致/已生成；1 = 不一致（--check 时）
 */
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const JSON_P = path.join(ROOT, "tools", "agent-intents.json");
const CORE = path.join(ROOT, "shared", "core.js");

const BEGIN = "  /* ==== GENERATED FROM tools/agent-intents.json — DO NOT EDIT ==== */";
const END = "  /* ==== /GENERATED ==== */";

const CHECK_ONLY = process.argv.includes("--check");

function js(s) {
  return JSON.stringify(s);
}

function renderBlock(doc) {
  const lines = [];
  lines.push(BEGIN);
  lines.push("  /* generator: scripts/gen-shared-core.js · source: tools/agent-intents.json */");
  lines.push("  var CRISIS = " + js(doc.crisis) + ";");
  lines.push("  var BANNED = " + js(doc.banned) + ";");
  lines.push("  var NEGATIVE = " + js(doc.negative) + ";");
  lines.push("  var INTENTS = [");
  doc.intents.forEach((it, i) => {
    const anchors = it.anchors.map((a) => js(a)).join(", ");
    const comma = i === doc.intents.length - 1 ? "" : ",";
    lines.push("    [" + js(it.id) + ", [" + anchors + "]]" + comma);
  });
  lines.push("  ];");
  lines.push(END);
  return lines.join("\n");
}

const doc = JSON.parse(fs.readFileSync(JSON_P, "utf8"));
const want = renderBlock(doc);
// 行尾归一：工作副本可能因 autocrlf 检出为 CRLF（blob 为 LF），生成块统一按 LF 对比，
// 否则同一份内容会在「本地绿 / CI 红」或「分支切换后假漂移」之间摇摆。
const src = fs.readFileSync(CORE, "utf8").replace(/\r\n/g, "\n");

const bi = src.indexOf(BEGIN);
const ei = src.indexOf(END);
if (bi < 0 || ei < 0) {
  console.error("shared/core.js 缺少 GENERATED 标记块");
  process.exit(1);
}
const have = src.slice(bi, ei + END.length);

if (CHECK_ONLY) {
  if (have === want) {
    console.log("ALL GREEN · shared/core.js 生成块与 agent-intents.json 一致");
    process.exit(0);
  }
  console.error("[DRIFT] shared/core.js 生成块已漂移，请运行：node scripts/gen-shared-core.js");
  process.exit(1);
}

if (have === want) {
  console.log("shared/core.js 已与 JSON 一致，无需改动");
  process.exit(0);
}
fs.writeFileSync(CORE, src.slice(0, bi) + want + src.slice(ei + END.length), "utf8");
console.log("shared/core.js 生成块已更新（意图 " + doc.intents.length + " 条）");
