package com.astralpath.nativeapp.service

import android.content.Context
import com.astralpath.nativeapp.data.AiCfg
import com.astralpath.nativeapp.data.AnswersShard
import com.astralpath.nativeapp.data.Book
import com.astralpath.nativeapp.data.Chapter
import com.astralpath.nativeapp.data.KEdge
import com.astralpath.nativeapp.data.KNode
import com.astralpath.nativeapp.data.MetaShard
import com.astralpath.nativeapp.data.Paper
import com.astralpath.nativeapp.data.PaperItem
import com.astralpath.nativeapp.data.PlanItem
import com.astralpath.nativeapp.data.Question
import org.json.JSONArray
import org.json.JSONObject

/**
 * 存储服务 —— 对齐 Web 版 shared/store.js 的分片布局 + ap:schema 版本协商 + 损坏自愈
 * （鸿蒙版 StoreService.ets 的 Kotlin 对应实现）。
 * 五分片各存一个 SharedPreferences 键（JSON 串），一次作答只回写 answers。
 */
object StoreService {
    private const val STORE = "astralpath"
    private const val KEY_META = "ap:meta"
    private const val KEY_BOOKS = "ap:books"
    private const val KEY_ANSWERS = "ap:answers"
    private const val KEY_PLAN = "ap:plan"
    private const val KEY_PAPERS = "ap:papers"
    private const val KEY_AI = "ap:aicfg"
    private const val KEY_SCHEMA = "ap:schema"
    private const val SCHEMA_VERSION = 2
    private const val TAG = "StoreService"

