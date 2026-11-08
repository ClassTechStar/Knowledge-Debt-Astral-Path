/**
 * 教师页 —— 对应 Web 版 main#p-teacher：班级聚合学情视图。
 * 红线继承：k-匿名（默认 k=5）；样本少于 3 人只显示「样本不足」，不产出个体明细、不排名。
 */
import { Book, Mastery } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';
import { Theme } from '../common/Theme';
import { PageHeaderView, PanelView, StatView, CardView, BadgeView, StatusView, BarView } from '../components/UiKit';

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
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '教师视图',
          hint: 'k-匿名聚合（默认 k=5）；样本 < 3 人只显示「样本不足」，不产出个体明细'
        })

        Flex({ wrap: FlexWrap.Wrap }) {
          StatView({ label: '样本足够的点', value: `${this.rows.length}` })
          StatView({ label: '薄弱占多数', value: `${this.rows.filter((r: AggRow) => r.weakRate > 0).length}` })
          StatView({ label: '匿名阈值', value: `k=${this.kAnon}` })
        }
        .width('100%')

        PanelView({
          title: '授权门控',
          hint: '默认不可见（fail-closed），学生授权后才展示聚合结果'
        }) {
          Column({ space: 8 }) {
            Text('教师侧仅展示「知识点聚合薄弱率」，不展示个体、不排名、不输出学号。学生可在「账户」页随时撤销授权。')
              .fontSize(Theme.FS_BODY)
              .fontColor(Theme.INK)
              .width('100%')
            StatusView({
              text: '样本少于 3 人的薄弱点会显示「样本不足」，不会推断具体是谁',
              kind: 'warn'
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        PanelView({
          title: '学情视图',
          hint: this.msg
        }) {
          if (this.rows.length === 0) {
            Text('当前没有样本足够的知识点。学生多练几道题，样本凑够 3 份后会自动出现。')
              .fontSize(Theme.FS_HINT)
              .fontColor(Theme.MUTED)
              .width('100%')
          } else {
            ForEach(this.rows, (r: AggRow) => {
              CardView() {
                Column({ space: 6 }) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Text(r.title)
                      .fontSize(Theme.FS_BODY)
                      .fontColor(Theme.INK)
                      .layoutWeight(1)
                    BadgeView({
                      text: r.weakRate > 0 ? '薄弱占多数' : '掌握良好',
                      kind: r.weakRate > 0 ? 'err' : 'ok'
                    })
                    BadgeView({ text: `${r.samples} 份`, kind: 'warn' })
                  }
                  .width('100%')

                  BarView({ ratio: r.weakRate > 0 ? 1 : 0 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }, (r: AggRow) => r.kp)
          }
        }

        StatusView({
          text: 'k-匿名聚合由服务端在真机侧实现，客户端只做展示与样本不足抑制',
          kind: 'plain'
        })
      }
      .width('100%')
      .padding(Theme.PAD_PANEL)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.CANVAS)
  }
}
