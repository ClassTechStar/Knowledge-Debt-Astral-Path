/**
  * app-glue.js —— 页面装配层：通知 / 计划运行时 / 临时调整 / 免打扰 / 壳桥接
  * ===========================================================
  * 本文件由 scripts/gen_frontend_regions.py 内联进 index.html 末尾生成区。
  * 为什么放在页面最末：它引用 S / save / renderToday 等页面全局，
  * 也需要在 DOM 就绪后挂钩按钮；作为最后一段脚本执行最稳。
  * 原则：只装配不改业务——计划状态、K 合约、公式都不在这里。
  */
(function () {
  "use strict";
  function $(id) { return document.getElementById(id); }

  /* ── 通知装配：免打扰跟随 S.dnd（演示模式）── */
  if (window.APNotify) {
    APNotify.setDndProvider(function () { return !!S.dnd; });
    APNotify.mount();
  }

  /* ── 存储版本与自愈（store.js T1）：版本标记 + 损坏分片修复 ── */
  try {
    // ── 云端调用显式同意（威胁模型 T10：授权粒度）──────────────────
  // 默认关闭（fail-closed）：不勾就不出网，与「配了密钥即同意」彻底分开。
  // 持久化在 ap:meta.cloudOptIn（store.js 的 meta 收留未知键，不会丢）；
  // 这里用同步标志 window.__AP_CLOUD_OPTIN__ 供出口守卫读取，避免守卫里做异步。
  var AP_CLOUD_LS = "ap:cloudOptIn";
  window.APCloudConsent = {
    get: function () {
      try { return window.localStorage.getItem(AP_CLOUD_LS) === "1"; } catch (e) { return false; }
    },
    set: function (on) {
      try {
        if (on) window.localStorage.setItem(AP_CLOUD_LS, "1");
        else window.localStorage.removeItem(AP_CLOUD_LS);
      } catch (e) {}
      window.__AP_CLOUD_OPTIN__ = !!on;
      try { if (window.__AP_ON_CLOUD_CONSENT__) window.__AP_ON_CLOUD_CONSENT__(!!on); } catch (e) {}
    },
    sync: function () { window.__AP_CLOUD_OPTIN__ = this.get(); return this.get(); }
  };
  window.APCloudConsent.sync();

  // ── 吊销清单离线更新（威胁模型 T8）────────────────────────────
  // 内置 __AP_REVOKED__（随版本发布）+ 用户离线导入的清单（localStorage）合并。
  // 不改源码、不重新构建即可吊销被盗/误发的密钥信封（按 env.kid 匹配）。
  var AP_REVOKE_LS = "ap:revokedKids";
  window.APRevoked = {
    load: function () {
      var extra = [];
      try {
        var raw = window.localStorage.getItem(AP_REVOKE_LS);
        if (raw) {
          var arr = JSON.parse(raw);
          if (Array.isArray(arr)) {
            for (var i = 0; i < arr.length; i++) if (arr[i]) extra.push(String(arr[i]));
          }
        }
      } catch (e) {}
      return extra;
    },
    /** 返回合并后的吊销清单（内置 + 离线导入，去重） */
    list: function () {
      var built = [];
      try { if (Array.isArray(window.__AP_REVOKED__)) built = window.__AP_REVOKED__.slice(); } catch (e) {}
      var extra = this.load(), out = [];
      function push(v) {
        var k = String(v).toLowerCase();
        for (var i = 0; i < out.length; i++) if (out[i] === k) return;
        out.push(k);
      }
      for (var i = 0; i < built.length; i++) push(built[i]);
      for (var j = 0; j < extra.length; j++) push(extra[j]);
      return out;
    },
    /** 导入离线吊销清单：JSON 数组（kid 字符串），返回条数；非法输入抛错 */
    import: function (text) {
      var arr = JSON.parse(String(text));
      if (!Array.isArray(arr)) throw new Error("清单必须是 JSON 数组");
      var clean = [];
      for (var i = 0; i < arr.length; i++) {
        var v = String(arr[i] == null ? "" : arr[i]).trim();
        if (!v) continue;
        if (!/^[a-z0-9_.:-]{1,128}$/i.test(v)) throw new Error("第 " + (i + 1) + " 项不是合法的密钥标识");
        clean.push(v);
      }
      try { window.localStorage.setItem(AP_REVOKE_LS, JSON.stringify(clean)); } catch (e) {}
      // 让 __apEnvRevoked 立即看到合并结果
      try {
        window.__AP_REVOKED__ = this.list();
      } catch (e) {}
      return clean.length;
    },
    clear: function () {
      try { window.localStorage.removeItem(AP_REVOKE_LS); } catch (e) {}
      try { window.__AP_REVOKED__ = this.list(); } catch (e) {}
    }
  };
  // 启动即合并，__apEnvRevoked 读 window.__AP_REVOKED__ 时自动生效
  try { window.__AP_REVOKED__ = window.APRevoked.list(); } catch (e) {}

  // ── 账户页 UI 自动接管（云同意 + 吊销清单）────────────────────
  // 绑定逻辑收在这里，页面只写 HTML、不留手写内联 JS（内联 JS 棘轮只许降不许涨）。
  window.APCloudUi = {
    render: function () {
      function $(id) { return document.getElementById(id); }
      var chk = $("chkCloud"), line = $("cloudLine"), rline = $("revokeLine");
      if (!chk) return;
      var on = window.APCloudConsent.get();
      chk.checked = !!on;
      if (line) {
        line.textContent = on ? "已授权：仅在开放问题且无危机/禁用词时调用云模型。" : "未授权：云端调用已禁用。";
        line.className = "status" + (on ? " ok" : "");
      }
      if (rline) {
        rline.textContent = "当前生效 " + window.APRevoked.list().length + " 条（内置 + 本地追加）。";
      }
    },
    bind: function () {
      var self = this;
      function $(id) { return document.getElementById(id); }
      var chk = $("chkCloud");
      if (!chk || chk.__apBound) return;
      chk.__apBound = true;
      chk.onchange = function () { window.APCloudConsent.set(this.checked); self.render(); };
      var imp = $("btnRevokeImport"), clr = $("btnRevokeClear"), rline = $("revokeLine");
      if (imp) imp.onclick = function () {
        try {
          var n = window.APRevoked.import($("revokeInput").value);
          $("revokeInput").value = "";
          self.render();
          if (rline) {
            rline.textContent = "已导入 " + n + " 条，当前生效 " + window.APRevoked.list().length + " 条。";
            rline.className = "status ok";
          }
        } catch (e) {
          if (rline) { rline.textContent = "导入失败：" + e.message; rline.className = "status err"; }
        }
      };
      if (clr) clr.onclick = function () { window.APRevoked.clear(); self.render(); };
      self.render();
    }
  };

  // 出口守卫装配（威胁模型 T10）：把危机词/禁用词拦截下沉到唯一网络出口，
  // 任何调用入口（生成/出题/对话）都不得把这类内容送出设备。
  // 词表来自 core.js 生成区（INTENTS/CRISIS/BANNED 由 tools/agent-intents.json 生成）。
  window.__AP_EGRESS_GUARD__ = function (text) {
    // 云端调用显式同意（T10）：未勾选一律不出网，fail-closed
    if (window.__AP_CLOUD_OPTIN__ !== true) return false;
    var core = window.APCore || null;
    if (!core) return true; // 词表未就绪：放行，装配本身由 verify_cloud_consent.py 门禁保证
    var t = String(text == null ? "" : text).toLowerCase();
    function hit(list) {
      if (!list || !list.length) return false;
      for (var i = 0; i < list.length; i++) {
        if (t.indexOf(String(list[i]).toLowerCase()) >= 0) return true;
      }
      return false;
    }
    return !hit(core.CRISIS) && !hit(core.BANNED);
  };

  var sc = APStore.ensureSchema(window.localStorage);
    if (sc && sc.downgrade) {
      APNotify.push({
        level: "warn", tag: "schema-downgrade", force: true,
        title: "数据来自更新版本",
        msg: "检测到本机数据由更高版本写入。已按只读方式加载，请勿在本版本覆盖保存重要进度。",
      });
    }
  } catch (e) { /* 版本检查失败不阻断启动 */ }

  /* ── 配额预警（每会话最多一次）── */
  var quotaWarned = false;
  try {
    APStore.estimate().then(function (r) {
      if (r && r.ratio > 0.85 && !quotaWarned) {
        quotaWarned = true;
        APNotify.push({
          level: "warn", tag: "quota",
          title: "本机存储接近上限",
          msg: "浏览器为网页分配的存储已用 " + Math.round(r.ratio * 100) + "%。建议到「账户」页导出进度后清理不再需要的教材。",
        });
      }
    }).catch(function () { /* 配额 API 不可用 */ });
  } catch (e) { /* 忽略 */ }

  /* ── 今日页运行时接入（快照状态条 / 临时调整 / 内置提醒）── */
  var lastSnap = null;

  function statusText(snap) {
    if (snap.paused) return "暂停中（临时调整生效）";
    if (snap.status === "behind") return "落后：有 " + snap.overdueCount + " 个过期任务待补";
    if (snap.status === "ahead") return "今日任务已全部完成";
    return "进度正常";
  }

  function paintStatus() {
    var host = $("todayStats");
    if (!host) return;
    var old = $("apPlanStatusLine");
    if (old) old.parentNode.removeChild(old);
    if (!lastSnap || !S.plan) return;
    var line = document.createElement("div");
    line.id = "apPlanStatusLine";
    line.style.cssText = "font-size:12px;color:var(--muted,#6b7077);margin:4px 0";
    line.textContent = "计划状态：" + statusText(lastSnap) +
      " · 已完成 " + lastSnap.doneItems + "/" + lastSnap.totalItems +
      " · 剩余约 " + lastSnap.remainMin + " 分钟" +
      (lastSnap.streak > 0 ? " · 连续 " + lastSnap.streak + " 天有进展" : "");
    host.parentNode.insertBefore(line, host);
  }

  function activeOverrides() {
    return (S.planOverrides || []).filter(function (o) {
      return !o.removed && S.day >= (o.startDay || 1) && S.day < (o.startDay || 1) + (o.days || 0);
    });
  }

  function paintOverrides() {
    var host = $("planOvBanner");
    if (!host) return;
    host.textContent = "";
    var act = activeOverrides();
    if (!act.length) { host.style.display = "none"; return; }
    host.style.display = "";
    var txt = document.createElement("span");
    txt.textContent = "临时调整生效中：" + act.map(function (o) {
      var left = (o.startDay || 1) + (o.days || 0) - S.day;
      return (o.type === "pause" ? "请假暂停" : "本周减半") + "（剩 " + left + " 天）";
    }).join("；") + "。结束后自动恢复原计划。";
    host.appendChild(txt);
    var btn = document.createElement("button");
    btn.className = "btn quiet";
    btn.style.cssText = "margin-left:8px;padding:2px 10px;min-height:24px;font-size:11px";
    btn.textContent = "立即恢复";
    btn.onclick = function () {
      S.planOverrides = (S.planOverrides || []).map(function (o) { o.removed = true; return o; });
      save(S);
      APNotify.push({ level: "info", title: "已恢复原计划", msg: "临时调整已全部取消，按原计划继续。" });
      afterToday();
    };
    host.appendChild(btn);
  }

  function fireAutomations() {
    if (!lastSnap) return;
    var now = Date.now();
    var msgs = APRuntime.evaluateAutomations(lastSnap, S.autoLast || {}, now);
    if (!msgs.length) return;
    S.autoLast = S.autoLast || {};
    msgs.forEach(function (m) {
      APNotify.push({ level: m.level, title: m.title, msg: m.msg, tag: m.key });
      S.autoLast[m.key === "relief" ? "relief" : "streakMilestone"] = m.key === "relief" ? now : lastSnap.streak;
    });
    save(S);
  }

  function afterToday() {
    try {
      if (typeof renderToday === "function") renderToday();
      lastSnap = S.plan ? APRuntime.computeSnapshot(S.plan, { day: S.day, overrides: S.planOverrides }) : null;
      paintStatus();
      paintOverrides();
      fireAutomations();
    } catch (e) { /* 运行时接入失败不影响原今日页 */ }
  }

  /* 重新挂钩今日页两个入口，在原有渲染后追加运行时快照 */
  try {
    $("btnLoadToday").onclick = function () { afterToday(); };
    $("btnDay").onclick = function () {
      S.day = Math.min(14, (S.day || 1) + 1);
      save(S);
      afterToday();
    };
    if (S.plan) afterToday();
  } catch (e) { /* 挂钩失败不影响原按钮 */ }

  /* ── 临时调整按钮（知债页 · 修复计划面板）── */
  try {
    function addOverride(type) {
      S.planOverrides = S.planOverrides || [];
      var ov = {
        id: "ov" + Date.now(),
        type: type,
        days: type === "pause" ? 3 : 7,
        startDay: S.day || 1,
        ratio: type === "relief" ? 0.5 : 1,
        createdAt: Date.now(),
      };
      S.planOverrides = S.planOverrides.filter(function (o) { return !o.removed; }).concat([ov]);
      save(S);
      APNotify.push({
        level: "info", tag: "override",
        title: type === "pause" ? "已请假暂停 3 天" : "本周任务已减半",
        msg: type === "pause"
          ? "暂停期间不提醒、不计入连续未完成。3 天后自动恢复原计划。"
          : "剩余任务时长按一半排入展示，跟上了随时可以「立即恢复」。",
      });
      afterToday();
    }
    var bp = $("btnOvPause"), br = $("btnOvRelief");
    if (bp) bp.onclick = function () { addOverride("pause"); };
    if (br) br.onclick = function () { addOverride("relief"); };
  } catch (e) { /* 忽略 */ }

  /* ── 免打扰（演示模式）开关 ── */
  try {
    var chk = $("chkDnd"), dndLine = $("dndLine");
    if (chk) {
      chk.checked = !!S.dnd;
      chk.onchange = function () {
        S.dnd = chk.checked;
        save(S);
        if (dndLine) dndLine.textContent = S.dnd
          ? "已开启：提醒与建议静音，仅保留危机提醒。"
          : "已关闭：正常提醒。";
        APNotify.push({
          level: "info", force: true,
          title: S.dnd ? "已进入免打扰" : "已退出免打扰",
          msg: S.dnd ? "演示与投影时不会再弹提醒；危机提醒仍然可见。" : "提醒恢复正常。",
        });
      };
      if (dndLine && S.dnd) dndLine.textContent = "已开启：提醒与建议静音，仅保留危机提醒。";
    }
  } catch (e) { /* 忽略 */ }

  /* ── Windows 壳桥（托盘 / 演示模式），页面功能在无壳环境全部可用 ── */
  window.__APShell = {
    toggleDnd: function () {
      var chk = $("chkDnd");
      if (chk) { chk.checked = !chk.checked; chk.onchange(); }
      return !!S.dnd;
    },
    todayRemaining: function () {
      try {
        if (!S.plan) return 0;
        var snap = APRuntime.computeSnapshot(S.plan, { day: S.day, overrides: S.planOverrides });
        return Math.max(0, snap.todayTotal - snap.todayDone);
      } catch (e) { return 0; }
    },
    openToday: function () {
      var btns = document.querySelectorAll('#nav button[data-p="today"]');
      if (btns && btns[0]) btns[0].click();
    },
  };
})();
