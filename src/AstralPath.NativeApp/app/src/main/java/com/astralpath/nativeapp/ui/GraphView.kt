package com.astralpath.nativeapp.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewConfiguration
import com.astralpath.nativeapp.data.KEdge
import com.astralpath.nativeapp.data.KNode
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 识网图谱自绘 —— 对齐 Web 版 CanvasRenderer 的交互模型：
 *
 * 变换模型（对齐 Web _worldToScreen/_screenToWorld）：
 *   screen = world * scale + offset
 * 布局：世界坐标系力导向（斥力 + 弹簧 + 向心力，迭代 220 轮、温度递减），与屏幕解耦；
 * 数据或尺寸变化时先布局再「适应视图」（按节点包围盒计算 scale/offset 居中），杜绝空白/跑出画面。
 *
 * 手势（触屏替代 Web 的鼠标/滚轮）：
 *   双指捏合 —— 以手势中心为定点缩放，倍率限制 [0.1, 10]（对齐 Web wheel 的 scale 钳制）
 *   单指拖拽 —— 平移（offset += delta，对齐 Web mousemove 拖拽）
 *   点按选中 —— 命中判定在世界坐标做，命中半径 = 20/scale（与 Web minDist 一致）；
 *              拖拽过距离则不算点击（GestureDetector 滑动超 touchSlop 即取消点按）
 *   双击 —— 以指针为中心放大 1.6 倍（触屏没有滚轮的快捷放大）
 * 角落「适应」胶囊按钮复位视图（触屏没有滚轮，双指不熟练的用户可一键回中）。
 */
