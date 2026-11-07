package com.astralpath.nativeapp.service

/**
 * 应用级通知总线 —— 对齐 Web 版分级通知（提示 / 注意 / 危机）的最小实现：
 * crisis 走常驻对话框（必须确认，免打扰下仍显示）；warn/info 走 Toast（免打扰下静默）。
 * 由 MainActivity 订阅 UI 呈现，页面只管发事件。
 */
object NotifyBus {
    enum class Level { INFO, WARN, CRISIS }

    interface Listener {
        fun onCrisis(title: String, message: String)
        fun onToast(message: String, level: Level)
    }

    private var listener: Listener? = null
    @Volatile private var dnd = false

    fun bind(l: Listener) { listener = l }

    fun setDnd(v: Boolean) { dnd = v }

    fun push(level: Level, title: String, message: String, force: Boolean = false) {
        if (level == Level.CRISIS) {
            listener?.onCrisis(title, message)
            return
        }
        if (dnd && !force) return
        listener?.onToast(message, level)
    }
}
