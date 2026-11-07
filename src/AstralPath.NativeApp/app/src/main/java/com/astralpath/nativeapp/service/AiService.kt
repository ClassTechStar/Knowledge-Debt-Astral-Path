package com.astralpath.nativeapp.service

import com.astralpath.nativeapp.data.AiCfg
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * 模型服务 —— OpenAI 兼容 /chat/completions（SSE 流式），与单文件版/鸿蒙版同一接口。
 * 亮点沿用 DeepTutor 迁移的两条语义：
 * ① 用户取消：cancel() 中止在飞请求，已收到的正文按「取消成功」返回（不计入故障冷却）；
 * ② 传输类错误与内容类错误区分（isTransportError），只有前者进冷却。
 * AI 挂了不影响核心功能：调用方拿 null / 空串走本地规则兜底（演示模式）。
 */
object AiService {
    const val DEFAULT_BASE = "https://api.xiaomimimo.com/v1"

    @Volatile private var currentConn: HttpURLConnection? = null
    @Volatile var cancelled: Boolean = false
        private set

    fun ready(cfg: AiCfg): Boolean = cfg.key.isNotEmpty()

    fun isTransportError(m: String): Boolean =
        Regex("HTTP 5|Failed to connect|NetworkError|network|abort|timeout|超时|connection|socket", RegexOption.IGNORE_CASE).containsMatchIn(m)

    /** 用户主动停止当前流式请求 */
    fun cancel() {
        cancelled = true
        try { currentConn?.disconnect() } catch (e: Exception) { /* 尽力而为 */ }
    }

    /**
     * 流式补全：逐块回调（reasoning 思维链走 onThinking），返回 {text, cancelled}。
     * 网络失败返回 null（调用方兜底），不打断主流程。
     */
    fun stream(
        cfg: AiCfg, system: String, user: String, maxTokens: Int,
        onDelta: (fullText: String) -> Unit,
        onThinking: (tail: String) -> Unit,
    ): Pair<String, Boolean>? {
        if (!ready(cfg)) return null
        cancelled = false
        var conn: HttpURLConnection? = null
        return try {
            val body = JSONObject()
                .put("model", cfg.model.ifEmpty { "mimo-7b-rl" })
                .put(
                    "messages",
                    org.json.JSONArray()
                        .put(JSONObject().put("role", "system").put("content", system))
                        .put(JSONObject().put("role", "user").put("content", user)),
                )
                .put("stream", true)
                .put("max_tokens", maxTokens)
            conn = (URL(cfg.baseUrl.ifEmpty { DEFAULT_BASE } + "/chat/completions").openConnection() as HttpURLConnection)
            currentConn = conn
            conn.requestMethod = "POST"
            conn.connectTimeout = 10_000
            conn.readTimeout = 60_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("Authorization", "Bearer " + cfg.key)
            conn.setRequestProperty("Accept", "text/event-stream")
            conn.outputStream.use { it.write(body.toString().toByteArray(StandardCharsets.UTF_8)) }

            val code = conn.responseCode
            if (code != 200) return null
            val out = StringBuilder()
            val reason = StringBuilder()
            var model = cfg.model
            var sseDone = false
            var userCancelled = false
            BufferedReader(InputStreamReader(conn.inputStream, StandardCharsets.UTF_8)).use { reader ->
                var line: String? = reader.readLine()
                while (line != null && !sseDone && !cancelled) {
                    if (line.startsWith("data:")) {
                        val payload = line.removePrefix("data:").trim()
                        if (payload == "[DONE]") {
                            sseDone = true
                        } else {
                            try {
                                val j = JSONObject(payload)
                                j.optString("model", "").takeIf { it.isNotEmpty() }?.let { model = it }
                                val choice = j.optJSONArray("choices")?.optJSONObject(0)
                                val d = choice?.optJSONObject("delta") ?: choice?.optJSONObject("message")
                                val rp = d?.optString("reasoning_content", "") ?: ""
                                if (rp.isNotEmpty()) { reason.append(rp); onThinking(rp.takeLast(64)) }
                                val piece = d?.optString("content", "") ?: ""
                                if (piece.isNotEmpty()) { out.append(piece); onDelta(out.toString()) }
                            } catch (e: Exception) { /* 半包/心跳，忽略 */ }
                        }
                    }
                    line = reader.readLine()
                }
                if (cancelled) userCancelled = true
            }
            var text = out.toString().trim()
            if (text.isEmpty() && reason.trim().length >= 4) text = reason.toString().trim()
            if (text.isEmpty()) return null
            text to userCancelled
        } catch (e: Exception) {
            if (cancelled) "" to true
            else null
        } finally {
            try { conn?.disconnect() } catch (e: Exception) { /* 尽力而为 */ }
            currentConn = null
        }
    }
}
