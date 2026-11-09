package com.astralpath.nativeapp.ui

import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.astralpath.nativeapp.MainActivity
import com.astralpath.nativeapp.data.AiCfg
import com.astralpath.nativeapp.service.AiService
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.StoreService

/**
 * 智能体页 —— 意图路由 + 危机转介 + 模型流式（可停止），移植自鸿蒙版 AgentPage.ets。
 * 版式对齐 Web：page-h 标题区 + panel 卡片流（对话面板 / 输入行 / 快捷入口）；
 * 业务功能与数据逻辑保持不变。
 */
object PagesAgent {
    /** 危机词：与 tools/agent-intents.json 的 crisis 列表一致（11 个，verify_agent_intents 对拍） */
    val CRISIS = listOf("不想活", "自杀", "轻生", "结束生命", "自残", "伤害自己", "跳楼", "上吊", "suicide", "kill myself", "活不下去")

    data class IntentDef(val id: String, val anchors: List<String>, val reply: String)

    /** 25 个意图锚点与本地兜底答复；crisis.handoff 由危机分支独立承担，合计覆盖登记表 26 个 */
    val INTENTS = listOf(
        IntentDef("debt.diagnose", listOf("知识债", "债边", "诊断", "红边", "薄弱", "搞不清", "漏洞", "哪里不会", "哪里薄弱", "帮我分析"), "去「知债」页点重新诊断，会按 impact 公式算出开放红边。"),
        IntentDef("debt.explain", listOf("解释", "为什么", "怎么来的", "公式", "讲解", "怎么回事", "什么意思", "怎么理解", "什么原理"), "影响分 = 先修缺口 × 后续薄弱 × 边权 ×（跨课程 1.15 倍）× 级联放大，≥0.08 判为开放红边。"),
        IntentDef("plan.create", listOf("计划", "14天", "安排", "复习计划", "做个计划", "怎么安排", "复习规划"), "「知债」页点生成 14 天计划：先修优先，每天不超过 40 分钟，同一知识点间隔至少 1 天。"),
        IntentDef("plan.rebalance", listOf("减负", "重排", "调整计划", "太重", "换个计划", "改一下计划"), "计划排完可以再点一次生成，把每天时长预算压低一点就会重排。"),
        IntentDef("today.tasks", listOf("今日", "今天做", "今日任务", "今天学什么", "现在学什么", "该学什么", "今天干什么"), "「今日」页会按掌握度从低到高列出 5 条任务，点开始练习就行。"),
        IntentDef("practice.start", listOf("练习", "做题", "小测", "测验", "来几道", "出几道", "出个题", "刷几道", "做几道", "练一下"), "「今日」页点开始练习；题库来自教材解析结果，答完会更新掌握度。"),
        IntentDef("progress.check", listOf("进度", "销账", "进展", "streak", "学得怎么样", "看看进度", "掌握怎么样"), "「知债」页点销账检查：连续 2 次达标且累计 3 次作答才算结清。"),
        IntentDef("graph.view", listOf("图谱", "识网", "知识图谱", "思维导图", "关系图", "知识网", "看看图"), "「识网」页看知识点和先修关系，点节点能看到它的先修与后续。"),
        IntentDef("material.parse", listOf("解析资料", "上传", "OCR", "教材", "藏书", "解析文件", "导入教材", "上传课本"), "「藏书阁」支持 TXT / DOCX / PPTX / EPUB 等文本类导入，解析完自动生成识网。"),
        IntentDef("material.list", listOf("列出资料", "教材列表", "藏书", "有哪些书", "书单", "几本书", "已解析教材", "有什么教材"), "「藏书阁」列出已解析教材，点「设为当前」切换。"),
        IntentDef("material.switch", listOf("切换教材", "换书", "切书", "切换到", "换一本", "切到", "切过去", "换个教材", "换本书"), "「藏书阁」点某本书的「设为当前」即可切换。"),
        IntentDef("kb.search", listOf("知识库", "检索", "什么是", "查资料", "文档", "搜索", "搜一下", "查一下", "找找", "章节", "帮我找", "找找看", "查一查", "讲一下", "知识点", "介绍", "概要", "概述", "概括"), "可以在「识网」页按知识点名称找，或在「藏书阁」翻章节目录。"),
        IntentDef("kb.ingest", listOf("入库", "上传文档", "发布知识"), "在「藏书阁」上传资料解析后自动入库，生成识网与题库。"),
        IntentDef("profile.view", listOf("画像", "我的标签", "学习画像", "我的情况"), "「画像」页看掌握/薄弱分布和累计作答；不想被画像可以随时关掉个性化。"),
        IntentDef("profile.optout", listOf("退出画像", "关闭画像", "opt-out"), "「画像」页底部开关：关掉后只按教材章节顺序安排，不依据知识债推断。"),
        IntentDef("teacher.hotspots", listOf("热点", "班级", "共性问题", "大家的情况"), "「教师」页是 k-匿名聚合的，样本少于 3 人只显示「样本不足」。"),
        IntentDef("consent.grant", listOf("授权", "同意可见", "consent", "允许查看"), "「账户」页有授权开关，不授权默认教师侧不可见（fail-closed）。"),
        IntentDef("consent.revoke", listOf("撤销", "取消授权", "关闭可见"), "「账户」页把授权开关关掉，立刻失效。注意「撤销授权」不是要授权。"),
        IntentDef("whatif.simulate", listOf("what-if", "如果", "模拟", "假设", "假如", "要是", "试想"), "「知债」页底部有 What-if 模拟：拖动前置掌握、目标掌握、错题频次三个滑杆，实时看影响分变化。"),
        IntentDef("narrative.read", listOf("故事", "叙事", "讲解", "讲个故事", "举个例子", "给我讲讲", "讲一讲"), "配了模型密钥就能讲；没配的话我可以按知识点给你一段要点。"),
        IntentDef("sale.check", listOf("销账检查", "能否销账", "销账条件", "能销账吗", "销账了没"), "「知债」页销账检查：加权得分 ≥0.65 且正确率 ≥70%、信心 ≥3，连续 2 次才算结清。"),
        IntentDef("chapter.read", listOf("目录", "读一下", "讲了什么", "讲了啥", "章节", "这一章", "内容是什么", "翻到", "第几章", "前几章", "本章", "这章", "有什么内容", "不明白", "不懂", "不理解", "不清楚"), "「藏书阁」选中教材后能看到章节骨架。"),
        IntentDef("graph.path", listOf("什么关系", "怎么联系", "有没有关", "路径", "谁先", "先后", "前置", "怎么到", "怎么学", "学习顺序", "什么联系", "有关吗", "先后顺序"), "「识网」页点节点，能看到它的先修和后续，按顺序学就行。"),
        IntentDef("meta.help", listOf("帮助", "怎么用", "说明", "你能干什么", "你会什么", "功能有哪些"), "流程是：藏书阁解析教材 → 识网看关系 → 今日做题 → 知债诊断 → 生成计划 → 练熟销账。"),
        IntentDef("meta.feedback", listOf("反馈", "建议", "不好用"), "记下了。也可以直接告诉我哪一步不顺手。"),
    )

