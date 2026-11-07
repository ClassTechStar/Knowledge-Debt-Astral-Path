package com.astralpath.nativeapp.data

/**
 * 数据模型 —— 与单文件版 localStorage 分片（ap:meta/books/answers/plan/papers）一一对应，
 * 字段名沿用原实现，便于跨端互导。移植自鸿蒙版 model/Models.ets。
 */
data class KNode(
    val id: String,
    val title: String,
    val body: String? = null,
    val diff: Int = 2,
    val course: String? = null,
    val kind: String? = null,
)

data class KEdge(val a: String, val b: String, val w: Double = 1.0, val tg: Boolean = false)

data class Chapter(val id: String, val title: String, var body: String? = null, val order: Int = 0)

data class Question(
    val id: String,
    val kp: String,
    val stem: String,
    val opts: List<String>,
    val ci: Int,
    val diff: Int = 2,
    val src: String? = "bank",
)

data class Mastery(var n: Int, var s: Int, var c: Int, var age: Int, var st: Int)

data class AnswerLog(val qid: String, val kp: String, val ok: Boolean, val conf: Int, val ts: Long)

data class DebtEdge(
    val id: String,
    val a: String,
    val b: String,
    val impact: Double,
    val why: String? = null,
    val open: Boolean,
)

data class SaleState(var streak: Int, var att: Int, var cleared: Boolean = false)

data class SaleResult(val streak: Int, val att: Int, val meets: Boolean, val cleared: Boolean)

data class PlanItem(
    val id: String,
    val day: Int,
    val kp: String,
    val minutes: Int,
    val layer: String? = null,
    val why: String? = null,
    val st: String? = null,
    val fromKp: String? = null,
    val rd: Int? = null,
    val label: String? = null,
)

data class PaperItem(
    val no: Int,
    val section: String? = null,
    val stem: String,
    val options: List<String>,
    val answer: String,
    val qtype: String,
)

data class Paper(val id: String, val name: String, val type: String, val items: List<PaperItem>, val created: Long = 0)

data class Book(
    val id: String,
    val name: String,
    val source: String? = null,
    val sourceText: String? = null,
    val chapters: List<Chapter> = emptyList(),
    val nodes: List<KNode> = emptyList(),
    val edges: List<KEdge> = emptyList(),
    val qs: List<Question> = emptyList(),
    val created: Long = 0,
)

data class MetaShard(
    val userName: String = "王小明（有债）",
    val activeBookId: String = "",
    val day: Int = 1,
    val consent: Boolean = false,
    val optOut: Boolean = false,
    val onboard: Boolean = false,
    val dnd: Boolean = false,
)

data class AnswersShard(
    val mastery: MutableMap<String, Mastery> = mutableMapOf(),
    val logs: MutableList<AnswerLog> = mutableListOf(),
    val sale: MutableMap<String, SaleState> = mutableMapOf(),
)

data class AiCfg(val baseUrl: String = "", val key: String = "", val model: String = "mimo-7b-rl")

/** 公式常量 —— 与 C# FormulaConstants.cs / JS K / 鸿蒙 FormulaConstants 同源，逐项一致 */
object K {
    val W_E = 0.50; val W_R = 0.30; val W_P = 0.20
    const val FLOOR = 0.55
    const val STAB0 = 2.5
    const val A = 0.45
    const val B = 0.25
    const val MIX = 0.65
    const val IMPACT_BASE = 0.55
    const val CROSS_TG = 1.15
    const val PG = 0.55
    const val CG = 0.50
    const val STEEP = 8.0
    const val HIT = 0.08
    const val CAS = 0.12
    const val VOL = 0.08
    const val SALE_BAR = 0.65
    const val SALE_ACC = 0.70
    const val SALE_CONF = 3.0
    const val SALE_STREAK = 2.0
    const val SALE_MIN_ATT = 3.0
    val SPACING_OFFSETS = intArrayOf(0, 2, 6)
}
