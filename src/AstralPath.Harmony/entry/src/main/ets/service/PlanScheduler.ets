/**
 * PlanScheduler —— 修复计划调度器，逐行移植自 Web 版 shared/plan-scheduler.js。
 *
 * 覆盖能力：逐日容量排程（每天 ≤ 预算、每天 ≤ 4 条、同知识点一天一条）、
 * 三遍复习（0/2/6 天间隔，先修任务在前、进阶在后）、先修深度排名（Kahn 最长链）、
 * K1–K5 合约校验、先修顺序自动重排（fixK2）、超预算减压（reliefDays）。
 *
 * 算法事实源在 shared/plan-scheduler.js（plan_scheduler_runner.js 有 8 项金样）：
 * 改算法先改那边并跑金样，这里只做同构移植；两边若有出入，以金样为准。
 *
 * 与 Web 版仅有的两类差异（类型层，非行为层）：
 * ① ArkTS 严格模式不允许动态键对象，bins/firstDay/rank 等换成 Map；
 * ② 图谱边入参统一为 CtxEdge{from,to,tg,w}（Harmony KEdge 的 a/b 在调用处映射）。
 * 不读 DOM、不读全局状态、不碰存储——纯函数，方便将来做三方对拍。
 */
import { KNode } from '../model/Models';

export interface CtxEdge {
  from: string;
  to: string;
  tg?: boolean;
  w?: number;
}

/** 债边入参（DebtEdge 的 a/b/impact 在调用处映射过来） */
export interface DebtInput {
  from: string;
  to: string;
  imp: number;
  fromName?: string;
  toName?: string;
}

export interface DeferredEdge {
  from: string;
  to: string;
  reason: string;
}

/** K5 校验用的债边事实 */
export interface K5Debt {
  from: string;
  to: string;
  fromName?: string;
  toName?: string;
}

/** 排程产物：与 Web 版 plan 条目同构（min 对应 Harmony PlanItem.minutes） */
export interface SchedItem {
  id: number;
  day: number;
  kp: string;
  layer: string;
  st: string;
  min: number;
  fromKp: string;
  rd: number;
  label: string;
  why: string;
  drop?: boolean;
}

export interface ScheduleResult {
  items: SchedItem[];
  deferred: DeferredEdge[];
  rounds: number;
}

export interface ScheduleCtx {
  edges: CtxEdge[];
  nodes?: KNode[];
  courseOf?: (id: string) => string;
  prereqsOf?: (id: string) => string[];
  label?: (d: DebtInput, kind: string, r: number) => string;
  why?: (d: DebtInput, kind: string, r: number, min: number, rdP: number) => string;
  spacingOffsets?: number[];
}

export interface ScheduleOpts {
  course?: string;
  debts?: K5Debt[];
  deferred?: DeferredEdge[];
}

export interface KCheckOpts {
  edges?: CtxEdge[];
  debts?: K5Debt[];
  deferred?: DeferredEdge[];
}

export interface KCheckCtx {
  titleOf?: (id: string) => string;
}

interface DayBin {
  min: number;
  n: number;
  kps: Set<string>;
}

interface EntryRec {
  d: DebtInput;
  di: number;
  r: number;
  kind: string;
  day: number;
  min: number;
  rdP: number;
}

/** fixK2 里「先修晚于后续最严重的一条边」 */
interface WorstEdge {
  from: string;
  to: string;
  dd: number;
}

export class PlanScheduler {
  /** 掌握度展示分（与 Web 版 goldenScore 同式：0.6 经验 + 0.3 稳定 + 0.1 信心） */
  static goldenScore(recentAcc: number, sev: number, selfConf: number): number {
    const sevNorm = 1 - Math.max(0, Math.min(1, sev || 0));
    const acc = Math.max(0, Math.min(1, recentAcc || 0));
    const conf = Math.max(1, Math.min(5, selfConf || 3));
    return Number((100 * (0.6 * acc + 0.3 * sevNorm + 0.1 * (conf / 5))).toFixed(1));
  }

