package com.astralpath.nativeapp.service

import com.astralpath.nativeapp.data.K
import com.astralpath.nativeapp.data.KEdge
import com.astralpath.nativeapp.data.KNode
import com.astralpath.nativeapp.data.PlanItem
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * 修复计划调度器 —— 移植自鸿蒙版 PlanScheduler.ets（其移植自 Web shared/plan-scheduler.js，
 * 金样 8 项在 JS 侧）。逐日容量 + 三遍复习 + K1–K5 合约 + fixK2 先修重排 + reliefDays 减压。
 * 纯函数；改动算法先改 JS 侧并跑金样（plan_scheduler_runner.js），这里保持同构。
 */
object PlanScheduler {
    data class DebtInput(val from: String, val to: String, val imp: Double)
    data class Deferred(val from: String, val to: String, val reason: String)
    data class SchedItem(
        var id: Int, var day: Int, val kp: String, val layer: String, val st: String,
        var min: Int, val fromKp: String, val rd: Int, val label: String, val why: String,
        var drop: Boolean = false,
    )
    data class Result(val items: MutableList<SchedItem>, val deferred: MutableList<Deferred>, val rounds: Int)

    private class Bin(val min: Int, val n: Int, val kps: Set<String>)

    private class MutableBin(var min: Int, var n: Int, val kps: MutableSet<String>)

    /** K1–K5 合约校验，返回违规清单（空 = 全过） */
    fun checkPlanK(
        plan: List<SchedItem>, budgetPerDay: Int,
        edges: List<KEdge>, debts: List<DebtInput>?, deferred: List<Deferred>,
        titleOf: (String) -> String,
    ): List<String> {
        val viol = mutableListOf<String>()
        val byDay = HashMap<Int, Int>()
        plan.forEach { byDay[it.day] = (byDay[it.day] ?: 0) + it.min }
        byDay.forEach { (d, sum) -> if (sum > budgetPerDay) viol.add("D$d 合计 ${sum}min 超出日预算 ${budgetPerDay}min（K1）") }
        plan.forEach { p ->
            val from = p.fromKp
            if (from != null && (p.why == null || (p.why.indexOf(from) < 0 && p.why.indexOf(titleOf(from)) < 0))) {
                viol.add("D${p.day} 条目「${p.kp}」的 why 未包含 from_kp（K3）")
            }
        }
        val seen = HashSet<String>()
        plan.forEach { p ->
            val k = "${p.day}|${p.kp}"
            if (!seen.add(k)) viol.add("D${p.day}「${titleOf(p.kp)}」重复安排（K4）")
        }
        val first = HashMap<String, Int>()
        plan.forEach { p -> val f = first[p.kp]; if (f == null || p.day < f) first[p.kp] = p.day }
        edges.forEach { e ->
            if (e.tg) return@forEach
            val fa = first[e.a]; val fb = first[e.b]
            if (fa != null && fb != null && fa > fb) viol.add("先修「${titleOf(e.a)}」的最早任务晚于「${titleOf(e.b)}」（K2）")
        }
        if (debts != null && debts.isNotEmpty()) {
            debts.forEach { d ->
                val covered = plan.any { it.fromKp == d.from && (it.kp == d.from || it.kp == d.to) }
                val def = deferred.any { it.from == d.from && it.to == d.to }
                if (!covered && !def) viol.add("债边「${d.from}→${d.to}」未覆盖也未显式延期（K5）")
            }
        }
        return viol
    }

