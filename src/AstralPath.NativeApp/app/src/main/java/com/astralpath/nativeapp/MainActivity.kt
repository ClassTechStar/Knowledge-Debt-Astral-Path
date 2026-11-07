package com.astralpath.nativeapp

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.astralpath.nativeapp.service.NotifyBus
import com.astralpath.nativeapp.service.StoreService
import com.astralpath.nativeapp.ui.PagesAgent
import com.astralpath.nativeapp.ui.PagesCore
import com.astralpath.nativeapp.ui.PagesDebt
import com.astralpath.nativeapp.ui.PagesMore
import com.astralpath.nativeapp.ui.Ui

/**
 * 主壳 —— 对应单文件版 header + nav.pills + main#p-* 结构：
 * 顶部品牌栏 + 可横滚胶囊导航 + 单页内容区（程序化构建，切页即刷新）。
 * 危机通知走常驻对话框（点确认才关），warn/info 走 Toast（免打扰静音）。
 */
class MainActivity : AppCompatActivity(), NotifyBus.Listener {

    private lateinit var content: FrameLayout
    private val pillButtons = LinkedHashMap<String, TextView>()

    private val pages = listOf(
        "home" to "起点", "materials" to "藏书阁", "graph" to "识网", "papers" to "试卷作业",
        "debt" to "知债", "today" to "今日", "agent" to "智能体", "profile" to "画像",
        "teacher" to "教师", "account" to "账户",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        val ctx: android.content.Context = this
        super.onCreate(savedInstanceState)
        StoreService.init(this)
        StoreService.ensureSchema()
        NotifyBus.bind(this)
        NotifyBus.setDnd(StoreService.loadMeta().dnd)

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Ui.BG) }

        // 品牌栏
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Ui.SURFACE)
            setPadding(Ui.dp(this@MainActivity, 16), Ui.dp(this@MainActivity, 12), Ui.dp(this@MainActivity, 16), Ui.dp(this@MainActivity, 8))
        }
        header.addView(Ui.label(this, "知债：星穹学途", 17f, Ui.INK, bold = true))
        val sp = View(this); header.addView(sp, LinearLayout.LayoutParams(0, 1, 1f))
        header.addView(Ui.button(this, "？") { PagesMore.helpDialog(this) })
        root.addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        // 胶囊导航
        val pillsRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(Ui.dp(ctx, 8), Ui.dp(ctx, 6), Ui.dp(ctx, 8), Ui.dp(ctx, 6)) }
        pages.forEach { (id, label) ->
            val t = TextView(this).apply {
                text = label; textSize = 13f; setPadding(Ui.dp(this@MainActivity, 10), Ui.dp(this@MainActivity, 5), Ui.dp(this@MainActivity, 10), Ui.dp(this@MainActivity, 5))
                tag = id
                setOnClickListener { nav(id) }
            }
            pillButtons[id] = t
            pillsRow.addView(t)
        }
        val pillsScroll = HorizontalScrollView(this).apply { addView(pillsRow); isHorizontalScrollBarEnabled = false }
        root.addView(pillsScroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        content = FrameLayout(this)
        root.addView(content, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
        nav("home")
    }

    fun nav(page: String) {
        pillButtons.forEach { (id, t) ->
            val on = id == page
            t.setTextColor(if (on) Ui.BRAND else Ui.MUTED)
            t.typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, if (on) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
            val d = android.graphics.drawable.GradientDrawable()
            d.cornerRadius = Ui.dp(this, 14).toFloat()
            d.setColor(if (on) Ui.BRAND_SOFT else Color.TRANSPARENT)
            t.background = d
        }
        val v: View = when (page) {
            "home" -> PagesCore.homePage(this)
            "materials" -> PagesCore.materialsPage(this)
            "graph" -> PagesCore.graphPage(this)
            "papers" -> PagesMore.papersPage(this)
            "debt" -> PagesDebt.debtPage(this)
            "today" -> PagesDebt.todayPage(this)
            "agent" -> PagesAgent.page(this)
            "profile" -> PagesMore.profilePage(this)
            "teacher" -> PagesMore.teacherPage(this)
            else -> PagesMore.accountPage(this)
        }
        content.removeAllViews()
        content.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    /** 打开系统文档选择器（藏书阁导入用） */
    fun openDocument(onPicked: (Uri, String) -> Unit) {
        picked = onPicked
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            val types = arrayOf("text/plain", "text/html", "text/markdown", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/epub+zip")
            putExtra(Intent.EXTRA_MIME_TYPES, types)
        }
        try {
            startActivityForResult(intent, REQ_DOC)
        } catch (e: Exception) {
            Toast.makeText(this, "无法打开文件选择器：${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private var picked: ((Uri, String) -> Unit)? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_DOC && resultCode == RESULT_OK) {
            data?.data?.let { uri ->
                val name = queryName(uri) ?: "material.txt"
                picked?.invoke(uri, name)
            }
        }
    }

    private fun queryName(uri: Uri): String? =
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (c.moveToFirst() && idx >= 0) c.getString(idx) else null
        }

    // ── NotifyBus.Listener ──
    override fun onCrisis(title: String, message: String) {
        runOnUiThread {
            AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton("我知道了", null)
                .setCancelable(false)
                .show()
        }
    }

    override fun onToast(message: String, level: NotifyBus.Level) {
        runOnUiThread {
            val t = Toast.makeText(this, message, Toast.LENGTH_SHORT)
            t.show()
        }
    }

    companion object { private const val REQ_DOC = 7001 }
}