  /**
   * K1–K5 合约校验，返回违规清单（空数组 = 全过）。
   * K1 单日预算；K2 先修有序；K3 why 必须含 from_kp（或其标题）；
   * K4 同日同知识点不重复；K5 开放债边被覆盖或显式延期。
   */
  static checkPlanK(plan: SchedItem[], budgetPerDay: number, opts: KCheckOpts, ctx: KCheckCtx): string[] {
    const titleOf = ctx.titleOf ?? ((x: string): string => x);
    const viol: string[] = [];
    const byDay = new Map<number, number>();
    plan.forEach((p: SchedItem) => {
      byDay.set(p.day, (byDay.get(p.day) ?? 0) + (p.min || 0));
    });
    byDay.forEach((sum: number, d: number) => {
      if (sum > budgetPerDay) {
        viol.push(`D${d} 合计 ${sum}min 超出日预算 ${budgetPerDay}min（K1）`);
      }
    });
    plan.forEach((p: SchedItem) => {
      const from = p.fromKp;
      const whyHas = !!from && !!p.why &&
        (p.why.indexOf(from) >= 0 || p.why.indexOf(titleOf(from)) >= 0);
      if (!whyHas) {
        viol.push(`D${p.day} 条目「${p.kp}」的 why 未包含 from_kp（K3）`);
      }
    });
    const seen = new Set<string>();
    plan.forEach((p: SchedItem) => {
      const k = `${p.day}|${p.kp}`;
      if (seen.has(k)) {
        viol.push(`D${p.day}「${titleOf(p.kp)}」重复安排（K4）`);
      }
      seen.add(k);
    });
    const edges = opts.edges ?? [];
    const first = new Map<string, number>();
    plan.forEach((p: SchedItem) => {
      const f = first.get(p.kp);
      if (f === undefined || p.day < f) {
        first.set(p.kp, p.day);
      }
    });
    edges.forEach((e: CtxEdge) => {
      if (e.tg) {
        return;
      }
      const fa = first.get(e.from);
      const fb = first.get(e.to);
      if (fa !== undefined && fb !== undefined && fa > fb) {
        viol.push(`先修「${titleOf(e.from)}」的最早任务晚于「${titleOf(e.to)}」（K2）`);
      }
    });
    const debts = opts.debts ?? null;
    if (debts && debts.length > 0) {
      const defd = opts.deferred ?? [];
      debts.forEach((d: K5Debt) => {
        const covered = plan.some((p: SchedItem) =>
          p.fromKp === d.from && (p.kp === d.from || p.kp === d.to));
        if (covered) {
          return;
        }
        const def = defd.some((x: DeferredEdge) => x && x.from === d.from && x.to === d.to);
        if (!def) {
          viol.push(`债边「${d.fromName ?? d.from}→${d.toName ?? d.to}」未覆盖也未显式延期（K5）`);
        }
      });
    }
    return viol;
  }

  /** 把 kp 的全部任务整体平移 delta 天；容量不够时按 allowShrink 决定能否压时长硬塞 */
  static moveNode(items: SchedItem[], bins: Map<number, DayBin>, budget: number,
    kp: string, delta: number, allowShrink: boolean, offsets: number[]): boolean {
    const offs = (offsets && offsets.length > 0) ? offsets : [0, 2, 6];
    const its = items.filter((p: SchedItem) => p.kp === kp);
    if (its.length === 0) {
      return false;
    }
    const newDays: number[] = [];
    for (let i = 0; i < its.length; i++) {
      const p = its[i];
      const nd = p.day + delta;
      const floorDay = 1 + (offs[p.rd ?? 0] ?? 0);
      if (nd < 1 || nd > 14 || nd < floorDay) {
        return false;
      }
      newDays.push(nd);
    }
    // 克隆容量表试排：失败直接返回 false，不污染原 bins
    const clone = new Map<number, DayBin>();
    bins.forEach((b: DayBin, k: number) => {
      clone.set(k, { min: b.min, n: b.n, kps: new Set<string>(b.kps) });
    });
    its.forEach((p: SchedItem) => {
      const b = clone.get(p.day);
      if (b) {
        b.min -= p.min;
        b.n -= 1;
        b.kps.delete(kp);
      }
    });
    const newMins: number[] = [];
    for (let j = 0; j < its.length; j++) {
      const nd2 = newDays[j];
      let b2 = clone.get(nd2);
      if (!b2) {
        b2 = { min: 0, n: 0, kps: new Set<string>() };
        clone.set(nd2, b2);
      }
      if (b2.kps.has(kp) || b2.n >= 4) {
        return false;
      }
      let mm = its[j].min;
      if (b2.min + mm > budget) {
        if (!allowShrink) {
          return false;
        }
        mm = Math.max(8, budget - b2.min);
        if (b2.min + mm > budget) {
          return false;
        }
      }
      b2.min += mm;
      b2.n += 1;
      b2.kps.add(kp);
      newMins.push(mm);
    }
    bins.clear();
    clone.forEach((b: DayBin, k: number) => {
      bins.set(k, b);
    });
    its.forEach((p: SchedItem, i: number) => {
      p.day = newDays[i];
      if (newMins[i] !== p.min) {
        p.min = newMins[i];
      }
    });
    return true;
  }

