/**
  * cat-diagnosis.js —— 冷启动认知诊断（CAT 式选题）
  * ===========================================================
  * 为什么：新用户没有作答记录，债务诊断只能靠顺序答题慢慢积累证据——
  * 题量花在「本来就强」的知识点上，定位欠债又慢又不准。本模块按
  * 「当前知识态向量」选**信息量最大**的下一题：目标选在掌握估计贴近
  * 判定边界的知识点（p≈0.5 时 Fisher 信息最大），一次作答就能把
  * 「欠债 / 不欠债」的分类定下来；强知识点一答即出线，不再浪费题量。
  *
  * 机制（确定性纯函数，金样 runner 用合成真值验证「一半题量同等精度」）：
  *   · 信息量 I = slope²·p·(1-p)，p = σ((est-d)·slope)：est 越贴近题难度越高；
  *   · 未确信加成：作答越少的知识点信息权重大（×1/(1+n)）；
  *   · 更新：est 向作答结果做对数几率漂移，且永不触顶（保留翻案余地）；
  *   · 停测：预算用尽，或全部知识点已定线（估强即出线，估弱需 ≥2 次证据）；
  *   · 诊断：欠债候选 = est<0.5 且 ≥2 次作答——一次噪声不误判。
  *
  * 知识态向量从既有作答日志推导（stateFrom），不新增状态字段；
  * rng 可注入：页面传 Math.random，金样传定序随机。
  *
  * UMD：浏览器 `window.APCat`，Node `require("./shared/cat-diagnosis.js")`。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APCat = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var SLOPE = 6;        // 响应曲线陡度（与页面判分模型同量级）
  var DRIFT = 1.2;      // 每次作答的对数几率漂移幅度（一答即可拉开明显对错）
  var BAND = 0.15;      // 不确定带：|est-0.5| ≤ BAND 视为「还没定下来」
  var DEFAULT_BUDGET = 24; // 冷启动诊断默认题量上限

  /** 从作答日志推导知识态向量：{ kp: { est, n, correct } }（Jeffreys 收缩）。 */
  function stateFrom(logs, kps) {
    var st = {};
    (kps || []).forEach(function (k) { st[k] = { est: 0.5, n: 0, correct: 0 }; });
    (logs || []).forEach(function (e) {
      if (!e || !e.kp) return;
      if (!st[e.kp]) st[e.kp] = { est: 0.5, n: 0, correct: 0 };
      var s = st[e.kp];
      s.n++;
      if (e.ok) s.correct++;
      s.est = (s.correct + 1) / (s.n + 2); // 后验均值，向 0.5 收缩
    });
    return st;
  }

  /** Fisher 信息：p(1-p)×slope²，p=σ((est-d)·slope)。est 越贴近难度信息越大。 */
  function information(est, difficulty) {
    var p = 1 / (1 + Math.exp(-SLOPE * (est - difficulty)));
    return SLOPE * SLOPE * p * (1 - p);
  }

  /**
   * 选信息量最大的下一题。
   * @param {object} state  知识态向量（stateFrom 产物）
   * @param {Array}  items  候选题：{id, kp, difficulty}（difficulty∈[0,1]）
   * @param {function} [rng] 随机源（同分破序用），默认 Math.random
   * @returns 选中的 item；候选为空返回 null
   */
  function pickNext(state, items, rng) {
    if (!items || !items.length) return null;
    var rand = rng || Math.random;
    var best = null, bestScore = -1, tie = 0;
    items.forEach(function (it) {
      var s = state[it.kp] || { est: 0.5, n: 0 };
      var score = information(s.est, it.difficulty == null ? 0.5 : it.difficulty) / (1 + s.n);
      if (score > bestScore + 1e-12) { best = it; bestScore = score; tie = 1; }
      else if (Math.abs(score - bestScore) <= 1e-12) {
        tie++;
        if (rand() < 1 / tie) best = it; // 同分均匀破序，可注入 rng 复现
      }
    });
    return best;
  }

  /** 作答更新：对数几率漂移，est 永不触顶（0.02~0.98），n 累计。 */
  function update(state, kp, correct) {
    if (!state[kp]) state[kp] = { est: 0.5, n: 0, correct: 0 };
    var s = state[kp];
    var logit = Math.log(s.est / (1 - s.est)) + (correct ? DRIFT : -DRIFT);
    s.est = 1 / (1 + Math.exp(-logit));
    if (s.est > 0.98) s.est = 0.98;
    if (s.est < 0.02) s.est = 0.02;
    s.n++;
    if (correct) s.correct++;
    return s;
  }

  /** 是否停测：预算用尽，或全部知识点已定线——
    * 未作答不算定线；一答明显出线（est ≥ 0.5+BAND）即可定强；估弱需 ≥2 次证据。 */
  function shouldStop(state, used, budget) {
    if (used >= (budget || DEFAULT_BUDGET)) return true;
    var kps = Object.keys(state);
    if (!kps.length) return false;
    return kps.every(function (k) {
      var s = state[k];
      return s.n >= 2 || (s.n >= 1 && s.est >= 0.5 + BAND);
    });
  }

  /** 诊断输出：欠债候选 = est < 0.5 且至少 2 次作答（一两次噪声不误判），可疑度升序。 */
  function diagnose(state) {
    return Object.keys(state)
      .filter(function (k) { return state[k].est < 0.5 && state[k].n >= 2; })
      .sort(function (a, b) { return state[a].est - state[b].est; });
  }

  return {
    SLOPE: SLOPE,
    DRIFT: DRIFT,
    BAND: BAND,
    DEFAULT_BUDGET: DEFAULT_BUDGET,
    stateFrom: stateFrom,
    information: information,
    pickNext: pickNext,
    update: update,
    shouldStop: shouldStop,
    diagnose: diagnose,
  };
});
