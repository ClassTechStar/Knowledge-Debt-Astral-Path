/**
 * 画像页 —— 对应 Web 版 main#p-profile：掌握度分布、练习量、个性化开关。
 * 红线继承：用户可随时关闭个性化（optOut），关闭后只按教材章节顺序安排，不依据知识债推断。
 */
import { Book, Mastery } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';
import { Theme } from '../common/Theme';
import { PageHeaderView, PanelView, StatView, BarView, BadgeView, BtnView, StatusView, CardView } from '../components/UiKit';

@Component
export struct ProfilePage {
  @State weak: number = 0;
  @State solid: number = 0;
  @State total: number = 0;
  @State attempts: number = 0;
  @State optOut: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const books = await StoreService.loadBooks();
    const meta = await StoreService.loadMeta();
    this.optOut = meta.optOut;
    let b: Book | undefined = books.find((x: Book) => x.id === meta.activeBookId);
    if (!b && books.length > 0) {
      b = books[0];
    }
    const ans = await StoreService.loadAnswers();
    let w = 0;
    let s = 0;
    for (const n of b?.nodes ?? []) {
      const m: Mastery = ans.mastery[n.id] ?? { n: 0, s: 0, c: 3, age: 0, st: 0 };
      const sc = FormulaService.scoreOfMastery(m, []);
      if (sc < 0.55) {
        w += 1;
      } else {
        s += 1;
      }
    }
    this.weak = w;
    this.solid = s;
    this.total = b?.nodes?.length ?? 0;
    this.attempts = ans.logs.length;
  }

  private async toggleOptOut(): Promise<void> {
    const meta = await StoreService.loadMeta();
    meta.optOut = !meta.optOut;
    await StoreService.saveMeta(meta);
    this.optOut = meta.optOut;
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '画像',
          hint: '掌握度分布、练习量、错题本与学习风格；可随时关闭个性化'
        })

        Flex({ wrap: FlexWrap.Wrap }) {
          StatView({ label: '已掌握', value: `${this.solid}` })
          StatView({ label: '薄弱', value: `${this.weak}` })
          StatView({ label: '累计作答', value: `${this.attempts}` })
        }
        .width('100%')

        PanelView({
          title: '掌握度分布',
          hint: `共 ${this.total} 个知识点`
        }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('已掌握')
                .fontSize(Theme.FS_HINT)
                .fontColor(Theme.MUTED)
                .width(72)
              BarView({ ratio: this.total > 0 ? this.solid / this.total : 0 })
                .layoutWeight(1)
              Text(`${this.total > 0 ? ((this.solid / this.total) * 100).toFixed(0) : 0}%`)
                .fontSize(Theme.FS_HINT)
                .fontColor(Theme.INK)
                .width(48)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Row({ space: 8 }) {
              Text('薄弱')
                .fontSize(Theme.FS_HINT)
                .fontColor(Theme.MUTED)
                .width(72)
              BarView({ ratio: this.total > 0 ? this.weak / this.total : 0 })
                .layoutWeight(1)
              Text(`${this.total > 0 ? ((this.weak / this.total) * 100).toFixed(0) : 0}%`)
                .fontSize(Theme.FS_HINT)
                .fontColor(Theme.INK)
                .width(48)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              BadgeView({ text: `薄弱 ${this.weak}`, kind: 'err' })
              BadgeView({ text: `已掌握 ${this.solid}`, kind: 'ok' })
              BadgeView({ text: `共 ${this.total}`, kind: 'warn' })
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        PanelView({
          title: '错题本',
          hint: '累计作答与薄弱点，优先推给今日练习'
        }) {
          if (this.attempts === 0) {
            Text('还没有作答记录。到「今日」页点开始练习，会自动记入错题本。')
              .fontSize(Theme.FS_HINT)
              .fontColor(Theme.MUTED)
              .width('100%')
          } else {
            Column({ space: 8 }) {
              Flex({ wrap: FlexWrap.Wrap }) {
                BadgeView({ text: `累计 ${this.attempts} 次`, kind: 'warn' })
                if (this.weak > 0) {
                  BadgeView({ text: `${this.weak} 个薄弱点待巩固`, kind: 'err' })
                } else {
                  BadgeView({ text: '当前没有薄弱点', kind: 'ok' })
                }
              }
              .width('100%')
              BtnView({
                label: '回到今日任务',
                kind: 'primary',
                click: () => {
                  AppStorage.setOrCreate('currentPage', 'today');
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }

        PanelView({
          title: '学习风格',
          hint: '按作答信心分布自动归类，不影响算法排序'
        }) {
          Text(this.attempts < 5
            ? '样本还不够，再做几道题就能给出学习风格判断。'
            : (this.solid > this.weak ? '偏「稳扎稳打」：先把基础补牢，再推后续。' : '偏「集中突击」：可以加练习频次，缩短间隔。'))
            .fontSize(Theme.FS_BODY)
            .fontColor(Theme.INK)
            .width('100%')
        }

        PanelView({
          title: '个性化',
          hint: '关掉后只按教材章节顺序安排，不依据知识债推断'
        }) {
          Row({ space: 8 }) {
            Text('关闭个性化')
              .fontSize(Theme.FS_BODY)
              .fontColor(Theme.INK)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.optOut })
              .onChange(() => this.toggleOptOut());
          }
          .width('100%')

          if (this.optOut) {
            StatusView({ text: '已关闭个性化：今日任务、修复计划都按章节顺序排。', kind: 'warn' })
          } else {
            StatusView({ text: '已开启个性化：会优先推薄弱与低掌握度的知识点。', kind: 'ok' })
          }
        }
      }
      .width('100%')
      .padding(Theme.PAD_PANEL)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.CANVAS)
  }
}
