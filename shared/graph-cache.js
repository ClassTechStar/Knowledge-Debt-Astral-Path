/**
  * graph-cache.js —— 图谱查询按修订号缓存（D1 算法优化）
  * ===========================================================
  * scoreOf / downMass / title / prereqs 四个热点函数原先各自独立计算，
  * 同一次诊断要重复做 O(E×V) 次递归与邻接表重建。本模块统一缓存，
  * 同一修订号内只算一遍 O(V+E)，save() → invalidate() 即失效。
  *
  * 边语义与页面一致：e.from / e.to；先修表（pre）排除 tg 引导边，
  * 下游邻接（adj）不过滤——与旧实现逐字段对齐，保证金样可对拍。
  *
  * 公式计算由调用方通过 computeScore 回调注入（依赖倒置——
  * 缓存层不知道 scoreV2 的实现细节），递归 Memoization 在此层统一管理。
  * 纯函数：edges/nodes/mastery 由调用方传入。
  *
  * UMD：浏览器 window.APGraphCache；Node require（graph_cache_runner.js 测正确性）。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APGraphCache = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var _graph = null;   // {adj, pre}：由 edges 构建（pre 过滤 tg 引导边）
  var _titles = null;  // {id: title}：由 nodes 构建
  var _scores = {};
  var _down = {};

  /** 修订号递增：save() / 切书 / 删书时调用，全部缓存一并失效 */
  function invalidate() {
    _graph = null;
    _titles = null;
    _scores = {};
    _down = {};
  }

  /** 邻接/先修表懒构建。tg 是引导边（非知识先修），只进下游量、不进先修链 */
  function ensureEdges(edges) {
    if (_graph) return;
    var adj = {}, pre = {};
    edges.forEach(function (e) {
      (adj[e.from] = adj[e.from] || []).push(e.to);
      if (!e.tg) (pre[e.to] = pre[e.to] || []).push(e.from);
    });
    _graph = { adj: adj, pre: pre };
  }

  /** 标题表懒构建。与邻接表分开缓存：downMass 只拿得到 edges，也能独立命中 */
  function ensureTitles(nodes) {
    if (_titles) return;
    _titles = {};
    nodes.forEach(function (n) { _titles[n.id] = n.title; });
  }

  /**
   * 递归得分（带跨调用缓存 + 环检测）。computeScore(m, pre) 由页面注入，
   * 返回 0..1 的掌握度值。同一修订号内相同 id 直接返回缓存——O(V+E)。
   */
  function scoreOf(id, edges, nodes, mastery, computeScore) {
    ensureEdges(edges);
    if (_scores[id] != null) return _scores[id];
    _scores[id] = 0.5; // 环检测：递归期间临时值，结束后覆写为真值
    var m = mastery[id] || { n: 0, s: 0, c: 3, age: 0, st: 0 };
    var pre = (_graph.pre[id] || []).map(function (pid) {
      return scoreOf(pid, edges, nodes, mastery, computeScore);
    });
    var v = computeScore(m, pre);
    _scores[id] = v;
    return v;
  }

  /** 下游 BFS 量（带缓存）；语义与旧实现一致：自身计入，仅当存在回环才含回边 */
  function downMass(id, edges) {
    ensureEdges(edges);
    if (_down[id] != null) return _down[id];
    var seen = {}, st = [id];
    while (st.length) {
      var x = st.pop();
      (_graph.adj[x] || []).forEach(function (y) {
        if (!Object.prototype.hasOwnProperty.call(seen, y)) { seen[y] = 1; st.push(y); }
      });
    }
    _down[id] = Object.keys(seen).length;
    return _down[id];
  }

  /** 标题查表（带缓存）；未知 id 回退为 id 本身 */
  function title(id, edges, nodes) {
    ensureTitles(nodes);
    if (_titles[id] != null) return _titles[id];
    _titles[id] = id;
    return id;
  }

  /** 先修列表（带缓存，已排除 tg 引导边） */
  function prereqs(id, edges) {
    ensureEdges(edges);
    return _graph.pre[id] || [];
  }

  /**
   * 债务扫描（D1 完成体）：公式件 scoreV2 / impactV2 / K 由页面注入，
   * 本层只做图遍历与缓存组装。返回按影响度降序、imp>0 的边列表。
   * freq 取该知识点历史错答次数（logs 形态 {kp, ok, ts}）。
   */
  function scanDebts(edges, nodes, mastery, logs, scoreV2, impactV2, K) {
    var wrongOn = {};
    (logs || []).forEach(function (l) {
      if (l && l.kp && !l.ok) wrongOn[l.kp] = (wrongOn[l.kp] || 0) + 1;
    });
    var cs = function (m, pre) { return scoreV2(m.n, m.s, m.c, m.age, m.st, pre); };
    return edges.map(function (e) {
      var sf = scoreOf(e.from, edges, nodes, mastery, cs);
      var st = scoreOf(e.to, edges, nodes, mastery, cs);
      var fr = wrongOn[e.to] > 0 ? wrongOn[e.to] : 0;
      var imp = impactV2(sf, st, e.w, e.tg, fr, downMass(e.to, edges));
      return { from: e.from, to: e.to, fromName: title(e.from, edges, nodes), toName: title(e.to, edges, nodes), sf: sf, st: st, imp: imp, freq: fr, status: imp >= K.hit ? "open" : "cleared" };
    }).filter(function (d) { return d.imp > 0; }).sort(function (a, b) { return b.imp - a.imp; });
  }

  return {
    invalidate: invalidate,
    scoreOf: scoreOf,
    downMass: downMass,
    title: title,
    prereqs: prereqs,
    scanDebts: scanDebts,
  };
});
