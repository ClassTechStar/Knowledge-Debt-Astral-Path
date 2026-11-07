package com.astralpath.nativeapp.ui

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.astralpath.nativeapp.MainActivity
import com.astralpath.nativeapp.data.Book
import com.astralpath.nativeapp.data.DemoData
import com.astralpath.nativeapp.service.DocService
import com.astralpath.nativeapp.service.FormulaService
import com.astralpath.nativeapp.service.KgService
import com.astralpath.nativeapp.service.SanitizeService
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.StoreService

/** 起点页 / 藏书阁 / 识网 —— 对应 Web 版 p-home / p-materials / p-graph */
object PagesCore {

    private fun scroll(content: LinearLayout): ScrollView {
        val sv = ScrollView(content.context)
        sv.addView(content)
        sv.setBackgroundColor(Ui.BG)
        return sv
    }

    fun activeBook(): Book? {
        val books = StoreService.loadBooks()
        val meta = StoreService.loadMeta()
        return books.find { it.id == meta.activeBookId } ?: books.firstOrNull()
    }

    // ── 起点页 ──
    fun homePage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        val hero = Ui.card(c, bg = Ui.SURFACE, radius = 18, pad = 16)
        hero.addView(Ui.label(c, "把讲义变成识网，再把欠债算清楚", 18f, Ui.INK, bold = true))
        hero.addView(Ui.label(c, "上传教材 → 本机解析 → 自动识网 → 今日任务与知识债诊断。全部计算在本机完成。", 12f, Ui.MUTED))
        val row = Ui.row(c)
        val seed = Ui.button(c, "导入示例教材", primary = true) {
            val books = StoreService.loadBooks().toMutableList()
            if (books.none { it.id == "demo-python" }) {
                books.add(DemoData.build())
                StoreService.saveBooks(books)
            }
            StoreService.saveMeta(StoreService.loadMeta().copy(activeBookId = "demo-python"))
            val ans = StoreService.loadAnswers()
            DemoData.seedMastery().forEach { (k, m) -> if (ans.mastery[k] == null) ans.mastery[k] = m }
            ans.logs.addAll(DemoData.seedLogs())
            StoreService.saveAnswers(ans)
            NotifyBus.push(NotifyBus.Level.INFO, "示例教材", "已导入示例教材与演示学情，去「知债」页看红边")
            a.nav("home")
        }
        val openMaterials = Ui.button(c, "打开藏书阁") { a.nav("materials") }
        row.addView(seed); row.addView(openMaterials, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = Ui.dp(c, 8) })
        hero.addView(row, Ui.fill(seed))
        root.addView(hero, Ui.fill(hero))

        val b = activeBook()
        val info = Ui.card(c)
        info.addView(Ui.label(c, "当前教材", 13f, Ui.MUTED))
        if (b == null) {
            info.addView(Ui.label(c, "暂无资料——点上面「导入示例教材」体验完整流程", 14f, Ui.MUTED))
        } else {
            info.addView(Ui.label(c, b.name, 15f, Ui.INK, bold = true))
            info.addView(Ui.label(c, "${b.nodes.size} 节点 / ${b.edges.size} 边 / ${b.qs.size} 题", 12f, Ui.MUTED))
        }
        root.addView(info, Ui.fill(info))

        val status = Ui.card(c)
        status.addView(Ui.label(c, "解析 → 构图 → 识网 → 今日任务，全部在这台设备上完成，不上传任何数据 · 离线就绪", 12f, Ui.OK, bold = true))
        root.addView(status, Ui.fill(status))
        return scroll(root)
    }

    // ── 藏书阁 ──
    fun materialsPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.label(c, "藏书阁", 18f, Ui.INK, bold = true))
        root.addView(Ui.label(c, "支持 TXT / Markdown / HTML / DOCX / PPTX / EPUB 导入（PDF 请用 Web 单文件版或 Windows 壳，原生 v1 暂不做文本层抽取）。解析后自动建识网。", 12f, Ui.MUTED))
        val tip = Ui.label(c, "", 12f, Ui.BRAND)
        val row = Ui.row(c)
        row.addView(Ui.button(c, "导入示例教材") {
            StoreService.saveBooks((StoreService.loadBooks() + DemoData.build()).distinctBy { it.id })
            StoreService.saveMeta(StoreService.loadMeta().copy(activeBookId = "demo-python"))
            NotifyBus.push(NotifyBus.Level.INFO, "示例教材", "已导入示例教材（含演示学情）")
            a.nav("materials")
        })
        val pick = Ui.button(c, "选择文件解析", primary = true) {
            a.openDocument { uri: Uri, name: String ->
                try {
                    val bytes = a.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                    val dr = DocService.parse(bytes, name)
                    val text = if (dr.kind == com.astralpath.nativeapp.service.DocService.Kind.MD || dr.kind == com.astralpath.nativeapp.service.DocService.Kind.TXT)
                        dr.text else KgService.splitChapters(dr.text).joinToString("\n") { "# ${it.title}\n${it.body}" }.ifEmpty { dr.text }
                    val book = KgService.build(name.removeSuffix(".${name.substringAfterLast('.')}"), SanitizeService.mask(text))
                    StoreService.saveBooks(StoreService.loadBooks() + book)
                    StoreService.saveMeta(StoreService.loadMeta().copy(activeBookId = book.id))
                    tip.text = "解析完成：${book.nodes.size} 节点 / ${book.edges.size} 边（${dr.note}）"
                    NotifyBus.push(NotifyBus.Level.INFO, "解析完成", "${book.name}：${book.nodes.size} 节点 / ${book.edges.size} 边")
                    a.nav("materials")
                } catch (e: Exception) {
                    tip.text = "解析失败：${e.message}"
                }
            }
        }
        row.addView(pick)
        root.addView(row, Ui.fill(pick))
        root.addView(tip, Ui.fill(tip))

        val books = StoreService.loadBooks()
        val meta = StoreService.loadMeta()
        for (b in books) {
            val card = Ui.card(c, bg = if (b.id == meta.activeBookId) Ui.BRAND_SOFT else Ui.SOFT)
            card.addView(Ui.label(c, b.name, 14f, Ui.INK, bold = true))
            card.addView(Ui.label(c, "${b.nodes.size} 节点 / ${b.edges.size} 边 / ${b.qs.size} 题 · ${b.source ?: "text"}", 11f, Ui.MUTED))
            if (b.id != meta.activeBookId) {
                card.addView(Ui.button(c, "设为当前") {
                    StoreService.saveMeta(StoreService.loadMeta().copy(activeBookId = b.id))
                    a.nav("materials")
                })
            }
            root.addView(card, Ui.fill(card))
        }
        return scroll(root)
    }

    // ── 识网 ──
    fun graphPage(a: MainActivity): View {
        val c = a
        val root = LinearLayout(c)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(Ui.BG)
        val header = Ui.card(c, pad = 10)
        header.addView(Ui.label(c, "识网", 18f, Ui.INK, bold = true))
        val detail = Ui.label(c, "点击节点查看先修与后续", 12f, Ui.MUTED)
        val book = activeBook()
        if (book == null) {
            header.addView(Ui.label(c, "该教材暂无图谱。请到藏书阁解析文件，或导入示例教材。", 13f, Ui.MUTED))
            root.addView(header)
            return root
        }
        val ans = StoreService.loadAnswers()
        val scores = HashMap<String, Double>()
        val visiting = mutableMapOf<String, Double>()
        book.nodes.forEach { n -> scores[n.id] = FormulaService.scoreOfGraph(n.id, book.edges, ans.mastery, visiting) }
        val debts = FormulaService.diagnose(book.edges, book.nodes.associate { it.id to it.title }, ans.mastery, ans.logs)
        val redIds = debts.map { it.id }.toSet()
        header.addView(Ui.label(c, "${book.name} · ${book.nodes.size} 节点 / ${book.edges.size} 边 · 红边 ${debts.size} 条", 12f, Ui.MUTED))
        root.addView(header, Ui.fill(header))

        val graph = GraphView(c, book.nodes, book.edges, redIds, scores, book.nodes.associate { it.id to it.title }) { id ->
            val pre = book.edges.filter { it.b == id }.mapNotNull { book.nodes.find { n -> n.id == it.a }?.title }
            val post = book.edges.filter { it.a == id }.mapNotNull { book.nodes.find { n -> n.id == it.b }?.title }
            val t = book.nodes.find { it.id == id }?.title ?: id
            detail.text = "「$t」掌握 ${((scores[id] ?: 0.0) * 100).toInt()}% · 先修：${pre.joinToString("、").ifEmpty { "无" }} · 后续：${post.joinToString("、").ifEmpty { "无" }}"
        }
        graph.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0).apply { weight = 1f; topMargin = Ui.dp(c, 6) }
        root.addView(graph)
        val dwrap = Ui.card(c, pad = 10)
        dwrap.addView(detail)
        root.addView(dwrap, Ui.fill(dwrap))
        return root
    }
}
