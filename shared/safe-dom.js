/**
  * safe-dom.js —— 内容进 DOM 前的唯一安全出口
  * ===========================================================
  * 模型输出和用户上传的教材内容都会进 DOM；以前 esc()/sanitizeText() 分散在各处、
  * 用法不一致（集成脚本里 `innerHTML = '…' + esc(...)` 和裸插并存）。
  * 这里收敛成**唯一安全出口**：
 *
  * esc(t)           纯文本转义（等价于现有 esc，行为保持逐字一致）
  * safeRich(text)   白名单富文本渲染：仅 <b><i><code><br><strong><em> 保留，
  * 其余（含任何带属性的标签）一律转义
  * setText(el, t)   文本优先写入（textContent）
  * setHTML(el, t)   富文本写入，内部强制过 safeRich
  * sanitizeUrl(u)   URL 白名单：只放行 http/https/mailto，其余返回 about:blank
 *
  * 几个约束：
  * 1. 零依赖，浏览器和 Node 都能加载（Node 侧给 verify_xss.py 跑用例）；
  * 2. 不引 DOMPurify 之类第三方（单文件形态，18MB 已经不小了）；
  * 3. 行为和原来的 esc() 逐字一致，替换点不产生视觉差异。
 *
  * ⚠ 这个文件可以改，但改完必须跑：
  * python scripts/verify_xss.py   （contracts/golden/xss-cases.json 12 例）
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APSafe = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // 注意：esc 保持「自包含」——映射表内联在函数体内，不依赖模块级变量。
  // 这样 scripts/gen_frontend_regions.py 可以按符号把单个函数抽进 index.html
  // 的生成区（页面作用域里没有 ESC_MAP），行为与旧内联实现逐字一致。
  /** 纯文本转义：与 index.html 内 esc() 逐字一致 */
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // 白名单标签：正则只允许**无属性**的开闭标签；<b onclick=…> 这类不会被匹配，
  // 因而整段被转义（属性是 XSS 的主要载体，故一律拒绝）
  var ALLOWED_TAG = /<\s*\/?\s*(b|i|code|br|strong|em)\s*\/?\s*>/gi;

  /** 白名单富文本渲染：除白名单标签外全部转义 */
  function safeRich(text) {
    var s = String(text == null ? "" : text);
    var out = "", last = 0, m;
    ALLOWED_TAG.lastIndex = 0;
    while ((m = ALLOWED_TAG.exec(s)) !== null) {
      out += esc(s.slice(last, m.index));
      var tag = m[0].replace(/\s+/g, "").toLowerCase();
      // <br/> → <br>；其余保持原样（<b>、</b>、<code>…）
      if (tag === "<br/>") tag = "<br>";
      out += tag;
      last = m.index + m[0].length;
    }
    out += esc(s.slice(last));
    return out;
  }

  /** 文本优先写入：永远不解析 HTML */
  function setText(el, t) {
    if (!el) return;
    el.textContent = String(t == null ? "" : t);
  }

  /** 富文本写入：强制过 safeRich，杜绝裸插 */
  function setHTML(el, t) {
    if (!el) return;
    el.innerHTML = safeRich(t);
  }

  /** 富文本片段生成：拼模板时用它替代手工 esc 拼接 */
  function rich(t) { return safeRich(t); }

  /** URL 白名单：阻断 javascript: / data:text-html 等协议级注入 */
  function sanitizeUrl(u) {
    var s = String(u == null ? "" : u).trim();
    if (/^(https?:|mailto:)/i.test(s)) return s;
    if (/^(\/|\.\/|\.\.\/|#)/.test(s)) return s; // 站内相对路径
    return "about:blank";
  }

  return {
    esc: esc,
    safeRich: safeRich,
    rich: rich,
    setText: setText,
    setHTML: setHTML,
    sanitizeUrl: sanitizeUrl,
  };
});
