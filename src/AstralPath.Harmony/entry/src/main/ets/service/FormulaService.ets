/**
 * 公式服务 —— score-v2 / impact-v2 / sale-v2，逐行移植自单文件版 JS 实现，
 * 取值与 C# FormulaConstants.cs、JS 常量块 K 同源（见 verify_constants.py）。
 * 这里刻意不引入任何平台 API，方便将来和 JS/C# 三方对拍。
 */
import { FormulaConstants as K } from '../model/FormulaConstants';
import { DebtEdge, Mastery, SaleInput, SaleResult } from '../model/Models';

export class FormulaService {
  static clamp01(v: number): number {
    return Math.max(0, Math.min(1, v));
  }

  /** sigmoid */
  static sig(x: number): number {
    return 1 / (1 + Math.exp(-x));
  }

  /** 经验项：Jeffreys 先验收缩估计 */
  static empirical(n: number, s: number): number {
    return (s + 0.5) / (n + 1);
  }

  /** 记忆稳定性：连对越多、练得越多，遗忘越慢 */
  static stability(streak: number, att: number): number {
    return K.stab0 * (1 + K.a * Math.max(streak, 0)) * (1 + K.b * Math.log(1 + Math.max(att, 1)));
  }

  /** 记忆保持：Ebbinghaus 指数衰减 */
  static retention(age: number, streak: number, att: number): number {
    return Math.exp(-Math.max(age, 0) / FormulaService.stability(streak, att));
  }

  /** 先修支撑：均值与最弱链的混合（mix 越大越看最弱链） */
  static prereqSup(arr: number[]): number {
    if (!arr || arr.length === 0) {
      return 0.5;
    }
    let sum = 0;
    for (let i = 0; i < arr.length; i++) {
      sum += arr[i];
    }
    const mean = sum / arr.length;
    let mn = arr[0];
    for (let i = 1; i < arr.length; i++) {
      if (arr[i] < mn) {
        mn = arr[i];
      }
    }
    return (1 - K.mix) * mean + K.mix * mn;
  }

  /** 先修天花板：先修不会，后续再练也上不去 */
  static prereqCeil(arr: number[]): number {
    if (!arr || arr.length === 0) {
      return 1;
    }
    let mn = arr[0];
    for (let i = 1; i < arr.length; i++) {
      if (arr[i] < mn) {
        mn = arr[i];
      }
    }
    return K.floor + (1 - K.floor) * mn;
  }

  /** score-v2：掌握度 = 经验项 + 保持项 + 先修支撑，再受先修天花板约束 */
  static scoreV2(att: number, ok: number, conf: number, age: number, streak: number, prereq: number[]): number {
    const know = 0.85 * FormulaService.empirical(att, ok) + 0.15 * FormulaService.clamp01(conf / 5);
    const raw = K.W.e * know + K.W.r * FormulaService.retention(age, streak, att) + K.W.p * FormulaService.prereqSup(prereq);
    return FormulaService.clamp01(Math.min(raw, FormulaService.prereqCeil(prereq)));
  }

  /** impact-v2：债边影响分；freq=0 直接为 0（没错过就不算债） */
  static impactV2(sf: number, st: number, w: number, tg: boolean, freq: number, down: number): number {
    if (!(freq > 0)) {
      return 0;
    }
    const ww = Number.isFinite(w) ? Math.max(w, 0) : 0;
    return K.impactBase *
      FormulaService.sig((sf - K.pg) * K.steep) *
      FormulaService.sig((K.cg - st) * K.steep) *
      ww *
      (tg ? K.crossTg : 1) *
      (1 + K.cas * Math.log(1 + Math.max(down, 0))) *
      (1 + K.vol * Math.log(1 + Math.max(freq, 0)));
  }

  /** 销账步进：连续达标 saleStreak 次且累计作答够数才算结清 */
  static saleStep(s: SaleInput | undefined, acc: number, conf: number): SaleResult {
    const st0 = s ?? { streak: 0, att: 0 };
    const meets = (0.7 * acc + 0.3 * FormulaService.clamp01(conf / 5)) >= K.saleBar &&
      acc >= K.saleAcc && conf >= K.saleConf;
    const streak = meets ? st0.streak + 1 : 0;
    const att = st0.att + 1;
    const cleared = streak >= K.saleStreak && att >= K.saleMinAtt;
    return { streak: streak, att: att, meets: meets, cleared: cleared };
  }

  /** 由掌握度记录计算某个知识点的得分（先修由调用方传入，避免递归查表） */
  static scoreOfMastery(m: Mastery, prereq: number[]): number {
    return FormulaService.scoreV2(m.n, m.s, m.c, m.age, m.st, prereq);
  }

  /** 开放红边判定 */
  static isOpen(impact: number): boolean {
    return impact >= K.hit;
  }

  /** 债边排序（impact 降序） */
  static sortDebts(list: DebtEdge[]): DebtEdge[] {
    return list.slice().sort((x: DebtEdge, y: DebtEdge) => y.impact - x.impact);
  }
}
