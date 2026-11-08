package com.astralpath.nativeapp.ui

import android.app.AlertDialog
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.Toast
import com.astralpath.nativeapp.MainActivity
import com.astralpath.nativeapp.data.AiCfg
import com.astralpath.nativeapp.service.AiService
import com.astralpath.nativeapp.service.ExamService
import com.astralpath.nativeapp.service.FormulaService
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.StoreService

/**
 * 画像 / 教师 / 账户 / 试卷作业 四页。
 * 版式对齐 Web：page-h 标题区 + panel 卡片流；业务功能与数据逻辑保持不变。
 */
object PagesMore {

    private fun scroll(content: LinearLayout): ScrollView {
        val sv = ScrollView(content.context)
        sv.addView(content); sv.setBackgroundColor(Ui.CANVAS) // 对齐 Web 页面底色 canvas
        return sv
    }

    // ── 画像 ──
    fun profilePage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
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

        root.addView(Ui.pageHeader(c, "画像", "掌握/薄弱分布与累计作答，只存本机。"), Ui.fill(root, 22))

        // 掌握分布（对齐 Web .stats 网格：手机单列/两列 → 横排 stat 块）
        val statPanel = Ui.panel(c, "掌握分布")
        val statRow = Ui.row(c)
        val s1 = Ui.stat(c, "薄弱", "$weak")
        statRow.addView(s1, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val s2 = Ui.stat(c, "扎实", "$solid")
        statRow.addView(s2, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val s3 = Ui.stat(c, "知识点", "${book?.nodes?.size ?: 0}")
        statRow.addView(s3, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        statPanel.addView(statRow, Ui.fill(statRow, 0))
        statPanel.addView(Ui.bar(c, if (book?.nodes.isNullOrEmpty()) 0f else solid.toFloat() / book!!.nodes.size))
        root.addView(statPanel, Ui.fill(statPanel))

        // 薄弱清单（err 徽标 + 卡片流）
        if (weakList.isNotEmpty()) {
            val weakPanel = Ui.panel(c, "薄弱知识点", "按掌握度从低到高。")
            weakList.sortedBy { it.second }.take(5).forEach { (t, s) ->
                val card = Ui.card(c)
                card.addView(Ui.row(c).apply {
                    addView(Ui.label(c, t, Ui.FS_BODY, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                    addView(Ui.badge(c, "${"%.0f".format(s * 100)}%", Ui.Kind.ERR))
                })
                weakPanel.addView(card, Ui.fillCard(card))
            }
            root.addView(weakPanel, Ui.fill(weakPanel))
        }

        val infoPanel = Ui.panel(c, "累计")
        infoPanel.addView(Ui.label(c, "累计作答 ${ans.logs.size} 次", Ui.FS_HINT, Ui.MUTED))
        val dndRow = Ui.row(c)
        dndRow.addView(Ui.label(c, "关闭个性化（opt-out）", Ui.FS_HINT, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val sw = Switch(c); sw.isChecked = meta.optOut
        sw.setOnCheckedChangeListener { _, v ->
            StoreService.saveMeta(StoreService.loadMeta().copy(optOut = v))
            Toast.makeText(c, if (v) "已关闭个性化" else "已恢复个性化", Toast.LENGTH_SHORT).show()
        }
        dndRow.addView(sw)
        infoPanel.addView(dndRow, Ui.fill(dndRow, 0))
        infoPanel.addView(Ui.label(c, "关闭后只按教材章节顺序安排，不依据知识债推断；数据只存本机。", Ui.FS_BADGE, Ui.MUTED))
        root.addView(infoPanel, Ui.fill(infoPanel))
        return scroll(root)
    }

    // ── 教师 ──
    fun teacherPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.pageHeader(c, "教师视图", "k-匿名聚合视图。"), Ui.fill(root, 22))
        val meta = StoreService.loadMeta()
        if (!meta.consent) {
            root.addView(Ui.status(c, "该学生未授权——按 fail-closed 口径不展示任何学情。学生可在「账户」页授权。"), Ui.fill(root))
            return scroll(root)
        }
        root.addView(Ui.status(c, "已授权 · 聚合视图（k-匿名下限 3 人，样本不足只显示「样本不足」）", Ui.Kind.OK), Ui.fill(root))
        val book = PagesCore.activeBook()
        val ans = StoreService.loadAnswers()
        val listPanel = Ui.panel(c, "班级学情")
        book?.nodes?.forEach { n ->
            val m = ans.mastery[n.id] ?: com.astralpath.nativeapp.data.Mastery(0, 0, 3, 0, 0)
            val sc = FormulaService.scoreV2(m.n, m.s, m.c, m.age, m.st, emptyList())
            val row = Ui.row(c)
            row.addView(Ui.label(c, n.title, Ui.FS_HINT, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (m.n >= 3) {
                row.addView(Ui.badge(
                    c, "${"%.0f".format(sc * 100)}%${if (sc < 0.55) " ⚠薄弱" else ""}",
                    if (sc < 0.55) Ui.Kind.ERR else Ui.Kind.OK,
                ))
            } else {
                row.addView(Ui.label(c, "样本不足", Ui.FS_BADGE, Ui.MUTED))
            }
            listPanel.addView(row, Ui.fill(row, 6))
        }
        root.addView(listPanel, Ui.fill(listPanel))
        return scroll(root)
    }

    // ── 账户 ──
    fun accountPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.pageHeader(c, "账户", "密钥、提醒与授权设置，全部只存本机。"), Ui.fill(root, 22))
        val meta = StoreService.loadMeta()
        val cfg = StoreService.loadAiCfg()

        // 密钥
        val keyCard = Ui.panel(c, "云端大脑（小米 MiMo · OpenAI 兼容）")
        val keyInput = EditText(c).apply {
            hint = "粘贴你的 API Key（sk-…）"
            setTextSize(0, Ui.sp(c, Ui.FS_HINT))
            background = Ui.shape(Ui.FIELD, Ui.dpF(c, Ui.R_CTRL), Ui.dp(c, 1), Ui.RULE)
            setPadding(Ui.dp(c, 12), Ui.dp(c, 8), Ui.dp(c, 12), Ui.dp(c, 8))
        }
        if (cfg.key.isNotEmpty()) keyInput.hint = "已配置密钥（本机加密前仅存本机）"
        keyCard.addView(keyInput, Ui.fill(keyInput, 0))
        val keyRow = Ui.row(c)
        keyRow.addView(Ui.btn(c, "保存", primary = true) {
            val k = keyInput.text.toString().trim()
            if (k.isEmpty()) return@btn
            StoreService.saveAiCfg(AiCfg(cfg.baseUrl.ifEmpty { AiService.DEFAULT_BASE }, k, cfg.model))
            Toast.makeText(c, "密钥已保存到本机", Toast.LENGTH_SHORT).show()
        })
        keyRow.addView(Ui.btn(c, "清除", danger = true) {
            StoreService.saveAiCfg(AiCfg(AiService.DEFAULT_BASE, "", "mimo-7b-rl"))
            Toast.makeText(c, "已移除密钥", Toast.LENGTH_SHORT).show()
        })
        keyCard.addView(keyRow, Ui.fill(keyRow, 0))
        keyCard.addView(Ui.label(c, "未配置密钥时自动走本地规则引擎（演示模式）。密钥只存本机，不上传、不写日志。", Ui.FS_BADGE, Ui.MUTED))
        root.addView(keyCard, Ui.fill(keyCard))

        // 免打扰（演示模式）
        val dndCard = Ui.panel(c, "提醒与演示模式")
        val dndRow = Ui.row(c)
        dndRow.addView(Ui.label(c, "免打扰（投影 / 评审时静音提醒，危机提醒仍然可见）", Ui.FS_HINT, Ui.INK), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val dnd = Switch(c); dnd.isChecked = meta.dnd
        dnd.setOnCheckedChangeListener { _, v ->
            StoreService.saveMeta(StoreService.loadMeta().copy(dnd = v))
            NotifyBus.setDnd(v)
        }
        dndRow.addView(dnd)
        dndCard.addView(dndRow, Ui.fill(dndRow, 0))
        root.addView(dndCard, Ui.fill(dndCard))

        // 授权
        val consentCard = Ui.panel(c, "教师可见授权", "默认不可见，撤销即时失效。")
        val cRow = Ui.row(c)
        cRow.addView(Ui.label(
            c,
            if (meta.consent) "已授权：教师视图可见本机聚合学情" else "未授权：教师视图不展示任何数据",
            Ui.FS_HINT, if (meta.consent) Ui.OK_TEXT else Ui.MUTED,
        ), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        cRow.addView(Ui.btn(c, if (meta.consent) "撤销授权" else "同意授权") {
            StoreService.saveMeta(StoreService.loadMeta().copy(consent = !meta.consent))
            a.nav("account")
        })
        consentCard.addView(cRow, Ui.fill(cRow, 0))
        root.addView(consentCard, Ui.fill(consentCard))

        // 演示数据 / 清除
        val dataCard = Ui.panel(c, "本机数据")
        dataCard.addView(Ui.btn(c, "载入演示诊断（示例学情）") {
            val ans = StoreService.loadAnswers()
            DemoDataCompat().seed(ans)
            StoreService.saveAnswers(ans)
            Toast.makeText(c, "已载入演示诊断（可在本页清除）", Toast.LENGTH_SHORT).show()
        })
        dataCard.addView(Ui.btn(c, "清除本机数据（全部重置）", danger = true) {
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
        root.addView(Ui.pageHeader(
            c, "试卷 · 作业 · 错题（文本导入）",
            "粘贴试卷文本 → 本地确定性结构化（板块/题头/选项/答案/题型）。拍照识别请用 Web 单文件版或 Windows 壳（OCR 引擎在浏览器内联）。",
        ), Ui.fill(root, 22))

        val inputPanel = Ui.panel(c, "粘贴试卷文本")
        val input = EditText(c).apply {
            hint = "示例：\n一、单选题\n1. 下面哪个是合法变量名？（ ）\nA. 1a\nB. _a\nC. for\n答案：B"
            setTextSize(0, Ui.sp(c, Ui.FS_HINT))
            minLines = 6
            background = Ui.shape(Ui.FIELD, Ui.dpF(c, Ui.R_CTRL), Ui.dp(c, 1), Ui.RULE)
            setPadding(Ui.dp(c, 12), Ui.dp(c, 10), Ui.dp(c, 12), Ui.dp(c, 10))
        }
        inputPanel.addView(input, Ui.fill(input, 0))
        val resultBox = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }
        inputPanel.addView(Ui.btn(c, "解析并结构化", primary = true) {
            val r = ExamService.structure(input.text.toString())
            resultBox.removeAllViews()
            if (r.items.isEmpty()) {
                resultBox.addView(Ui.status(c, "没有识别到题目——检查题头（1. ）与选项（A. ）格式。", Ui.Kind.WARN))
                return@btn
            }
            resultBox.addView(Ui.status(
                c, "识别 ${r.items.size} 题 · " + r.sections.joinToString("；") { "${it.first} ${it.second} 题" },
                Ui.Kind.OK,
            ))
            // 知识点匹配：当前教材节点标题长词优先（与 Web 版口径一致的单题上限 4）
            val book = PagesCore.activeBook()
            r.items.forEach { it2 ->
                val card = Ui.card(c)
                val kps = book?.nodes?.filter { it2.stem.contains(it.title) }?.map { it.title }?.take(4) ?: emptyList()
                card.addView(Ui.label(c, "${it2.no}. [${it2.qtype}] ${it2.stem.replace("\n", " ").take(60)}", Ui.FS_HINT, Ui.INK))
                if (it2.options.isNotEmpty()) card.addView(Ui.label(c, it2.options.joinToString("  "), Ui.FS_BADGE, Ui.MUTED))
                if (it2.answer.isNotEmpty()) card.addView(Ui.badge(c, "答案：${it2.answer}", Ui.Kind.OK))
                if (kps.isNotEmpty()) card.addView(Ui.label(c, "知识点：${kps.joinToString("、")}", Ui.FS_BADGE, Ui.PRIMARY))
                resultBox.addView(card, Ui.fillCard(card))
            }
            val newPaper = com.astralpath.nativeapp.data.Paper(
                id = "paper-" + System.currentTimeMillis(), name = "粘贴导入", type = "exam",
                items = r.items.map { com.astralpath.nativeapp.data.PaperItem(it.no, it.section, it.stem, it.options, it.answer, it.qtype) },
                created = System.currentTimeMillis(),
            )
            StoreService.savePapers(listOf(newPaper) + StoreService.loadPapers())
        })
        inputPanel.addView(resultBox, Ui.fill(resultBox, 0))
        root.addView(inputPanel, Ui.fill(inputPanel))
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
