/**
 * 折叠屏自适应 —— Mate X7（折叠态约 6.5 英寸 / 展开态约 8 英寸）与 Mate 90 系列：
 * 以窗口宽度 vp 为断点，折叠态单栏 + 底部导航，展开态双栏（列表 + 详情）或侧边导航。
 * 断点值取自 ArkUI 通用栅格建议：sm < 600vp、md 600–840vp、lg >= 840vp。
 */
export enum LayoutSize {
  SM = 0,   // 折叠态/竖屏手机：单栏、底部导航
  MD = 1,   // 大屏手机/折叠展开小窗：单栏 + 更宽卡片
  LG = 2    // Mate X7 展开态/平板：双栏、侧边导航
}

export class Breakpoint {
  static readonly SM_MAX: number = 600;
  static readonly MD_MAX: number = 840;

  /** 按窗口宽度（vp）判定档位 */
  static of(widthVp: number): LayoutSize {
    if (widthVp < Breakpoint.SM_MAX) {
      return LayoutSize.SM;
    }
    if (widthVp < Breakpoint.MD_MAX) {
      return LayoutSize.MD;
    }
    return LayoutSize.LG;
  }

  /** 是否双栏（展开态：左边列表、右边详情） */
  static isTwoPane(size: LayoutSize): boolean {
    return size === LayoutSize.LG;
  }

  /** 导航形态：展开态用侧边栏，折叠态用底部栏 */
  static useSideNav(size: LayoutSize): boolean {
    return size === LayoutSize.LG;
  }

  /** 栅格列数：折叠态 4 列、中屏 8 列、展开态 12 列 */
  static columns(size: LayoutSize): number {
    switch (size) {
      case LayoutSize.SM:
        return 4;
      case LayoutSize.MD:
        return 8;
      default:
        return 12;
    }
  }

  /** 卡片最大宽度：展开态限制行长，避免文字拉太长难读 */
  static contentMaxWidth(size: LayoutSize): number {
    switch (size) {
      case LayoutSize.SM:
        return 0; // 0 表示不限制，铺满
      case LayoutSize.MD:
        return 720;
      default:
        return 960;
    }
  }
}

/** 页面列表，顺序与 Web 版顶部 pills 导航一致 */
export const PAGE_ORDER: string[] = [
  'home', 'materials', 'graph', 'papers', 'debt', 'today', 'agent', 'profile', 'teacher', 'account'
];

export const PAGE_LABEL: Record<string, string> = {
  'home': '起点',
  'materials': '藏书阁',
  'graph': '识网',
  'papers': '试卷作业',
  'debt': '知债',
  'today': '今日',
  'agent': '智能体',
  'profile': '画像',
  'teacher': '教师',
  'account': '账户'
};
