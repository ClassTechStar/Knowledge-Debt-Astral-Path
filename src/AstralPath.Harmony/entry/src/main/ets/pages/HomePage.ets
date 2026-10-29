/**
 * 起点页 —— 对应 Web 版 main#p-home：
 * 「导入示例教材」按钮、当前书籍摘要（节点/边/题数）、进入藏书阁与今日页的入口。
 */
import { Book } from '../model/Models';
import { DemoData } from '../model/DemoData';
import { StoreService } from '../service/StoreService';

@Component
export struct HomePage {
  @State bookName: string = '暂无资料';
  @State nodes: number = 0;
  @State edges: number = 0;
  @State questions: number = 0;
  @State hasBook: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const books = await StoreService.loadBooks();
    const meta = await StoreService.loadMeta();
    let id = meta.activeBookId;
    let b: Book | undefined = books.find((x: Book) => x.id === id);
    if (!b && books.length > 0) {
      b = books[0];
    }
    if (b) {
      this.hasBook = true;
      this.bookName = b.name;
      this.nodes = b.nodes?.length ?? 0;
      this.edges = b.edges?.length ?? 0;
      this.questions = b.qs?.length ?? 0;
    } else {
      this.hasBook = false;
      this.bookName = '暂无资料';
      this.nodes = 0;
      this.edges = 0;
      this.questions = 0;
    }
  }

  private async seed(): Promise<void> {
    const books = await StoreService.loadBooks();
    if (!books.some((x: Book) => x.id === 'demo-python')) {
      books.push(DemoData.build());
      await StoreService.saveBooks(books);
    }
    const meta = await StoreService.loadMeta();
    meta.activeBookId = 'demo-python';
    await StoreService.saveMeta(meta);
    this.refresh();
  }

  build() {
    Column({ space: 12 }) {
      Text('把讲义变成识网，再把欠债算清楚')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.strong'));
      Text('ASTRALPATH WORKSPACE · 全部计算在设备本机完成')
        .fontSize(11)
        .fontColor($r('app.color.muted'));

      Row({ space: 10 }) {
        Button($r('app.string.home_seed'))
          .onClick(() => this.seed());
        Button($r('app.string.home_open_materials'))
          .onClick(() => {
            AppStorage.setOrCreate('currentPage', 'materials');
          });
      }

      Column() {
        Text(this.bookName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.hasBook ? $r('app.color.ink') : $r('app.color.muted'));
        Text(`${this.nodes} 节点 · ${this.edges} 边 · ${this.questions} 题`)
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .margin({ top: 4 });
      }
      .width('100%')
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.soft'));
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
