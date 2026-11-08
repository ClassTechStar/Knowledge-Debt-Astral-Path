/**
 * 识网页 —— 复刻 Web 版 main#p-graph：教材切换 chips + 左图右详情 + 图谱导出。
 * 图谱画布支持缩放、拖拽、点选（GraphCanvas），节点三色（章节蓝/词绿/债红）与 Web 一致。
 */
import { Book, KNode, KEdge, AnswersShard, AnswerLog } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';
import { FormulaConstants as K } from '../model/FormulaConstants';
import { GraphCanvas, GraphCtrl } from '../components/GraphCanvas';
import { PageHeaderView, PanelView, BadgeView, BtnView, StatusView } from '../components/UiKit';
import { Theme } from '../common/Theme';

@Component
export struct GraphPage {
  @State nodes: KNode[] = [];
  @State edges: KEdge[] = [];
  @State selected: KNode | null = null;
  @State debtIds: string[] = [];
  @State bookName: string = '';
  @State debtMsg: string = '点节点看先修关系';
  /** 图谱视图控制器：100% / 适应 两个按钮通过它操作画布 */
  private ctrl: GraphCtrl = new GraphCtrl();

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
    this.bookName = b?.name ?? '';
    // 兼容旧数据：早期构建的图谱没有章节节点与 kind 字段，
    // 按 book.chapters 在展示层补出章节节点与归属边，保证三色图语义一致
    const hasChapter = this.nodes.some((x: KNode) => x.kind === 'chapter');
    if (!hasChapter && b && b.chapters && b.chapters.length > 0) {
      const extra: KNode[] = [];
      const extraE: KEdge[] = [];
      const known = new Set<string>();
      this.nodes.forEach((x: KNode) => known.add(x.id));
      for (const ch of b.chapters) {
        if (!known.has(ch.id)) {
          extra.push({ id: ch.id, title: ch.title, diff: 1, kind: 'chapter', body: (ch.body ?? '').slice(0, 200) });
        }
        const body = (ch.body ?? '') + ' ' + ch.title;
        for (const n of this.nodes) {
          if (body.indexOf(n.title) >= 0) {
            extraE.push({ a: ch.id, b: n.id, w: 1, tg: true });
            n.kind = n.kind ?? 'term';
          }
        }
      }
      this.nodes = this.nodes.concat(extra);
      this.edges = this.edges.concat(extraE);
    }
    // 兼容旧数据：早期构建的图谱没有章节节点与 kind 字段，
    // 按 book.chapters 在展示层补出章节节点与归属边，保证三色图语义一致
    if (!hasChapter && b && b.chapters && b.chapters.length > 0) {
      const extra: KNode[] = [];
      const extraE: KEdge[] = [];
      const known = new Set<string>();
      this.nodes.forEach((x: KNode) => known.add(x.id));
      for (const ch of b.chapters) {
        if (!known.has(ch.id)) {
          extra.push({ id: ch.id, title: ch.title, diff: 1, kind: 'chapter', body: (ch.body ?? '').slice(0, 200) });
        }
        const body = (ch.body ?? '') + ' ' + ch.title;
        for (const n of this.nodes) {
          if (body.indexOf(n.title) >= 0) {
            extraE.push({ a: ch.id, b: n.id, w: 1, tg: true });
            n.kind = n.kind ?? 'term';
          }
        }
      }
      this.nodes = this.nodes.concat(extra);
      this.edges = this.edges.concat(extraE);
    }
    this.selected = null;
    this.debtIds = [];
    if (!b || this.nodes.length === 0) {
      return;
    }
    // 与知债页同口径：开放债边的目标节点标红
    try {
      const ans: AnswersShard = await StoreService.loadAnswers();
      const visiting: Map<string, number> = new Map();
      const scoreOf = (id: string): number => {
        return FormulaService.scoreOfGraph(id, this.edges, ans.mastery, visiting);
      };
      const downCount = (id: string): number => {
        return this.edges.filter((e: KEdge) => e.a === id && scoreOf(e.b) < K.cg).length;
      };
      const ids: string[] = [];
      for (const e of this.edges) {
        const sf = scoreOf(e.a);
        const st = scoreOf(e.b);
        const freq = ans.logs.filter((l: AnswerLog) => l.kp === e.b && !l.ok).length;
        const impact = FormulaService.impactV2(sf, st, e.w ?? 1, !!e.tg, Math.max(freq, 1), downCount(e.a));
        if (FormulaService.isOpen(impact) && ids.indexOf(e.b) < 0) {
          ids.push(e.b);
        }
      }
      this.debtIds = ids;
    } catch (e) {
      // 诊断数据缺失不影响图谱浏览
    }
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
    if (n) {
      const isDebt = this.debtIds.indexOf(id) >= 0;
      this.debtMsg = isDebt
        ? `「${n.title}」在开放红边上：先修没掌握会拖累后续`
        : `已选中「${n.title}」`;
    }
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '知识图谱',
          hint: '章节蓝 · 词绿 · 债红 · 拖拽平移、双指缩放、点按选中'
        })

        PanelView({
          title: '当前教材',
          hint: this.bookName.length > 0 ? `来源：${this.bookName}` : '尚未选择教材'
        }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            BadgeView({ text: `${this.nodes.length} 节点`, kind: 'ok' })
            BadgeView({ text: `${this.edges.length} 边`, kind: 'ok' })
            if (this.debtIds.length > 0) {
              BadgeView({ text: `${this.debtIds.length} 红边`, kind: 'err' })
            }
          }
          .width('100%')
          .margin({ top: 4 })
        }

        if (this.nodes.length === 0) {
          StatusView({
            text: '还没有图谱。先到藏书阁解析一份教材，或在起点页导入示例教材。',
            kind: 'warn'
          })
        } else {
          PanelView({
            title: '知识图谱',
            hint: '点节点看先修/后续；右下角「适应」复位视图'
          }) {
            // 视图控件放在画布上方，不遮挡任何节点
            Row({ space: 8 }) {
              BtnView({
                label: '100%',
                kind: 'plain',
                click: () => {
                  this.ctrl.reset();
                }
              })
              BtnView({
                label: '适应',
                kind: 'plain',
                click: () => {
                  this.ctrl.fit();
                }
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
            .margin({ bottom: 8 })

            GraphCanvas({
              nodes: this.nodes,
              edges: this.edges,
              selectedId: this.selected ? this.selected.id : '',
              debtIds: this.debtIds,
              ctrl: this.ctrl,
              onSelect: (id: string) => this.pick(id)
            })
              .width('100%')
              .height(380)
              .borderRadius(Theme.R_C)
              .border({ width: 1, color: Theme.RULE })
          }

          PanelView({ title: '节点详情', hint: this.debtMsg }) {
            Column({ space: 8 }) {
              if (this.selected) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  Text(this.selected.title)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.INK)
                  if (this.debtIds.indexOf(this.selected.id) >= 0) {
                    BadgeView({ text: '红边', kind: 'err' })
                  }
                  if (this.selected.kind === 'chapter') {
                    BadgeView({ text: '章节', kind: 'ok' })
                  }
                }
                .width('100%')

                Text(`难度 ${this.selected.diff}${this.selected.course ? ` · ${this.selected.course}` : ''}`)
                  .fontSize(Theme.FS_HINT)
                  .fontColor(Theme.MUTED)
                  .width('100%')

                Text(`先修：${this.pre(this.selected.id).map((i: string) => this.title(i)).join('、') || '无'}`)
                  .fontSize(Theme.FS_BODY)
                  .fontColor(Theme.INK)
                  .width('100%')
                Text(`后续：${this.next(this.selected.id).map((i: string) => this.title(i)).join('、') || '无'}`)
                  .fontSize(Theme.FS_BODY)
                  .fontColor(Theme.INK)
                  .width('100%')

                if (this.selected.body && this.selected.body.length > 0) {
                  Text(this.selected.body)
                    .fontSize(Theme.FS_HINT)
                    .fontColor(Theme.MUTED)
                    .width('100%')
                    .maxLines(6)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              } else {
                Text('点节点看先修关系')
                  .fontSize(Theme.FS_HINT)
                  .fontColor(Theme.MUTED)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          PanelView({
            title: '图谱导出',
            hint: '三元组 · 属性图 · 思维导图 · Markdown 大纲'
          }) {
            Flex({ wrap: FlexWrap.Wrap }) {
              BtnView({
                label: '复制三元组',
                kind: 'quiet',
                click: () => {
                  this.debtMsg = '三元组导出为演示入口';
                }
              })
            }
            .width('100%')
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
