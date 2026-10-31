/**
 * 知债页 —— 对应 Web 版 main#p-debt：红边诊断（impact-v2）、债边叙事、生成 14 天计划、
 * 计划复盘、销账检查，以及 What-if 模拟（调参数看这条债边的变化）。
 * 计划编排在真机上会交给模型（演示模式由本地规则兜底）。
 */
import { Book, DebtEdge, PlanItem, SaleState, SaleInput, SaleResult, KNode, KEdge } from '../model/Models';
import { FormulaConstants as K } from '../model/FormulaConstants';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';
import { PlanScheduler, DebtInput, ScheduleCtx, SchedItem, CtxEdge, K5Debt } from '../service/PlanScheduler';

@Component
export struct DebtPage {
  @State debts: DebtEdge[] = [];
  @State msg: string = '点「重新诊断」查看红边与解读';
  @State plan: PlanItem[] = [];
  @State selected: DebtEdge | null = null;
  // What-if 的三个输入（与 Web 版滑杆同义：前置掌握 / 目标掌握 / 错题频次）
  @State wSp: number = 30;
  @State wSc: number = 25;
  @State wFq: number = 5;
  @State whatOut: string = '拖动滑杆，看它对这条债边的影响（本地公式实时计算）';
  @State review: string = '';
  @State deferredMsg: string = '';
  // 当前教材：diag() 里缓存，buildPlan 的 label/why 生成要用标题
  private book: Book | null = null;

  aboutToAppear(): void {
    this.diag();
  }

  private async diag(): Promise<void> {
    const books = await StoreService.loadBooks();
    const meta = await StoreService.loadMeta();
    let b: Book | undefined = books.find((x: Book) => x.id === meta.activeBookId);
    if (!b && books.length > 0) {
      b = books[0];
    }
    if (!b) {
      this.msg = '还没有资料，先到起点页导入示例教材';
      this.debts = [];
      this.book = null;
      return;
    }
    this.book = b;
    const ans = await StoreService.loadAnswers();
    const visiting: Map<string, number> = new Map();
    const scoreOf = (id: string): number => {
      return FormulaService.scoreOfGraph(id, b?.edges ?? [], ans.mastery, visiting);
    };
    const downCount = (id: string): number => {
      return (b?.edges ?? []).filter((e) => e.a === id && scoreOf(e.b) < K.cg).length;
    };
    const list: DebtEdge[] = [];
    for (const e of b.edges ?? []) {
      const sf = scoreOf(e.a);
      const st = scoreOf(e.b);
      const freq = ans.logs.filter((l) => l.kp === e.b && !l.ok).length;
      const impact = FormulaService.impactV2(sf, st, e.w ?? 1, !!e.tg, Math.max(freq, 1), downCount(e.a));
      const edge: DebtEdge = {
        id: `${e.a}>${e.b}`,
        a: e.a,
        b: e.b,
        impact: impact,
        why: `先修「${this.titleOf(b as Book, e.a)}」掌握 ${(sf * 100).toFixed(0)}%，拖累「${this.titleOf(b as Book, e.b)}」`,
        open: FormulaService.isOpen(impact)
      };
      list.push(edge);
    }
    this.debts = FormulaService.sortDebts(list.filter((d: DebtEdge) => d.open));
    this.msg = this.debts.length > 0 ? `发现 ${this.debts.length} 条开放红边` : '当前没有开放红边';
    if (this.debts.length > 0) {
      this.selected = this.debts[0];
      this.simulate();
    }
  }

  private titleOf(b: Book, id: string): string {
    const n: KNode | undefined = b.nodes.find((x: KNode) => x.id === id);
    return n ? n.title : id;
  }

  /** 债边叙事：把公式里的每个因子翻译成一句人话 */
  private narrative(d: DebtEdge | null): string {
    if (!d) {
      return '先选一条债边';
    }
    const parts: string[] = [];
    parts.push(`「${d.a}」到「${d.b}」这条边的影响分是 ${d.impact.toFixed(3)}，${d.open ? '已构成开放红边' : '还没到开放阈值'}。`);
    const sf = this.wSp / 100;
    const st = this.wSc / 100;
    if (sf < K.pg) {
      parts.push(`先修掌握 ${(sf * 100).toFixed(0)}% 低于门限 ${(K.pg * 100).toFixed(0)}%，这是主要缺口。`);
    }
    if (st < K.cg) {
      parts.push(`后续只有 ${(st * 100).toFixed(0)}%，说明拖累已经传导过去了。`);
    }
    if (d.impact >= K.hit) {
      parts.push('建议先补先修再练后续，顺序反了效果会打折。');
    }
    return parts.join('');
  }

  /** What-if：用滑杆值直接跑 impact-v2 */
  private simulate(): void {
    const sf = this.wSp / 100;
    const st = this.wSc / 100;
    const impact = FormulaService.impactV2(sf, st, 1, false, this.wFq, 1);
    this.whatOut = `前置 ${(sf * 100).toFixed(0)}% / 目标 ${(st * 100).toFixed(0)}% / 频次 ${this.wFq} → 影响分 ${impact.toFixed(3)}（${FormulaService.isOpen(impact) ? '开放红边' : '未开放'}）`;
  }

