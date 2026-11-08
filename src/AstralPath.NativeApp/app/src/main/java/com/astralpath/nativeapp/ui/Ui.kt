package com.astralpath.nativeapp.ui

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 设计 token + 组件库 —— 对齐 Web 版 index.html 的 :root CSS 变量与组件规范。
 * 色板 / 圆角 / 字号 / 间距逐项照抄 Web；组件函数与 Web 类一一对应：
 *   pageHeader ↔ .page-h   panel ↔ .panel   card ↔ .card   btn ↔ .btn
 *   badge ↔ .badge        status ↔ .status  bar ↔ .bar     stat ↔ .stat
 * 全部 UI 程序化构建（对应 Web 的 DOM 组装）。
 */
object Ui {
    // ── 色板（对齐 Web 版 :root CSS 变量，十六进制照抄）──
    val CANVAS = 0xFFF3F4F5.toInt()        // --canvas 页面底
    val SURFACE = 0xFFFBFBFC.toInt()       // --surface 卡片面
    val SOFT = 0xFFE8EAEC.toInt()          // --soft 软灰块 / 进度底 / 胶囊导航底
    val STRONG = 0xFF6B7075.toInt()        // --strong
    val INK = 0xFF303236.toInt()           // --ink 正文
    val MUTED = 0xFF62676C.toInt()         // --muted 次要文字
    val RULE = 0xFFC7CACF.toInt()          // --rule 描边 / 分隔线
    val FIELD = 0xFFEFF0F2.toInt()         // --field 输入框底
    val PRIMARY = 0xFF0D72D9.toInt()       // --primary 主按钮 / 进度
    val PRIMARY_SOFT = 0xFF6AA8F0.toInt()  // 渐变末端
    val DANGER = 0xFFB64A58.toInt()        // --danger
    val OK = 0xFF55A77B.toInt()            // --ok
    val OK_BG = 0xFFDCF4E7.toInt()         // --ok-bg
    val OK_INK = 0xFF1E5D43.toInt()        // --ok-ink
    val OK_TEXT = 0xFF2F6B50.toInt()       // .status.ok 文字
    val WARN = 0xFFB8860B.toInt()          // --warn
    val WARN_BG = 0xFFFFF4D6.toInt()       // --warn-bg
    val WARN_INK = 0xFF6A5010.toInt()      // --warn-ink
    val ERR_BG = 0xFFFFE1E5.toInt()        // err 徽标底 #FFE1E5
    val ERR_INK = 0xFF792E38.toInt()       // err 徽标字 #792E38
    val ERR_TEXT = 0xFF8D2828.toInt()      // .status.err 文字

    // ── 图谱节点三色（对齐 Web .dnode.chapter / .term / .debt）──
    val CH_EDGE = 0xFF4F86C6.toInt(); val CH_FILL = 0xFFE0EDF9.toInt(); val CH_INK = 0xFF1D3D5F.toInt()
    val TM_EDGE = 0xFF55A77B.toInt(); val TM_FILL = 0xFFDCF2E8.toInt(); val TM_INK = 0xFF1E5D43.toInt()
    val DB_EDGE = 0xFFD95A67.toInt(); val DB_FILL = 0xFFFFE1E5.toInt(); val DB_INK = 0xFF792E38.toInt()
    val LINK = 0xFF55A77B.toInt()          // 连线 #55A77B（透明度 0.75 绘制时施加）

    // ── 圆角（对齐 Web --r-c 18 / --r-g 28 / --r-shell 36 / 胶囊 999）──
    const val R_CTRL = 18f
    const val R_CARD = 28f
    const val R_SHELL = 36f
    const val R_PILL = 999f

    // ── 字号 sp（对齐 Web 字号表）──
    const val FS_BODY = 15f      // 正文
    const val FS_PANEL = 20f     // 面板标题
    const val FS_HINT = 13f      // hint
    const val FS_BADGE = 12f     // 徽标
    const val FS_BTN = 14f       // 按钮
    const val FS_NODE = 12.5f    // 节点标签
    const val FS_NODE_CH = 11f   // 章节节点标签
    const val FS_PAGE = 26f      // 页面大标题
    const val FS_STAT = 24f      // stat 大数字

    // ── 间距 dp / 行高（对齐 Web 间距表）──
    const val PAD_PANEL = 20     // 面板内边距
    const val GAP_PANEL = 14     // 面板间距（.panel 下边距 14）
    const val PAD_CARD = 16      // 卡片水平内边距
    const val PAD_CARD_V = 14    // 卡片垂直内边距（.card padding 14px 16px）
    const val LINE = 1.55f       // 行高 1.55 倍

