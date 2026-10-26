/**
  * agent-router.js —— 智能体规则路由：听懂用户想干什么
  * ===========================================================
  * 从 index.html 抽出来的路由逻辑：口语归一、危机/负例拦截、授权前置、
  * 章节阅读与图谱关系特判、锚点打分、敏感词脱敏。当前教材的节点/章节
  * 和意图表由调用方通过 ctx 传进来，这里不读 DOM、不读全局状态。
 *
  * 用法：
  * 浏览器：window.APAgent（由 scripts/gen_frontend_regions.py 内联进页面生成区）
  * Node  ：require("./shared/agent-router.js")
  */
(function (root, factory) {
  "use strict";
  var core = (typeof module === "object" && module.exports && typeof require === "function")
    ? require("./core.js") : null;
  var api = factory(core);
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APAgent = api;
})(typeof self !== "undefined" ? self : this, function (core) {
  "use strict";

  function baseNormalize(s) {
    if (core && core.normalize) return core.normalize(s);
    if (typeof globalThis !== "undefined" && typeof globalThis.normalize === "function") return globalThis.normalize(s);
    return String(s || "");
  }

  function normSpoken(s) {
    // T3 口语归一（纯前端）：啥→什么、咋→怎么、去空格，扩大口语/带空格输入的规则与 ONNX 命中面
    return String(s || "").replace(/啥/g, "什么").replace(/咋/g, "怎么")
      .replace(/嘞/g, "").replace(/咯/g, "").replace(/ /g, "");
  }

  function fuzzyAnchorConfirm(intentId, t, intents) {
    // T3 R5：ML 低置信候选的模糊关键词二次确认（纯前端）。
    // 对候选意图的锚点做"单字按序出现"子序列匹配，仅对 >=3 字锚点、覆盖率 >=0.7 的判定为确认
    var table = intents || (core && core.INTENTS) || [];
    var pair = (table || []).find(function (p) { return p[0] === intentId; });
    if (!pair) return "";
    var best = "", bestCov = 0;
    for (var k = 0; k < pair[1].length; k++) {
      var a = pair[1][k];
      if (a.length < 3) continue;
      var i = -1, cnt = 0;
      for (var c = 0; c < a.length; c++) {
        var j = t.indexOf(a.charAt(c), i + 1);
        if (j < 0) break;
        i = j; cnt++;
      }
      var cov = cnt / a.length;
      if (cov >= 0.7 && cov > bestCov) { bestCov = cov; best = a; }
    }
    return bestCov > 0 ? best + "[" + Math.round(bestCov * 100) + "%]" : "";
  }

  function sanitize(text, banned) {
    var list = banned || (core && core.BANNED) || [];
    var t = String(text || "");
    for (var i = 0; i < list.length; i++) {
      if (t.indexOf(list[i]) >= 0) return "这段内容暂时无法展示，请查看教材原文或联系老师。";
    }
    return t;
  }

  /**
    * 规则路由。ctx 可注入：
    * nodes/chapters  当前教材（图谱关系特判用）
    * intents/crisis/negative  意图与词表（页面侧传入，保持唯一事实源）
    * kgCn2Num        中文数字章节号解析
    */
  function route(t, ctx) {
    ctx = ctx || {};
    var intents = ctx.intents || (core && core.INTENTS) || [];
    var crisis = ctx.crisis || (core && core.CRISIS) || [];
    var negative = ctx.negative || (core && core.NEGATIVE) || [];
    var norm = normSpoken(baseNormalize(t));

    if (crisis.some(function (c) { return norm.indexOf(baseNormalize(c)) >= 0; }))
      return { id: "crisis.handoff", score: 1, decision: "crisis.handoff", trace: "R0:crisis" };

    // 负例判定和后端 AgentRouter v3 保持一致。
    // 原实现 includes 命中即整句判死 →「好的，帮我生成计划」会被吞成兜底话术（实测复现）。
    // 现要求负例占整句 ≥60% 才算客套话。
    var negHit = negative.map(baseNormalize).filter(function (c) { return c && norm.indexOf(c) >= 0; })
      .reduce(function (a, b) { return b.length > a.length ? b : a; }, "");
    if (negHit && norm.length > 0 && negHit.length / norm.length >= 0.6)
      return { id: "meta.help", score: 0, decision: "fallback", trace: "R2.5:negative;ratio=" + (negHit.length / norm.length).toFixed(2) };

    // 撤销、关闭这类否定说法要排在「授权」锚点前面，不然"撤销授权"会被误判成 grant
    var revokeDemo = /(撤销|取消|撤回|关闭|收回).{0,4}(授权|可见)/;
    if (revokeDemo.test(norm))
      return { id: "consent.revoke", score: 0.9, decision: "execute", trace: "R2.6:revoke-deny" };
    var grantDemo = /(同意|允许|开启|给).{0,4}(授权|可见)/;
    if (grantDemo.test(norm))
      return { id: "consent.grant", score: 0.9, decision: "execute", trace: "R2.6:grant-affirm" };

    // 必须能从图谱中解析出 >=2 个节点才执行，否则降级继续规则路由（避免误伤"我和你说"）
    var relQ = /(?:\u548c|\u4e0e|\u8ddf)[\u4e00-\u9fa5A-Za-z0-9]{1,12}(?:\u7684?\u5173\u7cfb|\u600e\u4e48?\u8054\u7cfb|\u6709\u4f55\u5173\u8054|\u6709\u6ca1\u6709\u5173|\u8def\u5f84|\u8c01\u5148|\u5148\u540e|\u524d\u7f6e|\u600e\u4e48\u5b66|\u600e\u4e48\u5230)/;
    if (relQ.test(norm)) {
      var ns0 = ctx.nodes || [];
      var cands = ns0.filter(function (n) {
        var tt = n.title || "";
        return tt.length >= 2 && norm.indexOf(baseNormalize(tt)) >= 0;
      });
      // P4.8 chapter-number mapping: "第一章和第二章有什么关系" -> chapter titles -> graph nodes
      if (cands.length < 2) {
        var m2 = norm.match(/第\s*([0-9一二三四五六七八九十百千]+)\s*[章节篇]\s*[和与跟、,，]\s*第\s*([0-9一二三四五六七八九十百千]+)\s*[章节篇]/);
        if (m2) {
          var chs = ctx.chapters || [];
          var cn = ctx.kgCn2Num;
          var i1 = cn ? cn(m2[1]) : (parseInt(m2[1], 10) || 0);
          var i2 = cn ? cn(m2[2]) : (parseInt(m2[2], 10) || 0);
          var c1 = chs[i1 - 1], c2 = chs[i2 - 1];
          if (c1 && c2 && c1.title && c2.title && c1.title !== c2.title) {
            var hit1 = ns0.some(function (n) { return n.title === c1.title || n.ch === i1 - 1; });
            var hit2 = ns0.some(function (n) { return n.title === c2.title || n.ch === i2 - 1; });
            if (hit1 && hit2) { cands.push({ title: c1.title }, { title: c2.title }); }
          }
        }
      }
      if (cands.length >= 2) return { id: "graph.path", score: 0.92, decision: "execute", trace: "R2.8:graph-path" };
    }

    // R2.7 书籍章节阅读：显式"第X章/节/篇"比 kb.search 更具体，优先直达
    var chRead = /(?:\u7b2c\s*)?[0-9\u4e00\u4e8c\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d\u5341\u767e\u5343]+\s*[\u7ae0\u8282\u7bc7\u8bb2\u5185\u5bb9]/;
    if (chRead.test(norm)) return { id: "chapter.read", score: 0.95, decision: "execute", trace: "R2.7:chapter-read" };

    var best = null, bestScore = 0, bestAnchor = "";
    for (var k = 0; k < intents.length; k++) {
      var id = intents[k][0], anchors = intents[k][1], hit = 0, anc = "";
      for (var a = 0; a < anchors.length; a++) {
        var aa = baseNormalize(anchors[a]);
        if (!aa) continue;
        if (norm.indexOf(aa) >= 0) {
          var s = 0.55 + Math.min(0.45, aa.length / 12);
          if (s > hit) { hit = s; anc = anchors[a]; }
        }
      }
      if (hit > bestScore) { bestScore = hit; best = id; bestAnchor = anc; }
    }
    if (best && bestScore >= 0.5)
      return { id: best, score: bestScore, decision: "execute", trace: "R3:anchor:" + bestAnchor + ";score=" + bestScore.toFixed(2) };
    return { id: "meta.help", score: 0, decision: "fallback", trace: "R6:fallback" };
  }

  return {
    normSpoken: normSpoken,
    fuzzyAnchorConfirm: fuzzyAnchorConfirm,
    sanitize: sanitize,
    route: route
  };
});
