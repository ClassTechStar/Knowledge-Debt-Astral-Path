package com.astralpath.nativeapp.service

import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream

/**
 * 文档解析 —— 移植自鸿蒙版 DocService.ets 的取舍：
 * TXT/MD 直接读；HTML 去标签；DOCX/PPTX/EPUB 是 zip，解 word/document.xml、
 * ppt/slides/slide*.xml、html/xhtml 去标签；PDF 在原生 v1 不做文本抽取
 * （Android 无文本层 API，pdf.js 在 WebView 壳版承担），如实标注为扫描版。
 */
object DocService {
    enum class Kind { TXT, MD, HTML, DOCX, PPTX, EPUB, PDF, UNKNOWN }

    data class DocResult(val kind: Kind, val text: String, val chars: Int, val scanned: Boolean, val note: String)

    fun kindOf(name: String): Kind {
        val n = name.lowercase()
        return when {
            n.endsWith(".pdf") -> Kind.PDF
            n.endsWith(".docx") -> Kind.DOCX
            n.endsWith(".pptx") -> Kind.PPTX
            n.endsWith(".epub") -> Kind.EPUB
            n.endsWith(".html") || n.endsWith(".htm") -> Kind.HTML
            n.endsWith(".md") || n.endsWith(".markdown") -> Kind.MD
            n.endsWith(".txt") -> Kind.TXT
            else -> Kind.UNKNOWN
        }
    }

    fun parse(bytes: ByteArray, name: String): DocResult {
        val kind = kindOf(name)
        return when (kind) {
            Kind.UNKNOWN -> DocResult(kind, "", 0, false, "暂不支持这种格式")
            Kind.PDF -> DocResult(kind, "", 0, true, "PDF 文本层抽取在原生 v1 暂未支持；请用 Web 单文件版或 Windows 壳解析")
            Kind.DOCX -> wrap(kind, xmlText(zipEntry(bytes, "word/document.xml")), "docx")
            Kind.PPTX -> wrap(kind, slideText(bytes), "pptx")
            Kind.EPUB -> wrap(kind, epubText(bytes), "epub")
            Kind.HTML -> wrap(kind, stripTags(String(bytes, Charsets.UTF_8)), "html")
            else -> wrap(kind, String(bytes, Charsets.UTF_8), if (kind == Kind.MD) "md" else "txt")
        }
    }

    private fun wrap(kind: Kind, text: String, tag: String): DocResult =
        DocResult(kind, text, text.length, text.length < 200, if (text.length < 200) "抽取文本过短（${text.length} 字符）" else "$tag 解析完成")

    private fun stripTags(html: String): String =
        html.replace(Regex("<script[\\s\\S]*?</script>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<style[\\s\\S]*?</style>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<[^>]+>"), " ")
            .replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            .replace(Regex("[ \\t]+"), " ")

    private fun xmlText(xml: String?): String {
        if (xml == null) return ""
        val withBreaks = xml
            .replace("</w:p>", "\n").replace("<w:br/>", "\n").replace("<w:tab/>", "\t")
        return stripTags(withBreaks)
    }

    private fun zipEntry(bytes: ByteArray, name: String): String? {
        var zis: ZipInputStream? = null
        try {
            zis = ZipInputStream(bytes.inputStream())
            var e = zis.nextEntry
            while (e != null) {
                if (e.name == name) {
                    val out = ByteArrayOutputStream()
                    val buf = ByteArray(8192)
                    while (true) {
                        val r = zis.read(buf)
                        if (r < 0) break
                        out.write(buf, 0, r)
                    }
                    return out.toString("UTF-8")
                }
                e = zis.nextEntry
            }
            return null
        } catch (e: Exception) {
            return null
        } finally {
            try { zis?.close() } catch (e: Exception) { /* 尽力而为 */ }
        }
    }

    private fun eachEntry(bytes: ByteArray, fn: (name: String, content: String) -> Unit) {
        var zis: ZipInputStream? = null
        try {
            zis = ZipInputStream(bytes.inputStream())
            var e = zis.nextEntry
            while (e != null) {
                val out = ByteArrayOutputStream()
                val buf = ByteArray(8192)
                while (true) {
                    val r = zis.read(buf)
                    if (r < 0) break
                    out.write(buf, 0, r)
                }
                fn(e.name, out.toString("UTF-8"))
                e = zis.nextEntry
            }
        } catch (e: Exception) {
            // 解压失败按空处理
        } finally {
            try { zis?.close() } catch (e: Exception) { /* 尽力而为 */ }
        }
    }

    private fun slideText(bytes: ByteArray): String {
        val sb = StringBuilder()
        val slides = mutableListOf<Pair<Int, String>>()
        eachEntry(bytes) { name, content ->
            if (name.matches(Regex("ppt/slides/slide\\d+\\.xml"))) {
                val no = Regex("slide(\\d+)\\.xml").find(name)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                slides.add(no to xmlText(content))
            }
        }
        slides.sortedBy { it.first }.forEach { sb.append(it.second).append('\n') }
        return sb.toString()
    }

    private fun epubText(bytes: ByteArray): String {
        val sb = StringBuilder()
        eachEntry(bytes) { name, content ->
            if (name.endsWith(".html") || name.endsWith(".xhtml")) {
                sb.append(stripTags(content)).append('\n')
            }
        }
        return sb.toString()
    }
}
