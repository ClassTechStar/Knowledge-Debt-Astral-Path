/**
  * notify.js —— 页面内通知队列（借鉴 ClassIsland NotificationHost / ClassWidgets 双通道的最小子集）
  * ===========================================================
  * 目标：全站统一的通知出口。危机（转人工）最高级：置顶、常驻、响铃、免打扰下仍显示；
  * warn/info 走队列逐条播放、按 tag 去重；免打扰（演示模式）下 warn/info 静默。
  * UI 未就绪时通知进 pending 缓冲，mount() 后统一冲刷（借鉴 ClassWidgets 的 pending 队列）。
  * 纯 DOM textContent 渲染，不引入任何 HTML 拼接（XSS 门禁友好）。
  *
  * UMD：浏览器 window.APNotify；Node require（notify_runner.js 跑用例）。
  * Node 环境没有 DOM：push 会进 pending 并返回 {ok:true,queued:"pending"}，便于纯逻辑测试。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APNotify = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // UMD 包装层的 root 只在外层作用域，factory 里要自己取一次全局；
  // 之前直接写 root.AudioContext，ReferenceError 被 try 吞掉，响铃从来没响过。
  var GLOBAL = typeof self !== "undefined" ? self
    : (typeof window !== "undefined" ? window : null);

  var DWELL = { info: 4000, warn: 6500, crisis: 0 }; // 0 = 常驻，手动关闭
  var COLORS = { info: "#2f6fed", warn: "#b8860b", crisis: "#c0392b" };
  var TITLES = { info: "提示", warn: "注意", crisis: "重要提醒" };

  var queue = [];        // 待展示
  var showing = null;    // 当前展示中的通知
  var container = null;  // 右上角堆栈容器
  var pending = [];      // body 未就绪时的缓冲
  var dndProvider = function () { return false; };
  var seq = 0;

  function hasDOM() {
    try { return typeof document !== "undefined" && !!document.body; } catch (e) { return false; }
  }

  function ensureContainer() {
    if (container) return container;
    container = document.createElement("div");
    container.id = "ap-notify-stack";
    container.style.cssText = "position:fixed;top:14px;right:14px;z-index:99998;display:flex;flex-direction:column;gap:8px;max-width:340px";
    document.body.appendChild(container);
    return container;
  }

  /** 危机响铃：WebAudio 短促两声；失败静默（无手势/不支持时浏览器会拒绝） */
  function beep() {
    try {
      if (!GLOBAL) return;
      var AC = GLOBAL.AudioContext || GLOBAL.webkitAudioContext;
      if (!AC) return;
      var ctx = new AC();
      [0, 0.28].forEach(function (t) {
        var o = ctx.createOscillator(), g = ctx.createGain();
        o.frequency.value = 660; o.type = "sine";
        g.gain.setValueAtTime(0.12, ctx.currentTime + t);
        g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.2);
        o.connect(g); g.connect(ctx.destination);
        o.start(ctx.currentTime + t); o.stop(ctx.currentTime + t + 0.22);
      });
      setTimeout(function () { try { ctx.close(); } catch (e) { /* 忽略 */ } }, 900);
    } catch (e) { /* 响铃失败不阻断危机文案展示 */ }
  }

  function renderCard(n) {
    var card = document.createElement("div");
    card.style.cssText = "background:#fff;border:1px solid #d4d9de;border-left:4px solid " + (COLORS[n.level] || COLORS.info) +
      ";border-radius:10px;box-shadow:0 6px 20px rgba(0,0,0,.14);padding:10px 12px;font:13px/1.6 system-ui,sans-serif;color:#1e2228";
    var head = document.createElement("div");
    head.style.cssText = "font-weight:700;margin-bottom:2px";
    head.textContent = n.title || TITLES[n.level] || TITLES.info;
    var body = document.createElement("div");
    body.style.cssText = "color:#444a52;white-space:pre-wrap";
    body.textContent = n.msg || "";
    card.appendChild(head); card.appendChild(body);
    if (!DWELL[n.level]) { // 常驻通知给关闭按钮
      var x = document.createElement("button");
      x.textContent = "知道了";
      x.style.cssText = "margin-top:8px;padding:2px 12px;cursor:pointer";
      x.onclick = function () { dismiss(showing === n ? n : n); };
      card.appendChild(x);
    }
    return card;
  }

  function pump() {
    if (showing || !queue.length) return;
    var n = queue.shift();
    showing = n;
    if (!hasDOM()) { pending.push(n); showing = null; return; }
    n._el = renderCard(n);
    ensureContainer().appendChild(n._el);
    if (n.level === "crisis") beep();
    if (DWELL[n.level]) {
      n._timer = setTimeout(function () { dismiss(n); }, DWELL[n.level]);
    }
  }

  function dismiss(n) {
    if (n && n._timer) { clearTimeout(n._timer); n._timer = null; }
    if (n && n._el && n._el.parentNode) n._el.parentNode.removeChild(n._el);
    if (showing === n) showing = null;
    queue = queue.filter(function (q) { return q !== n; });
    pump();
  }

  /**
    * 推一条通知。
    * @param {{level?:string, title?:string, msg:string, tag?:string, force?:boolean}} opt
    *   level: info | warn | crisis（默认 info）；tag 相同的活动通知会被替换；force 跳过免打扰。
    * @returns {{ok:boolean, reason?:string, level?:string}}
    */
  function push(opt) {
    opt = opt || {};
    var level = opt.level === "warn" || opt.level === "crisis" ? opt.level : "info";
    if (level !== "crisis" && !opt.force && dndProvider()) {
      return { ok: false, reason: "dnd", level: level };
    }
    var n = { id: ++seq, level: level, title: opt.title, msg: String(opt.msg || ""), tag: opt.tag || null, ts: Date.now() };
    // 同 tag 替换：把旧的从缓冲/队列/展示里摘掉，只留最新
    if (n.tag) {
      queue = queue.filter(function (q) {
        if (q.tag === n.tag) { if (q._timer) clearTimeout(q._timer); return false; }
        return true;
      });
      pending = pending.filter(function (q) { return q.tag !== n.tag; });
      if (showing && showing.tag === n.tag) dismiss(showing);
    }
    if (!hasDOM()) { pending.push(n); return { ok: true, level: level, queued: "pending" }; }
    queue.push(n);
    pump();
    return { ok: true, level: level };
  }

  /** 页面就绪后冲刷 pending 缓冲 */
  function mount() {
    if (!hasDOM() || !pending.length) return;
    var buf = pending; pending = [];
    buf.forEach(function (n) { queue.push(n); });
    pump();
  }

  function setDndProvider(fn) { dndProvider = typeof fn === "function" ? fn : function () { return false; }; }

  /** 测试辅助：清空全部状态 */
  function _reset() {
    queue.forEach(function (q) { if (q._timer) clearTimeout(q._timer); });
    queue = []; pending = []; showing = null;
    if (container && container.parentNode) container.parentNode.removeChild(container);
    container = null;
  }

  return {
    push: push,
    mount: mount,
    setDndProvider: setDndProvider,
    _reset: _reset,
    _state: function () { return { queued: queue.length, showing: showing ? showing.level : null, pending: pending.length }; },
  };
});
