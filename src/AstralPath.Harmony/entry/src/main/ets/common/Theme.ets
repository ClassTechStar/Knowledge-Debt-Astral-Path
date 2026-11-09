/**
 * 设计系统 —— 与 Web 版 / Windows 版 / 单文件版严格一致的视觉基准。
 * 色板、圆角、字号、间距逐项取自 astralpath-monolith.html 的 CSS 变量与组件样式，
 * 移动端不再使用独立的"移动设计"，直接复刻 Web 版的视觉语言。
 */
export class Theme {
  // ── 色板（Web :root 变量的逐项对应）──
  /** 画布底：#f3f4f5 */
  static readonly CANVAS: string = '#F3F4F5';
  /** 卡片面：#fbfbfc */
  static readonly SURFACE: string = '#FBFBFC';
  /** 软灰块（进度条底、胶囊导航底、mark 底）：#e8eaec */
  static readonly SOFT: string = '#E8EAEC';
  /** 强灰（头像、mark 文字）：#6b7075 */
  static readonly STRONG: string = '#6B7075';
  /** 正文墨色：#303236 */
  static readonly INK: string = '#303236';
  /** 次要文字：#62676c */
  static readonly MUTED: string = '#62676C';
  /** 分隔线/描边：#c7cacf */
  static readonly RULE: string = '#C7CACF';
  /** 输入框底：#eff0f2 */
  static readonly FIELD: string = '#EFF0F2';
  /** 主色（primary 按钮、进度条）：#0D72D9 */
  static readonly PRIMARY: string = '#0D72D9';
  /** 渐变进度条末端：#6aa8f0 */
  static readonly PRIMARY_SOFT: string = '#6AA8F0';
  /** 危险：#b64a58 */
  static readonly DANGER: string = '#B64A58';
  /** 成功：#55a77b */
  static readonly OK: string = '#55A77B';
  /** 成功底：#dcf4e7 */
  static readonly OK_BG: string = '#DCF4E7';
  /** 成功字：#1e5d43 */
  static readonly OK_INK: string = '#1E5D43';
  /** 警示：#b8860b */
  static readonly WARN: string = '#B8860B';
  /** 警示底：#fff4d6 */
  static readonly WARN_BG: string = '#FFF4D6';
  /** 警示字：#6a5010 */
  static readonly WARN_INK: string = '#6A5010';
  /** 错误徽标底：#ffe1e5 / 字 #792e38（Web .badge.err） */
  static readonly ERR_BG: string = '#FFE1E5';
  static readonly ERR_INK: string = '#792E38';
  /** 状态文字（.status.ok / .status.err）：#2f6b50 / #8d2828 */
  static readonly OK_DEEP: string = '#2F6B50';
  static readonly ERR_TEXT: string = '#8D2828';
  /** 危机色（常驻提醒、转介入口）：#c0392b */
  static readonly CRISIS: string = '#C0392B';
  /** 默认图谱节点（无分类）：边 #b7bbc0 / 底 #fbfbfc */
  static readonly NODE_BD: string = '#B7BBC0';
  static readonly NODE_BG: string = '#FBFBFC';
  /** 识网连线（Web DOM 模式 .dline）：var(--strong) @45% */
  static readonly EDGE_GREY: string = '#6B7075';

  // ── 图谱节点三色（Web .dnode.chapter/term/debt）──
  static readonly NODE_CHAPTER_BORDER: string = '#4F86C6';
  static readonly NODE_CHAPTER_FILL: string = '#E8F2FB';
  static readonly NODE_CHAPTER_INK: string = '#1D3D5F';
  static readonly NODE_TERM_BORDER: string = '#55A77B';
  static readonly NODE_TERM_FILL: string = '#E5F7EE';
  static readonly NODE_TERM_INK: string = '#1E5D43';
  static readonly NODE_DEBT_BORDER: string = '#D95A67';
  static readonly NODE_DEBT_FILL: string = '#FFE1E5';
  static readonly NODE_DEBT_INK: string = '#792E38';
  /** 图谱连线色（Web canvas strokeStyle） */
  static readonly EDGE: string = '#55A77B';

  // ── 圆角（Web --r-c / --r-g / --r-shell）──
  /** 控件圆角 18px */
  static readonly R_C: number = 18;
  /** 卡片/面板圆角 28px */
  static readonly R_G: number = 28;
  /** 外壳圆角 36px */
  static readonly R_SHELL: number = 36;
  /** 胶囊（999px 在 vp 侧用大值代替） */
  static readonly R_PILL: number = 999;

  // ── 字号（Web：正文 15px/1.55、面板标题 20px、hint 13px、徽标 12px、节点标签 12.5px）──
  static readonly FS_BODY: number = 15;
  static readonly FS_TITLE: number = 20;
  static readonly FS_HINT: number = 13;
  static readonly FS_BADGE: number = 12;
  static readonly FS_BTN: number = 14;
  static readonly FS_SMALL: number = 11;

  // ── 间距（Web .panel padding 20px、margin-bottom 14px；.card padding 14/16）──
  static readonly PAD_PANEL: number = 20;
  static readonly GAP_PANEL: number = 16;
  static readonly PAD_CARD: number = 16;
}