  /** 先修顺序修复：找「先修首次任务晚于后续」最严重的一条边，平移到满足先后为止 */
  static fixK2(items: SchedItem[], bins: Map<number, DayBin>, budget: number,
    edges: CtxEdge[], offsets: number[]): boolean {
    for (let iter = 0; iter < 40; iter++) {
      const first = new Map<string, number>();
      items.forEach((p: SchedItem) => {
        const f = first.get(p.kp);
        if (f === undefined || p.day < f) {
          first.set(p.kp, p.day);
        }
      });
      let worst: WorstEdge | null = null;
      for (let i = 0; i < edges.length; i++) {
        const e = edges[i];
        if (e.tg) {
          continue;
        }
        if (!first.has(e.from) || !first.has(e.to)) {
          continue;
        }
        const dd = (first.get(e.from) ?? 0) - (first.get(e.to) ?? 0);
        if (dd > 0 && (!worst || dd > worst.dd)) {
          worst = { from: e.from, to: e.to, dd: dd };
        }
      }
      if (!worst) {
        return true;
      }
      if (PlanScheduler.moveNode(items, bins, budget, worst.to, worst.dd, false, offsets)) {
        continue;
      }
      if (PlanScheduler.moveNode(items, bins, budget, worst.from, -worst.dd, false, offsets)) {
        continue;
      }
      if (PlanScheduler.moveNode(items, bins, budget, worst.from, -worst.dd, true, offsets)) {
        continue;
      }
      if (PlanScheduler.moveNode(items, bins, budget, worst.to, worst.dd, true, offsets)) {
        continue;
      }
      return false;
    }
    return true;
  }

