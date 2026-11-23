/**
  * plan-ics.js —— 把 14 天计划导出成 .ics 日历（RFC 5545）
  * ===========================================================
  * 为什么：计划生成出来只能躺在应用里看，出不了应用就只是「电子便签」。
  * 导出成日历文件后，学生可以直接导入系统日历/手机日历，让复习进入真实时间管理。
  *
  * 约定（确定性纯函数，金样 runner 逐字节验证）：
  *   · 每个计划项一个 VEVENT，DTSTART 用**浮动本地时间**（不带 Z / TZID），
  *     导入方按本机时区解释——避免跨时区/夏令时换算带来的不确定性；
  *   · 默认每天 19:00 开始，时长 = 该项 min（分钟），可用 opts.hour 覆盖；
  *   · 行折叠按 RFC 5545：超过 75 字节折行，续行以单个空格开头；
  *   · 文本转义 \\ ; , 与换行；CRLF 行尾；
  *   · DTSTAMP 由 opts.stamp 决定（页面传当前时间，金样传定值），保证可复现。
  *
  * UMD：浏览器 `window.APPlanIcs`，Node `require("./shared/plan-ics.js")`。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APPlanIcs = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  function pad(n) { return (n < 10 ? "0" : "") + n; }

  /** 文本转义：反斜杠、分号、逗号、换行（RFC 5545 §3.3.11）。 */
  function escText(s) {
    return String(s == null ? "" : s)
      .replace(/\\/g, "\\\\")
      .replace(/;/g, "\\;")
      .replace(/,/g, "\\,")
      .replace(/\r\n|\r|\n/g, "\\n");
  }

  /** 按 UTF-8 字节数折叠成 ≤75 字节的多行（续行前导一个空格）。 */
  function fold(line) {
    var out = [], cur = "", bytes = 0;
    for (var i = 0; i < line.length; i++) {
      var ch = line[i];
      var b = encodeLen(ch);
      // 续行有 1 字节前导空格，所以首个物理行 75、后续物理行 74
      var limit = out.length === 0 ? 75 : 74;
      if (bytes + b > limit) { out.push(cur); cur = ""; bytes = 0; }
      cur += ch; bytes += b;
    }
    out.push(cur);
    return out.join("\r\n ");
  }

  /** 单字符 UTF-8 字节数（不依赖 TextEncoder，双端一致）。 */
  function encodeLen(ch) {
    var c = ch.codePointAt(0);
    if (c <= 0x7f) return 1;
    if (c <= 0x7ff) return 2;
    if (c <= 0xffff) return 3;
    return 4;
  }

  /** YYYY-MM-DD 解析；非法返回 null。 */
  function parseDate(s) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ""));
    if (!m) return null;
    return { y: +m[1], m: +m[2], d: +m[3] };
  }

  /** 本地浮动时间串：YYYYMMDDTHHMMSS（无 Z）。 */
  function localStamp(date, dayOffset, hour, minute) {
    var dt = new Date(Date.UTC(date.y, date.m - 1, date.d));
    dt.setUTCDate(dt.getUTCDate() + (dayOffset || 0));
    return String(dt.getUTCFullYear())
      + pad(dt.getUTCMonth() + 1) + pad(dt.getUTCDate())
      + "T" + pad(hour) + pad(minute) + "00";
  }

  function utcStamp(d) {
    return String(d.getUTCFullYear())
      + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate())
      + "T" + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + "Z";
  }

  /**
   * 生成 .ics 文本。
   * @param {Array} items 计划项：[{id, day, kp, min, label, why}]
   * @param {object} [opts] {startDate:"YYYY-MM-DD", hour:19, minute:0, stamp:Date, name:函数(kp)=>标题}
   * @returns {string} CRLF 行尾的 .ics 文本
   */
  function build(items, opts) {
    opts = opts || {};
    var start = parseDate(opts.startDate) || parseDate(new Date().toISOString().slice(0, 10));
    var hour = opts.hour == null ? 19 : opts.hour;
    var minute = opts.minute == null ? 0 : opts.minute;
    var stamp = utcStamp(opts.stamp instanceof Date ? opts.stamp : new Date());
    var nameOf = opts.name || function (kp) { return kp || "知识点"; };

    var lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//AstralPath//Study Plan//ZH",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "X-WR-CALNAME:知债：星穹学途 · 复习计划"
    ];

    (items || []).forEach(function (p, i) {
      if (!p || typeof p !== "object") return;
      var day = parseInt(p.day, 10);
      if (!(day >= 1)) return;
      var mins = parseInt(p.min, 10);
      if (!(mins > 0)) mins = 20;
      var kp = p.kp || "";
      var label = p.label || ("巩固「" + nameOf(kp) + "」");
      var uid = "astralpath-" + (p.id || (day + "-" + i)) + "@astralpath.local";

      lines.push("BEGIN:VEVENT");
      lines.push("UID:" + escText(uid));
      lines.push("DTSTAMP:" + stamp);
      lines.push("DTSTART:" + localStamp(start, day - 1, hour, minute));
      lines.push("DURATION:PT" + mins + "M");
      lines.push("SUMMARY:" + escText("D" + day + " · " + label));
      var desc = (p.why ? p.why + " " : "") + "（" + mins + " 分钟 · 知债：星穹学途）";
      lines.push("DESCRIPTION:" + escText(desc));
      if (kp) lines.push("CATEGORIES:" + escText(nameOf(kp)));
      lines.push("END:VEVENT");
    });

    lines.push("END:VCALENDAR");
    return lines.map(fold).join("\r\n") + "\r\n";
  }

  /**
   * 触发浏览器下载 .ics（DOM 胶水集中在本模块，页面只留一行调用）。
   * env 可注入 {Blob, URL, document, Date}，便于 Node 侧测试；缺省用全局。
   * @returns {{ok:boolean, count:number, filename:string, message:string}}
   */
  function download(items, opts, env) {
    opts = opts || {};
    var e = env || {};
    var BlobCtor = e.Blob || (typeof Blob !== "undefined" ? Blob : null);
    var URLObj = e.URL || (typeof URL !== "undefined" ? URL : null);
    var doc = e.document || (typeof document !== "undefined" ? document : null);
    var now = e.Date ? new e.Date() : new Date();
    var list = items || [];

    if (!list.length) return { ok: false, count: 0, filename: "", message: "还没有计划可导出：先生成 14 天计划。" };
    if (!BlobCtor || !URLObj || !doc) return { ok: false, count: 0, filename: "", message: "当前环境不支持文件下载。" };

    var text = build(list, {
      startDate: opts.startDate || now.toISOString().slice(0, 10),
      hour: opts.hour, minute: opts.minute, stamp: now, name: opts.name,
    });
    var filename = "astralpath-plan-" + (opts.startDate || now.toISOString().slice(0, 10)) + ".ics";
    var blob = new BlobCtor(["\ufeff" + text], { type: "text/calendar;charset=utf-8" });
    var a = doc.createElement("a");
    a.href = URLObj.createObjectURL(blob);
    a.download = filename;
    doc.body.appendChild(a);
    a.click();
    if (typeof setTimeout === "function") {
      setTimeout(function () { try { URLObj.revokeObjectURL(a.href); a.remove(); } catch (err) { /* 卸载失败不影响导出 */ } }, 0);
    }
    return { ok: true, count: list.length, filename: filename, message: "已导出 " + list.length + " 项复习任务（.ics）。" };
  }

  return {
    build: build,
    download: download,
    escText: escText,
    fold: fold,
    parseDate: parseDate,
    localStamp: localStamp,
  };
});