    private fun moveNode(
        items: MutableList<SchedItem>, bins: MutableMap<Int, MutableBin>, budget: Int,
        kp: String, delta: Int, allowShrink: Boolean, offsets: IntArray,
    ): Boolean {
        val its = items.filter { it.kp == kp }
        if (its.isEmpty()) return false
        val newDays = mutableListOf<Int>()
        for (p in its) {
            val nd = p.day + delta
            val floorDay = 1 + offsets.getOrElse(p.rd) { 0 }
            if (nd < 1 || nd > 14 || nd < floorDay) return false
            newDays.add(nd)
        }
        val clone = HashMap<Int, MutableBin>()
        bins.forEach { (k, b) -> clone[k] = MutableBin(b.min, b.n, b.kps.toMutableSet()) }
        its.forEach { p -> clone[p.day]?.let { b -> b.min -= p.min; b.n -= 1; b.kps.remove(kp) } }
        val newMins = mutableListOf<Int>()
        for (j in its.indices) {
            val b2 = clone.getOrPut(newDays[j]) { MutableBin(0, 0, mutableSetOf()) }
            if (kp in b2.kps || b2.n >= 4) return false
            var mm = its[j].min
            if (b2.min + mm > budget) {
                if (!allowShrink) return false
                mm = max(8, budget - b2.min)
                if (b2.min + mm > budget) return false
            }
            b2.min += mm; b2.n += 1; b2.kps.add(kp)
            newMins.add(mm)
        }
        bins.clear(); bins.putAll(clone)
        its.forEachIndexed { i, p -> p.day = newDays[i]; if (newMins[i] != p.min) p.min = newMins[i] }
        return true
    }

    private fun fixK2(
        items: MutableList<SchedItem>, bins: MutableMap<Int, MutableBin>, budget: Int,
        edges: List<KEdge>, offsets: IntArray,
    ): Boolean {
        for (iter in 0 until 40) {
            val first = HashMap<String, Int>()
            items.forEach { p -> val f = first[p.kp]; if (f == null || p.day < f) first[p.kp] = p.day }
            var worst: Triple<String, String, Int>? = null
            edges.forEach { e ->
                if (e.tg || !first.containsKey(e.a) || !first.containsKey(e.b)) return@forEach
                val dd = (first[e.a] ?: 0) - (first[e.b] ?: 0)
                if (dd > 0 && (worst == null || dd > worst!!.third)) worst = Triple(e.a, e.b, dd)
            }
            val w = worst ?: return true
            if (moveNode(items, bins, budget, w.second, w.third, false, offsets)) continue
            if (moveNode(items, bins, budget, w.first, -w.third, false, offsets)) continue
            if (moveNode(items, bins, budget, w.first, -w.third, true, offsets)) continue
            if (moveNode(items, bins, budget, w.second, w.third, true, offsets)) continue
            return false
        }
        return true
    }

