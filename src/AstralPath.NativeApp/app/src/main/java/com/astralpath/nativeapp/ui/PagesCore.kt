package com.astralpath.nativeapp.ui

import android.net.Uri
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import com.astralpath.nativeapp.MainActivity
import com.astralpath.nativeapp.data.Book
import com.astralpath.nativeapp.data.DemoData
import com.astralpath.nativeapp.service.DocService
import com.astralpath.nativeapp.service.FormulaService
import com.astralpath.nativeapp.service.KgService
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.SanitizeService
import com.astralpath.nativeapp.service.StoreService

/**
 * 起点页 / 藏书阁 / 识网 —— 对应 Web 版 p-home / p-materials / p-graph。
 * 版式对齐 Web：page-h 标题区 + panel 卡片流；业务功能与数据逻辑保持不变。
 */
object PagesCore {

    private fun scroll(content: LinearLayout): ScrollView {
        val sv = ScrollView(content.context)
        sv.addView(content)
        sv.setBackgroundColor(Ui.CANVAS) // 对齐 Web 页面底色 canvas
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
        root.addView(Ui.pageHeader(c, "起点", "把讲义变成识网，再把欠债算清楚"), Ui.fill(root, 22))

        // 对齐 Web .panel：导入操作面板
        val hero = Ui.panel(c, "开始", "上传教材 → 本机解析 → 自动识网 → 今日任务与知识债诊断。全部计算在本机完成。")
        val row = Ui.row(c)
        val seed = Ui.btn(c, "导入示例教材", primary = true) {
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
        val openMaterials = Ui.btn(c, "打开藏书阁") { a.nav("materials") }
        row.addView(seed)
        row.addView(openMaterials, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { leftMargin = Ui.dp(c, 8) })
        hero.addView(row, Ui.fill(row, 0))
        root.addView(hero, Ui.fill(hero))

        // 当前教材
        val b = activeBook()
        val info = Ui.panel(c, "当前教材")
        if (b == null) {
            info.addView(Ui.label(c, "暂无资料——点上面「导入示例教材」体验完整流程", Ui.FS_HINT, Ui.MUTED))
        } else {
            info.addView(Ui.label(c, b.name, Ui.FS_BODY, Ui.INK, bold = true))
            info.addView(Ui.label(c, "${b.nodes.size} 节点 / ${b.edges.size} 边 / ${b.qs.size} 题", Ui.FS_HINT, Ui.MUTED))
            info.addView(Ui.bar(c, if (b.nodes.isEmpty()) 0f else 1f)) // 对齐 Web .bar 进度条规范
        }
        root.addView(info, Ui.fill(info))

        // 状态条（对齐 Web .status.ok）
        root.addView(Ui.status(c, "解析 → 构图 → 识网 → 今日任务，全部在这台设备上完成，不上传任何数据 · 离线就绪", Ui.Kind.OK), Ui.fill(root))
        return scroll(root)
    }

    // ── 藏书阁 ──
    fun materialsPage(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.pageHeader(
            c, "藏书阁",
            "支持 TXT / Markdown / HTML / DOCX / PPTX / EPUB 导入（PDF 请用 Web 单文件版或 Windows 壳，原生 v1 暂不做文本层抽取）。解析后自动建识网。",
        ), Ui.fill(root, 22))

        val tip = Ui.label(c, "", Ui.FS_HINT, Ui.PRIMARY)
        val importPanel = Ui.panel(c, "导入", "解析完成会自动建识网并设为当前教材。")
        val row = Ui.row(c)
        row.addView(Ui.btn(c, "导入示例教材") {
            StoreService.saveBooks((StoreService.loadBooks() + DemoData.build()).distinctBy { it.id })
            StoreService.saveMeta(StoreService.loadMeta().copy(activeBookId = "demo-python"))
            NotifyBus.push(NotifyBus.Level.INFO, "示例教材", "已导入示例教材（含演示学情）")
            a.nav("materials")
        })
        val pick = Ui.btn(c, "选择文件解析", primary = true) {
            a.openDocument { uri: Uri, name: String ->
                try {
                    val bytes = a.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                    val dr = DocService.parse(bytes, name)
                    val text = if (dr.kind == DocService.Kind.MD || dr.kind == DocService.Kind.TXT)
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
        row.addView(pick, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { leftMargin = Ui.dp(c, 8) })
        importPanel.addView(row, Ui.fill(row, 0))
        importPanel.addView(tip, Ui.fill(tip, 0))
        root.addView(importPanel, Ui.fill(importPanel))

        // 教材列表
        val books = StoreService.loadBooks()
        val meta = StoreService.loadMeta()
        val listPanel = Ui.panel(c, "已解析教材", if (books.isEmpty()) "还没有教材，点上面「导入示例教材」。" else null)
        for (b in books) {
            val active = b.id == meta.activeBookId
            // 对齐 Web .card.active：选中教材 2dp primary 描边
            val card = Ui.card(c, selected = active)
            card.addView(Ui.row(c).apply {
                addView(Ui.label(c, b.name, Ui.FS_BODY, Ui.INK, bold = true), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                if (active) addView(Ui.badge(c, "当前", Ui.Kind.OK))
            })
            card.addView(Ui.label(c, "${b.nodes.size} 节点 / ${b.edges.size} 边 / ${b.qs.size} 题 · ${b.source ?: "text"}", Ui.FS_BADGE, Ui.MUTED))
            if (!active) {
                card.addView(Ui.btn(c, "设为当前", quiet = true) {
                    StoreService.saveMeta(StoreService.loadMeta().copy(activeBookId = b.id))
                    a.nav("materials")
                })
            }
            listPanel.addView(card, Ui.fillCard(card))
        }
        root.addView(listPanel, Ui.fill(listPanel))
        return scroll(root)
    }

    // ── 识网 ──
    fun graphPage(a: MainActivity): View {
        val c = a
        val root = LinearLayout(c)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(Ui.CANVAS)
        root.setPadding(Ui.dp(c, 16), Ui.dp(c, 12), Ui.dp(c, 16), Ui.dp(c, 16))

        val book = activeBook()
        val detail = Ui.label(c, "点按节点查看先修与后续", Ui.FS_HINT, Ui.MUTED)

        if (book == null) {
            root.addView(Ui.pageHeader(c, "识网", "该教材暂无图谱。请到藏书阁解析文件，或导入示例教材。"), Ui.fill(root, 22))
            return root
        }

        val ans = StoreService.loadAnswers()
        val scores = HashMap<String, Double>()
        val visiting = mutableMapOf<String, Double>()
        book.nodes.forEach { n -> scores[n.id] = FormulaService.scoreOfGraph(n.id, book.edges, ans.mastery, visiting) }
        val debts = FormulaService.diagnose(book.edges, book.nodes.associate { it.id to it.title }, ans.mastery, ans.logs)
        val redIds = debts.map { it.id }.toSet()

        root.addView(Ui.pageHeader(
            c, "识网",
            "${book.name} · ${book.nodes.size} 节点 / ${book.edges.size} 边 · 红边 ${debts.size} 条。双指捏合缩放，单指拖拽平移，双击放大。",
        ), Ui.fill(root, 22))

        val graph = GraphView(c, book.nodes, book.edges, redIds, scores, book.nodes.associate { it.id to it.title }) { id ->
            val pre = book.edges.filter { it.b == id }.mapNotNull { book.nodes.find { n -> n.id == it.a }?.title }
            val post = book.edges.filter { it.a == id }.mapNotNull { book.nodes.find { n -> n.id == it.b }?.title }
            val t = book.nodes.find { it.id == id }?.title ?: id
            detail.text = "「$t」掌握 ${((scores[id] ?: 0.0) * 100).toInt()}% · 先修：${pre.joinToString("、").ifEmpty { "无" }} · 后续：${post.joinToString("、").ifEmpty { "无" }}"
        }
        // 图谱占满剩余空间（世界坐标 + 缩放/平移由 GraphView 内部处理）
        graph.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0,
        ).apply { weight = 1f }
        root.addView(graph)

        // 详情面板（对齐 Web .panel）
        val dwrap = Ui.panel(c, "节点详情")
        dwrap.addView(detail, Ui.fill(detail, 0))
        root.addView(dwrap, Ui.fill(dwrap, 0))
        return root
    }
}
