package com.astralpath.nativeapp.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.MotionEvent
import android.view.View
import com.astralpath.nativeapp.data.KEdge
import com.astralpath.nativeapp.data.KNode
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 识网图谱自绘 —— 移植自鸿蒙版 GraphCanvas.ets：力导向布局（斥力 + 弹簧 + 向心力，
 * 220 轮温度递减），点击按最近节点命中；红边（开放债边）红色描粗。
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
    private val paintEdge = Paint(Paint.ANTI_ALIAS_FLAG)
    private val paintNode = Paint(Paint.ANTI_ALIAS_FLAG)
    private val paintText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE; textSize = 22f; textAlign = Paint.Align.CENTER
    }
    private val paintLabel = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Ui.INK; textSize = 24f; textAlign = Paint.Align.CENTER
    }
    private var selected: String? = null

    init { layout(w = 900f, h = 900f) }

    private fun layout(w: Float, h: Float) {
        val n = nodes.size
        if (n == 0) return
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

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        // 布局按 900×900 归一，实际按控件尺寸缩放
        val scale = min(w, h) / 900f
        val ox = (w - 900f * scale) / 2f
        val oy = (h - 900f * scale) / 2f
        fun px(id: String): Pair<Float, Float>? {
            val p = pos[id] ?: return null
            return (ox + p.x * scale) to (oy + p.y * scale)
        }
        for (e in edges) {
            val a = px(e.a) ?: continue
            val b = px(e.b) ?: continue
            val red = "${e.a}>${e.b}" in redEdgeIds
            paintEdge.color = if (red) Ui.DANGER else 0xFF9AA7B5.toInt()
            paintEdge.strokeWidth = if (red) 6f else 2.5f
            canvas.drawLine(a.first, a.second, b.first, b.second, paintEdge)
        }
        for (node in nodes) {
            val p = px(node.id) ?: continue
            val weak = (scores[node.id] ?: 1.0) < 0.55
            paintNode.color = when {
                node.id == selected -> 0xFF1B4FC4.toInt()
                weak -> Ui.DANGER
                node.course?.contains("深度学习") == true -> 0xFF7A5AF8.toInt()
                else -> Ui.BRAND
            }
            paintNode.setShadowLayer(6f, 0f, 2f, 0x33000000)
            setLayerType(LAYER_TYPE_SOFTWARE, paintNode)
            canvas.drawCircle(p.first, p.second, if (node.id == selected) 26f else 20f, paintNode)
            canvas.drawText(node.title.take(2), p.first, p.second + 8f, paintText)
            canvas.drawText(node.title, p.first, p.second + 42f, paintLabel)
        }
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (ev.action != MotionEvent.ACTION_DOWN) return false
        val w = width.toFloat(); val h = height.toFloat()
        val scale = min(w, h) / 900f
        val ox = (w - 900f * scale) / 2f
        val oy = (h - 900f * scale) / 2f
        var best: String? = null
        var bestD = Float.MAX_VALUE
        for (node in nodes) {
            val p = pos[node.id] ?: continue
            val x = ox + p.x * scale; val y = oy + p.y * scale
            val d = (x - ev.x) * (x - ev.x) + (y - ev.y) * (y - ev.y)
            if (d < bestD) { bestD = d; best = node.id }
        }
        if (best != null && bestD < 90f * 90f) {
            selected = best
            invalidate()
            onSelect(best)
            return true
        }
        return false
    }
}