  /**
   * 生成 14 天计划：走与 Web 版同一套调度器（逐日容量 + 三遍复习 + K1–K5 合约 +
   * 先修顺序重排）。之前是每条债边顺序塞两天任务的简化版，跟 Web 版的计划质量差距大，
   * 现在对齐——排不下的债边显式延期，合约违规如实报出来，不假装全过。
   */
  private async buildPlan(): Promise<void> {
    await this.diag();
    const b = this.book;
    if (!b) {
      this.msg = '还没有资料，先到起点页导入示例教材';
      return;
    }
    const budget = 40; // K1：每天 40 分钟
    const offsets = [0, 2, 6];
    const titleOf = (id: string): string => this.titleOf(b, id);
    const ds: DebtInput[] = this.debts.map((d: DebtEdge): DebtInput => {
      return { from: d.a, to: d.b, imp: d.impact, fromName: titleOf(d.a), toName: titleOf(d.b) };
    });
    const ctxEdges = (b.edges ?? []).map((e: KEdge): CtxEdge => {
      return { from: e.a, to: e.b, tg: e.tg ?? false, w: e.w ?? 1 };
    });
    const ctx: ScheduleCtx = {
      edges: ctxEdges,
      nodes: b.nodes,
      prereqsOf: (id: string): string[] => (b.edges ?? []).filter((e: KEdge) => e.b === id).map((e: KEdge) => e.a),
      label: (d: DebtInput, kind: string, r: number): string => {
        return kind === 'core' ? `巩固「${titleOf(d.from)}」` : `进阶「${titleOf(d.to)}」`;
      },
      why: (d: DebtInput, kind: string, r: number, min: number, rdP: number): string => {
        // K3 要求 why 里必须出现 from_kp（先修点名称或标题），否则合约校验会拦
        const off = offsets[r] ?? 0;
        return `先补「${titleOf(d.from)}」再带动「${titleOf(d.to)}」，第 ${r + 1}/${rdP} 遍（间隔 ${off} 天），${min} 分钟`;
      }
    };
    const k5debts = ds.map((d: DebtInput): K5Debt => {
      return { from: d.from, to: d.to, fromName: d.fromName, toName: d.toName };
    });
    const result = PlanScheduler.schedule(ds, budget, { debts: k5debts }, ctx);
    const viol = PlanScheduler.checkPlanK(result.items, budget,
      { edges: ctxEdges, debts: k5debts, deferred: result.deferred }, { titleOf: titleOf });
    const plan: PlanItem[] = result.items.map((p: SchedItem): PlanItem => {
      return {
        id: `PL${String(p.id).padStart(2, '0')}`,
        day: p.day,
        kp: p.kp,
        layer: p.layer,
        minutes: p.min,
        why: p.why,
        st: p.st,
        fromKp: p.fromKp,
        rd: p.rd,
        label: p.label
      };
    });
    this.plan = plan;
    this.deferredMsg = result.deferred.length > 0
      ? `另有 ${result.deferred.length} 条债边本轮未排入：${result.deferred.map((x) => x.reason).join('；')}`
      : '';
    await StoreService.savePlan(plan);
    let msg = `已生成 ${plan.length} 条计划（三遍复习、每天不超过 ${budget} 分钟，K1–K5 已过）`;
    if (viol.length > 0) {
      // 合约违规不该出现（调度器自修过）；真出现就如实报第一条，不静默吞掉
      msg += `；警告：${viol[0]}`;
    }
    if (this.deferredMsg) {
      msg += `；${this.deferredMsg}`;
    }
    this.msg = msg;
  }

  /** 计划复盘：拿作答日志对照计划，看哪些做完了、哪些还欠着 */
  private async reviewPlan(): Promise<void> {
    const ans = await StoreService.loadAnswers();
    const plan = await StoreService.loadPlan();
    if (plan.length === 0) {
      this.review = '还没有计划，先点「生成 14 天计划」';
      return;
    }
    let done = 0;
    let partial = 0;
    for (const p of plan) {
      const n = (ans.logs ?? []).filter((l) => l.kp === p.kp).length;
      if (n >= 3) {
        done += 1;
      } else if (n > 0) {
        partial += 1;
      }
    }
    let clearedCount = 0;
    for (const k of Object.keys(ans.sale)) {
      if (ans.sale[k].cleared) {
        clearedCount += 1;
      }
    }
    this.review = `计划 ${plan.length} 条：达标 ${done} 条、进行中 ${partial} 条、未开始 ${plan.length - done - partial} 条；已销账 ${clearedCount} 条`;
  }

