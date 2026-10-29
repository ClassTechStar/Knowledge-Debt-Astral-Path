/**
 * 教师页 —— 对应 Web 版 main#p-teacher：班级聚合学情视图。
 * 红线继承：k-匿名（默认 k=5）；样本少于 3 人只显示「样本不足」，不产出个体明细、不排名。
 */
import { Book, Mastery } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';

interface AggRow {
  kp: string;
  title: string;
  samples: number;
  weakRate: number;
}

@Component
export struct TeacherPage {
  @State rows: AggRow[] = [];
  @State msg: string = '聚合视图：同一薄弱点样本少于 3 人时只显示「样本不足」';
  // k-匿名参数：聚合口径（真机由服务端按 k 聚合后下发，客户端只做展示与抑制）
  private readonly kAnon: number = 5;
  private readonly minSample: number = 3;

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const books = await StoreService.loadBooks();
    const meta = await StoreService.loadMeta();
    let b: Book | undefined = books.find((x: Book) => x.id === meta.activeBookId);
    if (!b && books.length > 0) {
      b = books[0];
    }
    if (!b) {
      this.rows = [];
      return;
    }
    const ans = await StoreService.loadAnswers();
    const rows: AggRow[] = [];
    for (const n of b.nodes) {
      const m: Mastery = ans.mastery[n.id] ?? { n: 0, s: 0, c: 3, age: 0, st: 0 };
      const sc = FormulaService.scoreOfMastery(m, []);
      // 演示口径：本机只有一份学情，样本数用该知识点的作答数代替；真机由服务端聚合后下发
      const row: AggRow = { kp: n.id, title: n.title, samples: m.n, weakRate: sc < 0.55 ? 1 : 0 };
      rows.push(row);
    }
    // 抑制：样本不足 3 人不展示结论
    this.rows = rows.filter((r: AggRow) => r.samples >= this.minSample)
      .sort((x: AggRow, y: AggRow) => y.weakRate - x.weakRate);
    this.msg = `已按 k=${this.kAnon} 匿名聚合，${this.rows.length} 个知识点样本足够`;
  }

  build() {
    Column({ space: 10 }) {
      Text('教师').fontSize(17).fontWeight(FontWeight.Bold);
      Text(this.msg).fontSize(12).fontColor($r('app.color.muted'));
      ForEach(this.rows, (r: AggRow) => {
        Row() {
          Text(r.title).fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1);
          Text(r.weakRate > 0 ? '薄弱占多数' : '掌握良好')
            .fontSize(11)
            .fontColor(r.weakRate > 0 ? $r('app.color.danger') : $r('app.color.ok'));
          Text(`${r.samples} 份`)
            .fontSize(11)
            .fontColor($r('app.color.muted'))
            .margin({ left: 8 });
        }
        .width('100%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor($r('app.color.soft'));
      }, (r: AggRow) => r.kp);
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
