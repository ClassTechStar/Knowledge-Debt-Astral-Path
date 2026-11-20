/**
 * updater_runner.js —— shared/updater.js 用例（verify_all 的 updater-golden 步骤直接调用）。
 * 覆盖：版本比较（相等/补丁/跨次段/v 前缀/非法段）、latest 解析、资产挑选、
 * 无网络环境的 check 返回语义（manual 与静默两态）。网络真实请求不在纯函数范围。
 * 退出码：0 = 全过；1 = 有失败。
 */
"use strict";
const path = require("path");
const APUpdater = require(path.resolve(__dirname, "..", "shared", "updater.js"));

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
function eq(a, b, msg) { if (a !== b) throw new Error(`${msg}（实际 ${a} ≠ 期望 ${b}）`); }

check("UP-01", "版本相等", () => {
  eq(APUpdater.compareVersions("2.6.0", "2.6.0"), 0, "cmp");
  return "eq";
});

check("UP-02", "补丁号更新", () => {
  eq(APUpdater.compareVersions("2.6.1", "2.6.0"), 1, "cmp");
  eq(APUpdater.compareVersions("2.6.0", "2.6.1"), -1, "cmp");
  return "patch";
});

check("UP-03", "跨次段比较：2.10.0 > 2.9.9（逐段数字，不按字符串）", () => {
  eq(APUpdater.compareVersions("2.10.0", "2.9.9"), 1, "cmp");
  return "minor-carry";
});

check("UP-04", "v 前缀剥离（GitHub tag 形态）", () => {
  eq(APUpdater.compareVersions("v2.7.0", "2.6.0"), 1, "cmp");
  return "v-prefix";
});

check("UP-05", "非法段按 0 处理，不抛异常", () => {
  eq(APUpdater.compareVersions("abc", "0.0.0"), 0, "cmp");
  return "safe";
});

check("UP-06", "parseLatest：tag 剥 v、URL 回填", () => {
  const r = APUpdater.parseLatest({ tag_name: "v2.7.0", html_url: "https://github.com/x/y/releases/tag/v2.7.0" });
  eq(r.version, "2.7.0", "version");
  eq(r.url, "https://github.com/x/y/releases/tag/v2.7.0", "url");
  assert(r.draft === false && r.prerelease === false, "标志位");
  return r.version;
});

check("UP-07", "parseLatest：非法输入返回 null", () => {
  assert(APUpdater.parseLatest(null) === null, "null");
  assert(APUpdater.parseLatest({}) === null, "无 tag");
  assert(APUpdater.parseLatest({ tag_name: "  " }) === null, "空 tag");
  return "null-safe";
});

check("UP-08", "pickAsset：平台前缀匹配，忽略大小写", () => {
  const names = ["checksums.sha256", "astralpath-monolith-setup-2.7.0.exe", "AstralPath-Android-2.7.0-Store.apk", "manifest.json"];
  eq(APUpdater.pickAsset(names, "astralpath-monolith-setup"), "astralpath-monolith-setup-2.7.0.exe", "setup");
  eq(APUpdater.pickAsset(names, "AstralPath-Android"), "AstralPath-Android-2.7.0-Store.apk", "apk");
  eq(APUpdater.pickAsset(names, "linux-deb"), null, "无匹配");
  return "asset";
});

async function main() {
  // 异步用例：注入「网络不可达」的 fetch 存根（返回 rejected Promise，与真实网络错误同形）
  const netDown = function () { return Promise.reject(new Error("network unreachable")); };
  try {
    const r1 = await APUpdater.check(true, "2.6.0", netDown);
    const ok1 = r1.status === "error";
    results.push({ id: "UP-09", name: "check：无 fetch 且 manual → error", ok: ok1, detail: r1.status });
  } catch (e) {
    results.push({ id: "UP-09", name: "check：无 fetch 且 manual → error", ok: false, detail: String(e) });
  }
  try {
    const r2 = await APUpdater.check(false, "2.6.0", netDown);
    const ok2 = r2.status === "offline";
    results.push({ id: "UP-10", name: "check：无 fetch 且静默 → offline", ok: ok2, detail: r2.status });
  } catch (e) {
    results.push({ id: "UP-10", name: "check：无 fetch 且静默 → offline", ok: false, detail: String(e) });
  }

  const passed = results.filter((r) => r.ok).length;
  process.stdout.write(JSON.stringify({ passed, failed: results.length - passed, results }, null, 2));
  if (passed !== results.length) process.exit(1);
}

main();
