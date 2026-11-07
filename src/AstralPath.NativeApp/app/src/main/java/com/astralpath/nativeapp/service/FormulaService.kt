package com.astralpath.nativeapp.service

import com.astralpath.nativeapp.data.AnswerLog
import com.astralpath.nativeapp.data.DebtEdge
import com.astralpath.nativeapp.data.K
import com.astralpath.nativeapp.data.KEdge
import com.astralpath.nativeapp.data.Mastery
import com.astralpath.nativeapp.data.SaleResult
import com.astralpath.nativeapp.data.SaleState
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * 公式服务 —— score-v2 / impact-v2 / sale-v2，移植自鸿蒙版 FormulaService.ets
 * （其逐行移植自 Web 单文件版），取值与 C# FormulaConstants.cs 同源（verify_constants.py 对拍）。
 * 纯函数、无平台 API——保持可测。
 */
object FormulaService {
    fun clamp01(v: Double): Double = max(0.0, min(1.0, v))
    private fun sig(x: Double): Double = 1.0 / (1.0 + exp(-x))
    private fun empirical(n: Int, s: Int): Double = (s + 0.5) / (n + 1.0)

    fun stability(streak: Int, att: Int): Double =
        K.STAB0 * (1 + K.A * max(streak, 0)) * (1 + K.B * ln(1.0 + max(att, 1).toDouble()))

    fun retention(age: Int, streak: Int, att: Int): Double =
        exp(-max(age, 0) / stability(streak, att))

    fun prereqSup(arr: List<Double>): Double {
        if (arr.isEmpty()) return 0.5
        val mean = arr.sum() / arr.size
        val mn = arr.min()
        return (1 - K.MIX) * mean + K.MIX * mn
    }

    fun prereqCeil(arr: List<Double>): Double {
        if (arr.isEmpty()) return 1.0
        val mn = arr.min()
        return K.FLOOR + (1 - K.FLOOR) * mn
    }

    fun scoreV2(att: Int, ok: Int, conf: Int, age: Int, streak: Int, prereq: List<Double>): Double {
        val know = 0.85 * empirical(att, ok) + 0.15 * clamp01(conf / 5.0)
        val raw = K.W_E * know + K.W_R * retention(age, streak, att) + K.W_P * prereqSup(prereq)
        return clamp01(min(raw, prereqCeil(prereq)))
    }

    fun impactV2(sf: Double, st: Double, w: Double, tg: Boolean, freq: Int, down: Int): Double {
        if (freq <= 0) return 0.0
        val ww = if (w.isFinite()) max(w, 0.0) else 0.0
        return K.IMPACT_BASE * sig((sf - K.PG) * K.STEEP) * sig((K.CG - st) * K.STEEP) * ww *
            (if (tg) K.CROSS_TG else 1.0) *
            (1 + K.CAS * ln(1.0 + max(down, 0).toDouble())) *
            (1 + K.VOL * ln(1.0 + max(freq, 0).toDouble()))
    }

    fun saleStep(s0: SaleState?, acc: Double, conf: Int): SaleResult {
        val st0 = s0 ?: SaleState(0, 0)
        val meets = (0.7 * acc + 0.3 * clamp01(conf / 5.0)) >= K.SALE_BAR &&
            acc >= K.SALE_ACC && conf >= K.SALE_CONF
        val streak = if (meets) st0.streak + 1 else 0
        val att = st0.att + 1
        val cleared = streak >= K.SALE_STREAK && att >= K.SALE_MIN_ATT
        return SaleResult(streak, att, meets, cleared)
    }

    /** 递归算某知识点得分：先修由图谱边推出，visiting 防环（对齐 Web scoreOfMemo） */
    fun scoreOfGraph(
        id: String,
        edges: List<KEdge>,
        mastery: Map<String, Mastery>,
        visiting: MutableMap<String, Double>,
    ): Double {
        val cached = visiting[id]
        if (cached != null) return cached
        visiting[id] = 0.5
        val m = mastery[id] ?: Mastery(0, 0, 3, 0, 0)
        val pre = edges.filter { it.b == id }.map { scoreOfGraph(it.a, edges, mastery, visiting) }
        val v = scoreV2(m.n, m.s, m.c, m.age, m.st, pre)
        visiting[id] = v
        return v
    }

    fun isOpen(impact: Double): Boolean = impact >= K.HIT

    /** 知债诊断：对一本教材的全部边算影响分，返回按分降序的开放红边 */
    fun diagnose(
        edges: List<KEdge>,
        titles: Map<String, String>,
        mastery: Map<String, Mastery>,
        logs: List<AnswerLog>,
    ): List<DebtEdge> {
        val visiting = mutableMapOf<String, Double>()
        fun scoreOf(id: String): Double = scoreOfGraph(id, edges, mastery, visiting)
        val out = mutableListOf<DebtEdge>()
        for (e in edges) {
            val sf = scoreOf(e.a)
            val st = scoreOf(e.b)
            val freq = logs.count { it.kp == e.b && !it.ok }
            val down = edges.count { it.a == e.a && scoreOf(it.b) < K.CG }
            val impact = impactV2(sf, st, e.w, e.tg, max(freq, 1), down)
            if (FormulaService.isOpen(impact)) {
                out.add(
                    DebtEdge(
                        id = "${e.a}>${e.b}", a = e.a, b = e.b, impact = impact, open = true,
                        why = "先修「${titles[e.a] ?: e.a}」掌握 ${(sf * 100).toInt()}%，拖累「${titles[e.b] ?: e.b}」",
                    )
                )
            }
        }
        return out.sortedByDescending { it.impact }
    }
}
