/**
  * learn-report.js —— 学习轨迹报告（D3 反馈维度）
  * ===========================================================
  * 近 7 天作答统计与最易错知识点，全部从作答日志（S.logs）推导，
  * 零新增状态。日志形态 {kp, ok, conf, ts}（见页面作答口）。
  * 纯函数：now 由调用方传入（金样可对拍）；UMD 供页面与 Node 双端。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APReport = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var DAY = 86400000;
  function dayStart(ts) { var d = new Date(ts); d.setHours(0, 0, 0, 0); return d.getTime(); }
  function fmt(ts) {
    var d = new Date(ts);
    function p(x) { return (x < 10 ? "0" : "") + x; }
    return p(d.getMonth() + 1) + "-" + p(d.getDate());
  }

  /**
   * weekly(logs, nodes, now)：
   * days    — 近 7 天（旧→今）{label:"MM-DD", count, ok}
   * total   — 近 7 天作答总数；acc — 正确率（无作答为 0）
   * weakest — 错次最多的前 3 个知识点 [{id, title, wrong, total}]，
   *           错次并列按总作答多者靠前，排序稳定可对拍
   */
  function weekly(logs, nodes, now) {
    logs = Array.isArray(logs) ? logs : [];
    var base = dayStart(now);
    var days = [];
    for (var i = 6; i >= 0; i--) {
      var s = base - i * DAY, e = s + DAY;
      var cnt = 0, ok = 0;
      logs.forEach(function (l) {
        if (l && l.ts >= s && l.ts < e) { cnt++; if (l.ok) ok++; }
      });
      days.push({ label: fmt(s), count: cnt, ok: ok });
    }
    var total = days.reduce(function (a, d) { return a + d.count; }, 0);
    var accOk = days.reduce(function (a, d) { return a + d.ok; }, 0);
    // 最易错：只统计近 7 天（今天 0 点起往前 6 天，含今天全天）
    var byKp = {};
    logs.forEach(function (l) {
      if (!l || !l.kp || l.ts < base - 6 * DAY || l.ts >= base + DAY) return;
      var b = byKp[l.kp] || (byKp[l.kp] = { wrong: 0, total: 0 });
      b.total++; if (!l.ok) b.wrong++;
    });
    var titles = {};
    (Array.isArray(nodes) ? nodes : []).forEach(function (n) { titles[n.id] = n.title; });
    var weakest = Object.keys(byKp).map(function (k) {
      return { id: k, title: titles[k] || k, wrong: byKp[k].wrong, total: byKp[k].total };
    }).filter(function (w) { return w.wrong > 0; })
      .sort(function (a, b) { return (b.wrong - a.wrong) || (b.total - a.total); })
      .slice(0, 3);
    return { days: days, total: total, acc: total ? accOk / total : 0, weakest: weakest };
  }

  return { weekly: weekly };
});
