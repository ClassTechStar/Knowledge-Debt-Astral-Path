/**
 * camera_runner.js —— shared/camera-quality.js 的纯函数用例。
 * 输出 JSON：{ passed, failed, results:[{id,name,ok,detail}] }
 */
"use strict";
const path = require("path");
const Q = require(path.resolve(__dirname, "..", "shared", "camera-quality.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: detail || "" });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String(e && e.message || e) });
  }
}
function eq(a, b, msg) { if (a !== b) throw new Error(`${msg}: ${a} !== ${b}`); }
function ok(v, msg) { if (!v) throw new Error(msg); }

check("CAM-01", "模块导出完整（sharpness / captureBestFrame / qualityHint）", () => {
  ok(typeof Q.sharpness === "function", "sharpness 缺失");
  ok(typeof Q.captureBestFrame === "function", "captureBestFrame 缺失");
  ok(typeof Q.qualityHint === "function", "qualityHint 缺失");
  return "3 个导出齐备";
});

check("CAM-02", "qualityHint 三档阈值单调且边界确定", () => {
  const blur = Q.qualityHint(0), mid = Q.qualityHint(100), good = Q.qualityHint(500);
  ok(blur.indexOf("糊") >= 0, "低分应提示糊");
  ok(mid.indexOf("一般") >= 0, "中分应提示一般");
  ok(good.indexOf("良好") >= 0, "高分应提示良好");
  return `${blur} / ${mid} / ${good}`;
});

check("CAM-03", "无 canvas 环境 sharpness 安全返回 0（Node 侧不崩）", () => {
  eq(Q.sharpness(null), 0, "null 应返回 0");
  eq(Q.sharpness({}), 0, "无尺寸应返回 0");
  eq(Q.sharpness({ width: 640, height: 480 }), 0, "无 document 应返回 0");
  return "Node 环境安全降级";
});

check("CAM-04", "captureBestFrame 在无视频源时明确抛错而非静默返回", async () => {
  // 同步检查参数守卫：无 videoWidth 时应抛「相机未就绪」
  let threw = false;
  try { await Q.captureBestFrame({ videoWidth: 0, videoHeight: 0 }); }
  catch (e) { threw = /相机未就绪/.test(e.message); }
  ok(threw, "应抛「相机未就绪」");
  return "失败路径明确";
});

// 异步用例需等待后输出
setTimeout(() => {
  const passed = results.filter((r) => r.ok).length;
  process.stdout.write(JSON.stringify({ passed, failed: results.length - passed, results }, null, 2));
}, 30);
