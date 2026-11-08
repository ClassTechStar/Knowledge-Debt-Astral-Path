package com.astralpath.nativeapp

import android.content.Intent
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
 * 主壳 —— 对齐 Web 版 header + nav.pills + main#p-* 结构：
 * 顶部品牌栏 + 可横滚胶囊导航（对齐 Web nav.pills：soft 底 / 999 圆角 /
 * 选中项 surface 底 + ink 加粗）+ 单页内容区（程序化构建，切页即刷新）。
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

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Ui.CANVAS) }

        // 品牌栏（对齐 Web header.rail：mark + brand 标题/说明）
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Ui.CANVAS)
            setPadding(Ui.dp(this@MainActivity, 16), Ui.dp(this@MainActivity, 12), Ui.dp(this@MainActivity, 16), Ui.dp(this@MainActivity, 8))
        }
        // mark（对齐 Web .mark：soft 底圆角方块 + strong 字）
        val mark = TextView(this).apply {
            text = "债"
            setTextSize(0, Ui.sp(this@MainActivity, 15f))
            setTextColor(Ui.STRONG)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = Ui.shape(Ui.SOFT, Ui.dpF(this@MainActivity, 12f))
        }
        header.addView(mark, LinearLayout.LayoutParams(Ui.dp(this@MainActivity, 40), Ui.dp(this@MainActivity, 30)))
        val brand = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(Ui.dp(this@MainActivity, 10), 0, 0, 0) }
        brand.addView(Ui.label(this, "知债：星穹学途", 16f, Ui.INK, bold = true))
        brand.addView(Ui.label(this, "识网 · 知债 · 修复计划", 11f, Ui.MUTED))
        header.addView(brand)
        val sp = View(this); header.addView(sp, LinearLayout.LayoutParams(0, 1, 1f))
        header.addView(Ui.btn(this, "？", quiet = true) { PagesMore.helpDialog(this) })
        root.addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        // 胶囊导航（对齐 Web nav.pills：容器 soft 底 999 圆角；选中项 surface 底 + ink 加粗）
        val pillsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(Ui.dp(ctx, 5), Ui.dp(ctx, 5), Ui.dp(ctx, 5), Ui.dp(ctx, 5))
            background = Ui.shape(Ui.SOFT, Ui.dpF(ctx, Ui.R_PILL)) // --soft 底、999 圆角
        }
        pages.forEach { (id, label) ->
            val t = TextView(this).apply {
                text = label
                setTextSize(0, Ui.sp(this@MainActivity, Ui.FS_HINT))
                setPadding(Ui.dp(this@MainActivity, 14), Ui.dp(this@MainActivity, 8), Ui.dp(this@MainActivity, 14), Ui.dp(this@MainActivity, 8))
                minHeight = Ui.dp(this@MainActivity, 44) // 对齐 Web nav.pills button min-height:44
                gravity = Gravity.CENTER
                tag = id
                setOnClickListener { nav(id) }
            }
            pillButtons[id] = t
            pillsRow.addView(t, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = Ui.dp(ctx, 2); marginEnd = Ui.dp(ctx, 2) }) // gap 4px
        }
        val pillsWrap = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(Ui.dp(ctx, 16), Ui.dp(ctx, 4), Ui.dp(ctx, 16), Ui.dp(ctx, 8))
        }
        pillsWrap.addView(pillsRow)
        val pillsScroll = HorizontalScrollView(this).apply {
            addView(pillsWrap); isHorizontalScrollBarEnabled = false
            setBackgroundColor(Ui.CANVAS)
        }
        root.addView(pillsScroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        content = FrameLayout(this)
        root.addView(content, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
        nav("home")
    }

    fun nav(page: String) {
        // 胶囊选中态（对齐 Web nav.pills button.on：surface 底 + ink 加粗；未选中 muted 透明底）
        pillButtons.forEach { (id, t) ->
            val on = id == page
            t.setTextColor(if (on) Ui.INK else Ui.MUTED)
            t.typeface = android.graphics.Typeface.create(
                android.graphics.Typeface.DEFAULT,
                if (on) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL,
            )
            t.background = if (on) Ui.shape(Ui.SURFACE, Ui.dpF(this, Ui.R_PILL)) else null
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