    // ── 尺寸换算 ──
    fun dp(c: Context, v: Int): Int = (v * c.resources.displayMetrics.density).toInt()
    fun dpF(c: Context, v: Float): Float = v * c.resources.displayMetrics.density
    fun sp(c: Context, v: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, c.resources.displayMetrics)

    /** 画笔/背景用的圆角矩形 */
    fun shape(bg: Int, radius: Float, strokeW: Int = 0, stroke: Int = 0): GradientDrawable =
        GradientDrawable().apply {
            setColor(bg)
            cornerRadius = radius
            if (strokeW > 0) setStroke(strokeW, stroke)
        }

    /** 文本（行高 1.55 倍，对齐 Web font:15px/1.55） */
    fun label(c: Context, text: String, size: Float = FS_BODY, color: Int = INK, bold: Boolean = false): TextView {
        val t = TextView(c)
        t.text = text
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        t.setTextColor(color)
        t.setLineSpacing(0f, LINE)
        if (bold) t.typeface = Typeface.DEFAULT_BOLD
        return t
    }

    // ── 页面骨架 ──

    /** 页面根容器：canvas 底色，对应 html,body{background:var(--canvas)} */
    fun page(c: Context): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.setPadding(dp(c, 16), dp(c, 12), dp(c, 16), dp(c, 24))
        l.setBackgroundColor(CANVAS)
        return l
    }

    /** 页面标题区（对齐 Web .page-h：大标题 + muted 说明，下边距 22） */
    fun pageHeader(c: Context, title: String, desc: String? = null): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.addView(label(c, title, FS_PAGE, INK, bold = true))
        if (!desc.isNullOrEmpty()) {
            val d = label(c, desc, FS_HINT, MUTED)
            d.setPadding(0, dp(c, 2), 0, 0)
            l.addView(d)
        }
        return l
    }

    /**
     * 面板卡片（对齐 Web .panel：padding 20 / border 1dp rule / 圆角 28 / 背景 surface，
     * 标题 20sp bold ink，hint 13sp muted；面板间距 14 由 fill() 的下边距提供）。
     */
    fun panel(c: Context, title: String? = null, hint: String? = null): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.setPadding(dp(c, PAD_PANEL), dp(c, PAD_PANEL), dp(c, PAD_PANEL), dp(c, PAD_PANEL))
        l.background = shape(SURFACE, dpF(c, R_CARD), dp(c, 1), RULE)
        if (title != null) l.addView(label(c, title, FS_PANEL, INK, bold = true))
        if (!hint.isNullOrEmpty()) {
            val h = label(c, hint, FS_HINT, MUTED)
            if (title != null) h.setPadding(0, dp(c, 2), 0, dp(c, 4))
            l.addView(h)
        }
        return l
    }

    /**
     * 卡片（对齐 Web .card：圆角 28 / 背景 surface / border 1dp rule（选中 2dp primary）/
     * padding 14/16）。selected=true 时走 .card.active 规范。
     */
    fun card(c: Context, bg: Int = SURFACE, selected: Boolean = false): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.setPadding(dp(c, PAD_CARD), dp(c, PAD_CARD_V), dp(c, PAD_CARD), dp(c, PAD_CARD_V))
        val sw = if (selected) 2 else 1
        val sc = if (selected) PRIMARY else RULE
        l.background = shape(bg, dpF(c, R_CARD), dp(c, sw), sc)
        return l
    }

    /** 按钮（对齐 Web .btn：min-height 44 / padding 8/16 / 圆角 18 / 1dp rule / 字 14sp） */
    fun btn(
        c: Context, text: String,
        primary: Boolean = false, danger: Boolean = false, quiet: Boolean = false,
        onClick: (View) -> Unit,
    ): TextView {
        val t = TextView(c)
        t.text = text
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (quiet) FS_BADGE else FS_BTN)
        t.gravity = Gravity.CENTER
        t.setPadding(dp(c, 16), dp(c, 8), dp(c, 16), dp(c, 8))
        t.minimumHeight = dp(c, 44)
        t.background = when {
            quiet -> null                                    // .btn.quiet：无边透明
            primary -> shape(PRIMARY, dpF(c, R_CTRL))        // .btn.primary：底 primary 字白
            danger -> shape(SURFACE, dpF(c, R_CTRL), dp(c, 1), DANGER) // .btn.danger：边/字 danger
            else -> shape(SURFACE, dpF(c, R_CTRL), dp(c, 1), RULE)
        }
        t.setTextColor(
            when {
                primary -> 0xFFFFFFFF.toInt()
                danger -> DANGER
                quiet -> MUTED
                else -> INK
            }
        )
        t.isClickable = true
        t.isFocusable = true
        t.setOnClickListener(onClick)
        return t
    }

    /** 徽标（对齐 Web .badge：胶囊 / 12sp / padding 2/8，ok/warn/err 三色） */
    fun badge(c: Context, text: String, kind: Kind = Kind.OK): TextView {
        val t = TextView(c)
        t.text = text
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, FS_BADGE)
        t.setPadding(dp(c, 8), dp(c, 2), dp(c, 8), dp(c, 2))
        val (bg, ink) = when (kind) {
            Kind.OK -> OK_BG to OK_INK
            Kind.WARN -> WARN_BG to WARN_INK
            Kind.ERR -> ERR_BG to ERR_INK
        }
        t.background = shape(bg, dpF(c, R_PILL))
        t.setTextColor(ink)
        return t
    }

    /**
     * 状态条（对齐 Web .status：左边 3dp 实色竖条 + 软灰底 / 13sp，
     * ok/err/warn 变体换色，warn 底 warnBg）。
     */
    fun status(c: Context, text: String, kind: Kind? = null): LinearLayout {
        val wrap = LinearLayout(c)
        wrap.orientation = LinearLayout.HORIZONTAL
        wrap.gravity = Gravity.CENTER_VERTICAL
        val barColor = when (kind) {
            Kind.OK -> OK; Kind.ERR -> DANGER; Kind.WARN -> WARN; null -> STRONG
        }
        val bg = if (kind == Kind.WARN) WARN_BG else SOFT
        val ink = when (kind) {
            Kind.OK -> OK_TEXT; Kind.ERR -> ERR_TEXT; Kind.WARN -> WARN_INK; null -> MUTED
        }
        val strip = View(c)
        strip.setBackgroundColor(barColor)
        wrap.addView(strip, LinearLayout.LayoutParams(dp(c, 3), LinearLayout.LayoutParams.MATCH_PARENT))
        val body = LinearLayout(c)
        body.orientation = LinearLayout.VERTICAL
        body.setPadding(dp(c, 14), dp(c, 12), dp(c, 14), dp(c, 12))
        body.setBackgroundColor(bg)
        body.addView(label(c, text, FS_HINT, ink))
        wrap.addView(body, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return wrap
    }

    /** 进度条（对齐 Web .bar：高 10dp 圆角 99 / 底 soft / 填充 primary→primarySoft 横向渐变） */
    fun bar(c: Context, progress: Float): LinearLayout {
        val track = LinearLayout(c)
        track.orientation = LinearLayout.HORIZONTAL
        val p = progress.coerceIn(0f, 1f)
        val fill = View(c)
        val grad = GradientDrawable(
            GradientDrawable.Orientation.LEFT_RIGHT,
            intArrayOf(PRIMARY, PRIMARY_SOFT),
        ).apply { cornerRadius = dpF(c, R_PILL) }
        fill.background = grad
        track.addView(fill, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, p))
        track.addView(View(c), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f - p))
        track.background = shape(SOFT, dpF(c, R_PILL))
        val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(c, 10))
        lp.topMargin = dp(c, 8); lp.bottomMargin = dp(c, 8)
        track.layoutParams = lp
        return track
    }

    /** 统计块（对齐 Web .stat：小标题 13sp muted + 大数字 24sp bold ink） */
    fun stat(c: Context, title: String, value: String): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.addView(label(c, title, FS_HINT, MUTED))
        l.addView(label(c, value, FS_STAT, INK, bold = true))
        return l
    }

    // ── 通用布局辅助 ──

    fun row(c: Context): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.HORIZONTAL
        l.gravity = Gravity.CENTER_VERTICAL
        return l
    }

    /** 通用子项布局：整宽 + 下边距（面板间距 14 / 卡片间距 10，对齐 Web margin 规范） */
    fun fill(v: View, gap: Int = GAP_PANEL): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dp(v.context, gap)
        }

    /** 卡片间距（.card margin:10px 0 → 相邻卡片间隔 10） */
    fun fillCard(v: View): LinearLayout.LayoutParams = fill(v, 10)

    /** 三色徽标语义 */
    enum class Kind { OK, WARN, ERR }
}
