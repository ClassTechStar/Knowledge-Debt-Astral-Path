/**
 * 识网页 —— 对应 Web 版 main#p-graph：列出当前教材的知识点与先修关系。
 * 鸿蒙侧用列表 + 缩进表达层级（Web 版用 SVG 力导向图），展开态可配合双栏显示节点详情。
 */
import { Book, KNode, KEdge } from '../model/Models';
import { StoreService } from '../service/StoreService';

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

  build() {
    Row() {
      Column({ space: 8 }) {
        Text('识网').fontSize(17).fontWeight(FontWeight.Bold);
        List() {
          ForEach(this.nodes, (n: KNode) => {
            ListItem() {
              Text(n.title)
                .fontSize(13)
                .fontColor(this.selected?.id === n.id ? $r('app.color.brand') : $r('app.color.ink'))
                .width('100%')
                .padding(10)
                .borderRadius(10)
                .backgroundColor(this.selected?.id === n.id ? $r('app.color.brand_soft') : $r('app.color.surface'))
                .onClick(() => {
                  this.selected = n;
                });
            }
          }, (n: KNode) => n.id);
        }
        .layoutWeight(1);
      }
      .width('50%')
      .padding(12);

      Column({ space: 8 }) {
        if (this.selected) {
          Text(this.selected.title).fontSize(15).fontWeight(FontWeight.Bold);
          Text(`难度 ${this.selected.diff}`).fontSize(11).fontColor($r('app.color.muted'));
          Text(`先修：${this.pre(this.selected.id).map((i: string) => this.title(i)).join('、') || '无'}`)
            .fontSize(12);
          Text(`后续：${this.next(this.selected.id).map((i: string) => this.title(i)).join('、') || '无'}`)
            .fontSize(12);
        } else {
          Text('点左侧节点看先修关系').fontSize(12).fontColor($r('app.color.muted'));
        }
      }
      .width('50%')
      .padding(12)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%');
  }
}
