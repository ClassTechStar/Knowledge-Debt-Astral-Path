/**
  * plan-runtime.js —— 14 天计划的运行时快照（借鉴 CW2 ScheduleRuntime / ClassIsland TimeState）
  * ===========================================================
  * 纯函数：输入（计划 items / 今天第几天 / 临时调整），输出当日时间线快照与状态；
  * 不读 DOM、不读全局状态、不改输入。状态只在两次快照之间"翻转"时才值得发通知，
  * 由 diffSnapshots / evaluateAutomations 供调用方判断。
  *
  * 计划 item 形状（与 plan-scheduler.js 的产出一致）：
  *   { id, day(1..14), kp, layer:"core"|"challenge", st:"todo"|"done"|..., min, fromKp, rd, label, why }
  * 临时调整（override）形状：
  *   { id, type:"pause"|"relief", days, startDay, createdAt }
  *   pause  = 请假暂停：覆盖期内的天数不计入连续未完成、不出提醒
  *   relief = 减量：覆盖期内剩余任务时长按 ratio（默认 0.5）折算展示
  *
  * UMD：浏览器 window.APRuntime；Node require（plan_runtime_runner.js 跑用例）。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APRuntime = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var DAY_MS = 24 * 60 * 60 * 1000;

  /** 覆盖层生效计算：某天是否暂停 / 时长折算比例（纯函数） */
  function applyOverrides(overrides, day) {
    var paused = false, ratio = 1;
    (overrides || []).forEach(function (o) {
      if (!o || o.removed) return;
      var start = o.startDay || 1, days = o.days || 0;
      if (day < start || day >= start + days) return;
      if (o.type === "pause") paused = true;
      if (o.type === "relief") { var r = typeof o.ratio === "number" ? o.ratio : 0.5; if (r < ratio) ratio = r; }
    });
    return { paused: paused, ratio: ratio };
  }

  function overrideAt(overrides, day) { return applyOverrides(overrides, day).paused; }

  /**
    * 计算快照。
    * @param {Array} plan   计划 items
    * @param {{day:number, overrides?:Array}} ctx
    */
  function computeSnapshot(plan, ctx) {
    ctx = ctx || {};
    var today = ctx.day || 1;
    var overrides = ctx.overrides || [];
    var items = (plan || []).filter(function (i) { return i && i.day >= 1 && i.day <= 14; });
    var perDay = {};
    items.forEach(function (i) {
      var d = perDay[i.day] || (perDay[i.day] = { total: 0, done: 0, min: 0, doneMin: 0 });
      d.total++;
      var isDone = i.st === "done";
      if (isDone) d.done++;
      var ov = applyOverrides(overrides, i.day);
      var min = i.min || 0;
      if (!isDone && i.day >= today && ov.ratio < 1) min = Math.round(min * ov.ratio);
      d.min += min;
      if (isDone) d.doneMin += i.min || 0;
    });
    var td = perDay[today] || { total: 0, done: 0, min: 0, doneMin: 0 };
    var overdue = items.filter(function (i) { return i.day < today && i.st !== "done"; });
    // 连续未完成：从昨天往回数「有安排但一个都没做」的天；暂停天与无安排天都打断计数
    var consecutiveIncomplete = 0, streak = 0;
    for (var d = today - 1; d >= 1; d--) {
      var pd = perDay[d];
      if (!pd || pd.total === 0) break;
      if (overrideAt(overrides, d)) break;
      if (pd.done === 0) consecutiveIncomplete++;
      else break;
    }
    for (var s = today - 1; s >= 1; s--) {
      var ps = perDay[s];
      if (!ps || ps.total === 0) break;
      if (overrideAt(overrides, s)) break;
      if (ps.done > 0) streak++;
      else break;
    }
    var paused = applyOverrides(overrides, today).paused;
    var status;
    if (paused) status = "paused";
    else if (overdue.length > 0) status = "behind";
    else if (td.total > 0 && td.done >= td.total) status = "ahead";
    else status = "ontrack";
    var daysLeft = Math.max(0, 14 - today);
    var remainMin = 0;
    items.forEach(function (i) { if (i.st !== "done" && i.day >= today) remainMin += i.min || 0; });
    if (applyOverrides(overrides, today).ratio < 1) remainMin = Math.round(remainMin * applyOverrides(overrides, today).ratio);
    return {
      day: today, status: status, paused: paused,
      totalItems: items.length,
      doneItems: items.filter(function (i) { return i.st === "done"; }).length,
      todayTotal: td.total, todayDone: td.done, todayMin: td.min,
      overdueCount: overdue.length, overdueMin: overdue.reduce(function (a, i) { return a + (i.min || 0); }, 0),
      consecutiveIncomplete: consecutiveIncomplete,
      streak: streak, daysLeft: daysLeft, remainMin: remainMin,
      perDay: perDay,
    };
  }

  /** 两次快照之间翻转了哪些字段（供"状态翻转才提醒"用） */
  function diffSnapshots(prev, next) {
    var keys = ["status", "paused"];
    var flips = [];
    (prev && next ? keys : []).forEach(function (k) {
      if (prev[k] !== next[k]) flips.push({ key: k, from: prev[k], to: next[k] });
    });
    if (prev && next && prev.overdueCount !== next.overdueCount) {
      flips.push({ key: "overdueCount", from: prev.overdueCount, to: next.overdueCount });
    }
    return flips;
  }

  /**
    * 内置自动化（状态翻转驱动，冷却持久化交给调用方）。
    * @returns Array<{key, level, title, msg}>  key 同时是冷却存储键；streak 的 key 含里程碑数
    */
  function evaluateAutomations(snap, lastFired, nowMs) {
    var out = [];
    var last = lastFired || {};
    var now = nowMs || 0;
    if (!snap.paused && snap.consecutiveIncomplete >= 3) {
      if (now - (last.relief || 0) >= 7 * DAY_MS) {
        out.push({
          key: "relief", level: "warn",
          title: "要不要减点量？",
          msg: "已连续 " + snap.consecutiveIncomplete + " 天没完成今天的任务。计划不是欠条——到「知债」页点「本周减半」，把节奏调到能坚持的强度。",
        });
      }
    }
    if (snap.streak > 0 && snap.streak % 7 === 0 && last.streakMilestone !== snap.streak) {
      out.push({
        key: "streak" + snap.streak, level: "info",
        title: "连续 " + snap.streak + " 天有进展",
        msg: "过去 " + snap.streak + " 天每天都推进了至少一个任务。保持节奏，销账就是这么攒出来的。",
      });
    }
    return out;
  }

  return {
    applyOverrides: applyOverrides,
    computeSnapshot: computeSnapshot,
    diffSnapshots: diffSnapshots,
    evaluateAutomations: evaluateAutomations,
  };
});
