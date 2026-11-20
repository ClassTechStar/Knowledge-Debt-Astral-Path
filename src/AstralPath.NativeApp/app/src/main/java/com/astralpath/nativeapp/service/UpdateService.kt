package com.astralpath.nativeapp.service

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 检查更新 —— 更新源默认 GitHub Release（releases/latest）。
 * 与 Web 版 shared/updater.js / Windows 壳 UpdateService 同口径：
 * 版本比较逐段数字；匿名查询 api.github.com（限流 60 次/小时），失败返回 null 走静默。
 *
 * 安全口径（THREAT_MODEL T22）：安卓端只「检查 + 跳转 Release 页」，不做应用内
 * 静默安装—— sideload 自装需要 REQUEST_INSTALL_PACKAGES 权限（商店风险），
 * 用户在 Release 页下载的 APK 自带系统安装器确认，安装决策权留给用户。
 */
object UpdateService {
    const val REPO = "ClassTechStar/Knowledge-Debt-Astral-Path"
    const val RELEASE_URL = "https://github.com/$REPO/releases/latest"

    data class UpdateCheck(val version: String, val url: String)

    /** 版本比较：逐段数字（与 shared/updater.js compareVersions 同构） */
    fun compareVersions(a: String, b: String): Int {
        fun segs(v: String): List<Int> {
            val t = v.trim().removePrefix("v").removePrefix("V")
            return (0 until 3).map { i -> t.split(".").getOrNull(i)?.toIntOrNull() ?: 0 }
        }
        val A = segs(a); val B = segs(b)
        return when {
            A[0] != B[0] -> if (A[0] < B[0]) -1 else 1
            A[1] != B[1] -> if (A[1] < B[1]) -1 else 1
            A[2] != B[2] -> if (A[2] < B[2]) -1 else 1
            else -> 0
        }
    }

    /**
     * 检查最新 Release。返回 UpdateCheck（tag 已剥 v 前缀）或 null（离线/限流/解析失败）。
     * 在线程里调用（不要在主线程发网络请求）。
     */
    fun checkLatest(currentVersion: String): UpdateCheck? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL("https://api.github.com/repos/$REPO/releases/latest").openConnection() as HttpURLConnection)
            conn.requestMethod = "GET"
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            if (conn.responseCode != 200) return null
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val j = JSONObject(body)
            val version = j.optString("tag_name", "").removePrefix("v").removePrefix("V").trim()
            if (version.isEmpty()) return null
            val url = j.optString("html_url", RELEASE_URL)
            UpdateCheck(version = version, url = url.ifEmpty { RELEASE_URL })
        } catch (e: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (e: Exception) { /* 尽力而为 */ }
        }
    }
}
