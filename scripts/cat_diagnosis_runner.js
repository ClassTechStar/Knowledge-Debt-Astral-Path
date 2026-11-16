/**
 * cat_diagnosis_runner.js —— shared/cat-diagnosis.js 用例（verify_all / CI 调用）
 * 覆盖：信息量峰值、未确信加成、更新/停测/诊断语义、日志推导，
 * 以及核心实验：CAT 式选题用显著少于顺序答题的题量达到同等诊断精度。
 * 随机源全部注入定序序列，结果可复现。
 */
"use strict";
const path = require("path");
const cat = require(path.resolve(__dirname, "..", "shared", "cat-diagnosis.js"));

const results = [];
function check(id, name, fn) {
  try {
    const detail = fn();
    results.push({ id, name, ok: true, detail: String(detail == null ? "ok" : detail) });
  } catch (e) {
    results.push({ id, name, ok: false, detail: String((e && e.message) || e) });
  }
}
function eq(a, b, what) {
  const sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error(`${what}: 期望 ${sb}，实际 ${sa}`);
}
function seq(values) {
  let i = 0;
  return () => (i < values.length ? values[i++] : 0.5);
}

check("QCAT-01", "信息量在 est=难度（p=0.5）处取峰，两侧衰减", () => {
  const peak = cat.information(0.5, 0.5);
  for (const est of [0.05, 0.2, 0.35, 0.65, 0.8, 0.95]) {
    if (!(cat.information(est, 0.5) < peak)) throw new Error(`est=${est} 信息量未低于峰值`);
  }
  eq(cat.information(0.2, 0.2), peak, "峰随难度平移");
  return `峰值 ${peak.toFixed(1)}`;
});

check("QCAT-02", "选题偏好未确信 + 贴近判定边界的知识点", () => {
  const state = {
    A: { est: 0.5, n: 0, correct: 0 },   // 全新，判定边界上
    B: { est: 0.5, n: 6, correct: 3 },  // 同样在边界但已答 6 次
    C: { est: 0.9, n: 1, correct: 1 },  // 已出线的强知识点
  };
  const items = [
    { id: "a", kp: "A", difficulty: 0.5 },
    { id: "b", kp: "B", difficulty: 0.5 },
    { id: "c", kp: "C", difficulty: 0.5 },
  ];
  const q = cat.pickNext(state, items, seq([]));
  eq(q.id, "a", "应选全新且在边界的 A");
  return "A > B(多答过) > C(已出线)";
});

check("QCAT-03", "核心实验：CAT 题量显著少于顺序答题，诊断精度不降", () => {
  // 真值：16 个知识点，4 个欠债（K02/K03/K09/K14）；每点 3 题的题池
  const allKps = [];
  for (let i = 1; i <= 16; i++) allKps.push("K" + String(i).padStart(2, "0"));
  const truth = new Set(["K02", "K03", "K09", "K14"]);
  const theta = (kp) => (truth.has(kp) ? 0.25 : 0.75);

  const items = [];
  for (const kp of allKps) {
    for (let j = 1; j <= 3; j++) items.push({ id: kp + "#" + j, kp, difficulty: 0.5 });
  }

  const f1 = (state) => {
    const pred = new Set(cat.diagnose(state));
    let tp = 0, fp = 0, fn = 0;
    for (const kp of allKps) {
      if (pred.has(kp) && truth.has(kp)) tp++;
      else if (pred.has(kp) && !truth.has(kp)) fp++;
      else if (!pred.has(kp) && truth.has(kp)) fn++;
    }
    const prec = tp + fp ? tp / (tp + fp) : 0;
    const rec = tp + fn ? tp / (tp + fn) : 0;
    return prec + rec ? (2 * prec * rec) / (prec + rec) : 0;
  };
  // 定序随机：按种子生成可复现的 [0,1) 序列
  const rngFor = (seed) => {
    let x = seed >>> 0;
    return () => {
      x = (x * 1664525 + 1013904223) >>> 0;
      return x / 4294967296;
    };
  };
  const fresh = () => {
    const st = {};
    allKps.forEach((k) => (st[k] = { est: 0.5, n: 0, correct: 0 }));
    return st;
  };
  const answer = (st, it, rng) => {
    const ok = rng() < 1 / (1 + Math.exp(-6 * (theta(it.kp) - 0.5))); // p=σ((θ-d)·6)
    cat.update(st, it.kp, ok);
  };

  let catTotal = 0, fixTotal = 0, catF1 = 0, fixF1 = 0;
  for (const seed of [3, 11, 29]) {
    // CAT：信息量选题 + 停测（题池 3 题/点，预算 24）
    const rng = rngFor(seed);
    const st = fresh();
    const pool = items.slice();
    let used = 0;
    while (!cat.shouldStop(st, used, cat.DEFAULT_BUDGET) && pool.length) {
      const it = cat.pickNext(st, pool, rng);
      pool.splice(pool.indexOf(it), 1);
      answer(st, it, rng);
      used++;
    }
    catTotal += used;
    catF1 += f1(st);

    // 顺序答题：预定诊断题表按序答满 2 轮（每点 2 题 = 32 题），无停测
    const rng2 = rngFor(seed);
    const st2 = fresh();
    const fixed = items.filter((it) => !it.id.endsWith("#3"));
    for (const it of fixed) answer(st2, it, rng2);
    fixTotal += fixed.length;
    fixF1 += f1(st2);
  }

  if (!(catF1 / 3 >= fixF1 / 3 - 0.02))
    throw new Error(`精度不保：CAT F1=${(catF1 / 3).toFixed(3)} < 顺序 ${(fixF1 / 3).toFixed(3)}`);
  if (!(catTotal / 3 <= 0.75 * (fixTotal / 3)))
    throw new Error(`题量没省下来：CAT ${(catTotal / 3).toFixed(1)} vs 顺序 ${fixTotal / 3}`);
  return `CAT ${(catTotal / 3).toFixed(1)} 题（F1 ${(catF1 / 3).toFixed(3)}）vs 顺序 ${fixTotal / 3} 题（F1 ${(fixF1 / 3).toFixed(3)}）`;
});

