/**
  * store.js —— 轻状态分片存 localStorage
  * ===========================================================
  * 以前整包轻状态塞在**一个** localStorage 键里（`astralpath_monolith_v2`），
  * 每次作答都要 JSON.stringify 全量再写回去，配额一爆就整包写失败。
  * 教材正文已经搬去 IndexedDB 了，这里把剩下的轻状态拆成分片：
 *
  * ap:meta      user / consent / optOut / activeBookId / day / userName / userTag
  *                / kgMode / onboard / planMeta / chat（+ 任何未知键兜底）
  * ap:books     books[]（章节骨架；大文本已在 IndexedDB，这里只留索引）
  * ap:answers   mastery / logs / debtExplain（作答与诊断，写最频繁）
  * ap:plan      plan / sale
  * ap:papers    papers[]（试卷作业识别结果）
 *
  * 好处：一次作答只重写 `ap:answers`（通常几 KB），不是几百 KB 的整包。
  * 迁移：第一次加载如果只看到旧单键，先备份到 `ap:backup:<ts>`，再写分片；
  * 分片写成功后才让调用方删旧键（回退路径一直留着）。
 *
  * 兼容：`ap:meta` 收留所有没登记的新键，所以调用方加字段**不会丢**。
  * 不做写入节流——作答即落盘是原来的持久性语义，节流会在关标签页时丢数据。
 *
  * UMD：浏览器 `window.APStore`，Node `require("./shared/store.js")`（verify_store.py 跑用例）。
  */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.APStore = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var VERSION = 2;
  var PARTS = ["meta", "books", "answers", "plan", "papers"];
  var SHARD_KEYS = {
    meta: "ap:meta",
    books: "ap:books",
    answers: "ap:answers",
    plan: "ap:plan",
    papers: "ap:papers",
  };
  var BACKUP_PREFIX = "ap:backup:";
  var SCHEMA_KEY = "ap:schema";
  var SCHEMA_VERSION = 2; // 分片布局 v2；未来布局变更在此登记迁移器

  // 每个分片「拥有」的状态键；未登记的键一律归 meta（保证新增字段不丢）
  var OWNER = {
    books: ["books"],
    answers: ["mastery", "logs", "debtExplain"],
    plan: ["plan", "sale"],
    papers: ["papers"],
  };
  var PART_OF = {};
  Object.keys(OWNER).forEach(function (p) {
    OWNER[p].forEach(function (k) { PART_OF[k] = p; });
  });

  /** 状态 → 分片对象（纯函数） */
  function pick(state) {
    var out = { meta: {}, books: {}, answers: {}, plan: {}, papers: {} };
    Object.keys(state || {}).forEach(function (k) {
      var p = PART_OF[k] || "meta";
      out[p][k] = state[k];
    });
    return out;
  }

  /** 分片对象 → 状态（纯函数）；books 缺失或为空时返回 null（视为无数据） */
  function merge(parts) {
    if (!parts || !parts.books || !Array.isArray(parts.books.books) || !parts.books.books.length) return null;
    var out = {};
    PARTS.forEach(function (p) {
      var o = parts[p] || {};
      Object.keys(o).forEach(function (k) { out[k] = o[k]; });
    });
    return out;
  }

  /** 读全部分片；hasShards 表示「至少有一个分片存在」。
    * 注意：JSON.parse("null") 不抛错但结果是 null，parse 成功≠数据可用，
   * 因此解析后还必须校验「非空对象」才算有效，否则记入 missing。 */
  function read(ls) {
    var parts = {}, missing = [], has = false;
    PARTS.forEach(function (p) {
      var raw = null, v = null;
      try { raw = ls.getItem(SHARD_KEYS[p]); } catch (e) { raw = null; }
      if (raw != null) {
        try { v = JSON.parse(raw); } catch (e) { v = null; }
        if (v === null || typeof v !== "object" || Array.isArray(v)) v = null;
      }
      if (v === null) { parts[p] = null; missing.push(p); return; }
      parts[p] = v;
      has = true;
    });
    return { hasShards: has, parts: parts, missing: missing };
  }

  /**
    * 写分片：只写**内容变化**的分片。
    * @param {object} ls      localStorage 兼容对象（getItem/setItem/removeItem）
    * @param {object} state   要落盘的状态（通常是 liteCopy 后的轻状态）
    * @param {object} [cache] 上次写入的 part→json 缓存，用于跳过未变更分片
    * @returns {{written:string[], failed:string[], cache:object, bytes:number, changed:boolean}}
    */
  function write(ls, state, cache) {
    var parts = pick(state);
    var written = [], failed = [], nc = {}, bytes = 0;
    PARTS.forEach(function (p) {
      var json;
      try { json = JSON.stringify(parts[p]); } catch (e) { json = "{}"; }
      bytes += json.length;
      var prev = cache ? cache[p] : undefined;
      if (prev === json) { nc[p] = json; return; }        // 未变更 → 跳过
      try {
        ls.setItem(SHARD_KEYS[p], json);
        written.push(p);
        nc[p] = json;
      } catch (e) {
        failed.push(p);
        if (prev !== undefined) nc[p] = prev;             // 保留旧缓存，下次重试
      }
    });
    return { written: written, failed: failed, cache: nc, bytes: bytes, changed: written.length > 0 };
  }

  /** 清空分片（重置用）；返回被删除的键 */
  function clear(ls) {
    var removed = [];
    PARTS.forEach(function (p) {
      try { ls.removeItem(SHARD_KEYS[p]); removed.push(SHARD_KEYS[p]); } catch (e) { /* 忽略：清空尽力而为 */ }
    });
    return removed;
  }

  /** 迁移备份：把旧单键原始串存到 ap:backup:<ts>，并只保留最新一份。
   * 键带毫秒时间戳，同毫秒内连续备份会撞键 → 先探测占用，冲突则追加序号。 */
  function backup(ls, raw) {
    var key = null;
    for (var attempt = 0; attempt < 64; attempt++) {
      var cand = BACKUP_PREFIX + Date.now() + (attempt === 0 ? "" : "-" + attempt);
      var exists = null;
      try { exists = ls.getItem(cand); } catch (e) { exists = null; }
      if (exists === null) { key = cand; break; }
    }
    if (key === null) return null;
    try {
      ls.setItem(key, raw);
      // 清理更早的备份（只留最新，避免备份本身撑爆配额）
      var stale = [];
      for (var i = 0; i < (ls.length || 0); i++) {
        var k = ls.key(i);
        if (k && k.indexOf(BACKUP_PREFIX) === 0 && k !== key) stale.push(k);
      }
      stale.forEach(function (k) { try { ls.removeItem(k); } catch (e) { /* 忽略 */ } });
      return key;
    } catch (e) {
      return null; // 备份失败不阻断迁移，但调用方不应删除旧键
    }
  }

  /** 丢弃迁移备份（配额吃紧时由调用方重试前调用；备份是冗余副本，删除不丢数据） */
  function dropBackups(ls) {
    var removed = [];
    try {
      var stale = [];
      for (var i = 0; i < (ls.length || 0); i++) {
        var k = ls.key(i);
        if (k && k.indexOf(BACKUP_PREFIX) === 0) stale.push(k);
      }
      stale.forEach(function (k) { try { ls.removeItem(k); removed.push(k); } catch (e) { /* 忽略 */ } });
    } catch (e) { /* 忽略：尽力而为 */ }
    return removed;
  }

  /** 读 schema 标记；v=0 表示无标记（老数据），v=-1 表示标记损坏 */
  function readSchema(ls) {
    try {
      var raw = ls.getItem(SCHEMA_KEY);
      if (raw == null) return { v: 0, ok: true };
      var v = JSON.parse(raw);
      if (typeof v !== "number" || v < 0) return { v: -1, ok: false };
      return { v: v, ok: true };
    } catch (e) { return { v: -1, ok: false }; }
  }

  function writeSchema(ls, v) {
    try { ls.setItem(SCHEMA_KEY, JSON.stringify(v)); return true; } catch (e) { return false; }
  }

  /**
    * 版本协商（每次加载调用，幂等）：
    * 无标记 → 补写当前版本（老数据首次进入带版本的存储）；
    * 标记损坏 → 重写标记（分片本体另有 repairIfCorrupt 兜底）；
    * 版本更新（降级打开）→ 不动数据，返回 downgrade 由调用方提示。
    * 未来 v3：在 MIGRATORS 登记迁移函数并在此逐级执行。
    */
  function ensureSchema(ls) {
    var s = readSchema(ls);
    if (s.ok && s.v === SCHEMA_VERSION) return { changed: false };
    if (s.ok && s.v > SCHEMA_VERSION) return { changed: false, downgrade: true };
    return { changed: writeSchema(ls, SCHEMA_VERSION), recovered: s.v === -1 };
  }

  /** 损坏自愈：解析失败的分片先备份原始串再移除，读路径随即退回缺片/默认；返回修复的分片名 */
  function repairIfCorrupt(ls) {
    var fixed = [];
    PARTS.forEach(function (p) {
      var raw = null;
      try { raw = ls.getItem(SHARD_KEYS[p]); } catch (e) { raw = null; }
      if (raw == null) return;
      var ok = true;
      try {
        var v = JSON.parse(raw);
        if (v === null || typeof v !== "object" || Array.isArray(v)) ok = false;
      } catch (e) { ok = false; }
      if (!ok) {
        backup(ls, raw);
        try { ls.removeItem(SHARD_KEYS[p]); fixed.push(p); } catch (e) { /* 尽力而为 */ }
      }
    });
    return fixed;
  }

  /** 配额预估（浏览器）；不可用时返回 null */
  function estimate() {
    try {
      if (!(navigator && navigator.storage && navigator.storage.estimate)) return Promise.resolve(null);
      return navigator.storage.estimate().then(function (e) {
        var usage = e && e.usage || 0, quota = e && e.quota || 0;
        return { usage: usage, quota: quota, ratio: quota ? usage / quota : 0 };
      }).catch(function () { return null; });
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  return {
    VERSION: VERSION,
    PARTS: PARTS,
    SHARD_KEYS: SHARD_KEYS,
    BACKUP_PREFIX: BACKUP_PREFIX,
    pick: pick,
    merge: merge,
    read: read,
    write: write,
    clear: clear,
    backup: backup,
    dropBackups: dropBackups,
    estimate: estimate,
    SCHEMA_KEY: SCHEMA_KEY,
    SCHEMA_VERSION: SCHEMA_VERSION,
    readSchema: readSchema,
    writeSchema: writeSchema,
    ensureSchema: ensureSchema,
    repairIfCorrupt: repairIfCorrupt,
  };
});
