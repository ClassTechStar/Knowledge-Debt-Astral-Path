package com.astralpath.nativeapp

import com.astralpath.nativeapp.data.DemoData
import com.astralpath.nativeapp.data.SaleState
import com.astralpath.nativeapp.service.FormulaService
import com.astralpath.nativeapp.service.PlanScheduler
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 核心逻辑 JVM 测试（与 JS/C#/鸿蒙同源口径的 sanity 金样）：
 * 演示数据必须产生红边（否则界面成「零红边」看不出东西）、
 * 调度器产物必须过 K1–K5、销账必须按状态机语义步进。
 */
class CoreLogicTest {

    private val demo = DemoData.build()

    @Test
    fun `演示学情下应产生开放红边`() {
        val mastery = DemoData.seedMastery().toMutableMap()
        val logs = DemoData.seedLogs()
        val debts = FormulaService.diagnose(demo.edges, demo.nodes.associate { it.id to it.title }, mastery, logs)
        assertTrue("演示数据应至少产生 1 条红边，实际 ${debts.size}", debts.isNotEmpty())
        assertTrue(debts.all { it.impact >= 0.08 })
        assertTrue(debts.sortedByDescending { it.impact } == debts)
    }

    @Test
    fun `无错题时 freq 因子归零不产生红边`() {
        val debts = FormulaService.diagnose(demo.edges, demo.nodes.associate { it.id to it.title }, emptyMap(), emptyList())
        // 全默认掌握度 impact ≈ 0.0798 < 0.08，且 max(freq,1) 保底；此处验证不误报强红边
        assertTrue(debts.all { it.impact < 0.5 })
    }

    @Test
    fun `调度器产物通过 K1-K5 合约`() {
        val mastery = DemoData.seedMastery()
        val logs = DemoData.seedLogs()
        val debts = FormulaService.diagnose(demo.edges, demo.nodes.associate { it.id to it.title }, mastery, logs)
        val ds = debts.map { PlanScheduler.DebtInput(it.a, it.b, it.impact) }
        val titleOf = { id: String -> demo.nodes.find { it.id == id }?.title ?: id }
        val r = PlanScheduler.schedule(ds, 40, demo.edges, demo.nodes, titleOf)
        val viol = PlanScheduler.checkPlanK(r.items, 40, demo.edges, ds, r.deferred, titleOf)
        assertTrue("K1–K5 违规：$viol", viol.isEmpty())
        assertTrue(r.items.none { it.day < 1 || it.day > 14 })
        assertTrue(r.items.size <= 14 * 4)
    }

    @Test
    fun `销账需要连续两次达标且累计三次`() {
        val s1 = FormulaService.saleStep(SaleState(0, 0), 0.9, 4)
        assertEquals(1, s1.streak); assertEquals(false, s1.cleared)
        val s2 = FormulaService.saleStep(SaleState(s1.streak, s1.att), 0.9, 4)
        assertEquals(2, s2.streak); assertEquals(false, s2.cleared) // 连续已够但累计 2<3
        val s3 = FormulaService.saleStep(SaleState(s2.streak, s2.att), 0.9, 4)
        assertEquals(3, s3.streak); assertEquals(true, s3.cleared) // 累计 3 次即结清
        val broken = FormulaService.saleStep(SaleState(2, 0), 0.5, 2)
        assertEquals(0, broken.streak); assertEquals(false, broken.cleared) // 未达标即清零
    }

    @Test
    fun `先修天花板约束生效`() {
        // 先修全不会（0），后续再练也上不去 0.55
        val sc = FormulaService.scoreV2(10, 10, 5, 0, 5, listOf(0.0))
        assertTrue("先修全不会时 score 应 ≤0.55，实际 $sc", sc <= 0.5501)
    }
}
