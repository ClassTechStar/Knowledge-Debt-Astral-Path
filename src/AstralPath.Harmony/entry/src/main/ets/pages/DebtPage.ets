/**
 * 知债页 —— 对应 Web 版 main#p-debt：红边诊断（impact-v2）、生成 14 天计划（K1–K5 约束）、销账检查。
 * 计划编排在真机上会交给模型（演示模式由本地规则兜底），这里先给出与 Web 版一致的本地实现。
 */
import { Book, DebtEdge, Mastery, PlanItem, SaleState, SaleInput, SaleResult, KNode } from '../model/Models';
import { FormulaConstants as K } from '../model/FormulaConstants';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';

@Component
export struct DebtPage {
  @State debts: DebtEdge[] = [];
  @State msg: string = '点「重新诊断」查看红边与解读';
  @State plan: PlanItem[] = [];

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
      return;
    }
    const ans = await StoreService.loadAnswers();
    const scoreOf = (id: string): number => {
      const m: Mastery = ans.mastery[id] ?? { n: 0, s: 0, c: 3, age: 0, st: 0 };
      return FormulaService.scoreOfMastery(m, []);
    };
    // 某知识点被下游拖累的次数：统计它的后续节点里有多少个处于低分
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
  }

  private titleOf(b: Book, id: string): string {
    const n: KNode | undefined = b.nodes.find((x: KNode) => x.id === id);
    return n ? n.title : id;
  }

  /** 本地规则编排：先修有序、单日时长预算、间隔 >= 1 天、开放债边全覆盖（K1–K5 的简化版） */
  private async buildPlan(): Promise<void> {
    await this.diag();
    const items: PlanItem[] = [];
    let day = 1;
    const budget = 40; // K1：每天 40 分钟
    for (const d of this.debts) {
      // K2：先排先修（a），再排后续（b）
      const seq: string[] = [d.a, d.b];
      for (const kp of seq) {
        if (items.some((p: PlanItem) => p.kp === kp)) {
          continue;
        }
        items.push({
          id: `PL${String(items.length + 1).padStart(2, '0')}`,
          day: day,
          kp: kp,
          minutes: 20,
          why: `补先修债：${d.id}`
        });
        // K4：同一知识点间隔 >= 1 天
        day = Math.min(14, day + 1);
      }
      if (items.reduce((s: number, p: PlanItem) => s + p.minutes, 0) >= budget * 14) {
        break;
      }
    }
    this.plan = items;
    await StoreService.savePlan(items);
    this.msg = `已生成 ${items.length} 条计划（每天不超过 ${budget} 分钟）`;
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
      // ArkTS 不支持结构化类型，入参要按接口显式构造
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
    Column({ space: 10 }) {
      Row() {
        Text('知债：星穹学途')
          .fontSize(17)
          .fontWeight(FontWeight.Bold);
        Blank();
        Button($r('app.string.debt_diag')).fontSize(11).onClick(() => this.diag());
        Button($r('app.string.debt_plan')).fontSize(11).onClick(() => this.buildPlan());
        Button($r('app.string.debt_sale')).fontSize(11).onClick(() => this.checkSale());
      }
      .width('100%');

      Text(this.msg).fontSize(12).fontColor($r('app.color.muted'));

      ForEach(this.debts, (d: DebtEdge) => {
        Column({ space: 3 }) {
          Text(`${d.a} → ${d.b}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.danger'));
          Text(`影响分 ${d.impact.toFixed(3)}`)
            .fontSize(11)
            .fontColor($r('app.color.muted'));
          if (d.why) {
            Text(d.why).fontSize(11).fontColor($r('app.color.muted'));
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor($r('app.color.soft'))
        .alignItems(HorizontalAlign.Start);
      }, (d: DebtEdge) => d.id);

      if (this.plan.length > 0) {
        Text(`修复计划（${this.plan.length} 条）`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 6 });
        ForEach(this.plan, (p: PlanItem) => {
          Row() {
            Text(`D${p.day}`).fontSize(12).fontColor($r('app.color.brand')).width(36);
            Text(p.kp).fontSize(13).fontColor($r('app.color.ink'));
            Blank();
            Text(`${p.minutes} 分钟`).fontSize(11).fontColor($r('app.color.muted'));
          }
          .width('100%')
          .padding(10)
          .borderRadius(10)
          .backgroundColor($r('app.color.surface'));
        }, (p: PlanItem) => p.id);
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
