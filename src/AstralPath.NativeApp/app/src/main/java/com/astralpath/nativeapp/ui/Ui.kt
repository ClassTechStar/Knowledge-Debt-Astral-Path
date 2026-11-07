package com.astralpath.nativeapp.ui

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat

/** 主题与视图工厂 —— 色板与单文件版 :root 同源；全部 UI 程序化构建（对应 Web 的 DOM 组装） */
object Ui {
    val BRAND = 0xFF2F6FED.toInt()
    val BRAND_SOFT = 0xFFE4EDFD.toInt()
    val SURFACE = Color.WHITE
    val BG = 0xFFF3F5F8.toInt()
    val SOFT = 0xFFF0F3F7.toInt()
    val RULE = 0xFFD4D9DE.toInt()
    val INK = 0xFF1E2228.toInt()
    val MUTED = 0xFF6B7077.toInt()
    val DANGER = 0xFFC0392B.toInt()
    val DANGER_SOFT = 0xFFFDECEC.toInt()
    val OK = 0xFF2EA05A.toInt()
    val WARN = 0xFFB8860B.toInt()

    fun dp(c: Context, v: Int): Int = (v * c.resources.displayMetrics.density).toInt()

    fun card(c: Context, bg: Int = SOFT, radius: Int = 14, pad: Int = 12): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.setPadding(dp(c, pad), dp(c, pad), dp(c, pad), dp(c, pad))
        val d = GradientDrawable()
        d.setColor(bg)
        d.cornerRadius = dp(c, radius).toFloat()
        l.background = d
        return l
    }

    fun label(c: Context, text: String, size: Float = 13f, color: Int = INK, bold: Boolean = false): TextView {
        val t = TextView(c)
        t.text = text
        t.textSize = size
        t.setTextColor(color)
        if (bold) t.typeface = Typeface.DEFAULT_BOLD
        return t
    }

    fun button(c: Context, text: String, primary: Boolean = false, onClick: (View) -> Unit): Button {
        val b = Button(c)
        b.text = text
        b.textSize = 12f
        b.isAllCaps = false
        b.setMinHeight(0)
        b.minimumHeight = dp(c, 32)
        b.setPadding(dp(c, 12), dp(c, 4), dp(c, 12), dp(c, 4))
        val d = GradientDrawable()
        d.setColor(if (primary) BRAND else SURFACE)
        d.cornerRadius = dp(c, 12).toFloat()
        if (!primary) d.setStroke(dp(c, 1), RULE)
        b.background = d
        b.setTextColor(if (primary) Color.WHITE else INK)
        b.setOnClickListener(onClick)
        return b
    }

    /** 竖排卡片容器（页面根） */
    fun page(c: Context): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.VERTICAL
        l.setPadding(dp(c, 16), dp(c, 12), dp(c, 16), dp(c, 24))
        l.setBackgroundColor(BG)
        return l
    }

    fun row(c: Context): LinearLayout {
        val l = LinearLayout(c)
        l.orientation = LinearLayout.HORIZONTAL
        l.gravity = Gravity.CENTER_VERTICAL
        return l
    }

    fun fill(v: View): LinearLayout.LayoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
        setMargins(0, dp(v.context, 4), 0, dp(v.context, 4))
    }

    fun colorOf(c: Context, res: Int): Int = ContextCompat.getColor(c, res)
}
