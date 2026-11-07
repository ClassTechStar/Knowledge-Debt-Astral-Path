package com.astralpath.nativeapp.data

/** 示例教材与演示学情 —— 移植自鸿蒙版 DemoData.ets（内容与 Web 版「导入示例教材」一致） */
object DemoData {
    fun build(): Book {
        val nodes = listOf(
            KNode("P01", "变量与类型", diff = 1, course = "Python"),
            KNode("P02", "运算符与表达式", diff = 1, course = "Python"),
            KNode("P03", "条件分支", diff = 2, course = "Python"),
            KNode("P04", "循环结构", diff = 2, course = "Python"),
            KNode("P05", "函数定义", diff = 2, course = "Python"),
            KNode("P06", "列表与切片", diff = 2, course = "Python"),
            KNode("P07", "字典与集合", diff = 3, course = "Python"),
            KNode("P08", "异常处理", diff = 3, course = "Python"),
            KNode("P09", "文件读写", diff = 3, course = "Python"),
            KNode("P10", "类与对象", diff = 3, course = "Python"),
            KNode("D01", "神经元与激活函数", diff = 2, course = "深度学习"),
            KNode("D02", "损失函数", diff = 3, course = "深度学习"),
            KNode("D03", "梯度下降", diff = 3, course = "深度学习"),
            KNode("D04", "反向传播", diff = 4, course = "深度学习"),
        )
        val edges = listOf(
            KEdge("P01", "P02", 1.0), KEdge("P02", "P03", 0.9), KEdge("P03", "P04", 0.9),
            KEdge("P04", "P05", 0.8), KEdge("P01", "P06", 0.8), KEdge("P06", "P07", 0.7),
            KEdge("P05", "P08", 0.7), KEdge("P08", "P09", 0.6), KEdge("P05", "P10", 0.8),
            KEdge("P01", "D01", 0.5, tg = true), KEdge("D01", "D02", 0.9),
            KEdge("D02", "D03", 0.9), KEdge("D03", "D04", 0.9),
        )
        return Book(
            id = "demo-python",
            name = "Python 从入门到实践（示例）",
            source = "demo",
            nodes = nodes,
            edges = edges,
            qs = questions(),
            created = System.currentTimeMillis(),
        )
    }

    private fun questions(): List<Question> {
        val seeds = listOf(
            Triple("P01", "下面哪个是合法的变量名？", listOf("1a", "_a", "for", "a-b")) to 1,
            Triple("P02", "表达式 7 // 2 的结果是？", listOf("3", "3.5", "4", "3.0")) to 0,
            Triple("P03", "条件分支使用的关键字是？", listOf("if", "switch", "when", "case")) to 0,
            Triple("P04", "for 循环常用于？", listOf("遍历序列", "定义函数", "捕获异常", "声明类")) to 0,
            Triple("P05", "定义函数使用？", listOf("def", "function", "lambda", "func")) to 0,
            Triple("P06", "lst[1:3] 的切片结果是？", listOf("第 1 到第 3 个", "第 2 到第 3 个", "第 1 到第 2 个", "全部")) to 1,
            Triple("P07", "字典的键必须？", listOf("可哈希", "有序", "可变", "数字")) to 0,
            Triple("P08", "捕获异常使用？", listOf("try/except", "do/catch", "if/else", "throw")) to 0,
            Triple("P09", "打开文件使用？", listOf("open()", "read()", "file()", "load()")) to 0,
            Triple("P10", "定义类使用？", listOf("class", "struct", "type", "def class")) to 0,
            Triple("D01", "神经元的输出经过？", listOf("激活函数", "损失函数", "优化器", "池化")) to 0,
            Triple("D02", "分类任务常用损失是？", listOf("交叉熵", "MSE", "MAE", "Huber")) to 0,
            Triple("D03", "梯度下降用于？", listOf("最小化损失", "最大化损失", "数据增强", "归一化")) to 0,
            Triple("D04", "反向传播的本质是？", listOf("链式法则求梯度", "前向传播", "随机初始化", "正则化")) to 0,
        )
        return seeds.mapIndexed { i, (t, ci) ->
            Question(id = "Q" + (i + 1).toString().padStart(3, '0'), kp = t.first, stem = t.second, opts = t.third, ci = ci)
        }
    }

    /**
     * 演示学情：让 3 个「后续」知识点带着错题（先修还算正常）。
     * 全默认掌握度时 impact 约为 0.0798，恰卡在 0.08 阈值下——演示数据就成了「零红边」。
     */
    fun seedMastery(): Map<String, Mastery> = mapOf(
        "P02" to Mastery(3, 0, 2, 6, 0),
        "P06" to Mastery(2, 0, 1, 8, 0),
        "D02" to Mastery(2, 0, 1, 5, 0),
    )

    fun seedLogs(): List<AnswerLog> {
        val now = System.currentTimeMillis()
        val out = mutableListOf<AnswerLog>()
        fun push(kp: String, times: Int) {
            for (i in 0 until times) {
                out.add(AnswerLog("seed-$kp-$i", kp, false, 2, now - i * 86_400_000L))
            }
        }
        push("P02", 3); push("P06", 2); push("D02", 2)
        return out
    }
}
