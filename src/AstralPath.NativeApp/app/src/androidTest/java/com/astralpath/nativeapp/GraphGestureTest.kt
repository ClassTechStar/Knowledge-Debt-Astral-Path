package com.astralpath.nativeapp

import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.astralpath.nativeapp.ui.GraphView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 识网（GraphView）手势仪器化测试 —— 与鸿蒙端 scripts/verify-graph-gestures.ps1 等价。
 *
 * 断言不走截图比对，直接读 GraphView 的 internal 探针（debugScale/debugOffX/...），
 * 因为仪器化测试与主代码同模块，可访问 internal 成员。
 *
 * 与鸿蒙脚本的差异：这里能注入**双指捏合**（UiAutomation 多指 MotionEvent），
 * 鸿蒙侧的 uitest 不支持多指，只能靠同路径（zoomAt）间接覆盖。
 *
 * 运行前提：连了设备/模拟器，且应用内至少有一本书的图谱。
 * 没有图谱时用 JUnit 的 Assume 跳过（skipped，不算失败）。
 */
@RunWith(AndroidJUnit4::class)
class GraphGestureTest {

    private lateinit var device: UiDevice
    private lateinit var scenario: ActivityScenario<MainActivity>

    private val inst get() = InstrumentationRegistry.getInstrumentation()

    @Before
    fun setUp() {
        device = UiDevice.getInstance(inst)
        scenario = ActivityScenario.launch(MainActivity::class.java)
        // 切到识网页（导航胶囊按文案定位）
        val nav = device.wait(Until.findObject(By.text("识网")), 5_000)
        if (nav != null) {
            nav.click()
            SystemClock.sleep(1_500)
        }
    }

    // ── 工具 ──

