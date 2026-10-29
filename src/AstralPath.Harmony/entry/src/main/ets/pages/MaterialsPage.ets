/**
 * 藏书阁 —— 对应 Web 版 main#p-materials：教材列表、设为当前、导入示例资料。
 * 文件解析（PDF/TXT）在鸿蒙侧走文件选择器 + KgService；这里先接通列表与切换。
 */
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Book } from '../model/Models';
import { DemoData } from '../model/DemoData';
import { StoreService } from '../service/StoreService';
import { KgService } from '../service/KgService';

@Component
export struct MaterialsPage {
  @State books: Book[] = [];
  @State activeId: string = '';
  @State tip: string = '';

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

  /** 选文件解析：目前支持 TXT / Markdown（扫描版 PDF 的 OCR 链鸿蒙侧还没接） */
  private async pickAndParse(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const uris: string[] = await docPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.txt', '.md', '.markdown']
      });
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const name = uri.split('/').pop() ?? '未命名资料';
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const size = fileIo.statSync(file.fd).size;
      const buf = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const text = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
      if (!text || text.trim().length < 20) {
        this.tip = '这份文件没读出文本内容，可能不是文本类资料';
        return;
      }
      const book: Book = KgService.build(name, text);
      if (book.nodes.length === 0) {
        this.tip = '没抽出知识点，换一份资料试试';
        return;
      }
      const books = await StoreService.loadBooks();
      books.push(book);
      await StoreService.saveBooks(books);
      const meta = await StoreService.loadMeta();
      meta.activeBookId = book.id;
      await StoreService.saveMeta(meta);
      this.tip = `《${name}》解析完成：${book.nodes.length} 个知识点、${book.edges.length} 条关系`;
      this.refresh();
    } catch (e) {
      this.tip = `解析失败：${(e as Error).message}`;
    }
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
        Button('选择文本资料')
          .fontSize(12)
          .onClick(() => this.pickAndParse());
      }
      .width('100%');

      if (this.tip) {
        Text(this.tip)
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding({ left: 4, bottom: 4 });
      }

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