check("QCAT-04", "更新有界、停测与诊断语义", () => {
  const st = { A: { est: 0.5, n: 0, correct: 0 } };
  for (let i = 0; i < 30; i++) cat.update(st, "A", true);
  if (!(st.A.est <= 0.98 && st.A.est > 0.5)) throw new Error(`est 越界：${st.A.est}`);
  const st2 = {};
  for (let i = 0; i < 30; i++) cat.update(st2, "B", false);
  if (!(st2.B.est >= 0.02 && st2.B.est < 0.5)) throw new Error(`est 越界：${st2.B.est}`);

  const decided = { A: { est: 0.2, n: 2 }, B: { est: 0.8, n: 1 } }; // 弱者有 2 证 / 强者 1 答出线
  if (!cat.shouldStop(decided, 0, 100)) throw new Error("全部定线应停测");
  const undecided = { A: { est: 0.2, n: 1 }, B: { est: 0.8, n: 1 } }; // 弱候选证据不足
  if (cat.shouldStop(undecided, 0, 100)) throw new Error("仍有未定线不应停测");
  if (!cat.shouldStop(undecided, 100, 100)) throw new Error("预算用尽应停测");

  // 诊断要 ≥2 次证据：一次噪声不误判
  const diag = cat.diagnose({ A: { est: 0.3, n: 2 }, B: { est: 0.2, n: 3 }, C: { est: 0.7, n: 2 }, D: { est: 0.25, n: 1 } });
  eq(diag, ["B", "A"], "可疑度升序，且 n=1 的 D 不入列");
  return "语义通过";
});

check("QCAT-05", "日志推导知识态 + 空候选边界", () => {
  const logs = [
    { kp: "A", ok: true }, { kp: "A", ok: true }, { kp: "A", ok: false },
    { kp: "B", ok: false },
    { kp: null, ok: true }, // 脏日志不致崩
  ];
  const st = cat.stateFrom(logs, ["A", "B", "C"]);
  eq(st.A.n, 3, "A 计数");
  eq(st.C.n, 0, "未作答知识点有先验");
  if (!(st.A.est > st.B.est)) throw new Error("对得多应估得高");
  eq(cat.pickNext(st, [], seq([])), null, "空候选返回 null");
  return `est(A)=${st.A.est.toFixed(2)} est(B)=${st.B.est.toFixed(2)}`;
});

const passed = results.filter((r) => r.ok).length;
const failed = results.length - passed;
for (const r of results) console.log(`  [${r.ok ? "PASS" : "FAIL"}] ${r.id} ${r.name} — ${r.detail}`);
console.log(JSON.stringify({ passed, failed, results }));
process.exit(failed ? 1 : 0);
