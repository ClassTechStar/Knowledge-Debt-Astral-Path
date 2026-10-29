/**
 * 公式常量 —— 与 C# FormulaConstants.cs、JS 侧的 K 同源，三端必须逐项一致。
 * 数值来源：src/AstralPath.Core/Formula/FormulaConstants.cs（单一事实源）。
 * 校验：scripts/verify_constants.py（C# ↔ JS）；ArkTS 侧由本文件与 C# 的取值对照表保证。
 */
export class FormulaConstants {
  /** 掌握度三项权重 */
  static readonly W: Weights = { e: 0.50, r: 0.30, p: 0.20 };
  /** 先修天花板下限：先修全不会时，后续最高只能到 0.55 */
  static readonly floor: number = 0.55;
  /** 记忆稳定性基线 */
  static readonly stab0: number = 2.5;
  /** 连对加成系数 */
  static readonly a: number = 0.45;
  /** 练习量加成系数 */
  static readonly b: number = 0.25;
  /** 先修支撑取「最弱链」与「均值」的混合比例（越大越保守） */
  static readonly mix: number = 0.65;
  /** 影响分基线 */
  static readonly impactBase: number = 0.55;
  /** 跨课程（跨教材）债边的额外放大 */
  static readonly crossTg: number = 1.15;
  /** 先修掌握度判定门（低于此值视为存在缺口） */
  static readonly pg: number = 0.55;
  /** 后续掌握度判定门 */
  static readonly cg: number = 0.50;
  /** 门的陡峭程度 */
  static readonly steep: number = 8.0;
  /** 开放红边判定阈值 */
  static readonly hit: number = 0.08;
  /** 级联放大系数 */
  static readonly cas: number = 0.12;
  /** 题量放大系数 */
  static readonly vol: number = 0.08;
  /** 销账达标线（加权得分） */
  static readonly saleBar: number = 0.65;
  /** 销账正确率下限 */
  static readonly saleAcc: number = 0.70;
  /** 销账信心下限 */
  static readonly saleConf: number = 3.0;
  /** 销账所需连续达标次数 */
  static readonly saleStreak: number = 2.0;
  /** 销账所需累计作答次数 */
  static readonly saleMinAtt: number = 3.0;
  /** 计划间隔偏移（天）：同一知识点重复出现的间隔候选 */
  static readonly spacingOffsets: number[] = [0, 2, 6];

  /** 算法版本号，落盘时一并写入，便于未来迁移 */
  static readonly scoreVersion: string = 'score-v2';
  static readonly impactVersion: string = 'impact-v2';
}

export interface Weights {
  e: number;
  r: number;
  p: number;
}
