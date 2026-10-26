/**
  * plan-scheduler.js —— 修复计划的排程与 K1–K5 合约检查
  * ===========================================================
  * 从 index.html 抽出来的纯计划逻辑：合约校验、14 天逐日容量排程、
  * 先修感知重排、超预算减压。图谱边、节点、标题、文案由 ctx 传进来，
  * 这里不读 DOM、不读全局状态。
 *
  * 用法：
  * 浏览器：window.APPlan（由 scripts/gen_frontend_regions.py 内联进页面生成区）
  * Node  ：require("./shared/plan-scheduler.js")
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APPlan = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  function goldenScore(recent_acc, sev, self_conf) {
    const sev_norm = 1 - Math.max(0, Math.min(1, sev || 0));
    const acc = Math.max(0, Math.min(1, recent_acc || 0));
    const conf = Math.max(1, Math.min(5, self_conf || 3));
    return +(100 * (0.6 * acc + 0.3 * sev_norm + 0.1 * (conf / 5))).toFixed(1);
  }

  /**
    * K1–K5 合约。ctx：edges（图谱边）、titleOf（id→标题）、deferred（显式延期）。
    * opts：edges / debts / deferred 可覆盖 ctx。
    */
  function checkPlanK(plan, budgetPerDay, opts, ctx) {
    opts = opts || {};
    ctx = ctx || {};
    budgetPerDay = budgetPerDay || 40;
    const titleOf = ctx.titleOf || function (x) { return x; };
    const viol = [], byDay = {};
    (plan || []).forEach(function (p) { byDay[p.day] = (byDay[p.day] || 0) + (p.min || 0); });
    Object.keys(byDay).forEach(function (d) {
      if (byDay[d] > budgetPerDay) viol.push("D" + d + " 合计 " + byDay[d] + "min 超出日预算 " + budgetPerDay + "min（K1）");
    });
    (plan || []).forEach(function (p) {
      const from = p.fromKp;
      const whyHas = from && p.why && (String(p.why).indexOf(String(from)) >= 0 || String(p.why).indexOf(titleOf(from)) >= 0);
      if (!whyHas) viol.push("D" + p.day + " 条目「" + (p.kp || "") + "」的 why 未包含 from_kp（K3）");
    });
    const seen = {};
    (plan || []).forEach(function (p) {
      const k = p.day + "|" + p.kp;
      if (seen[k]) viol.push("D" + p.day + "「" + titleOf(p.kp) + "」重复安排（K4）");
      seen[k] = 1;
    });
    const edges = opts.edges || ctx.edges || [];
    const first = {};
    (plan || []).forEach(function (p) { if (first[p.kp] == null || p.day < first[p.kp]) first[p.kp] = p.day; });
    (edges || []).forEach(function (e) {
      if (e.tg) return;
      if (first[e.from] != null && first[e.to] != null && first[e.from] > first[e.to])
        viol.push("先修「" + titleOf(e.from) + "」的最早任务晚于「" + titleOf(e.to) + "」（K2）");
    });
    const debts = opts.debts || null;
    if (debts && debts.length) {
      const defd = opts.deferred || ctx.deferred || [];
      debts.forEach(function (d) {
        const cov = (plan || []).some(function (p) { return p.fromKp === d.from && (p.kp === d.from || p.kp === d.to); });
        if (cov) return;
        const def = defd.some(function (x) { return x && x.from === d.from && x.to === d.to; });
        if (!def) viol.push("债边「" + d.fromName + "→" + d.toName + "」未覆盖也未显式延期（K5）");
      });
    }
    return viol;
  }

  function moveNode(items, bins, budget, kp, delta, allowShrink, offsets) {
    offsets = offsets || [0, 2, 6];
    const its = items.filter(function (p) { return p.kp === kp; });
    if (!its.length) return false;
    const newDays = [];
    for (let i = 0; i < its.length; i++) {
      const p = its[i];
      const nd = p.day + delta;
      const floorDay = 1 + (offsets[p.rd || 0] || 0);
      if (nd < 1 || nd > 14 || nd < floorDay) return false;
      newDays.push(nd);
    }
    const clone = {};
    Object.keys(bins).forEach(function (k) {
      const b = bins[k];
      clone[k] = { min: b.min, n: b.n, kps: Object.assign({}, b.kps) };
    });
    its.forEach(function (p) {
      const b = clone[p.day];
      if (b) { b.min -= p.min; b.n--; delete b.kps[kp]; }
    });
    const newMins = [];
    for (let j = 0; j < its.length; j++) {
      const nd2 = newDays[j];
      const b2 = clone[nd2] || (clone[nd2] = { min: 0, n: 0, kps: {} });
      if (b2.kps[kp] || b2.n >= 4) return false;
      let mm = its[j].min;
      if (b2.min + mm > budget) {
        if (!allowShrink) return false;
        mm = Math.max(8, budget - b2.min);
        if (b2.min + mm > budget) return false;
      }
      b2.min += mm; b2.n++; b2.kps[kp] = 1;
      newMins.push(mm);
    }
    Object.keys(bins).forEach(function (k) { delete bins[k]; });
    Object.keys(clone).forEach(function (k) { bins[k] = clone[k]; });
    its.forEach(function (p, i) { p.day = newDays[i]; if (newMins[i] !== p.min) p.min = newMins[i]; });
    return true;
  }

  function fixK2(items, bins, budget, edges, offsets) {
    edges = edges || [];
    for (let iter = 0; iter < 40; iter++) {
      const first = {};
      items.forEach(function (p) { if (first[p.kp] == null || p.day < first[p.kp]) first[p.kp] = p.day; });
      let worst = null;
      for (let i = 0; i < edges.length; i++) {
        const e = edges[i];
        if (e.tg) continue;
        if (first[e.from] == null || first[e.to] == null) continue;
        const dd = first[e.from] - first[e.to];
        if (dd > 0 && (!worst || dd > worst.dd)) worst = { from: e.from, to: e.to, dd: dd };
      }
      if (!worst) return true;
      if (moveNode(items, bins, budget, worst.to, worst.dd, false, offsets)) continue;
      if (moveNode(items, bins, budget, worst.from, -worst.dd, false, offsets)) continue;
      if (moveNode(items, bins, budget, worst.from, -worst.dd, true, offsets)) continue;
      if (moveNode(items, bins, budget, worst.to, worst.dd, true, offsets)) continue;
      return false;
    }
    return true;
  }

  /**
    * 本地版调度器 v2：逐日容量 + 先修感知。
    * ctx：edges / nodes、courseOf、prereqs、label、why、spacingOffsets。
    */
  function schedule(ds, budget, opts, ctx) {
    opts = opts || {};
    ctx = ctx || {};
    const offsets = ctx.spacingOffsets || [0, 2, 6];
    const edges = ctx.edges || [];
    const nodes = ctx.nodes || [];
    const courseOf = ctx.courseOf || function () { return ""; };
    const prereqsOf = ctx.prereqs || function () { return []; };
    const label = ctx.label || function (d, kind, r) { return kind + ":" + r; };
    const why = ctx.why || function () { return ""; };
    const rounds = budget >= 30 ? Math.min(3, offsets.length) : 2;
    const maxDebts = budget >= 30 ? 6 : 4;
    const maxPerDay = 4;
    const bins = {};
    const entries = [];
    const deferred = [];
    const bin = function (day) { if (!bins[day]) bins[day] = { min: 0, n: 0, kps: {} }; return bins[day]; };
    const canPlace = function (kp, min, day) {
      const b = bin(day);
      if (b.kps[kp]) return false;
      if (b.n >= maxPerDay) return false;
      if (b.min + min > budget) return false;
      return true;
    };
    const place = function (kp, min, day) { const b = bin(day); b.min += min; b.n++; b.kps[kp] = 1; };
    const findDay = function (kp, min, minDay) {
      for (let day = Math.max(1, minDay); day <= 14; day++) { if (canPlace(kp, min, day)) return day; }
      return -1;
    };
    const rank = {};
    try {
      const indeg = {};
      nodes.forEach(function (n) { indeg[n.id] = 0; });
      edges.forEach(function (e) { if (!e.tg && indeg[e.to] != null && indeg[e.from] != null) indeg[e.to]++; });
      const q = nodes.filter(function (n) { return !indeg[n.id]; }).map(function (n) { return n.id; });
      const dep = {};
      nodes.forEach(function (n) { dep[n.id] = 0; });
      let guard = 0;
      while (q.length && guard++ < 4000) {
        const x = q.shift();
        edges.forEach(function (e) {
          if (e.tg || e.from !== x) return;
          if (dep[e.to] < dep[x] + 1) dep[e.to] = dep[x] + 1;
          indeg[e.to]--;
          if (indeg[e.to] <= 0) q.push(e.to);
        });
      }
      nodes.forEach(function (n) { rank[n.id] = dep[n.id] || 0; });
    } catch (e) { /* 图异常时按空排名继续，调度仍可产出计划 */ }
    const list = ds.slice(0).sort(function (a, b) {
      const ra = rank[a.from] || 0, rb = rank[b.from] || 0;
      if (ra !== rb) return ra - rb;
      if (opts.course) {
        const ca = (courseOf(a.from) === opts.course) ? 0 : 1;
        const cb = (courseOf(b.from) === opts.course) ? 0 : 1;
        if (ca !== cb) return ca - cb;
      }
      return (b.imp || 0) - (a.imp || 0);
    });
    const firstDay = {};
    const MINS = (budget >= 35) ? [[12, 12], [10, 10], [8, 8]] : [[10, 10], [8, 8], [8, 8]];
    list.slice(0, maxDebts).forEach(function (d, di) {
      let prev = 0, ok = true, tot = 0;
      for (let r = 0; r < rounds && ok; r++) {
        const off = (offsets[r] != null) ? offsets[r] : (r * 2);
        for (let step = 0; step < 2 && ok; step++) {
          const isCore = (step === 0);
          const kp = isCore ? d.from : d.to;
          let md = Math.max(1 + off, prev + 1);
          if (!isCore && firstDay[d.from] != null) md = Math.max(md, firstDay[d.from] + 1);
          try {
            (prereqsOf(kp) || []).forEach(function (pr) {
              if (firstDay[pr] != null && firstDay[pr] + 1 > md) md = firstDay[pr] + 1;
            });
          } catch (e) { /* 先修查询失败不阻断本条排程 */ }
          const m = (MINS[r] || [8, 8])[isCore ? 0 : 1];
          const day = findDay(kp, m, md);
          if (day < 0) { ok = false; break; }
          place(kp, m, day);
          entries.push({ d: d, di: di, r: r, kind: isCore ? "core" : "challenge", day: day, min: m, rdP: rounds });
          if (firstDay[kp] == null || day < firstDay[kp]) firstDay[kp] = day;
          prev = day; tot++;
        }
      }
      if (!ok || tot === 0) {
        deferred.push({ from: d.from, to: d.to, reason: (tot ? "部分轮次延后（日预算已满）" : "本轮未排入（预算已满）") });
      }
    });
    list.slice(maxDebts).forEach(function (d) {
      deferred.push({ from: d.from, to: d.to, reason: "本轮未排入（优先级靠后，下轮再排）" });
    });
    entries.sort(function (a, b) { return a.day - b.day || a.di - b.di || (a.kind === "core" ? 0 : 1); });
    let id = 0;
    const items = entries.map(function (e) {
      id++;
      return {
        id: id, day: e.day, kp: (e.kind === "core" ? e.d.from : e.d.to), layer: (e.kind === "core" ? "core" : "challenge"),
        st: "todo", min: e.min, fromKp: e.d.from, rd: e.r,
        label: label(e.d, e.kind, e.r), why: why(e.d, e.kind, e.r, e.min, e.rdP)
      };
    });
    try { fixK2(items, bins, budget, edges, offsets); } catch (e) { /* 重排失败不阻断计划产出，与页面原实现一致 */ }
    items.sort(function (a, b) { return a.day - b.day || a.id - b.id; });
    items.forEach(function (p, i) { p.id = i + 1; });
    return { items: items, deferred: deferred, rounds: rounds };
  }

  /** 超预算减压：先按比例压缩时长，再顺延，最后丢弃。 */
  function reliefDays(items, budget, repairs) {
    const byDay = {};
    items.forEach(function (p) { if (!byDay[p.day]) byDay[p.day] = []; byDay[p.day].push(p); });
    Object.keys(byDay).forEach(function (dk) {
      const list = byDay[dk];
      let sum = list.reduce(function (a, p) { return a + p.min; }, 0);
      if (sum <= budget) return;
      let ch = false;
      list.forEach(function (p) {
        const np = Math.max(8, Math.round(p.min * budget / sum));
        if (np !== p.min) { p.min = np; ch = true; }
      });
      if (ch) repairs.push("D" + dk + " 超预算：时长按比例压缩");
      sum = list.reduce(function (a, p) { return a + p.min; }, 0);
      if (sum <= budget) return;
      for (let i = list.length - 1; i >= 0 && sum > budget; i--) {
        const p = list[i];
        let moved = false;
        for (let nd = p.day + 1; nd <= 14; nd++) {
          const tl = byDay[nd] || [];
          const tsum = tl.reduce(function (a, q) { return a + q.min; }, 0);
          const clash = tl.some(function (q) { return q.kp === p.kp; });
          if (!clash && tsum + p.min <= budget) {
            p.day = nd; tl.push(p); byDay[nd] = tl; sum -= p.min; moved = true;
            repairs.push("顺延 1 条至 D" + nd + "（预算缓冲）");
            break;
          }
        }
        if (!moved) { p._drop = true; sum -= p.min; repairs.push("丢弃 1 条超额任务（预算排不下）"); }
      }
    });
    for (let j = items.length - 1; j >= 0; j--) { if (items[j]._drop) items.splice(j, 1); }
  }

  return {
    goldenScore: goldenScore,
    checkPlanK: checkPlanK,
    schedule: schedule,
    moveNode: moveNode,
    fixK2: fixK2,
    reliefDays: reliefDays
  };
});
