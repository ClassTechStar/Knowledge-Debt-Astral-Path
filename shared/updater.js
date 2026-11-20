/**
  * updater.js —— 检查更新（更新源默认 GitHub Release，可整体切换）
  * ===========================================================
  * 纯逻辑（compareVersions / parseLatest）与网络（check）分离：
  *   - 纯函数在 Node 侧测试（scripts/updater_runner.js 金样）
  *   - check() 浏览器侧用 fetch + AbortController（10s 超时），匿名请求
  *     api.github.com（限流 60 次/小时），失败静默——离线优先不惩罚
  *
  * 安全口径（对齐 THREAT_MODEL.md T22）：Web 端只「检查 + 跳转 Release 页」，
  * 不自动下载安装；Windows 壳的原生更新器才做应用内下载，且下载后必须用
  * 同一 Release 的 checksums.sha256 核验（T19 供应链清单）+ 用户确认后才运行安装器。
  *
  * UMD：浏览器 window.APUpdater；Node require（updater_runner.js 测纯函数）。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APUpdater = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var REPO = "ClassTechStar/Knowledge-Debt-Astral-Path";
  var RELEASE_URL = "https://github.com/" + REPO + "/releases/latest";

  /**
    * 版本比较：只认数字段（x.y.z），逐段比大小，短段补 0。
    * 非 v 前缀在这里剥离；非法段按 0 处理（tag 手误不抛异常）。
    * 返回 -1 / 0 / 1（a 相对 b）。
    */
  function compareVersions(a, b) {
    function segs(v) {
      var t = String(v || "").replace(/^v/i, "").trim();
      var parts = t.split(".");
      var out = [];
      for (var i = 0; i < 3; i++) {
        var n = parseInt(parts[i], 10);
        out.push(isNaN(n) ? 0 : n);
      }
      return out;
    }
    var A = segs(a), B = segs(b);
    for (var i = 0; i < 3; i++) {
      if (A[i] !== B[i]) return A[i] < B[i] ? -1 : 1;
    }
    return 0;
  }

  /**
    * 从 GitHub /releases/latest 的 JSON 取检查结果。
    * tag_name 形如 v2.6.1；html_url 是发布页。资产名不在 Web 端消费
    * （Web 只跳转），Windows 原生更新器自行挑 Setup 资产。
    */
  function parseLatest(json) {
    if (!json || typeof json !== "object") return null;
    var tag = String(json.tag_name || "");
    var version = tag.replace(/^v/i, "").trim();
    if (!version) return null;
    return {
      version: version,
      url: String(json.html_url || ("https://github.com/" + REPO + "/releases/tag/" + tag)),
      draft: !!json.draft,
      prerelease: !!json.prerelease,
    };
  }

  /** Windows 原生更新器用：在资产名里挑当前平台的安装包（前缀匹配，忽略大小写） */
  function pickAsset(names, prefix) {
    var p = String(prefix || "").toLowerCase();
    for (var i = 0; i < (names || []).length; i++) {
      if (String(names[i] || "").toLowerCase().indexOf(p) === 0) return names[i];
    }
    return null;
  }

  /**
    * 检查更新。manual=true 由按钮触发（失败要给反馈）；false 为启动静默检查。
    * 返回 { status: "newer"|"latest"|"offline"|"error", version?, url? }。
    * currentVersion 来自 window.AP_VERSION（构建期由单一事实源校验，见
    * scripts/verify_release_version.py）。
    */
  function check(manual, currentVersion, fetchImpl) {
    var f = fetchImpl || (typeof fetch === "function" ? fetch : null);
    if (!f) return Promise.resolve({ status: manual ? "error" : "offline" });
    var ctrl = typeof AbortController !== "undefined" ? new AbortController() : null;
    var timer = ctrl ? setTimeout(function () { try { ctrl.abort(); } catch (e) {} }, 10000) : null;
    return f("https://api.github.com/repos/" + REPO + "/releases/latest", {
      method: "GET",
      headers: { "Accept": "application/vnd.github+json" },
      signal: ctrl ? ctrl.signal : undefined,
    }).then(function (resp) {
      if (timer) clearTimeout(timer);
      if (!resp.ok) return { status: manual ? "error" : "offline" };
      return resp.json().then(function (j) {
        var info = parseLatest(j);
        if (!info) return { status: manual ? "error" : "offline" };
        var cmp = compareVersions(info.version, currentVersion || "0.0.0");
        if (cmp > 0) return { status: "newer", version: info.version, url: info.url };
        return { status: "latest", version: info.version, url: info.url };
      });
    }).catch(function () {
      if (timer) clearTimeout(timer);
      // manual（按钮触发）要把「连不上」如实报给界面；静默检查则不惊扰
      return { status: manual ? "error" : "offline" };
    });
  }

  return {
    REPO: REPO,
    RELEASE_URL: RELEASE_URL,
    compareVersions: compareVersions,
    parseLatest: parseLatest,
    pickAsset: pickAsset,
    check: check,
  };
});
