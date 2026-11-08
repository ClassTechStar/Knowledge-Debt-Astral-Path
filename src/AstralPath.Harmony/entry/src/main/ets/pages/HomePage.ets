/**
 * 起点页 —— 对应 Web 版 main#p-home：
 * 「导入示例教材」按钮、当前书籍摘要（节点/边/题数）、进入藏书阁与今日页的入口。
 */
import { Book } from '../model/Models';
import { DemoData } from '../model/DemoData';
import { StoreService } from '../service/StoreService';
import { Theme } from '../common/Theme';
import { PageHeaderView, PanelView, StatView, BadgeView, BtnView, StatusView } from '../components/UiKit';

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

  build() {
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '把讲义变成识网，再把欠债算清楚',
          hint: 'ASTRALPATH WORKSPACE · 全部计算在设备本机完成'
        })

        // Web 起点页 stats 网格：资料数 / 自动图谱 / 今日任务 / 开放债边
        Flex({ wrap: FlexWrap.Wrap }) {
          StatView({ label: '资料数', value: this.hasBook ? '1' : '0' })
          StatView({ label: '自动图谱', value: `${this.nodes}` })
          StatView({ label: '题库', value: `${this.questions}` })
          StatView({ label: '图谱边', value: `${this.edges}` })
        }
        .width('100%')

        PanelView({ title: '当前教材', hint: this.hasBook ? '已选择教材，可直接进入识网与今日任务' : '尚未选择教材' }) {
          Column({ space: 8 }) {
            Text(this.bookName)
              .fontSize(Theme.FS_BODY)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.hasBook ? Theme.INK : Theme.MUTED)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              BadgeView({ text: `${this.nodes} 节点`, kind: 'ok' })
              BadgeView({ text: `${this.edges} 边`, kind: 'ok' })
              BadgeView({ text: `${this.questions} 题`, kind: 'ok' })
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        PanelView({ title: '快速开始', hint: '导入资料 → 查看识网 → 开始任务' }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            BtnView({
              label: '导入示例教材',
              kind: 'primary',
              click: () => {
                this.seed();
              }
            })
            BtnView({
              label: '进入藏书阁',
              kind: 'plain',
              click: () => {
                AppStorage.setOrCreate('currentPage', 'materials');
              }
            })
          }
          .width('100%')
        }

        StatusView({
          text: '解析 → 构图 → 识网 → 今日任务，全部在这台设备上完成，不上传任何数据',
          kind: 'ok'
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