    private var prefs: android.content.SharedPreferences? = null

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(STORE, Context.MODE_PRIVATE)
        }
    }

    private fun get(): android.content.SharedPreferences =
        prefs ?: throw IllegalStateException("StoreService 未初始化，请先调用 init(context)")

    /** 读分片：损坏时先把原始串备份到 ap:backup:<key> 再删坏键，返回 null 由调用方走默认值 */
    private inline fun <T> loadShard(key: String, revive: (String) -> T): T? {
        val raw = get().getString(key, "") ?: ""
        if (raw.isEmpty()) return null
        try {
            return revive(raw)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "shard $key corrupted, backup and reset: ${e.message}")
            val ed = get().edit()
            ed.putString("ap:backup:$key", raw)
            ed.remove(key)
            ed.apply()
            return null
        }
    }

    /** 版本协商：无标记补写、标记损坏重写、更高版本告警只读（对齐 Web ap:schema） */
    fun ensureSchema(): Unit {
        val raw = get().getString(KEY_SCHEMA, "") ?: ""
        var v = 0
        var broken = false
        if (raw.isNotEmpty()) {
            v = try { Integer.parseInt(raw.trim()) } catch (e: Exception) { broken = true; 0 }
        }
        when {
            broken -> { put(KEY_SCHEMA, SCHEMA_VERSION.toString()) }
            v > SCHEMA_VERSION -> android.util.Log.w(TAG, "data written by newer version (v$v), treat as read-only")
            v < SCHEMA_VERSION -> put(KEY_SCHEMA, SCHEMA_VERSION.toString())
        }
    }

    private fun put(key: String, value: String) {
        get().edit().putString(key, value).apply()
    }

    // ── meta ──
    fun loadMeta(): MetaShard = loadShard(KEY_META) {
        val o = JSONObject(it)
        MetaShard(
            userName = o.optString("userName", "王小明（有债）"),
            activeBookId = o.optString("activeBookId", ""),
            day = o.optInt("day", 1),
            consent = o.optBoolean("consent", false),
            optOut = o.optBoolean("optOut", false),
            onboard = o.optBoolean("onboard", false),
            dnd = o.optBoolean("dnd", false),
        )
    } ?: MetaShard()

    fun saveMeta(m: MetaShard) {
        val o = JSONObject()
            .put("userName", m.userName).put("activeBookId", m.activeBookId)
            .put("day", m.day).put("consent", m.consent)
            .put("optOut", m.optOut).put("onboard", m.onboard).put("dnd", m.dnd)
        put(KEY_META, o.toString())
    }

    // ── books ──
    fun loadBooks(): List<Book> = loadShard(KEY_BOOKS) { raw ->
        val arr = JSONArray(raw)
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            val nodes = o.optJSONArray("nodes") ?: JSONArray()
            val edges = o.optJSONArray("edges") ?: JSONArray()
            val qs = o.optJSONArray("qs") ?: JSONArray()
            val chs = o.optJSONArray("chapters") ?: JSONArray()
            Book(
                id = o.getString("id"), name = o.optString("name", ""),
                source = o.optString("source", ""), sourceText = o.optString("sourceText", ""),
                chapters = (0 until chs.length()).map { j ->
                    val c = chs.getJSONObject(j)
                    Chapter(c.optString("id"), c.optString("title"), c.optString("body"), c.optInt("order", j))
                },
                nodes = (0 until nodes.length()).map { j ->
                    val n = nodes.getJSONObject(j)
                    KNode(
                        id = n.getString("id"), title = n.optString("title", ""),
                        diff = n.optInt("diff", 2), course = n.optString("course", ""),
                        kind = n.optString("kind", "term"),
                    )
                },
                edges = (0 until edges.length()).map { j ->
                    val e = edges.getJSONObject(j)
                    KEdge(e.getString("a"), e.getString("b"), e.optDouble("w", 1.0), e.optBoolean("tg", false))
                },
                qs = (0 until qs.length()).map { j ->
                    val q = qs.getJSONObject(j)
                    val opts = q.optJSONArray("opts") ?: JSONArray()
                    Question(
                        id = q.optString("id", "Q$j"), kp = q.optString("kp", ""),
                        stem = q.optString("stem", ""), ci = q.optInt("ci", 0),
                        opts = (0 until opts.length()).map { opts.getString(it) },
                        src = q.optString("src", "bank"),
                    )
                },
                created = o.optLong("created", 0),
            )
        }
    } ?: emptyList()

    fun saveBooks(books: List<Book>) {
        val arr = JSONArray()
        books.forEach { b ->
            val nodes = JSONArray()
            b.nodes.forEach { n -> nodes.put(JSONObject().put("id", n.id).put("title", n.title).put("diff", n.diff).put("course", n.course ?: "")) }
            val edges = JSONArray()
            b.edges.forEach { e -> edges.put(JSONObject().put("a", e.a).put("b", e.b).put("w", e.w).put("tg", e.tg)) }
            val qs = JSONArray()
            b.qs.forEach { q -> qs.put(JSONObject().put("id", q.id).put("kp", q.kp).put("stem", q.stem).put("ci", q.ci).put("opts", JSONArray(q.opts))) }
            val chs = JSONArray()
            b.chapters.forEach { c -> chs.put(JSONObject().put("id", c.id).put("title", c.title).put("order", c.order)) }
            arr.put(
                JSONObject()
                    .put("id", b.id).put("name", b.name).put("source", b.source ?: "")
                    .put("sourceText", b.sourceText ?: "").put("nodes", nodes)
                    .put("edges", edges).put("qs", qs).put("chapters", chs).put("created", b.created)
            )
        }
        put(KEY_BOOKS, arr.toString())
    }

    // ── answers ──
    fun loadAnswers(): AnswersShard = loadShard(KEY_ANSWERS) { raw ->
        val o = JSONObject(raw)
        val mastery = mutableMapOf<String, com.astralpath.nativeapp.data.Mastery>()
        o.optJSONObject("mastery")?.let { mo ->
            mo.keys().forEach { k ->
                val m = mo.getJSONObject(k)
                mastery[k] = com.astralpath.nativeapp.data.Mastery(
                    m.optInt("n"), m.optInt("s"), m.optInt("c"), m.optInt("age"), m.optInt("st"),
                )
            }
        }
        val logs = mutableListOf<com.astralpath.nativeapp.data.AnswerLog>()
        o.optJSONArray("logs")?.let { la ->
            (0 until la.length()).forEach { i ->
                val l = la.getJSONObject(i)
                logs.add(com.astralpath.nativeapp.data.AnswerLog(l.optString("qid"), l.optString("kp"), l.optBoolean("ok"), l.optInt("conf"), l.optLong("ts")))
            }
        }
        val sale = mutableMapOf<String, com.astralpath.nativeapp.data.SaleState>()
        o.optJSONObject("sale")?.let { so ->
            so.keys().forEach { k ->
                val sv = so.getJSONObject(k)
                sale[k] = com.astralpath.nativeapp.data.SaleState(sv.optInt("streak"), sv.optInt("att"), sv.optBoolean("cleared"))
            }
        }
        AnswersShard(mastery, logs, sale)
    } ?: AnswersShard()

    fun saveAnswers(a: AnswersShard) {
        val o = JSONObject()
        val mo = JSONObject()
        a.mastery.forEach { (k, m) -> mo.put(k, JSONObject().put("n", m.n).put("s", m.s).put("c", m.c).put("age", m.age).put("st", m.st)) }
        o.put("mastery", mo)
        val la = JSONArray()
        a.logs.takeLast(500).forEach { l -> la.put(JSONObject().put("qid", l.qid).put("kp", l.kp).put("ok", l.ok).put("conf", l.conf).put("ts", l.ts)) }
        o.put("logs", la)
        val so = JSONObject()
        a.sale.forEach { (k, s) -> so.put(k, JSONObject().put("streak", s.streak).put("att", s.att).put("cleared", s.cleared)) }
        o.put("sale", so)
        put(KEY_ANSWERS, o.toString())
    }

    // ── plan ──
    fun loadPlan(): List<PlanItem> = loadShard(KEY_PLAN) { raw ->
        val arr = JSONArray(raw)
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            PlanItem(
                id = o.optString("id"), day = o.optInt("day"), kp = o.optString("kp"),
                minutes = o.optInt("minutes"), layer = o.optString("layer", "core"),
                why = o.optString("why", ""), st = o.optString("st", "todo"),
                fromKp = o.optString("fromKp", ""), rd = o.optInt("rd", 0),
                label = o.optString("label", ""),
            )
        }
    } ?: emptyList()

    fun savePlan(plan: List<PlanItem>) {
        val arr = JSONArray()
        plan.forEach { p ->
            arr.put(
                JSONObject().put("id", p.id).put("day", p.day).put("kp", p.kp)
                    .put("minutes", p.minutes).put("layer", p.layer ?: "core")
                    .put("why", p.why ?: "").put("st", p.st ?: "todo")
                    .put("fromKp", p.fromKp ?: "").put("rd", p.rd ?: 0).put("label", p.label ?: "")
            )
        }
        put(KEY_PLAN, arr.toString())
    }

    // ── papers ──
    fun loadPapers(): List<Paper> = loadShard(KEY_PAPERS) { raw ->
        val arr = JSONArray(raw)
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            val items = o.optJSONArray("items") ?: JSONArray()
            Paper(
                id = o.optString("id"), name = o.optString("name"), type = o.optString("type", "exam"),
                items = (0 until items.length()).map { j ->
                    val it = items.getJSONObject(j)
                    val opts = it.optJSONArray("options") ?: JSONArray()
                    PaperItem(
                        no = it.optInt("no", j + 1), section = it.optString("section", ""),
                        stem = it.optString("stem"), options = (0 until opts.length()).map { j -> opts.getString(j) },
                        answer = it.optString("answer"), qtype = it.optString("qtype"),
                    )
                },
                created = o.optLong("created"),
            )
        }
    } ?: emptyList()

    fun savePapers(papers: List<Paper>) {
        val arr = JSONArray()
        papers.takeLast(20).forEach { p ->
            val items = JSONArray()
            p.items.forEach { it2 ->
                items.put(
                    JSONObject().put("no", it2.no).put("section", it2.section ?: "")
                        .put("stem", it2.stem).put("options", JSONArray(it2.options))
                        .put("answer", it2.answer).put("qtype", it2.qtype)
                )
            }
            arr.put(JSONObject().put("id", p.id).put("name", p.name).put("type", p.type).put("items", items).put("created", p.created))
        }
        put(KEY_PAPERS, arr.toString())
    }

    // ── AI 配置 ──
    fun loadAiCfg(): AiCfg = loadShard(KEY_AI) { raw ->
        val o = JSONObject(raw)
        AiCfg(o.optString("baseUrl"), o.optString("key"), o.optString("model", "mimo-7b-rl"))
    } ?: AiCfg()

    fun saveAiCfg(c: AiCfg) {
        put(KEY_AI, JSONObject().put("baseUrl", c.baseUrl).put("key", c.key).put("model", c.model).toString())
    }

    /** 清空本机数据（账户页「清除本机数据」）：分片 + 版本标记 + 损坏备份一并清掉 */
    fun wipe() {
        val ed = get().edit()
        listOf(KEY_META, KEY_BOOKS, KEY_ANSWERS, KEY_PLAN, KEY_PAPERS, KEY_AI, KEY_SCHEMA).forEach { ed.remove(it) }
        listOf(KEY_META, KEY_BOOKS, KEY_ANSWERS, KEY_PLAN, KEY_PAPERS, KEY_AI).forEach { ed.remove("ap:backup:$it") }
        ed.apply()
    }
}
