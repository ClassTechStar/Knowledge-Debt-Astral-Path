package com.astralpath.nativeapp.ui

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import com.astralpath.nativeapp.MainActivity
import com.astralpath.nativeapp.data.AiCfg
import com.astralpath.nativeapp.service.AiService
import com.astralpath.nativeapp.service.ExamService
import com.astralpath.nativeapp.service.FormulaService
import com.astralpath.nativeapp.service.KgService
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.StoreService

/** 画像 / 教师 / 账户 / 试卷作业 四页 */
object PagesMore {

    private fun scroll(content: LinearLayout): ScrollView {
        val sv = ScrollView(content.context)
        sv.addView(content); sv.setBackgroundColor(Ui.BG)
        return sv
    }

    // ── 画像 ──
    fun profilePage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.label(c, "画像", 18f, Ui.INK, bold = true))
        val book = PagesCore.activeBook()
        val ans = StoreService.loadAnswers()
        val meta = StoreService.loadMeta()
        var weak = 0; var solid = 0
        val weakList = mutableListOf<Pair<String, Double>>()
        book?.nodes?.forEach { n ->
            val m = ans.mastery[n.id] ?: com.astralpath.nativeapp.data.Mastery(0, 0, 3, 0, 0)
            val sc = FormulaService.scoreV2(m.n, m.s, m.c, m.age, m.st, emptyList())
            if (sc < 0.55) { weak += 1; weakList.add(n.title to sc) } else solid += 1
        }
        root.addView(Ui.label(c, "掌握分布：薄弱 $weak · 扎实 $solid（共 ${book?.nodes?.size ?: 0} 个知识点）", 14f, Ui.INK, bold = true))
        weakList.sortedBy { it.second }.take(5).forEach { (t, s) ->
            root.addView(Ui.label(c, "⚠ ${t} · ${"%.0f".format(s * 100)}%", 12f, Ui.DANGER))
        }
        root.addView(Ui.label(c, "累计作答 ${ans.logs.size} 次", 12f, Ui.MUTED))
        val dndRow = Ui.row(c)
        dndRow.addView(Ui.label(c, "关闭个性化（opt-out）", 13f, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val sw = Switch(c); sw.isChecked = meta.optOut
        sw.setOnCheckedChangeListener { _, v ->
            StoreService.saveMeta(StoreService.loadMeta().copy(optOut = v))
            Toast.makeText(c, if (v) "已关闭个性化" else "已恢复个性化", Toast.LENGTH_SHORT).show()
        }
        dndRow.addView(sw)
        root.addView(dndRow, Ui.fill(dndRow))
        root.addView(Ui.label(c, "关闭后只按教材章节顺序安排，不依据知识债推断；数据只存本机。", 11f, Ui.MUTED))
        return scroll(root)
    }

    // ── 教师 ──
    fun teacherPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.label(c, "教师视图", 18f, Ui.INK, bold = true))
        val meta = StoreService.loadMeta()
        if (!meta.consent) {
            root.addView(Ui.label(c, "该学生未授权——按 fail-closed 口径不展示任何学情。学生可在「账户」页授权。", 13f, Ui.MUTED))
            return scroll(root)
        }
        root.addView(Ui.label(c, "已授权 · 聚合视图（k-匿名下限 3 人，样本不足只显示「样本不足」）", 12f, Ui.OK))
        val book = PagesCore.activeBook()
        val ans = StoreService.loadAnswers()
        book?.nodes?.forEach { n ->
            val m = ans.mastery[n.id] ?: com.astralpath.nativeapp.data.Mastery(0, 0, 3, 0, 0)
            val sc = FormulaService.scoreV2(m.n, m.s, m.c, m.age, m.st, emptyList())
            val row = Ui.row(c)
            row.addView(Ui.label(c, n.title, 13f, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (m.n >= 3) {
                row.addView(Ui.label(c, "${"%.0f".format(sc * 100)}%${if (sc < 0.55) " ⚠薄弱" else ""}", 12f, if (sc < 0.55) Ui.DANGER else Ui.MUTED))
            } else {
                row.addView(Ui.label(c, "样本不足", 12f, Ui.MUTED))
            }
            root.addView(row, Ui.fill(row))
        }
        return scroll(root)
    }

    // ── 账户 ──
    fun accountPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.label(c, "账户", 18f, Ui.INK, bold = true))
        val meta = StoreService.loadMeta()
        val cfg = StoreService.loadAiCfg()

        // 密钥
        val keyCard = Ui.card(c)
        keyCard.addView(Ui.label(c, "云端大脑（小米 MiMo · OpenAI 兼容）", 13f, Ui.INK, bold = true))
        val keyInput = EditText(c).apply { hint = "粘贴你的 API Key（sk-…）"; textSize = 12f }
        if (cfg.key.isNotEmpty()) keyInput.hint = "已配置密钥（本机加密前仅存本机）"
        keyCard.addView(keyInput, Ui.fill(keyInput))
        val keyRow = Ui.row(c)
        keyRow.addView(Ui.button(c, "保存") {
            val k = keyInput.text.toString().trim()
            if (k.isEmpty()) return@button
            StoreService.saveAiCfg(AiCfg(cfg.baseUrl.ifEmpty { AiService.DEFAULT_BASE }, k, cfg.model))
            Toast.makeText(c, "密钥已保存到本机", Toast.LENGTH_SHORT).show()
        })
        keyRow.addView(Ui.button(c, "清除") {
            StoreService.saveAiCfg(AiCfg(AiService.DEFAULT_BASE, "", "mimo-7b-rl"))
            Toast.makeText(c, "已移除密钥", Toast.LENGTH_SHORT).show()
        })
        keyCard.addView(keyRow, Ui.fill(keyRow))
        keyCard.addView(Ui.label(c, "未配置密钥时自动走本地规则引擎（演示模式）。密钥只存本机，不上传、不写日志。", 11f, Ui.MUTED))
        root.addView(keyCard, Ui.fill(keyCard))

        // 免打扰（演示模式）
        val dndCard = Ui.card(c)
        dndCard.addView(Ui.label(c, "提醒与演示模式", 13f, Ui.INK, bold = true))
        val dndRow = Ui.row(c)
        dndRow.addView(Ui.label(c, "免打扰（投影 / 评审时静音提醒，危机提醒仍然可见）", 12f, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val dnd = Switch(c); dnd.isChecked = meta.dnd
        dnd.setOnCheckedChangeListener { _, v ->
            StoreService.saveMeta(StoreService.loadMeta().copy(dnd = v))
            NotifyBus.setDnd(v)
        }
        dndRow.addView(dnd)
        dndCard.addView(dndRow, Ui.fill(dndRow))
        root.addView(dndCard, Ui.fill(dndCard))

        // 授权
        val consentCard = Ui.card(c)
        consentCard.addView(Ui.label(c, "教师可见授权（默认不可见，撤销即时失效）", 13f, Ui.INK, bold = true))
        val cRow = Ui.row(c)
        cRow.addView(Ui.label(c, if (meta.consent) "已授权：教师视图可见本机聚合学情" else "未授权：教师视图不展示任何数据", 12f, if (meta.consent) Ui.OK else Ui.MUTED), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        cRow.addView(Ui.button(c, if (meta.consent) "撤销授权" else "同意授权") {
            StoreService.saveMeta(StoreService.loadMeta().copy(consent = !meta.consent))
            a.nav("account")
        })
        consentCard.addView(cRow, Ui.fill(cRow))
        root.addView(consentCard, Ui.fill(consentCard))

        // 演示数据 / 清除
        val dataCard = Ui.card(c)
        dataCard.addView(Ui.label(c, "本机数据", 13f, Ui.INK, bold = true))
        dataCard.addView(Ui.button(c, "载入演示诊断（示例学情）") {
            val ans = StoreService.loadAnswers()
            DemoDataCompat().seed(ans)
            StoreService.saveAnswers(ans)
            Toast.makeText(c, "已载入演示诊断（可在本页清除）", Toast.LENGTH_SHORT).show()
        })
        dataCard.addView(Ui.button(c, "清除本机数据（全部重置）") {
            AlertDialog.Builder(c)
                .setTitle("确认清除")
                .setMessage("将删除本机全部学习数据（教材/作答/计划），且不可恢复。")
                .setPositiveButton("清除") { _, _ -> StoreService.wipe(); Toast.makeText(c, "已重置", Toast.LENGTH_SHORT).show(); a.nav("home") }
                .setNegativeButton("取消", null).show()
        })
        root.addView(dataCard, Ui.fill(dataCard))
        return scroll(root)
    }

    /** 演示学情注入（与 DemoData.seedMastery/seedLogs 同源） */
    private class DemoDataCompat {
        fun seed(ans: com.astralpath.nativeapp.data.AnswersShard) {
            com.astralpath.nativeapp.data.DemoData.seedMastery().forEach { (k, m) -> if (ans.mastery[k] == null) ans.mastery[k] = m }
            ans.logs.addAll(com.astralpath.nativeapp.data.DemoData.seedLogs())
        }
    }

    // ── 试卷作业（文本结构化）──
    fun papersPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.label(c, "试卷 · 作业 · 错题（文本导入）", 18f, Ui.INK, bold = true))
        root.addView(Ui.label(c, "粘贴试卷文本 → 本地确定性结构化（板块/题头/选项/答案/题型）。拍照识别请用 Web 单文件版或 Windows 壳（OCR 引擎在浏览器内联）。", 12f, Ui.MUTED))
        val input = EditText(c).apply {
            hint = "示例：\n一、单选题\n1. 下面哪个是合法变量名？（ ）\nA. 1a\nB. _a\nC. for\n答案：B"
            textSize = 12f
            minLines = 6
            setBackgroundColor(Ui.SURFACE)
            setPadding(Ui.dp(c, 10), Ui.dp(c, 10), Ui.dp(c, 10), Ui.dp(c, 10))
        }
        root.addView(input, Ui.fill(input))
        val resultBox = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }
        root.addView(Ui.button(c, "解析并结构化", primary = true) {
            val r = ExamService.structure(input.text.toString())
            resultBox.removeAllViews()
            if (r.items.isEmpty()) {
                resultBox.addView(Ui.label(c, "没有识别到题目——检查题头（1. ）与选项（A. ）格式。", 12f, Ui.WARN))
                return@button
            }
            resultBox.addView(Ui.label(c, "识别 ${r.items.size} 题 · " + r.sections.joinToString("；") { "${it.first} ${it.second} 题" }, 13f, Ui.OK, bold = true))
            // 知识点匹配：当前教材节点标题长词优先（与 Web 版口径一致的单题上限 4）
            val book = PagesCore.activeBook()
            r.items.forEach { it2 ->
                val card = Ui.card(c)
                val kps = book?.nodes?.filter { it2.stem.contains(it.title) }?.map { it.title }?.take(4) ?: emptyList()
                card.addView(Ui.label(c, "${it2.no}. [${it2.qtype}] ${it2.stem.replace("\n", " ").take(60)}", 13f, Ui.INK))
                if (it2.options.isNotEmpty()) card.addView(Ui.label(c, it2.options.joinToString("  "), 11f, Ui.MUTED))
                if (it2.answer.isNotEmpty()) card.addView(Ui.label(c, "答案：${it2.answer}", 11f, Ui.OK))
                if (kps.isNotEmpty()) card.addView(Ui.label(c, "知识点：${kps.joinToString("、")}", 11f, Ui.BRAND))
                resultBox.addView(card, Ui.fill(card))
            }
            val newPaper = com.astralpath.nativeapp.data.Paper(
                id = "paper-" + System.currentTimeMillis(), name = "粘贴导入", type = "exam",
                items = r.items.map { com.astralpath.nativeapp.data.PaperItem(it.no, it.section, it.stem, it.options, it.answer, it.qtype) },
                created = System.currentTimeMillis(),
            )
            StoreService.savePapers(listOf(newPaper) + StoreService.loadPapers())
        })
        root.addView(resultBox)
        return scroll(root)
    }

    /** 帮助中心（对齐 Web 版「？」三步上手 + 术语词典） */
    fun helpDialog(a: MainActivity) {
        val msg = """
            三步上手：① 起点页「导入示例教材」② 识网看先修关系 ③ 今日页开始练习。

            术语：
            · 知识债——未掌握且拖累后续学习的先修缺口
            · 红边——影响分 ≥0.08 的先修缺口关系
            · 销账——连续 2 次达标且累计 ≥3 次作答才结清
            · K1–K5——修复计划的五项合约（日预算/先修有序/说明含先修点/不重复/覆盖或延期）
        """.trimIndent()
        AlertDialog.Builder(a)
            .setTitle("知债：星穹学途 · 新手引导")
            .setMessage(msg)
            .setPositiveButton("开始", null)
            .show()
    }
}