class GraphView(
    context: Context,
    private val nodes: List<KNode>,
    private val edges: List<KEdge>,
    private val redEdgeIds: Set<String>,
    private val scores: Map<String, Double>,
    private val titles: Map<String, String>,
    private val onSelect: (String) -> Unit,
) : View(context) {

    private class Pt(var x: Float, var y: Float, var vx: Float = 0f, var vy: Float = 0f)

    private val pos = LinkedHashMap<String, Pt>()

    // ── 视图变换：screen = world * scale + offset（对齐 Web CanvasRenderer）──
    private var scale = 1f
    private var offX = 0f
    private var offY = 0f
    private var selected: String? = null

    private val density = resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()

    // 债边端点（对齐 Web _debtNodeMap：红边两端为债务节点，走 .dnode.debt 配色）
    private val debtNodeIds: Set<String> = buildSet {
        edges.forEach { e -> if ("${e.a}>${e.b}" in redEdgeIds) { add(e.a); add(e.b) } }
    }

    // ── 画笔 ──
    private val paintEdge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val paintFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val paintStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val paintLabel = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.DEFAULT_BOLD
    }
    private val paintPillText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        color = Ui.INK
        textSize = 12f * density
    }

    /** 节点半径（对齐 Web CanvasRenderer r = chapter 22 / term 14，按 dp 折算保证触屏可点） */
    private fun nodeRadius(id: String): Float =
        if (isChapter(id)) 22f * density else 14f * density

    private fun isChapter(id: String): Boolean = nodes.find { it.id == id }?.kind == "chapter"
    private fun isDebt(id: String): Boolean = id in debtNodeIds || (scores[id] ?: 1.0) < 0.55

    init {
        layoutWorld()
    }

    // ── 世界坐标系力导向布局（斥力 + 弹簧 + 向心力，220 轮温度递减；与屏幕解耦）──
    private fun layoutWorld() {
        val n = nodes.size
        if (n == 0) return
        val w = 900f
        val h = 900f
        val cx = w / 2
        val cy = h / 2
        nodes.forEachIndexed { i, node ->
            val ang = 2.0 * Math.PI * i / n
            val r = min(w, h) * 0.3f
            pos[node.id] = Pt((cx + r * Math.cos(ang)).toFloat(), (cy + r * Math.sin(ang)).toFloat())
        }
        val k = sqrt((w * h) / max(n.toDouble(), 1.0)).toFloat() * 0.6f
        for (step in 0 until 220) {
            val temp = max(1f, 20f * (1f - step / 220f))
            // 斥力
            for (i in nodes.indices) {
                val a = pos[nodes[i].id] ?: continue
                for (j in i + 1 until nodes.size) {
                    val b = pos[nodes[j].id] ?: continue
                    var dx = a.x - b.x; var dy = a.y - b.y
                    var d2 = dx * dx + dy * dy
                    if (d2 < 0.01f) { dx = ((i % 3) + 1).toFloat(); dy = ((j % 2) + 1).toFloat(); d2 = dx * dx + dy * dy }
                    val d = sqrt(d2)
                    val f = (k * k / d2) * 0.02f
                    val fx = dx / d * f; val fy = dy / d * f
                    a.vx += fx; a.vy += fy; b.vx -= fx; b.vy -= fy
                }
            }
            // 弹簧（边拉近）
            for (e in edges) {
                val a = pos[e.a] ?: continue
                val b = pos[e.b] ?: continue
                val dx = b.x - a.x; val dy = b.y - a.y
                val d = sqrt(dx * dx + dy * dy)
                if (d < 0.01f) continue
                val f = (d * d - k * k) / d * 0.01f
                a.vx += dx / d * f; a.vy += dy / d * f
                b.vx -= dx / d * f; b.vy -= dy / d * f
            }
            // 向心力 + 温度限位
            for (node in nodes) {
                val p = pos[node.id] ?: continue
                p.vx += (cx - p.x) * 0.0015f
                p.vy += (cy - p.y) * 0.0015f
                val v = sqrt(p.vx * p.vx + p.vy * p.vy)
                if (v > temp) { p.vx = p.vx / v * temp; p.vy = p.vy / v * temp }
                p.x += p.vx; p.y += p.vy
                p.x = min(w - 40f, max(40f, p.x)); p.y = min(h - 40f, max(40f, p.y))
                p.vx *= 0.5f; p.vy *= 0.5f
            }
        }
    }

    /** 「适应视图」：按节点包围盒计算 scale/offset 居中（对齐 Web 初始视图自适应思路） */
    private fun fitView() {
        if (nodes.isEmpty() || width == 0 || height == 0) return
        var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE
        nodes.forEach { n ->
            val p = pos[n.id] ?: return@forEach
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        if (minX > maxX) return
        val pad = 60f // 世界单位内边距，容纳节点半径与标签
        val bw = max(maxX - minX + pad * 2, 1f)
        val bh = max(maxY - minY + pad * 2, 1f)
        scale = min(width / bw, height / bh).coerceIn(0.1f, 10f) // 倍率限制 [0.1, 10]
        offX = width / 2f - (minX + maxX) / 2f * scale
        offY = height / 2f - (minY + maxY) / 2f * scale
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // 尺寸变化时先布局再「适应视图」，杜绝空白/跑出画面
        fitView()
    }

    // ── 坐标换算（对齐 Web _worldToScreen / _screenToWorld）──
    private fun worldToScreenX(wx: Float) = wx * scale + offX
    private fun worldToScreenY(wy: Float) = wy * scale + offY

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()

        // 连线：默认 #55A77B 透明度 0.75（对齐 Web 连线规范）；债边保留红边语义（业务口径：红边=开放债）
        for (e in edges) {
            val a = pos[e.a] ?: continue
            val b = pos[e.b] ?: continue
            val red = "${e.a}>${e.b}" in redEdgeIds
            paintEdge.color = if (red) Ui.DB_EDGE else Ui.LINK
            paintEdge.alpha = if (red) 204 else 191 // 0.8 / 0.75
            paintEdge.strokeWidth = if (red) 4.5f * density else max(1.0, e.w * 1.5).toFloat() * density
            canvas.drawLine(
                worldToScreenX(a.x), worldToScreenY(a.y),
                worldToScreenX(b.x), worldToScreenY(b.y),
                paintEdge,
            )
        }

        for (node in nodes) {
            val p = pos[node.id] ?: continue
            val cx = worldToScreenX(p.x)
            val cy = worldToScreenY(p.y)
            val r = nodeRadius(node.id)
            if (cx < -r || cx > w + r || cy < -r || cy > h + r) continue // 视口裁剪（对齐 Web）

            val (fill, edge, ink) = when {
                isChapter(node.id) -> Triple(Ui.CH_FILL, Ui.CH_EDGE, Ui.CH_INK) // .dnode.chapter
                isDebt(node.id) -> Triple(Ui.DB_FILL, Ui.DB_EDGE, Ui.DB_INK)    // .dnode.debt
                else -> Triple(Ui.TM_FILL, Ui.TM_EDGE, Ui.TM_INK)               // .dnode.term
            }

            paintFill.color = fill
            canvas.drawCircle(cx, cy, r, paintFill)
            paintStroke.color = edge
            paintStroke.strokeWidth = 1.5f * density
            canvas.drawCircle(cx, cy, r, paintStroke)

            // 选中节点画 primary 外圈高亮（2.5 线宽、外扩 3.5dp）
            if (node.id == selected) {
                paintStroke.color = Ui.PRIMARY
                paintStroke.strokeWidth = 2.5f * density
                canvas.drawCircle(cx, cy, r + 3.5f * density, paintStroke)
            }

            // 标签 8 字截断省略（对齐 Web n._label：【前缀】不占位 + slice(0,8)）
            paintLabel.color = ink
            paintLabel.textSize = sp(if (isChapter(node.id)) Ui.FS_NODE_CH else Ui.FS_NODE)
            canvas.drawText(shortLabel(node.title), cx, cy + r + paintLabel.textSize + 2f * density, paintLabel)
        }

        drawFitPill(canvas)
    }

    /** 标签截断：【前缀】不占标签位 + 8 字截断省略（对齐 Web P1-2/P2-3 口径） */
    private fun shortLabel(title: String): String {
        val pi = title.indexOf('】')
        val t = if (title.startsWith("【") && pi > 0) title.substring(pi + 1) else title
        return if (t.length > 8) t.substring(0, 8) + "…" else t
    }

    private fun sp(v: Float): Float =
        android.util.TypedValue.applyDimension(
            android.util.TypedValue.COMPLEX_UNIT_SP, v, resources.displayMetrics,
        )

    // ── 角落「适应」胶囊按钮（触屏没有滚轮，一键复位视图）──
    private val pillRect = RectF()
    private fun drawFitPill(canvas: Canvas) {
        val padH = 16f * density
        val padV = 8f * density
        val tw = paintPillText.measureText("适应")
        val bw = tw + padH * 2
        val bh = paintPillText.textSize + padV * 2
        val left = width - bw - 12f * density
        val top = 12f * density
        pillRect.set(left, top, left + bw, top + bh)
        paintFill.color = Ui.SURFACE
        canvas.drawRoundRect(pillRect, bh / 2, bh / 2, paintFill)
        paintStroke.color = Ui.RULE
        paintStroke.strokeWidth = 1f * density
        canvas.drawRoundRect(pillRect, bh / 2, bh / 2, paintStroke)
        canvas.drawText(
            "适应",
            pillRect.centerX(),
            pillRect.centerY() + paintPillText.textSize / 2.5f,
            paintPillText,
        )
    }

    // ── 手势：捏合缩放 + 拖拽平移 + 点按选中 + 双击放大 ──
    private val scaleDet = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(d: ScaleGestureDetector): Boolean {
                // 双指捏合以手势中心为定点缩放（对齐 Web wheel：先取指针下世界点，缩放后反推 offset）
                val fx = d.focusX
                val fy = d.focusY
                val newScale = (scale * d.scaleFactor).coerceIn(0.1f, 10f) // 倍率限制 [0.1, 10]
                val wx = (fx - offX) / scale
                val wy = (fy - offY) / scale
                scale = newScale
                offX = fx - wx * scale
                offY = fy - wy * scale
                invalidate()
                return true
            }
        },
    )

    private val gestureDet = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true

            override fun onScroll(
                e1: MotionEvent?, e2: MotionEvent,
                distanceX: Float, distanceY: Float,
            ): Boolean {
                if (scaleDet.isInProgress) return false // 捏合时不叠加平移
                // 单指拖拽平移：offset += delta（对齐 Web mousemove 拖拽）
                offX -= distanceX
                offY -= distanceY
                invalidate()
                return true
            }

            override fun onSingleTapUp(e: MotionEvent): Boolean {
                // 点按选中：拖拽过距离则不算点击（onScroll 超 touchSlop 时不会走到这里）
                hitTest(e.x, e.y)?.let { id ->
                    selected = if (selected == id) null else id // 再次点按取消选中（对齐 Web 点击切换）
                    invalidate()
                    onSelect(id)
                }
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                // 双击：以指针为中心放大 1.6 倍
                val wx = (e.x - offX) / scale
                val wy = (e.y - offY) / scale
                scale = (scale * 1.6f).coerceIn(0.1f, 10f)
                offX = e.x - wx * scale
                offY = e.y - wy * scale
                invalidate()
                return true
            }
        },
    )

    /** 命中判定在世界坐标做，命中半径 = 20/scale（与 Web minDist 一致，取最近节点） */
    private fun hitTest(sx: Float, sy: Float): String? {
        val wx = (sx - offX) / scale
        val wy = (sy - offY) / scale
        var best: String? = null
        var bestD = Float.MAX_VALUE
        for (node in nodes) {
            val p = pos[node.id] ?: continue
            val dx = p.x - wx
            val dy = p.y - wy
            val d = sqrt(dx * dx + dy * dy)
            if (d < bestD) { bestD = d; best = node.id }
        }
        val minDist = 20f * density / scale // 20/scale（Web minDist），dp 折算保证触屏命中面积
        return best?.takeIf { bestD < minDist }
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        // 角落「适应」按钮优先（触屏没有滚轮，一键复位）
        if (ev.actionMasked == MotionEvent.ACTION_DOWN && pillRect.contains(ev.x, ev.y)) {
            fitView()
            return true
        }
        scaleDet.onTouchEvent(ev)
        gestureDet.onTouchEvent(ev)
        return true
    }
}