  /**
   * 主调度器：债边按先修深度与影响分排序，逐边排 core（先修点）与 challenge（后续点）
   * 两个任务、共 rounds 遍；日容量塞不下就显式延期。
   */
  static schedule(ds: DebtInput[], budget: number, opts: ScheduleOpts, ctx: ScheduleCtx): ScheduleResult {
    const offsets = ctx.spacingOffsets ?? [0, 2, 6];
    const edges = ctx.edges ?? [];
    const nodes = ctx.nodes ?? [];
    const courseOf = ctx.courseOf ?? ((id: string): string => '');
    const prereqsOf = ctx.prereqsOf ?? ((id: string): string[] => []);
    const label = ctx.label ?? ((d: DebtInput, kind: string, r: number): string => `${kind}:${r}`);
    const why = ctx.why ??
      ((d: DebtInput, kind: string, r: number, min: number, rdP: number): string => '');
    const rounds = budget >= 30 ? Math.min(3, offsets.length) : 2;
    const maxDebts = budget >= 30 ? 6 : 4;
    const maxPerDay = 4;
    const bins = new Map<number, DayBin>();
    const entries: EntryRec[] = [];
    const deferred: DeferredEdge[] = [];
    const bin = (day: number): DayBin => {
      let b = bins.get(day);
      if (!b) {
        b = { min: 0, n: 0, kps: new Set<string>() };
        bins.set(day, b);
      }
      return b;
    };
    const canPlace = (kp: string, min: number, day: number): boolean => {
      const b = bin(day);
      if (b.kps.has(kp)) {
        return false;
      }
      if (b.n >= maxPerDay) {
        return false;
      }
      if (b.min + min > budget) {
        return false;
      }
      return true;
    };
    const place = (kp: string, min: number, day: number): void => {
      const b = bin(day);
      b.min += min;
      b.n += 1;
      b.kps.add(kp);
    };
    const findDay = (kp: string, min: number, minDay: number): number => {
      for (let day = Math.max(1, minDay); day <= 14; day++) {
        if (canPlace(kp, min, day)) {
          return day;
        }
      }
      return -1;
    };
    // 先修深度排名：Kahn 最长链，深度深的先修点先排（图异常时按空排名继续，调度仍可产出）
    const rank = new Map<string, number>();
    try {
      const indeg = new Map<string, number>();
      nodes.forEach((n: KNode) => indeg.set(n.id, 0));
      edges.forEach((e: CtxEdge) => {
        if (!e.tg && indeg.has(e.to) && indeg.has(e.from)) {
          indeg.set(e.to, (indeg.get(e.to) ?? 0) + 1);
        }
      });
      const q: string[] = [];
      nodes.forEach((n: KNode) => {
        if ((indeg.get(n.id) ?? 0) === 0) {
          q.push(n.id);
        }
      });
      const dep = new Map<string, number>();
      nodes.forEach((n: KNode) => dep.set(n.id, 0));
      let guard = 0;
      while (q.length > 0 && guard++ < 4000) {
        const x = q.shift() as string;
        edges.forEach((e: CtxEdge) => {
          if (e.tg || e.from !== x) {
            return;
          }
          const dTo = dep.get(e.to) ?? 0;
          const dX = dep.get(x) ?? 0;
          if (dTo < dX + 1) {
            dep.set(e.to, dX + 1);
          }
          // 入度减到 0 就入队；图带环时这里可能重复入队，guard 兜底（与 Web 版一致）
          if (indeg.has(e.to)) {
            indeg.set(e.to, (indeg.get(e.to) ?? 0) - 1);
            if ((indeg.get(e.to) ?? 0) <= 0) {
              q.push(e.to);
            }
          }
        });
      }
      nodes.forEach((n: KNode) => rank.set(n.id, dep.get(n.id) ?? 0));
    } catch (e) {
      // 图异常时按空排名继续
    }
    const list = ds.slice(0).sort((a: DebtInput, b: DebtInput) => {
      const ra = rank.get(a.from) ?? 0;
      const rb = rank.get(b.from) ?? 0;
      if (ra !== rb) {
        return ra - rb;
      }
      if (opts.course) {
        const ca = courseOf(a.from) === opts.course ? 0 : 1;
        const cb = courseOf(b.from) === opts.course ? 0 : 1;
        if (ca !== cb) {
          return ca - cb;
        }
      }
      return (b.imp || 0) - (a.imp || 0);
    });
    const firstDay = new Map<string, number>();
    const MINS: number[][] = budget >= 35 ?
      [[12, 12], [10, 10], [8, 8]] : [[10, 10], [8, 8], [8, 8]];
    list.slice(0, maxDebts).forEach((d: DebtInput, di: number) => {
      let prev = 0;
      let ok = true;
      let tot = 0;
      for (let r = 0; r < rounds && ok; r++) {
        const off = (offsets[r] != null) ? offsets[r] : (r * 2);
        for (let step = 0; step < 2 && ok; step++) {
          const isCore = step === 0;
          const kp = isCore ? d.from : d.to;
          let md = Math.max(1 + off, prev + 1);
          if (!isCore && firstDay.has(d.from)) {
            md = Math.max(md, (firstDay.get(d.from) ?? 0) + 1);
          }
          try {
            const prs = prereqsOf(kp) ?? [];
            prs.forEach((pr: string) => {
              if (firstDay.has(pr) && (firstDay.get(pr) ?? 0) + 1 > md) {
                md = (firstDay.get(pr) ?? 0) + 1;
              }
            });
          } catch (e) {
            // 先修查询失败不阻断本条排程
          }
          const m = (MINS[r] ?? [8, 8])[isCore ? 0 : 1];
          const day = findDay(kp, m, md);
          if (day < 0) {
            ok = false;
            break;
          }
          place(kp, m, day);
          entries.push({ d: d, di: di, r: r, kind: isCore ? 'core' : 'challenge', day: day, min: m, rdP: rounds });
          if (!firstDay.has(kp) || day < (firstDay.get(kp) ?? 0)) {
            firstDay.set(kp, day);
          }
          prev = day;
          tot += 1;
        }
      }
      if (!ok || tot === 0) {
        deferred.push({
          from: d.from, to: d.to,
          reason: (tot > 0 ? '部分轮次延后（日预算已满）' : '本轮未排入（预算已满）')
        });
      }
    });
    list.slice(maxDebts).forEach((d: DebtInput) => {
      deferred.push({ from: d.from, to: d.to, reason: '本轮未排入（优先级靠后，下轮再排）' });
    });
    entries.sort((a: EntryRec, b: EntryRec) => {
      return a.day - b.day || a.di - b.di || (a.kind === 'core' ? 0 : 1);
    });
    let id = 0;
    const items: SchedItem[] = entries.map((e: EntryRec): SchedItem => {
      id += 1;
      return {
        id: id,
        day: e.day,
        kp: (e.kind === 'core' ? e.d.from : e.d.to),
        layer: (e.kind === 'core' ? 'core' : 'challenge'),
        st: 'todo',
        min: e.min,
        fromKp: e.d.from,
        rd: e.r,
        label: label(e.d, e.kind, e.r),
        why: why(e.d, e.kind, e.r, e.min, e.rdP)
      };
    });
    try {
      PlanScheduler.fixK2(items, bins, budget, edges, offsets);
    } catch (e) {
      // 重排失败不阻断计划产出，与 Web 版一致
    }
    items.sort((a: SchedItem, b: SchedItem) => a.day - b.day || a.id - b.id);
    items.forEach((p: SchedItem, i: number) => {
      p.id = i + 1;
    });
    return { items: items, deferred: deferred, rounds: rounds };
  }

