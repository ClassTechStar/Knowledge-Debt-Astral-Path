/**
 * 识网页 —— 对应 Web 版 main#p-graph：力导向图 + 点节点看先修/后续。
 * 展开态（LG）左图右详情，折叠态上下排布。
 */
import { Book, KNode, KEdge } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { GraphCanvas } from '../components/GraphCanvas';

@Component
export struct GraphPage {
  @State nodes: KNode[] = [];
  @State edges: KEdge[] = [];
  @State selected: KNode | null = null;

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
    this.nodes = b?.nodes ?? [];
    this.edges = b?.edges ?? [];
  }

  private pre(id: string): string[] {
    return this.edges.filter((e: KEdge) => e.b === id).map((e: KEdge) => e.a);
  }

  private next(id: string): string[] {
    return this.edges.filter((e: KEdge) => e.a === id).map((e: KEdge) => e.b);
  }

  private title(id: string): string {
    const n = this.nodes.find((x: KNode) => x.id === id);
    return n ? n.title : id;
  }

  private pick(id: string): void {
    const n = this.nodes.find((x: KNode) => x.id === id);
    this.selected = n ?? null;
  }

  @Builder
  detail() {
    Column({ space: 6 }) {
      if (this.selected) {
        Text(this.selected.title).fontSize(15).fontWeight(FontWeight.Bold);
        Text(`难度 ${this.selected.diff}${this.selected.course ? ` · ${this.selected.course}` : ''}`)
          .fontSize(11)
          .fontColor($r('app.color.muted'));
        Text(`先修：${this.pre(this.selected.id).map((i: string) => this.title(i)).join('、') || '无'}`).fontSize(12);
        Text(`后续：${this.next(this.selected.id).map((i: string) => this.title(i)).join('、') || '无'}`).fontSize(12);
      } else {
        Text('点节点看先修关系').fontSize(12).fontColor($r('app.color.muted'));
      }
    }
    .width('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('识网').fontSize(17).fontWeight(FontWeight.Bold);
        Blank();
        Text(`${this.nodes.length} 节点 · ${this.edges.length} 边`)
          .fontSize(11)
          .fontColor($r('app.color.muted'));
      }
      .width('100%');

      if (this.nodes.length === 0) {
        Text('还没有图谱。先到藏书阁解析一份教材，或在起点页导入示例教材。')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding(14);
      } else {
        GraphCanvas({
          nodes: this.nodes,
          edges: this.edges,
          selectedId: this.selected?.id ?? '',
          onSelect: (id: string) => this.pick(id)
        })
          .width('100%')
          .layoutWeight(1);

        this.detail();
      }
    }
    .width('100%')
    .height('100%')
    .padding(16);
  }
}