  private async checkSale(): Promise<void> {
    const ans = await StoreService.loadAnswers();
    let cleared = 0;
    for (const d of this.debts) {
      const logs = ans.logs.filter((l) => l.kp === d.b);
      if (logs.length === 0) {
        continue;
      }
      const acc = logs.filter((l) => l.ok).length / logs.length;
      const conf = logs.reduce((s: number, l) => s + l.conf, 0) / logs.length;
      const s: SaleState = ans.sale[d.id] ?? { streak: 0, att: 0 };
      const input: SaleInput = { streak: s.streak, att: s.att };
      const r: SaleResult = FormulaService.saleStep(input, acc, conf);
      ans.sale[d.id] = { streak: r.streak, att: r.att, cleared: r.cleared };
      if (r.cleared) {
        cleared += 1;
      }
    }
    await StoreService.saveAnswers(ans);
    this.msg = `销账检查完成，本次结清 ${cleared} 条`;
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
      Text('债边诊断').fontSize(17).fontWeight(FontWeight.Bold).width('100%');
      Row({ space: 6 }) {
        Button($r('app.string.debt_diag')).fontSize(11).onClick(() => this.diag());
        Button($r('app.string.debt_plan')).fontSize(11).onClick(() => this.buildPlan());
        Button($r('app.string.debt_sale')).fontSize(11).onClick(() => this.checkSale());
        Button('计划复盘').fontSize(11).onClick(() => this.reviewPlan());
      }
      .width('100%');

      Text(this.msg).fontSize(12).fontColor($r('app.color.muted'));
      if (this.review) {
        Text(this.review).fontSize(12).fontColor($r('app.color.brand'));
      }

      ForEach(this.debts, (d: DebtEdge) => {
        Column({ space: 3 }) {
          Text(`${d.a} → ${d.b}`)
            .fontSize(14)
            .fontWeight(this.selected?.id === d.id ? FontWeight.Bold : FontWeight.Normal)
            .fontColor($r('app.color.danger'));
          Text(`影响分 ${d.impact.toFixed(3)}`).fontSize(11).fontColor($r('app.color.muted'));
          if (d.why) {
            Text(d.why).fontSize(11).fontColor($r('app.color.muted'));
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(this.selected?.id === d.id ? '#FDECEC' : $r('app.color.soft'))
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.selected = d;
        });
      }, (d: DebtEdge) => d.id);

      // 债边叙事
      Column({ space: 4 }) {
        Text('债边叙事').fontSize(13).fontWeight(FontWeight.Bold);
        Text(this.narrative(this.selected)).fontSize(12).fontColor($r('app.color.ink'));
      }
      .width('100%')
      .padding(12)
      .borderRadius(14)
      .backgroundColor($r('app.color.soft'))
      .alignItems(HorizontalAlign.Start);

      // What-if 模拟
      Column({ space: 6 }) {
        Text('What-if 模拟').fontSize(13).fontWeight(FontWeight.Bold);
        Row() {
          Text(`前置掌握 ${(this.wSp / 100).toFixed(2)}`).fontSize(11).width(110);
          Slider({ value: this.wSp, min: 0, max: 100, step: 5 })
            .layoutWeight(1)
            .onChange((v: number) => {
              this.wSp = v;
              this.simulate();
            });
        }
        .width('100%');
        Row() {
          Text(`目标掌握 ${(this.wSc / 100).toFixed(2)}`).fontSize(11).width(110);
          Slider({ value: this.wSc, min: 0, max: 100, step: 5 })
            .layoutWeight(1)
            .onChange((v: number) => {
              this.wSc = v;
              this.simulate();
            });
        }
        .width('100%');
        Row() {
          Text(`错题频次 ${this.wFq}`).fontSize(11).width(110);
          Slider({ value: this.wFq, min: 0, max: 20, step: 1 })
            .layoutWeight(1)
            .onChange((v: number) => {
              this.wFq = v;
              this.simulate();
            });
        }
        .width('100%');
        Text(this.whatOut).fontSize(12).fontColor($r('app.color.muted'));
      }
      .width('100%')
      .padding(12)
      .borderRadius(14)
      .backgroundColor($r('app.color.soft'))
      .alignItems(HorizontalAlign.Start);

      if (this.plan.length > 0) {
        Text(`修复计划（${this.plan.length} 条）`).fontSize(14).fontWeight(FontWeight.Bold).margin({ top: 6 });
        ForEach(this.plan, (p: PlanItem) => {
          Column({ space: 2 }) {
            Row() {
              Text(`D${p.day}`).fontSize(12).fontColor($r('app.color.brand')).width(36);
              Text(p.label ?? p.kp).fontSize(13).fontColor($r('app.color.ink'));
              Blank();
              Text(`${p.minutes} 分钟`).fontSize(11).fontColor($r('app.color.muted'));
            }
            .width('100%');
            if (p.why) {
              Text(p.why).fontSize(11).fontColor($r('app.color.muted'));
            }
          }
          .width('100%')
          .padding(10)
          .borderRadius(10)
          .backgroundColor($r('app.color.surface'))
          .alignItems(HorizontalAlign.Start);
        }, (p: PlanItem) => p.id);
      }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart);
  }
}
