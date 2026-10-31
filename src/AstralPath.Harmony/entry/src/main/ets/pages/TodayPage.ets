/**
 * 今日页 —— 对应 Web 版 main#p-today：加载今日任务（先修不稳且低分的知识点优先），
 * 点「开始练习」做题；作答后写 answers 分片并按 score-v2 更新掌握度。
 */
import { Book, Question, Mastery } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { FormulaService } from '../service/FormulaService';

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
        Column({ space: 10 }) {
      Row() {
        Text('今日')
          .fontSize(17)
          .fontWeight(FontWeight.Bold);
        Blank();
        Button($r('app.string.today_load'))
          .fontSize(12)
          .onClick(() => this.loadToday());
      }
      .width('100%');

      ForEach(this.tasks, (t: TaskItem) => {
        Row() {
          Column({ space: 2 }) {
            Text(t.title).fontSize(14).fontColor($r('app.color.ink'));
            Text(`掌握度 ${(t.score * 100).toFixed(0)}%`)
              .fontSize(11)
              .fontColor(t.score < 0.55 ? $r('app.color.danger') : $r('app.color.muted'));
          }
          .alignItems(HorizontalAlign.Start);
          Blank();
          Button($r('app.string.today_start'))
            .fontSize(11)
            .onClick(() => this.start(t.kp));
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor($r('app.color.soft'));
      }, (t: TaskItem) => t.kp);

      if (this.quiz) {
        Column({ space: 8 }) {
          Text(this.quiz.stem)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'));
          ForEach(this.quiz.opts, (opt: string, idx: number) => {
            Text(opt)
              .fontSize(13)
              .fontColor(this.picked === idx ? $r('app.color.brand') : $r('app.color.ink'))
              .width('100%')
              .padding(10)
              .borderRadius(10)
              .backgroundColor(this.picked === idx ? $r('app.color.brand_soft') : $r('app.color.surface'))
              .border({ width: 1, color: $r('app.color.soft') })
              .onClick(() => {
                this.picked = idx;
              });
          }, (opt: string, idx: number) => `${idx}-${opt}`);
          Row() {
            Text(`信心 ${this.conf}/5`).fontSize(11).fontColor($r('app.color.muted')).width(64);
            Slider({ value: this.conf, min: 1, max: 5, step: 1 })
              .layoutWeight(1)
              .onChange((v: number) => {
                this.conf = v;
              });
          }
          .width('100%');
          Button('提交')
            .onClick(() => this.submit());
          if (this.result) {
            Text(this.result).fontSize(12).fontColor($r('app.color.ok'));
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.soft'));
      }
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart);
  }
}
