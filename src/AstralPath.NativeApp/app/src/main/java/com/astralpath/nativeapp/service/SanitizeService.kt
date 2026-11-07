package com.astralpath.nativeapp.service

/**
 * 脱敏服务 —— 移植自鸿蒙版 SanitizeService.ets：命中即整段替换（不做可反推的部分打码）。
 * 交互路径（给 LLM 的上下文）与入库文本都应过一遍。
 */
object SanitizeService {
    private val RULES = listOf(
        Regex("1[3-9]\\d{9}"),                  // 手机号
        Regex("\\d{17}[\\dXx]"),                // 身份证
        Regex("\\d{16,19}"),                    // 银行卡 / 长数字串
        Regex("[\\w.+-]+@[\\w-]+\\.[\\w.]+"),   // 邮箱
        Regex("(?:QQ|qq|微信|wechat)[^\\d]{0,4}\\d{5,12}"),
        Regex("(?:我叫|姓名|本人)[^\\n，,。]{0,6}"),
    )

    fun mask(text: String): String {
        var out = text
        for (re in RULES) out = re.replace(out) { "***" }
        return out
    }

    fun hits(text: String): List<String> = RULES.flatMap { it.findAll(text).map { m -> m.value } }
}
