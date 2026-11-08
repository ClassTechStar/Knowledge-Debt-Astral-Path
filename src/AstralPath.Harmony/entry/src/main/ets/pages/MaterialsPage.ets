/**
 * 藏书阁 —— 对应 Web 版 main#p-materials：教材列表、设为当前、导入示例资料。
 * 文件解析（PDF/TXT）在鸿蒙侧走文件选择器 + KgService；这里先接通列表与切换。
 */
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Book } from '../model/Models';
import { DemoData } from '../model/DemoData';
import { StoreService } from '../service/StoreService';
import { KgService } from '../service/KgService';
import { DocService, DocResult } from '../service/DocService';
import { OcrService } from '../service/OcrService';
import { SanitizeService } from '../service/SanitizeService';
import { BatchTest, BatchItem } from '../service/BatchTest';
import { Theme } from '../common/Theme';
import { PageHeaderView, PanelView, CardView, BtnView, BadgeView, StatusView } from '../components/UiKit';

@Component
export struct MaterialsPage {
  @State books: Book[] = [];
  @State activeId: string = '';
  @State tip: string = '';
  @State batch: string = '';
  @State busy: boolean = false;

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
    // 写入演示学情，否则 impact 刚好卡在阈值下，页面会显示「零红边」
    const ans = await StoreService.loadAnswers();
    const seed = DemoData.seedMastery();
    for (const k of Object.keys(seed)) {
      if (!ans.mastery[k]) {
        ans.mastery[k] = seed[k];
      }
    }
    ans.logs = ans.logs.concat(DemoData.seedLogs());
    await StoreService.saveAnswers(ans);
    this.refresh();
  }

  /** 选文件解析：目前支持 TXT / Markdown（扫描版 PDF 的 OCR 链鸿蒙侧还没接） */
  private async pickAndParse(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const uris: string[] = await docPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.txt', '.md', '.markdown', '.pdf', '.docx', '.pptx', '.epub', '.html']
      });
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const name = uri.split('/').pop() ?? '未命名资料';
      const ctx = getContext(this) as common.UIAbilityContext;
      const doc: DocResult = await DocService.parse(uri, name, ctx.cacheDir);
      let text = SanitizeService.mask(doc.text);
      if (doc.note) {
        this.tip = doc.note;
      }
      // 文本层太少 → 判定扫描版，走 OCR（本机没装 Core Vision 时这里会明确提示）
      if (OcrService.needOcr(doc.chars, doc.scanned)) {
        const ocr = await OcrService.recognize(uri);
        if (ocr.ok) {
          text = SanitizeService.mask(ocr.text);
          this.tip = `已用 OCR 识别（${ocr.engine}）`;
        } else {
          this.tip = `没读到文本层：${ocr.note}`;
        }
      }
      if (!text || text.trim().length < 20) {
        this.tip = this.tip || '这份文件没读出文本内容';
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

  /** 批量解析测试：跑 /data/local/tmp/pdftest/ 下全部资料，逐条打到 hilog */
  private async runBatch(): Promise<void> {
    this.busy = true;
    this.batch = '测试中…';
    const ctx = getContext(this) as common.UIAbilityContext;
    const items: BatchItem[] = await BatchTest.runHttp(ctx);
    let okNode = 0;
    let needOcr = 0;
    let ocrFail = 0;
    for (const it of items) {
      if (it.nodes > 0) {
        okNode += 1;
      }
      if (it.ocr === '不可用(none)') {
        ocrFail += 1;
      }
      if (it.scanned || it.ocr.startsWith('不可用')) {
        needOcr += 1;
      }
    }
    this.batch = `共 ${items.length} 份：建出图谱 ${okNode} 份、需要 OCR ${needOcr} 份（其中 OCR 不可用 ${ocrFail} 份）。明细见 hilog [BATCH]`;
    this.busy = false;
  }

  private async use(id: string): Promise<void> {
    const meta = await StoreService.loadMeta();
    meta.activeBookId = id;
    await StoreService.saveMeta(meta);
    this.refresh();
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '藏书阁',
          hint: '解析 PDF / TXT / Markdown / DOCX，抽出知识点建识网'
        })

        PanelView({
          title: '导入与测试',
          hint: '先导入一份示例教材，或选择本地文件解析'
        }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            BtnView({
              label: '导入示例资料',
              kind: 'primary',
              click: () => this.seed()
            })
            BtnView({
              label: '选择文本资料',
              kind: 'plain',
              click: () => this.pickAndParse()
            })
            BtnView({
              label: this.busy ? '测试中…' : '批量测试',
              kind: 'quiet',
              click: () => this.runBatch()
            })
          }
          .width('100%')

          if (this.batch.length > 0) {
            StatusView({ text: this.batch, kind: 'ok' })
          }
          if (this.tip.length > 0) {
            StatusView({ text: this.tip, kind: 'plain' })
          }
        }

        PanelView({
          title: `教材列表（${this.books.length}）`,
          hint: '选中的教材是「当前教材」，识网与今日任务都从这里出'
        }) {
          if (this.books.length === 0) {
            Text('暂无资料。点「导入示例资料」，或选择 PDF / TXT 文件解析。')
              .fontSize(Theme.FS_HINT)
              .fontColor(Theme.MUTED)
              .width('100%')
          } else {
            ForEach(this.books, (b: Book) => {
              CardView({ selected: this.activeId === b.id }) {
                Column({ space: 6 }) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Text(b.name)
                      .fontSize(Theme.FS_BODY)
                      .fontWeight(this.activeId === b.id ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(Theme.INK)
                    if (this.activeId === b.id) {
                      BadgeView({ text: '当前', kind: 'ok' })
                    }
                  }
                  .width('100%')

                  Text(`${b.nodes?.length ?? 0} 节点 · ${b.edges?.length ?? 0} 边 · ${b.qs?.length ?? 0} 题`)
                    .fontSize(Theme.FS_HINT)
                    .fontColor(Theme.MUTED)
                    .width('100%')

                  Flex({ wrap: FlexWrap.Wrap }) {
                    if (this.activeId !== b.id) {
                      BtnView({
                        label: '设为当前',
                        kind: 'primary',
                        click: () => this.use(b.id)
                      })
                    }
                    BtnView({
                      label: '查看详情',
                      kind: 'quiet',
                      click: () => {
                        this.tip = `《${b.name}》共 ${b.nodes?.length ?? 0} 个知识点、${b.edges?.length ?? 0} 条关系`;
                      }
                    })
                  }
                  .width('100%')
                  .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }, (b: Book) => b.id)
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