    /** 递归找 GraphView（按 class，避免依赖内部层级） */
    private fun findGraph(v: View): GraphView? {
        if (v is GraphView) return v
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) {
                findGraph(v.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun graph(): GraphView? {
        var g: GraphView? = null
        scenario.onActivity { a -> g = findGraph(a.window.decorView) }
        return g
    }

    /** 视图内坐标 → 屏幕坐标 */
    private fun toScreen(g: GraphView, x: Float, y: Float): FloatArray {
        val loc = IntArray(2)
        g.getLocationOnScreen(loc)
        return floatArrayOf(loc[0] + x, loc[1] + y)
    }

    private fun inject(ev: MotionEvent) {
        inst.uiAutomation.injectInputEvent(ev, true)
        ev.recycle()
    }

    /** 单指滑动（ACTION_DOWN → 若干 MOVE → UP） */
    private fun swipe(x0: Float, y0: Float, x1: Float, y1: Float, steps: Int = 12) {
        val down = SystemClock.uptimeMillis()
        var t = down
        inject(MotionEvent.obtain(down, t, MotionEvent.ACTION_DOWN, x0, y0, 0))
        for (i in 1..steps) {
            t = down + i * 16L
            val k = i.toFloat() / steps
            inject(MotionEvent.obtain(down, t, MotionEvent.ACTION_MOVE, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, 0))
        }
        inject(MotionEvent.obtain(down, t + 16, MotionEvent.ACTION_UP, x1, y1, 0))
    }

    /** 双击（两次 tap 间隔 80ms，落在 450ms 双击窗口内） */
    private fun doubleTap(x: Float, y: Float) {
        val t0 = SystemClock.uptimeMillis()
        inject(MotionEvent.obtain(t0, t0, MotionEvent.ACTION_DOWN, x, y, 0))
        inject(MotionEvent.obtain(t0, t0 + 40, MotionEvent.ACTION_UP, x, y, 0))
        inject(MotionEvent.obtain(t0 + 80, t0 + 80, MotionEvent.ACTION_DOWN, x, y, 0))
        inject(MotionEvent.obtain(t0 + 80, t0 + 120, MotionEvent.ACTION_UP, x, y, 0))
    }

    /** 双指捏合：两指以 (cx,cy) 为中心从 from 间距张开到 to 间距 */
    private fun pinch(cx: Float, cy: Float, from: Float, to: Float, steps: Int = 14) {
        val props = arrayOf(
            MotionEvent.PointerProperties().apply {
                id = 0; toolType = MotionEvent.TOOL_TYPE_FINGER
            },
            MotionEvent.PointerProperties().apply {
                id = 1; toolType = MotionEvent.TOOL_TYPE_FINGER
            },
        )
        val coords = Array(2) { MotionEvent.PointerCoords() }
        val down = SystemClock.uptimeMillis()
        var t = down

        fun setSpan(span: Float) {
            coords[0].x = cx - span / 2f; coords[0].y = cy
            coords[1].x = cx + span / 2f; coords[1].y = cy
        }
        setSpan(from)
        // 第一指按下
        inject(
            MotionEvent.obtain(
                down, t, MotionEvent.ACTION_DOWN, 1, props, coords,
                0, 0, 1f, 1f, 0, 0, 0, 0,
            ),
        )
        // 第二指按下
        inject(
            MotionEvent.obtain(
                down, t, MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                2, props, coords, 0, 0, 1f, 1f, 0, 0, 0, 0,
            ),
        )
        for (i in 1..steps) {
            t = down + i * 16L
            setSpan(from + (to - from) * i / steps)
            inject(
                MotionEvent.obtain(
                    down, t, MotionEvent.ACTION_MOVE, 2, props, coords,
                    0, 0, 1f, 1f, 0, 0, 0, 0,
                ),
            )
        }
        inject(
            MotionEvent.obtain(
                down, t + 16, MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                2, props, coords, 0, 0, 1f, 1f, 0, 0, 0, 0,
            ),
        )
        inject(
            MotionEvent.obtain(
                down, t + 24, MotionEvent.ACTION_UP, 1, props, coords,
                0, 0, 1f, 1f, 0, 0, 0, 0,
            ),
        )
    }

    private fun requireGraph(): GraphView {
        val g = graph()
        assumeTrue("未进入识网页（导航失败或用例环境无界面）", g != null)
        assumeTrue("图谱无节点（需先导入教材）", g!!.debugNodeCount() > 0)
        return g!!
    }

    // ── 用例 ──

    @Test
    fun drag_pansGraphWithoutChangingScale() {
        val g = requireGraph()
        val s0 = g.debugScale(); val x0 = g.debugOffX(); val y0 = g.debugOffY()
        val c = toScreen(g, g.width / 2f, g.height / 2f)
        swipe(c[0], c[1], c[0] + 120f, c[1] + 80f)
        SystemClock.sleep(300)
        val dx = g.debugOffX() - x0
        val dy = g.debugOffY() - y0
        // 平移量与像素位移一致（±20px 容差：触摸采样与惯性）
        assertEquals("拖拽后 X 位移不符", 120f, dx, 20f)
        assertEquals("拖拽后 Y 位移不符", 80f, dy, 20f)
        assertEquals("拖拽不应改变缩放", s0, g.debugScale(), 0.001f)
    }

    @Test
    fun doubleTap_zoomsInBySixteenPercentSteps() {
        val g = requireGraph()
        val s0 = g.debugScale()
        val c = toScreen(g, g.width / 2f, g.height / 2f)
        doubleTap(c[0], c[1])
        SystemClock.sleep(300)
        val s1 = g.debugScale()
        assertTrue("双击应放大（$s0 → $s1）", s1 > s0 * 1.4f && s1 < s0 * 1.8f)
        doubleTap(c[0], c[1])
        SystemClock.sleep(300)
        val s2 = g.debugScale()
        assertTrue("连续双击应继续放大（$s1 → $s2）", s2 > s1 * 1.4f)
    }

    @Test
    fun pinch_zoomsAtFocusPoint() {
        val g = requireGraph()
        val s0 = g.debugScale()
        val c = toScreen(g, g.width / 2f, g.height / 2f)
        // 两指从 120px 间距张到 360px → 期望约 3 倍（钳制在 10 以内）
        pinch(c[0], c[1], 120f, 360f)
        SystemClock.sleep(400)
        val s1 = g.debugScale()
        assertTrue("捏合应放大（$s0 → $s1）", s1 > s0 * 1.5f)
    }

    @Test
    fun tap_selectsNode() {
        val g = requireGraph()
        val id = g.debugFirstNodeId()
        assumeTrue("无节点可点", id != null)
        val p = g.debugNodeScreenPos(id!!)
        assumeTrue("节点坐标不可用", p != null)
        val s = toScreen(g, p!![0], p[1])
        device.click(s[0].toInt(), s[1].toInt())
        SystemClock.sleep(400)
        assertNotNull("点按后应有选中节点", g.debugSelected())
    }

    @Test
    fun resetButton_setsScaleToOne() {
        val g = requireGraph()
        val c = toScreen(g, g.width / 2f, g.height / 2f)
        doubleTap(c[0], c[1]) // 先把缩放改掉
        SystemClock.sleep(300)
        assumeTrue("缩放未生效，跳过 100% 断言", kotlin.math.abs(g.debugScale() - 1f) > 0.01f)
        // 控件已移到画布上方，按文本定位（不再用画布内矩形）
        val btn = device.wait(Until.findObject(By.text("100%")), 3_000)
        assumeTrue("未找到 100% 控件", btn != null)
        btn!!.click()
        SystemClock.sleep(400)
        assertEquals("点 100% 后缩放应为 1.0", 1f, g.debugScale(), 0.001f)
    }

    @Test
    fun fitButton_restoresView() {
        val g = requireGraph()
        val s0 = g.debugScale(); val x0 = g.debugOffX(); val y0 = g.debugOffY()
        val c = toScreen(g, g.width / 2f, g.height / 2f)
        doubleTap(c[0], c[1])           // 先改变视图
        SystemClock.sleep(300)
        assumeTrue("缩放未生效，跳过复位断言", kotlin.math.abs(g.debugScale() - s0) > 0.01f)
        val btn = device.wait(Until.findObject(By.text("适应")), 3_000)
        assumeTrue("未找到适应控件", btn != null)
        btn!!.click()
        SystemClock.sleep(400)
        assertEquals("适应后缩放应回到基线", s0, g.debugScale(), 0.02f)
        assertEquals("适应后 X 偏移应回到基线", x0, g.debugOffX(), 6f)
        assertEquals("适应后 Y 偏移应回到基线", y0, g.debugOffY(), 6f)
    }
}
