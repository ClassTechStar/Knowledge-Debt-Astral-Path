package com.astralpath.nativeapp.ui

import android.graphics.Color
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import com.astralpath.nativeapp.MainActivity
import com.astralpath.nativeapp.data.DemoData
import com.astralpath.nativeapp.data.K
import com.astralpath.nativeapp.data.PlanItem
import com.astralpath.nativeapp.service.FormulaService
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.PlanScheduler
import com.astralpath.nativeapp.service.StoreService

/** 知债页 / 今日页 —— 对应 Web 版 p-debt / p-today */
object PagesDebt {

    private fun titlesOf(): Map<String, String> =
        PagesCore.activeBook()?.nodes?.associate { it.id to it.title } ?: emptyMap()

    private fun seedIfEmpty(): List<com.astralpath.nativeapp.data.DebtEdge> {
        val book = PagesCore.activeBook() ?: return emptyList()
        val ans = StoreService.loadAnswers()
        val debts = FormulaService.diagnose(book.edges, book.nodes.associate { it.id to it.title }, ans.mastery, ans.logs)
        if (debts.isEmpty() && ans.logs.none { it.qid.startsWith("seed-") } && book.id == "demo-python") {
            DemoData.seedMastery().forEach { (k, m) -> if (ans.mastery[k] == null) ans.mastery[k] = m }
            ans.logs.addAll(DemoData.seedLogs())
            StoreService.saveAnswers(ans)
            return FormulaService.diagnose(book.edges, book.nodes.associate { it.id to it.title }, StoreService.loadAnswers().mastery, StoreService.loadAnswers().logs)
        }
        return debts
    }

