/**
 * 今日页 —— 对应 Web 版 main#p-today：加载今日任务（先修不稳且低分的知识点优先），
 * 点「开始练习」做题；作答后写 answers 分片并按 score-v2 更新掌握度。
 */
import { Book, Question, Mastery } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';
import { Theme } from '../common/Theme';
import { PageHeaderView, PanelView, CardView, BtnView, BadgeView, StatusView, BarView } from '../components/UiKit';

interface TaskItem {
  kp: string;
  title: string;
  score: number;
}

@Component
export struct TodayPage {
  @State tasks: TaskItem[] = [];
  @State quiz: Question | null = null;
  @State picked: number = -1;
  @State conf: number = 4;
  @State result: string = '';
  private book: Book | null = null;

  aboutToAppear(): void {
    this.loadToday();
  }

  private async loadToday(): Promise<void> {
    const books = await StoreService.loadBooks();
    const meta = await StoreService.loadMeta();
    let b: Book | undefined = books.find((x: Book) => x.id === meta.activeBookId);
    if (!b && books.length > 0) {
      b = books[0];
    }
    if (!b) {
      this.tasks = [];
      return;
    }
    this.book = b;
    const ans = await StoreService.loadAnswers();
    const list: TaskItem[] = [];
    const visiting: Map<string, number> = new Map();
    for (const n of b.nodes) {
      const sc = FormulaService.scoreOfGraph(n.id, b.edges ?? [], ans.mastery, visiting);
      const item: TaskItem = { kp: n.id, title: n.title, score: sc };
      list.push(item);
    }
    this.tasks = list.sort((x: TaskItem, y: TaskItem) => x.score - y.score).slice(0, 5);
  }

  private start(kp: string): void {
    const pool = (this.book?.qs ?? []).filter((q: Question) => q.kp === kp);
    if (pool.length === 0) {
      this.quiz = null;
      this.result = '该知识点暂无题目';
      return;
    }
    this.quiz = pool[Math.floor(Math.random() * pool.length)];
    this.picked = -1;
    this.conf = 4;
    this.result = '';
  }

  private async submit(): Promise<void> {
    if (!this.quiz || this.picked < 0) {
      return;
    }
    const q = this.quiz;
    const ok = this.picked === q.ci;
    const ans = await StoreService.loadAnswers();
    const m: Mastery = ans.mastery[q.kp] ?? { n: 0, s: 0, c: 3, age: 0, st: 0 };
    m.n += 1;
    if (ok) {
      m.s += 1;
      m.st += 1;
    } else {
      m.st = 0;
    }
    m.age = 0;
    ans.mastery[q.kp] = m;
    ans.logs.push({ qid: q.id, kp: q.kp, ok: ok, conf: this.conf, ts: Date.now() });
    await StoreService.saveAnswers(ans);
    const sc = FormulaService.scoreOfMastery(m, []);
    this.result = `${ok ? '答对了' : '答错了'} · 信心 ${this.conf}/5 · 该知识点掌握度 ${(sc * 100).toFixed(0)}%`;
    this.loadToday();
  }

  build() {
    // 内容会超过一屏（任务列表 + 题卡），必须能滚，否则提交按钮被底部挤住
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '今日任务',
          hint: '先修不稳且低分的知识点优先，做完一道刷新一次掌握度'
        })

        PanelView({
          title: '今日清单',
          hint: '按当前掌握度升序排列，最多 5 项'
        }) {
          if (this.tasks.length === 0) {
            Text('还没有今日任务。先在藏书阁解析教材，或在起点页导入示例教材。')
              .fontSize(Theme.FS_HINT)
              .fontColor(Theme.MUTED)
              .width('100%')
          } else {
            ForEach(this.tasks, (t: TaskItem) => {
              CardView() {
                Column({ space: 6 }) {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Text(t.title)
                      .fontSize(Theme.FS_BODY)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.INK)
                    if (t.score < 0.55) {
                      BadgeView({ text: '待巩固', kind: 'err' })
                    } else if (t.score < 0.75) {
                      BadgeView({ text: '进行中', kind: 'warn' })
                    } else {
                      BadgeView({ text: '良好', kind: 'ok' })
                    }
                  }
                  .width('100%')

                  Text(`掌握度 ${(t.score * 100).toFixed(0)}%`)
                    .fontSize(Theme.FS_HINT)
                    .fontColor(t.score < 0.55 ? Theme.DANGER : Theme.MUTED)
                    .width('100%')

                  BarView({ ratio: t.score })

                  Flex({ wrap: FlexWrap.Wrap }) {
                    BtnView({
                      label: '开始练习',
                      kind: 'primary',
                      click: () => this.start(t.kp)
                    })
                  }
                  .width('100%')
                  .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }, (t: TaskItem) => t.kp)
          }

          Flex({ wrap: FlexWrap.Wrap }) {
            BtnView({
              label: '加载今日任务',
              kind: 'plain',
              click: () => this.loadToday()
            })
          }
          .width('100%')
          .margin({ top: 8 })
        }

        if (this.quiz) {
          PanelView({
            title: '题目练习',
            hint: '选一个答案，然后拉信心滑杆，提交后写回掌握度'
          }) {
            Column({ space: 10 }) {
              Text(this.quiz.stem)
                .fontSize(Theme.FS_BODY)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.INK)
                .width('100%')

              ForEach(this.quiz.opts, (opt: string, idx: number) => {
                Text(opt)
                  .fontSize(Theme.FS_BODY)
                  .fontColor(this.picked === idx ? Theme.PRIMARY : Theme.INK)
                  .width('100%')
                  .padding(Theme.PAD_CARD)
                  .borderRadius(Theme.R_C)
                  .backgroundColor(this.picked === idx ? Theme.SOFT : Theme.SURFACE)
                  .border({
                    width: this.picked === idx ? 2 : 1,
                    color: this.picked === idx ? Theme.PRIMARY : Theme.RULE
                  })
                  .onClick(() => {
                    this.picked = idx;
                  });
              }, (opt: string, idx: number) => `${idx}-${opt}`)

              Row() {
                Text(`信心 ${this.conf}/5`)
                  .fontSize(Theme.FS_HINT)
                  .fontColor(Theme.MUTED)
                  .width(72)
                Slider({ value: this.conf, min: 1, max: 5, step: 1 })
                  .layoutWeight(1)
                  .onChange((v: number) => {
                    this.conf = v;
                  });
              }
              .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                BtnView({
                  label: '提交',
                  kind: 'primary',
                  click: () => this.submit()
                })
              }
              .width('100%')

              if (this.result) {
                StatusView({ text: this.result, kind: 'ok' })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }

        if (!this.quiz && this.result.length > 0) {
          StatusView({ text: this.result, kind: 'warn' })
        }
      }
      .width('100%')
      .padding(Theme.PAD_PANEL)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.CANVAS)
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
  }
}