    fun page(a: MainActivity): View {
        val c = a
        val root = Ui.page(c)
        root.addView(Ui.pageHeader(
            c, "受约束智能体",
            "意图路由、危机转人工、敏感词脱敏。数字只来自本地公式。",
        ), Ui.fill(root, 22))

        // 对话面板（对齐 Web .panel + .chat：面板内滚动对话区）
        val chatPanel = Ui.panel(c, "对话", "可问「我的知识债」「生成计划」「这周学不完」等。")
        val transcript = ScrollView(c).apply {
            setBackgroundColor(Ui.SOFT)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0,
            ).apply { weight = 1f }
        }
        val transcriptInner = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.dp(c, 8), Ui.dp(c, 8), Ui.dp(c, 8), Ui.dp(c, 8))
        }
        transcript.addView(transcriptInner)
        chatPanel.addView(transcript)
        root.addView(chatPanel, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f,
        ).apply { bottomMargin = Ui.dp(c, Ui.GAP_PANEL) })

        val input = EditText(c).apply {
            hint = "问点什么，例如「帮我讲讲会计等式」"
            setTextSize(0, Ui.sp(c, Ui.FS_HINT))
            background = Ui.shape(Ui.FIELD, Ui.dpF(c, Ui.R_CTRL), Ui.dp(c, 1), Ui.RULE)
            setPadding(Ui.dp(c, 12), Ui.dp(c, 8), Ui.dp(c, 12), Ui.dp(c, 8))
        }
        val sendBtnHolder = arrayOfNulls<TextView>(1)
        val chat = LinearLayout(c).apply { orientation = LinearLayout.VERTICAL }
        transcriptInner.addView(chat)

        // 气泡（对齐 Web .bub.user / .bub.bot）
        fun addBubble(text: String, isUser: Boolean) {
            val t = TextView(c).apply {
                this.text = text
                setTextSize(0, Ui.sp(c, Ui.FS_HINT))
                setTextColor(if (isUser) Ui.SURFACE else Ui.INK)
                setPadding(Ui.dp(c, 10), Ui.dp(c, 6), Ui.dp(c, 10), Ui.dp(c, 6))
                background = Ui.shape(
                    if (isUser) Ui.PRIMARY else Ui.SOFT,
                    Ui.dpF(c, 14f),
                )
            }
            val wrap = LinearLayout(c).apply { orientation = LinearLayout.HORIZONTAL }
            val lp = LinearLayout.LayoutParams(
                if (isUser) LinearLayout.LayoutParams.WRAP_CONTENT else LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = Ui.dp(c, 4); bottomMargin = Ui.dp(c, 4)
                gravity = if (isUser) android.view.Gravity.END else android.view.Gravity.START
            }
            wrap.addView(t)
            chat.addView(wrap, lp)
            transcript.post { transcript.fullScroll(ScrollView.FOCUS_DOWN) }
        }

        fun crisis(text: String): Boolean = CRISIS.any { text.lowercase().contains(it.lowercase()) }

        fun route(text: String): IntentDef? =
            INTENTS.map { it to it.anchors.count { a -> text.contains(a) } }
                .maxByOrNull { it.second }?.takeIf { it.second > 0 }?.first

        fun localReply(q: String): String =
            route(q)?.reply ?: "（演示模式，未配置模型密钥）先补先修知识点，再回到这道题。"

        fun send() {
            if (input.text.isNullOrBlank()) return
            val q = input.text.toString().trim()
            input.setText("")
            addBubble("我：$q", isUser = true)
            if (crisis(q)) {
                // 红线 1：危机词最高优先级，不作答；常驻对话框（点确认才关），对齐 Web 危机口径
                addBubble("智能体：这类问题我不回答。请联系学校心理辅导老师，或拨打心理援助热线，有人能帮你。", isUser = false)
                NotifyBus.push(NotifyBus.Level.CRISIS, "你不是一个人在扛",
                    "请联系学校心理辅导老师，或拨打心理援助热线（全国 24 小时）。系统不会把这段对话当作处分依据。")
                return
            }
            val cfg0 = StoreService.loadAiCfg()
            val cfg = AiCfg(cfg0.baseUrl.ifEmpty { AiService.DEFAULT_BASE }, cfg0.key, cfg0.model.ifEmpty { "mimo-7b-rl" })
            if (!AiService.ready(cfg)) {
                addBubble("智能体：${localReply(q)}", isUser = false)
                return
            }
            // 模型流式：按钮变「■ 停止」；取消≠失败，保留已生成部分（DeepTutor cancel 语义）
            sendBtnHolder[0]?.text = "■ 停止"
            val live = TextView(c).apply {
                setTextSize(0, Ui.sp(c, Ui.FS_HINT)); setTextColor(Ui.MUTED); text = "▍思考中…"
            }
            chat.addView(live)
            transcript.post { transcript.fullScroll(ScrollView.FOCUS_DOWN) }
            val ctx = buildString {
                append("你是「知债：星穹学途」的学习助手。只负责讲解与建议，不得改写任何由本地公式算出的数字。")
                PagesCore.activeBook()?.let { append("\n当前教材：${it.name}；知识点：${it.nodes.take(20).joinToString("、") { n -> n.title }}") }
                append("\n学生问题：").append(q)
            }
            Thread {
                val r = AiService.stream(cfg, ctx, ctx, 1500,
                    onDelta = { full -> a.runOnUiThread { if (!AiService.cancelled) live.text = "▍" + full.takeLast(600) } },
                    onThinking = { tail -> a.runOnUiThread { if (!AiService.cancelled) live.text = "▍思考中：…$tail" } },
                )
                a.runOnUiThread {
                    sendBtnHolder[0]?.text = "发送"
                    chat.removeView(live)
                    when {
                        r == null -> {
                            addBubble("智能体：（网络不可用或模型异常）${localReply(q)}", isUser = false)
                        }
                        r.second && r.first.isEmpty() -> {
                            // 一个字都没收到就停止：回退本地兜底，不出空泡
                            addBubble("智能体：（已停止）${localReply(q)}", isUser = false)
                        }
                        r.second -> addBubble("智能体：${r.first}\n\n（已手动停止，以上为已生成部分）", isUser = false)
                        else -> addBubble("智能体：${com.astralpath.nativeapp.service.SanitizeService.mask(r.first)}", isUser = false)
                    }
                }
            }.start()
        }

        // 输入行（对齐 Web input.chatin + .btn.primary）
        val row = Ui.row(c)
        row.addView(input, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val sendBtn = Ui.btn(c, "发送", primary = true) { send() }
        sendBtnHolder[0] = sendBtn
        row.addView(sendBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { leftMargin = Ui.dp(c, 8) })
        root.addView(row, Ui.fill(row))

        // 快捷入口（对齐 Web 版 data-q 快捷按钮）
        val quick = Ui.row(c)
        listOf("压力求助" to "我这周学不完计划了", "诊断债" to "帮我诊断知识债", "生成计划" to "生成14天计划").forEach { (label, q) ->
            quick.addView(Ui.btn(c, label, quiet = true) { input.setText(q); send() })
        }
        root.addView(quick, Ui.fill(quick))
        addBubble("你好，我是知债学习助手。可问「我的知识债」「生成计划」「这周学不完」等。", isUser = false)
        return root
    }
}
