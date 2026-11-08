package com.astralpath.nativeapp.service

import com.astralpath.nativeapp.data.Book
import com.astralpath.nativeapp.data.Chapter
import com.astralpath.nativeapp.data.KEdge
import com.astralpath.nativeapp.data.KNode
import com.astralpath.nativeapp.data.Question

/**
 * 教材解析（文本 → 图谱）—— 移植自鸿蒙版 KgService.ets（对应 Web 版 kg_builder 流程）：
 * ① 按标题行切章（第N章/节、# 标题、1. 标题）② 2–6 字中文短语词频抽概念
 * ③ 同章内按出现顺序连先修边。只处理「已经是文本」的输入。
 */
object KgService {
    private val STOP = listOf(
        "我们", "你们", "他们", "可以", "这个", "那个", "什么", "怎么", "因为", "所以",
        "但是", "如果", "就是", "还有", "一个", "没有", "这样", "那样",
    )

    fun splitChapters(text: String): List<Chapter> {
        val chapters = mutableListOf<Chapter>()
        var cur: Chapter? = null
        var order = 0
        for (raw in text.split('\n')) {
            val ln = raw.trim()
            val isHead = Regex("^#{1,4}\\s+\\S+").containsMatchIn(ln) ||
                Regex("^第\\s*[0-9一二三四五六七八九十]+\\s*[章节]\\s*\\S*").containsMatchIn(ln) ||
                Regex("^[0-9]+(\\.[0-9]+)*\\s+\\S{1,40}$").containsMatchIn(ln)
            if (isHead) {
                cur?.let { chapters.add(it) }
                order += 1
                cur = Chapter("C" + order.toString().padStart(2, '0'), ln.replace(Regex("^#+\\s*"), ""), "", order)
                continue
            }
            cur?.let { c ->
                c.body = if (c.body.isNullOrEmpty()) ln else c.body + "\n" + ln
            }
        }
        cur?.let { chapters.add(it) }
        if (chapters.isEmpty()) {
            val first = text.split('\n').firstOrNull { it.trim().isNotEmpty() } ?: "全文"
            chapters.add(Chapter("C01", first.trim().take(30), text, 1))
        }
        return chapters
    }

    private data class Cand(val term: String, val count: Int)

    fun extractTerms(chapters: List<Chapter>, maxTerms: Int): List<String> {
        val freq = HashMap<String, Int>()
        for (ch in chapters) {
            val body = ch.body ?: ""
            var i = 0
            while (i < body.length) {
                if (isCjk(body[i])) {
                    var len = 2
                    while (len <= 6 && i + len <= body.length) {
                        if (!isCjk(body[i + len - 1])) break
                        val sub = body.substring(i, i + len)
                        if (sub !in STOP) freq[sub] = (freq[sub] ?: 0) + 1
                        len += 1
                    }
                }
                i += 1
            }
        }
        val cands = freq.filter { it.value >= 2 }
            .map { Cand(it.key, it.value) }
            .sortedWith(compareByDescending<Cand> { it.count }.thenByDescending { it.term.length })
        val picked = mutableListOf<String>()
        for (c in cands) {
            if (picked.none { it.contains(c.term) }) picked.add(c.term)
            if (picked.size >= maxTerms) break
        }
        return picked
    }

    fun buildEdges(chapters: List<Chapter>, terms: List<String>): List<KEdge> {
        val edges = mutableListOf<KEdge>()
        val seen = HashSet<String>()
        for (ch in chapters) {
            val body = ch.body ?: ""
            val hit = terms.filter { body.contains(it) }
            var i = 0
            while (i + 1 < hit.size && i < 6) {
                val key = "${hit[i]}>${hit[i + 1]}"
                if (key !in seen) {
                    seen.add(key)
                    edges.add(KEdge(idOf(hit[i]), idOf(hit[i + 1]), 0.8))
                }
                i += 1
            }
        }
        return edges
    }

    fun idOf(term: String): String {
        var h = 0L
        for (c in term) h = (h * 31 + c.code) and 0xFFFFFFFFL
        return "N" + java.lang.Long.toHexString(h).uppercase().take(6).padEnd(6, '0')
    }

    private fun isCjk(ch: Char): Boolean = ch.code in 0x4e00..0x9fff

    fun build(name: String, text: String, maxTerms: Int = 24): Book {
        val chapters = splitChapters(text)
        val terms = extractTerms(chapters, maxTerms)
        // 章节节点（kind="chapter"，对齐 Web .dnode.chapter 章节蓝）
        val chapterNodes = chapters.map { ch ->
            KNode(ch.id, ch.title, diff = 1, course = name, kind = "chapter", body = (ch.body ?: "").take(200))
        }
        val nodes = chapterNodes + terms.mapIndexed { i, t ->
            KNode(idOf(t), t, diff = if (i < terms.size / 3) 1 else 2, course = name, kind = "term")
        }
        val edges = buildEdges(chapters, terms).toMutableList()
        // 归属边：章节 → 章内术语，tg=true 教材边
        val seen = HashSet<String>()
        for (ch in chapters) {
            val body = (ch.body ?: "") + " " + ch.title
            for (t in terms) {
                if (body.contains(t)) {
                    val tid = idOf(t)
                    if (seen.add(tid)) {
                        edges.add(KEdge(ch.id, tid, 1.0, tg = true))
                    }
                }
            }
        }
        return Book(
            id = "book-${System.currentTimeMillis()}", name = name, source = "text",
            sourceText = text.take(20000), chapters = chapters, nodes = nodes,
            edges = edges, qs = emptyList(), created = System.currentTimeMillis(),
        )
    }
}