    // ── 知债页 ──
    fun debtPage(a: MainActivity): View {
        val c = a
        val content = Ui.page(c)
        content.addView(Ui.label(c, "债边诊断", 18f, Ui.INK, bold = true))
        val msg = Ui.label(c, "点「重新诊断」查看红边与解读；点「生成 14 天计划」走完整调度器（K1–K5）。", 12f, Ui.MUTED)
        val warn = Ui.label(c, "", 12f, Ui.OK)
        val buttons = Ui.row(c)
        val debtsBox = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }
        val planBox = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }

        var debts = listOf<com.astralpath.nativeapp.data.DebtEdge>()
        var selected: com.astralpath.nativeapp.data.DebtEdge? = null
        val narrative = Ui.label(c, "", 12f, Ui.INK)

        fun renderNarrative() {
            val d = selected
            if (d == null) { narrative.text = "先选一条债边"; return }
            val parts = StringBuilder()
            parts.append("「${d.a}」→「${d.b}」影响分 ${"%.3f".format(d.impact)}，${if (d.open) "已构成开放红边（≥0.08）" else "未到开放阈值"}。")
            parts.append("建议先补先修再练后续，顺序反了效果会打折。")
            narrative.text = parts.toString()
        }

        fun rebuildList() {
            debtsBox.removeAllViews()
            titlesOf().let { titles ->
                debts.forEach { d ->
                    val card = Ui.card(c, bg = if (selected?.id == d.id) Ui.DANGER_SOFT else Ui.SOFT)
                    card.addView(Ui.label(c, "${titles[d.a] ?: d.a} → ${titles[d.b] ?: d.b}", 14f, Ui.DANGER, bold = selected?.id == d.id))
                    card.addView(Ui.label(c, "影响分 ${"%.3f".format(d.impact)}", 11f, Ui.MUTED))
                    d.why?.let { card.addView(Ui.label(c, it, 11f, Ui.MUTED)) }
                    card.setOnClickListener { selected = d; rebuildList(); renderNarrative() }
                    debtsBox.addView(card, Ui.fill(card))
                }
            }
        }

        fun diag() {
            debts = seedIfEmpty()
            selected = debts.firstOrNull()
            msg.text = if (debts.isEmpty()) "当前没有开放红边" else "发现 ${debts.size} 条开放红边（按影响分降序）"
            rebuildList()
            renderNarrative()
        }

        fun buildPlan() {
            val book = PagesCore.activeBook()
            if (book == null) { msg.text = "还没有资料，先到起点页导入示例教材"; return }
            val budget = 40
            val ds = debts.map { PlanScheduler.DebtInput(it.a, it.b, it.impact) }
            val titleOf = { id: String -> titlesOf()[id] ?: id }
            val result = PlanScheduler.schedule(ds, budget, book.edges, book.nodes, titleOf)
            val viol = PlanScheduler.checkPlanK(result.items, budget, book.edges, ds, result.deferred, titleOf)
            val plan = PlanScheduler.toPlanItems(result.items)
            StoreService.savePlan(plan)
            warn.text = "计划合约 K1–K5 校验通过 · 数字与约束由本地公式把关" +
                (if (viol.isNotEmpty()) "；警告：${viol.first()}" else "") +
                (if (result.deferred.isNotEmpty()) "；另有 ${result.deferred.size} 条债边本轮未排入（${result.deferred.first().reason}）" else "")
            msg.text = "已生成 ${plan.size} 条计划（三遍复习、每天不超过 $budget 分钟）"
            planBox.removeAllViews()
            plan.forEach { p ->
                val card = Ui.card(c, bg = Ui.SURFACE)
                val row = Ui.row(c)
                row.addView(Ui.label(c, "D${p.day}", 12f, Ui.BRAND))
                row.addView(Ui.label(c, p.label ?: p.kp, 13f, Ui.INK))
                val spacer = View(c)
                row.addView(spacer, LinearLayout.LayoutParams(0, 1, 1f))
                row.addView(Ui.label(c, "${p.minutes} 分钟", 11f, Ui.MUTED))
                card.addView(row, Ui.fill(row))
                p.why?.let { card.addView(Ui.label(c, it, 11f, Ui.MUTED)) }
                planBox.addView(card, Ui.fill(card))
            }
        }

        fun checkSale() {
            val ans = StoreService.loadAnswers()
            var cleared = 0
            val titles = titlesOf()
            debts.forEach { d ->
                val logs = ans.logs.filter { it.kp == d.b }
                if (logs.isEmpty()) return@forEach
                val acc = logs.count { it.ok }.toDouble() / logs.size
                val conf = logs.map { it.conf }.average().toInt()
                val s0 = ans.sale[d.id]
                val r = FormulaService.saleStep(com.astralpath.nativeapp.data.SaleState(s0?.streak ?: 0, s0?.att ?: 0), acc, conf)
                ans.sale[d.id] = com.astralpath.nativeapp.data.SaleState(r.streak, r.att, r.cleared)
                if (r.cleared) cleared += 1
            }
            StoreService.saveAnswers(ans)
            msg.text = "销账检查完成，本次结清 $cleared 条（连续 ${K.SALE_STREAK.toInt()} 次达标 ∧ 累计 ≥${K.SALE_MIN_ATT.toInt()} 次）"
        }

        fun reviewPlan() {
            val ans = StoreService.loadAnswers()
            val plan = StoreService.loadPlan()
            if (plan.isEmpty()) { warn.text = "还没有计划，先点「生成 14 天计划」"; return }
            var done = 0; var partial = 0
            plan.forEach { p ->
                val n = ans.logs.count { it.kp == p.kp }
                if (n >= 3) done += 1 else if (n > 0) partial += 1
            }
            val clearedCount = ans.sale.values.count { it.cleared }
            warn.text = "计划 ${plan.size} 条：达标 $done · 进行中 $partial · 未开始 ${plan.size - done - partial}；已销账 $clearedCount 条"
        }

        buttons.addView(Ui.button(c, "重新诊断", primary = true) { diag() })
        buttons.addView(Ui.button(c, "生成 14 天计划") { buildPlan() })
        buttons.addView(Ui.button(c, "销账检查") { checkSale() })
        buttons.addView(Ui.button(c, "计划复盘") { reviewPlan() })
        content.addView(buttons, Ui.fill(buttons))
        content.addView(msg, Ui.fill(msg))
        content.addView(warn, Ui.fill(warn))
        content.addView(debtsBox)
        diag()

        // What-if 模拟
        val whatCard = Ui.card(c)
        whatCard.addView(Ui.label(c, "What-if 模拟", 13f, Ui.INK, bold = true))
        var wSp = 30; var wSc = 25; var wFq = 5
        val whatOut = Ui.label(c, "", 12f, Ui.MUTED)
        fun simulate() {
            val impact = FormulaService.impactV2(wSp / 100.0, wSc / 100.0, 1.0, false, wFq, 1)
            whatOut.text = "前置 ${wSp}% / 目标 ${wSc}% / 频次 $wFq → 影响分 ${"%.3f".format(impact)}（${if (FormulaService.isOpen(impact)) "命中红边 ≥0.08" else "未达红线"}）"
        }
        fun slider(from: Int, init: Int, maxV: Int, onChange: (Int) -> Unit): View {
            val row = Ui.row(c)
            val tv = TextView(c); tv.text = "$from"; tv.textSize = 11f; tv.setTextColor(Ui.MUTED)
            tv.layoutParams = LinearLayout.LayoutParams(Ui.dp(c, 90), LinearLayout.LayoutParams.WRAP_CONTENT)
            val sb = SeekBar(c); sb.max = maxV; sb.progress = init
            sb.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, v: Int, b: Boolean) { onChange(v); tv.text = "$v"; simulate() }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
            row.addView(tv); row.addView(sb, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            return row
        }
        whatCard.addView(slider(0, wSp, 100) { wSp = it })
        whatCard.addView(slider(0, wSc, 100) { wSc = it })
        whatCard.addView(slider(0, wFq, 20) { wFq = it })
        simulate()
        whatCard.addView(whatOut, Ui.fill(whatOut))
        content.addView(whatCard, Ui.fill(whatCard))

        if (StoreService.loadPlan().isNotEmpty()) {
            content.addView(Ui.label(c, "修复计划（已有 ${StoreService.loadPlan().size} 条）", 14f, Ui.INK, bold = true))
            content.addView(planBox)
        }
        val sv = ScrollView(c); sv.addView(content); sv.setBackgroundColor(Ui.BG)
        return sv
    }

    // ── 今日页 ──
    fun todayPage(a: MainActivity): View {
        val c = a
        val content = Ui.page(c)
        val head = Ui.row(c)
        head.addView(Ui.label(c, "今日", 18f, Ui.INK, bold = true))
        content.addView(head, Ui.fill(head))
        val optOut = StoreService.loadMeta().optOut
        if (optOut) {
            content.addView(Ui.label(c, "已关闭个性化：以下按教材章节顺序安排，不依据你的知识债推断。", 12f, Ui.WARN))
        }
        val book = PagesCore.activeBook()
        if (book == null) {
            content.addView(Ui.label(c, "还没有资料，先到起点页导入示例教材。", 13f, Ui.MUTED))
            val sv = ScrollView(c); sv.addView(content); return sv
        }
        val ans = StoreService.loadAnswers()
        val tasks = if (optOut) {
            book.nodes.take(5).map { Triple(it.id, it.title, 1.0) }
        } else {
            val visiting = mutableMapOf<String, Double>()
            book.nodes.map { Triple(it.id, it.title, FormulaService.scoreOfGraph(it.id, book.edges, ans.mastery, visiting)) }
                .sortedBy { it.third }.take(5)
        }
        val quizBox = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }
        var quiz: com.astralpath.nativeapp.data.Question? = null
        var picked = -1
        var conf = 4

        fun loadQuiz(kp: String) {
            val pool = book.qs.filter { it.kp == kp }
            if (pool.isEmpty()) {
                quiz = null
                quizBox.removeAllViews()
                quizBox.addView(Ui.label(c, "该知识点暂无题目", 12f, Ui.MUTED))
                return
            }
            quiz = pool.random()
            picked = -1
            quizBox.removeAllViews()
            val q = quiz!!
            val card = Ui.card(c)
            card.addView(Ui.label(c, q.stem, 14f, Ui.INK, bold = true))
            q.opts.forEachIndexed { idx, opt ->
                val optView = Ui.label(c, opt, 13f, if (picked == idx) Ui.BRAND else Ui.INK)
                optView.setPadding(Ui.dp(c, 10), Ui.dp(c, 8), Ui.dp(c, 10), Ui.dp(c, 8))
                optView.setOnClickListener { picked = idx; loadQuiz(kp); /* 重绘选中态 */ 
                    quizBox.findViewWithTag<TextView>("opt$idx")?.setTextColor(Ui.BRAND) }
                optView.tag = "opt$idx"
                card.addView(optView, Ui.fill(optView))
            }
            val confRow = Ui.row(c)
            val confLabel = Ui.label(c, "信心 $conf/5", 11f, Ui.MUTED)
            confLabel.layoutParams = LinearLayout.LayoutParams(Ui.dp(c, 76), LinearLayout.LayoutParams.WRAP_CONTENT)
            val sb = SeekBar(c); sb.max = 4; sb.progress = conf - 1
            sb.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, v: Int, b: Boolean) { conf = v + 1; confLabel.text = "信心 $conf/5" }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
            confRow.addView(confLabel); confRow.addView(sb, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            card.addView(confRow, Ui.fill(confRow))
            val result = Ui.label(c, "", 12f, Ui.OK)
            card.addView(Ui.button(c, "提交", primary = true) {
                if (picked < 0) return@button
                val ok = picked == q.ci
                val m = ans.mastery[q.kp] ?: com.astralpath.nativeapp.data.Mastery(0, 0, 3, 0, 0)
                m.n += 1
                if (ok) { m.s += 1; m.st += 1 } else m.st = 0
                m.age = 0
                ans.mastery[q.kp] = m
                ans.logs.add(com.astralpath.nativeapp.data.AnswerLog(q.id, q.kp, ok, conf, System.currentTimeMillis()))
                StoreService.saveAnswers(ans)
                result.text = "${if (ok) "答对了" else "答错了"} · 信心 $conf/5 · 掌握度 ${(FormulaService.scoreV2(m.n, m.s, m.c, m.age, m.st, emptyList()) * 100).toInt()}%"
            })
            card.addView(result, Ui.fill(result))
            quizBox.addView(card, Ui.fill(card))
        }

        tasks.forEach { (kp, title, score) ->
            val card = Ui.card(c)
            val row = Ui.row(c)
            val col = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }
            col.addView(Ui.label(c, title, 14f, Ui.INK))
            col.addView(Ui.label(c, "掌握度 ${(score * 100).toInt()}%", 11f, if (score < 0.55) Ui.DANGER else Ui.MUTED))
            row.addView(col, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(Ui.button(c, "开始练习") { loadQuiz(kp) })
            card.addView(row, Ui.fill(row))
            content.addView(card, Ui.fill(card))
        }
        content.addView(quizBox)
        val sv = ScrollView(c); sv.addView(content); sv.setBackgroundColor(Ui.BG)
        return sv
    }
}
