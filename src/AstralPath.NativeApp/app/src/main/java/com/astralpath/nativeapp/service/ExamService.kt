package com.astralpath.nativeapp.service

/**
 * 试卷文本结构化 —— 移植自 Web 版 shared/exam.js 的 structureExamText 核心口径（简化版）：
 * 板块识别（一、二、…）→ 题头切分（N. / N、）→ 选项行（A. 独立行）→ 答案行（答案：B / 1.A 2.C）
 * → 题型推断（选择 / 填空 / 判断 / 解答）。金样在 JS 侧（exam_runner.js 8 例），此处同构移植。
 */
object ExamService {
    data class ExamItem(
        val no: Int,
        val section: String,
        val stem: String,
        val options: List<String>,
        val answer: String,
        val qtype: String,
    )

    data class ExamResult(val items: List<ExamItem>, val sections: List<Pair<String, Int>>)

    fun structure(text: String): ExamResult {
        val sectionRe = Regex("^第?[一二三四五六七八九十]+[、.]\\s*(\\S+)$")
        val headRe = Regex("^(\\d{1,3})\\s*[.、．]\\s*(.*)$")
        val optRe = Regex("^([A-D])\\s*[.、．]\\s*(.*)$")
        val ansRe = Regex("^答案[:：]?\\s*(.*)$")
        val items = mutableListOf<ExamItem>()
        var section = ""
        var cur: MutableItem? = null

        fun flush() {
            cur?.let {
                if (it.stem.isNotBlank() || it.options.isNotEmpty()) {
                    items.add(ExamItem(it.no, section, it.stem.trim(), it.options.toList(), it.answer, qtype(it)))
                }
            }
        }

        text.split('\n').forEach { raw ->
            val ln = raw.trim()
            if (ln.isEmpty()) return@forEach
            sectionRe.find(ln)?.let { m ->
                flush(); cur = null
                section = m.groupValues[1]
                return@forEach
            }
            if (ln.startsWith("答案")) {
                ansRe.find(ln)?.let { m ->
                    distributeAnswers(m.groupValues[1], items)
                    return@forEach
                }
            }
            headRe.find(ln)?.let { m ->
                val no = m.groupValues[1].toIntOrNull()
                if (no != null && (cur == null || no == cur!!.no + 1 || cur!!.no != no)) {
                    flush()
                    cur = MutableItem(no, m.groupValues[2].trim())
                    return@forEach
                }
            }
            optRe.find(ln)?.let { m ->
                val c = cur ?: MutableItem(items.size + 1, "").also { cur = it }
                c.options.add("${m.groupValues[1]}. ${m.groupValues[2].trim()}")
                return@forEach
            }
            val c2 = cur ?: MutableItem(items.size + 1, "").also { cur = it }
            c2.stem = if (c2.stem.isEmpty()) ln else c2.stem + "\n" + ln
        }
        flush()

        // 答案批量分发（1.A 2.C 形式已在 distributeAnswers 处理；剩余按序补）
        val sections = mutableListOf<Pair<String, Int>>()
        items.groupBy { it.section }.forEach { (sec, list) -> sections.add(sec to list.size) }
        return ExamResult(items, sections)
    }

    private class MutableItem(val no: Int, var stem: String) {
        val options = mutableListOf<String>()
        var answer = ""
    }

    private fun qtype(it: MutableItem): String = when {
        it.options.isNotEmpty() -> if (it.stem.contains("正确") || it.stem.contains("对") && it.options.size == 2) "判断题" else "选择题"
        it.answer.length <= 8 && it.stem.contains("____") -> "填空题"
        it.answer.isNotEmpty() -> "解答题"
        it.stem.contains("____") -> "填空题"
        else -> "解答题"
    }

    /** 答案行：优先「题号.字母」批量分发；否则追加到最后一个未作答题 */
    private fun distributeAnswers(raw: String, items: MutableList<ExamItem>) {
        val pairs = Regex("(\\d{1,3})\\s*[.、．]?\\s*([A-D对错√×])").findAll(raw).toList()
        if (pairs.size >= 2 || (pairs.size == 1 && pairs[0].groupValues[1].toIntOrNull() != null && items.any { it.no.toString() == pairs[0].groupValues[1] })) {
            pairs.forEach { m ->
                val no = m.groupValues[1].toIntOrNull() ?: return@forEach
                val idx = items.indexOfFirst { it.no == no }
                if (idx >= 0) items[idx] = items[idx].copy(answer = m.groupValues[2])
            }
            return
        }
        val last = items.lastOrNull() ?: return
        items[items.size - 1] = last.copy(answer = raw.trim())
    }
}