  /** 超预算减压：先按比例压缩时长，再顺延，最后丢弃（就地修改 items） */
  static reliefDays(items: SchedItem[], budget: number, repairs: string[]): void {
    const byDay = new Map<number, SchedItem[]>();
    items.forEach((p: SchedItem) => {
      const l = byDay.get(p.day);
      if (l) {
        l.push(p);
      } else {
        byDay.set(p.day, [p]);
      }
    });
    const dayKeys = Array.from(byDay.keys()).sort((a: number, b: number) => a - b);
    dayKeys.forEach((dk: number) => {
      const list = byDay.get(dk) as SchedItem[];
      let sum = list.reduce((a: number, p: SchedItem) => a + p.min, 0);
      if (sum <= budget) {
        return;
      }
      let ch = false;
      list.forEach((p: SchedItem) => {
        const np = Math.max(8, Math.round(p.min * budget / sum));
        if (np !== p.min) {
          p.min = np;
          ch = true;
        }
      });
      if (ch) {
        repairs.push(`D${dk} 超预算：时长按比例压缩`);
      }
      sum = list.reduce((a: number, p: SchedItem) => a + p.min, 0);
      if (sum <= budget) {
        return;
      }
      for (let i = list.length - 1; i >= 0 && sum > budget; i--) {
        const p = list[i];
        let moved = false;
        for (let nd = p.day + 1; nd <= 14; nd++) {
          const tl = byDay.get(nd) ?? [];
          const tsum = tl.reduce((a: number, q: SchedItem) => a + q.min, 0);
          const clash = tl.some((q: SchedItem) => q.kp === p.kp);
          if (!clash && tsum + p.min <= budget) {
            p.day = nd;
            tl.push(p);
            byDay.set(nd, tl);
            sum -= p.min;
            moved = true;
            repairs.push(`顺延 1 条至 D${nd}（预算缓冲）`);
            break;
          }
        }
        if (!moved) {
          p.drop = true;
          sum -= p.min;
          repairs.push('丢弃 1 条超额任务（预算排不下）');
        }
      }
    });
    for (let j = items.length - 1; j >= 0; j--) {
      if (items[j].drop) {
        items.splice(j, 1);
      }
    }
  }
}
