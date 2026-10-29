/**
 * 脱敏服务 —— 对应 Web 版「敏感域不进画像、入库前脱敏」。
 * 规则保持简单可解释：手机号、身份证、邮箱、QQ 号、银行卡、常见姓名称谓。
 * 命中即整段替换，不做部分保留（避免「138****1234」这种还能反推的写法）。
 */
export class SanitizeService {
  private static readonly RULES: RegExp[] = [
    /1[3-9]\d{9}/g,                       // 手机号
    /\d{17}[\dXx]/g,                      // 身份证
    /\d{16,19}/g,                         // 银行卡 / 长数字串
    /[\w.+-]+@[\w-]+\.[\w.]+/g,           // 邮箱
    /(?:QQ|qq|微信|wechat)[^\d]{0,4}\d{5,12}/g,
    /(?:我叫|姓名|本人)[^\n，,。]{0,6}/g
  ];

  static mask(text: string): string {
    let out = text;
    for (const re of SanitizeService.RULES) {
      out = out.replace(re, (m: string) => SanitizeService.stars(m));
    }
    return out;
  }

  private static stars(m: string): string {
    return '***';
  }

  /** 命中项列表（给用户看「我替你挡了什么」） */
  static hits(text: string): string[] {
    const found: string[] = [];
    for (const re of SanitizeService.RULES) {
      const m = text.match(re);
      if (m) {
        for (const s of m) {
          found.push(s);
        }
      }
    }
    return found;
  }
}