    /** 主调度器：先修深度排名 → 逐边排 core/challenge 两任务 × rounds 遍 → 排不下显式延期 */
    fun schedule(
        ds: List<DebtInput>, budget: Int, edges: List<KEdge>, nodes: List<KNode>,
        titleOf: (String) -> String,
    ): Result {
        val offsets = K.SPACING_OFFSETS
        val rounds = if (budget >= 30) min(3, offsets.size) else 2
        val maxDebts = if (budget >= 30) 6 else 4
        val bins = HashMap<Int, MutableBin>()
        val entries = mutableListOf<Pair<SchedItem, Pair<DebtInput, Int>>>() // item ← (debt, di)
        val deferred = mutableListOf<Deferred>()

        fun bin(day: Int): MutableBin = bins.getOrPut(day) { MutableBin(0, 0, mutableSetOf()) }
        fun canPlace(kp: String, min: Int, day: Int): Boolean {
            val b = bin(day)
            return kp !in b.kps && b.n < 4 && b.min + min <= budget
        }
        fun findDay(kp: String, min: Int, minDay: Int): Int {
            for (day in max(1, minDay)..14) if (canPlace(kp, min, day)) return day
            return -1
        }

        // Kahn 最长链深度排名（图异常时按空排名继续）
        val rank = HashMap<String, Int>()
        run {
            val indeg = HashMap<String, Int>()
            nodes.forEach { indeg[it.id] = 0 }
            edges.forEach { e ->
                if (!e.tg && indeg.containsKey(e.b) && indeg.containsKey(e.a)) {
                    indeg[e.b] = (indeg[e.b] ?: 0) + 1
                }
            }
            val q = ArrayDeque<String>()
            nodes.forEach { if ((indeg[it.id] ?: 0) == 0) q.add(it.id) }
            val dep = HashMap<String, Int>()
            nodes.forEach { dep[it.id] = 0 }
            var guard = 0
            while (q.isNotEmpty() && guard++ < 4000) {
                val x = q.removeFirst()
                edges.forEach { e ->
                    if (e.tg || e.a != x) return@forEach
                    if ((dep[e.b] ?: 0) < (dep[x] ?: 0) + 1) dep[e.b] = (dep[x] ?: 0) + 1
                    if (indeg.containsKey(e.b)) {
                        indeg[e.b] = (indeg[e.b] ?: 0) - 1
                        if ((indeg[e.b] ?: 0) <= 0) q.add(e.b)
                    }
                }
            }
            nodes.forEach { rank[it.id] = dep[it.id] ?: 0 }
        }

        val list = ds.sortedWith(
            compareBy({ rank[it.from] ?: 0 }, { -it.imp })
        )
        val firstDay = HashMap<String, Int>()
        val MINS = if (budget >= 35) arrayOf(intArrayOf(12, 12), intArrayOf(10, 10), intArrayOf(8, 8))
        else arrayOf(intArrayOf(10, 10), intArrayOf(8, 8), intArrayOf(8, 8))

        list.take(maxDebts).forEachIndexed { di, d ->
            var prev = 0
            var ok = true
            var tot = 0
            for (r in 0 until rounds) {
                if (!ok) break
                val off = offsets.getOrElse(r) { r * 2 }
                for (step in 0 until 2) {
                    if (!ok) break
                    val isCore = step == 0
                    val kp = if (isCore) d.from else d.to
                    var md = max(1 + off, prev + 1)
                    if (!isCore && firstDay.containsKey(d.from)) md = max(md, (firstDay[d.from] ?: 0) + 1)
                    val m = MINS[r][if (isCore) 0 else 1]
                    val day = findDay(kp, m, md)
                    if (day < 0) { ok = false; break }
                    bin(day).let { b -> b.min += m; b.n += 1; b.kps.add(kp) }
                    val kind = if (isCore) "core" else "challenge"
                    val label = if (isCore) "巩固「${titleOf(d.from)}」" else "进阶「${titleOf(d.to)}」"
                    val why = "先补「${titleOf(d.from)}」再带动「${titleOf(d.to)}」，第 ${r + 1}/$rounds 遍（间隔 $off 天），$m 分钟"
                    entries.add(
                        SchedItem(0, day, kp, kind, "todo", m, d.from, r, label, why) to (d to di)
                    )
                    if (day < (firstDay[kp] ?: Int.MAX_VALUE)) firstDay[kp] = day
                    prev = day
                    tot += 1
                }
            }
            if (!ok || tot == 0) {
                deferred.add(Deferred(d.from, d.to, if (tot > 0) "部分轮次延后（日预算已满）" else "本轮未排入（预算已满）"))
            }
        }
        list.drop(maxDebts).forEach { deferred.add(Deferred(it.from, it.to, "本轮未排入（优先级靠后，下轮再排）")) }

        entries.sortWith(compareBy({ it.first.day }, { it.second.second }, { if (it.first.layer == "core") 0 else 1 }))
        val items = mutableListOf<SchedItem>()
        entries.forEachIndexed { i, pair ->
            val it = pair.first
            items.add(SchedItem(i + 1, it.day, it.kp, it.layer, it.st, it.min, it.fromKp, it.rd, it.label, it.why))
        }
        try { fixK2(items, bins, budget, edges, offsets) } catch (e: Exception) { /* 与 Web 版一致：重排失败不阻断产出 */ }
        items.sortWith(compareBy({ it.day }, { it.id }))
        items.forEachIndexed { i, p -> p.id = i + 1 }
        return Result(items, deferred, rounds)
    }

    fun toPlanItems(items: List<SchedItem>): List<PlanItem> = items.map {
        PlanItem(
            id = "PL" + it.id.toString().padStart(2, '0'), day = it.day, kp = it.kp,
            minutes = it.min, layer = it.layer, why = it.why, st = it.st,
            fromKp = it.fromKp, rd = it.rd, label = it.label,
        )
    }
}
