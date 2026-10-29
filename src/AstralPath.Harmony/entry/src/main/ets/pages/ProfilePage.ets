/**
 * 画像页 —— 对应 Web 版 main#p-profile：掌握度分布、练习量、个性化开关。
 * 红线继承：用户可随时关闭个性化（optOut），关闭后只按教材章节顺序安排，不依据知识债推断。
 */
import { Book, Mastery } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';

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
    Column({ space: 10 }) {
      Text('画像').fontSize(17).fontWeight(FontWeight.Bold);
      Row({ space: 12 }) {
        this.statCard('已掌握', `${this.solid}`);
        this.statCard('薄弱', `${this.weak}`);
        this.statCard('累计作答', `${this.attempts}`);
      }
      Text(`共 ${this.total} 个知识点`)
        .fontSize(12)
        .fontColor($r('app.color.muted'));

      Row() {
        Text('关闭个性化（按章节顺序安排，不依据知识债推断）')
          .fontSize(13)
          .layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.optOut })
          .onChange(() => this.toggleOptOut());
      }
      .width('100%')
      .padding(12)
      .borderRadius(14)
      .backgroundColor($r('app.color.soft'));
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  statCard(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'));
      Text(label).fontSize(11).fontColor($r('app.color.muted'));
    }
    .padding(14)
    .borderRadius(14)
    .backgroundColor($r('app.color.soft'))
    .alignItems(HorizontalAlign.Center);
  }
}
