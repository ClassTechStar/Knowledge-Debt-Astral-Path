/**
 * 藏书阁 —— 对应 Web 版 main#p-materials：教材列表、设为当前、导入示例资料。
 * 文件解析（PDF/TXT）在鸿蒙侧走文件选择器 + KgService；这里先接通列表与切换。
 */
import { Book } from '../model/Models';
import { DemoData } from '../model/DemoData';
import { StoreService } from '../service/StoreService';

@Component
export struct MaterialsPage {
  @State books: Book[] = [];
  @State activeId: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.books = await StoreService.loadBooks();
    const meta = await StoreService.loadMeta();
    this.activeId = meta.activeBookId;
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

  private async use(id: string): Promise<void> {
    const meta = await StoreService.loadMeta();
    meta.activeBookId = id;
    await StoreService.saveMeta(meta);
    this.refresh();
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('藏书阁')
          .fontSize(17)
          .fontWeight(FontWeight.Bold);
        Blank();
        Button('导入示例资料')
          .fontSize(12)
          .onClick(() => this.seed());
      }
      .width('100%');

      if (this.books.length === 0) {
        Text('暂无资料。点「导入示例资料」，或选择 PDF / TXT 文件解析。')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding(14);
      }

      ForEach(this.books, (b: Book) => {
        Row() {
          Column({ space: 3 }) {
            Text(b.name)
              .fontSize(14)
              .fontWeight(this.activeId === b.id ? FontWeight.Bold : FontWeight.Normal)
              .fontColor($r('app.color.ink'));
            Text(`${b.nodes?.length ?? 0} 节点 · ${b.edges?.length ?? 0} 边 · ${b.qs?.length ?? 0} 题`)
              .fontSize(11)
              .fontColor($r('app.color.muted'));
          }
          .alignItems(HorizontalAlign.Start);
          Blank();
          if (this.activeId === b.id) {
            Text('当前')
              .fontSize(11)
              .fontColor($r('app.color.brand'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor($r('app.color.brand_soft'));
          } else {
            Button('设为当前')
              .fontSize(11)
              .onClick(() => this.use(b.id));
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.soft'));
      }, (b: Book) => b.id);
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
