/**
  * question-exposure.js —— 题目曝光控制与降温
  * ===========================================================
  * 为什么要有这个模块：销账要求「累计 ≥3 次作答 + 连续 2 次达标」，而内置题池
  * 每个知识点只有 2~5 道题。纯随机选题会让同一题反复出现——学生记住的是题面
  * 而不是知识，retention / streak 度量被重复曝光污染，销账判定也跟着失真。
  *
  * 机制（确定性纯函数，金样 runner 定序验证）：
  *   · 降温权重 w = 1/(1 + DECAY·shown)：一道题曝光越多，再被选中的概率越低；
  *   · 冷却：最近 COOLDOWN 次展示过的题直接出局，杜绝「换一题又换回来」；
  *   · 兜底：候选全部在冷却中时放开冷却按权重选，但刚出过的题仍让位——
  *     宁可隔一轮也不连发同题；单候选例外（练习不断题优先），绝不返回空；
  *   · 修剪：shown 计数超过 PRUNE_CAP 时先删低频条目，轻状态不撑爆配额。
  *
  * rng 可注入：页面传 Math.random，金样 runner 传定序随机（同一选择序列可复现）。
  * 曝光状态挂在业务状态的 `exposure` 字段（默认值已登记 shared/store.js 的 DEFAULTS，
  * 归 answers 分片落盘），形态为 { shown: {qid:次数}, recent: [qid,…] }。
  *
  * UMD：浏览器 `window.APExposure`，Node `require("./shared/question-exposure.js")`。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APExposure = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var DECAY = 0.6;       // 降温斜率：第 n 次曝光的权重 ≈ 1/(1+0.6n)
  var COOLDOWN = 4;      // 最近 4 次展示过的题不再出（约一轮小练习内不重复）
  var RECENT_CAP = 8;    // recent 环保留双倍冷却窗口，够兜底判断即可
  var PRUNE_CAP = 500;   // shown 条目上限：题库 + AI 题长期累积的硬顶

  /** 形状归一：把任意历史形态的 exposure 升级成 {shown,recent}，缺失则新建。 */
  function ensure(state) {
    if (!state || typeof state !== "object") return { shown: {}, recent: [] };
    var e = state.exposure;
    if (!e || typeof e !== "object" || Array.isArray(e) || !e.shown || typeof e.shown !== "object" || !Array.isArray(e.recent)) {
      e = { shown: {}, recent: [] };
      state.exposure = e;
    }
    return e;
  }

  /** 记一次曝光：shown 计数 +1，recent 压栈并截断。 */
  function record(state, qid) {
    if (!qid) return null;
    var e = ensure(state);
    e.shown[qid] = (e.shown[qid] || 0) + 1;
    e.recent.push(qid);
    if (e.recent.length > RECENT_CAP) e.recent.splice(0, e.recent.length - RECENT_CAP);
    prune(e);
    return e;
  }

  /** 修剪：条目超上限时丢掉曝光最少的（低频条目丢了也无所谓，重新累计即可）。 */
  function prune(e) {
    var keys = Object.keys(e.shown);
    if (keys.length <= PRUNE_CAP) return;
    keys.sort(function (a, b) { return e.shown[a] - e.shown[b]; });
    var drop = keys.length - PRUNE_CAP;
    for (var i = 0; i < drop; i++) delete e.shown[keys[i]];
  }

  /** 降温权重：曝光 0 次为 1，单调递减，永不归零（永远还有机会再出）。 */
  function weightOf(shown) {
    return 1 / (1 + DECAY * (shown || 0));
  }

  /**
   * 加权选一题并记一次曝光（被选中即曝光）。
   * @param {Array} candidates 候选题（元素可为字符串 id 或带 id 字段的对象）
   * @param {object} state     业务状态（用其 exposure 字段）
   * @param {function} [rng]   随机源，默认 Math.random
   * @returns 选中的候选题；候选为空返回 null
   */
  function pick(candidates, state, rng) {
    if (!candidates || !candidates.length) return null;
    var rand = rng || Math.random;
    var e = ensure(state);
    var idOf = function (c) { return (c && typeof c === "object") ? c.id : c; };

    // 冷却过滤：recent 内的出局
    var pool = candidates.filter(function (c) { return e.recent.indexOf(idOf(c)) < 0; });
    if (!pool.length) {
      // 全冷却兜底：放开窗口，但刚出过的那题仍让位——宁可隔一轮，不连发同题；
      // 单候选时无处让位，只能出它（练习不断题优先）。
      var last = e.recent.length ? e.recent[e.recent.length - 1] : null;
      pool = candidates.filter(function (c) { return idOf(c) !== last; });
      if (!pool.length) pool = candidates.slice();
    }

    var weights = pool.map(function (c) { return weightOf(e.shown[idOf(c)]); });
    var total = 0;
    for (var i = 0; i < weights.length; i++) total += weights[i];
    var r = rand() * total;
    var acc = 0;
    for (var j = 0; j < pool.length; j++) {
      acc += weights[j];
      if (r < acc) { record(state, idOf(pool[j])); return pool[j]; }
    }
    record(state, idOf(pool[pool.length - 1]));
    return pool[pool.length - 1];
  }

  return {
    DECAY: DECAY,
    COOLDOWN: COOLDOWN,
    RECENT_CAP: RECENT_CAP,
    PRUNE_CAP: PRUNE_CAP,
    ensure: ensure,
    record: record,
    prune: prune,
    weightOf: weightOf,
    pick: pick,
  };
});
