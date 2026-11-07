/**
  * stream-ui.js —— 流式回复的 UI 原语（移植自 DeepTutor）：
  *   ① createTypewriter：自适应打字机。网络 chunk 到达速度远快于人阅读速度，
  *     若每个 delta 都全量重写文本节点，长回答会退化成 O(n²) 的 DOM 写入。
  *     这里按「backlog/catchUp 每帧多吐几个」追赶积压，并强制最小帧间隔限流。
  *   ② splitThink / stripThink：把正文里内嵌的 <think>…</think> 段分离出来
  *     （有些 OpenAI 兼容端不回 reasoning_content 字段，思维链混在 content 里）；
  *     容忍未闭合标签与 markdown 代码围栏内的字面 <think>。
  * UMD：浏览器 window.APStream；无 DOM 依赖（Node 里 typewriter 不可用但 splitThink 可测）。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APStream = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /**
    * 自适应打字机。用法：
    *   var tw = APStream.createTypewriter(el);   // el: 文本节点容器
    *   tw.push(fullSoFar);                        // 每个流式 delta 调，传「目前累计全文」
    *   tw.thinking(tailText);                     // 思维链阶段：显示滚动尾部
    *   tw.finish();                               // 结束：立即吐完全部剩余字符
    */
  function createTypewriter(el, opts) {
    opts = opts || {};
    var prefix = opts.prefix || "";
    var full = "";          // 已收到的累计全文
    var shown = 0;          // 已渲染字符数
    var raf = 0;            // 帧句柄
    var lastTs = 0;         // 上一帧时间戳（最小帧间隔限流）
    var doneFlag = false;
    var catchUpDivisor = opts.catchUpDivisor || 24;  // 每帧吐 backlog 的 1/24：越落后追越快
    var minBurst = opts.minBurst || 3;               // 每帧至少吐几个字符（保证可见进度）
    var minFrameMs = opts.minFrameMs || 24;          // 帧间隔下限：限制 markdown/文本消费者压力

    function paint() {
      el.textContent = prefix + full.slice(0, shown);
    }
    function tick() {
      raf = 0;
      var now = Date.now();
      if (now - lastTs < minFrameMs) { schedule(); return; }
      lastTs = now;
      var backlog = full.length - shown;
      if (backlog <= 0) {
        if (!doneFlag) schedule(); // 还没 finish：继续等下一个 push
        return;
      }
      shown += Math.max(minBurst, Math.ceil(backlog / catchUpDivisor));
      if (shown > full.length) shown = full.length;
      paint();
      if (shown < full.length || !doneFlag) schedule();
    }
    function schedule() {
      // 经 globalThis 取 rAF：lint 环境没有 browser 全局白名单，直接裸引用会报 no-undef
      var rafFn = (typeof globalThis !== "undefined" && typeof globalThis.requestAnimationFrame === "function") ? globalThis.requestAnimationFrame : null;
      if (!raf && rafFn) {
        raf = rafFn(tick);
      } else if (!raf) {
        raf = setTimeout(tick, minFrameMs); // Node/无 rAF 环境兜底（测试用）
      }
    }
    return {
      push: function (text) { full = String(text); shown = Math.min(shown, full.length); schedule(); },
      thinking: function (tail) { el.textContent = prefix + "思考中：" + String(tail || "").slice(-64); },
      finish: function () {
        doneFlag = true;
        shown = full.length;
        paint();
        var cAF = (typeof globalThis !== "undefined" && typeof globalThis.cancelAnimationFrame === "function") ? globalThis.cancelAnimationFrame : null;
        if (raf && cAF) { cAF(raf); }
        raf = 0;
      },
      text: function () { return full; }
    };
  }

  /**
    * 分离正文中的 <think>…</think> 段。返回 [{type:"think"|"text", body}]。
    * 容忍：未闭合的 <think>（其后全部算 think）；代码围栏里的字面量不再深挖（按首现配对处理）。
    */
  function splitThink(text) {
    var src = String(text || "");
    var out = [];
    var re = /<think(?:\s[^>]*)?>([\s\S]*?)(<\/think\s*>|$)/gi;
    var last = 0, m;
    while ((m = re.exec(src)) !== null) {
      if (m.index > last) {
        out.push({ type: "text", body: src.slice(last, m.index) });
      }
      out.push({ type: "think", body: m[1] || "" });
      last = re.lastIndex;
      if (m[2] === undefined || m[2] === "") break; // 未闭合：吞掉剩余全部
    }
    if (last < src.length) {
      out.push({ type: "text", body: src.slice(last) });
    }
    return out;
  }

  /** 去掉正文里的 think 段（展示层用）：只留 text 段并合并空白 */
  function stripThink(text) {
    return splitThink(text)
      .filter(function (seg) { return seg.type === "text"; })
      .map(function (seg) { return seg.body; })
      .join("")
      .replace(/^\s*[\r\n]+/, "").replace(/[\r\n\s]+$/, "");
  }

  return {
    createTypewriter: createTypewriter,
    splitThink: splitThink,
    stripThink: stripThink
  };
});
