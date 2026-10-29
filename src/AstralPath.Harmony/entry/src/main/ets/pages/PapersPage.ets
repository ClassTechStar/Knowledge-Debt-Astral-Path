/**
 * 试卷作业 —— 对应 Web 版 main#p-papers：识别试卷/作业/错题并结构化。
 * 结构化逻辑与 shared/exam.js 同源（题头、选项、答案、批量分发），鸿蒙侧用同一套正则重写。
 */
import { Paper, PaperItem } from '../model/Models';
import { StoreService } from '../service/StoreService';

interface AnswerPair {
  no: number | null;
  text: string;
}

@Component
export struct PapersPage {
  @State papers: Paper[] = [];
  @State demo: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.papers = await StoreService.loadPapers();
  }

  /** 与 exam.js 一致的解析口径：题头 → 选项 → 答案（含 1.A 2.B 批量分发） */
  private parse(text: string, type: 'exam' | 'hw' | 'wrong'): Paper {
    const lines = text.split('\n').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    const items: PaperItem[] = [];
    let cur: PaperItem | null = null;
    const ansPool: AnswerPair[] = [];
    for (const ln of lines) {
      const qh = /^(\d+)\s*[.、．)]\s*(.+)$/.exec(ln);
      if (qh) {
        if (cur) {
          items.push(cur);
        }
        cur = { no: items.length + 1, stem: qh[2], options: [], answer: '', qtype: 'solve' };
        continue;
      }
      const om = /^([A-Da-d])\s*[.、．)]\s*(.+)$/.exec(ln);
      if (om && cur) {
        cur.options.push(`${om[1].toUpperCase()}.${om[2].trim()}`);
        if (cur.qtype === 'solve') {
          cur.qtype = 'choice';
        }
        continue;
      }
      const am = /^(?:【?\s*答案\s*】?|参考答案|答案|答)\s*[:：]?\s*(.+)$/.exec(ln);
      if (am) {
        const body = am[1].trim();
        const re = /(\d+)\s*[.、]?\s*([A-Da-d])/g;
        let mm = re.exec(body);
        let hit = false;
        while (mm !== null) {
          ansPool.push({ no: Number(mm[1]), text: mm[2].toUpperCase() });
          mm = re.exec(body);
          hit = true;
        }
        if (!hit && cur) {
          cur.answer = body;
          if (['正确', '错误', '对', '错', '√', '×'].includes(body)) {
            cur.qtype = 'judge';
          } else if (cur.options.length === 0) {
            cur.qtype = 'blank';
          }
        }
      }
    }
    if (cur) {
      items.push(cur);
    }
    for (const a of ansPool) {
      const it = a.no !== null ? items.find((x: PaperItem) => x.no === a.no) : undefined;
      if (it) {
        it.answer = a.text;
      }
    }
    return { id: `paper-${Date.now()}`, name: `识别结果 ${new Date().toLocaleDateString()}`, type: type, items: items, created: Date.now() };
  }

  private async addDemo(): Promise<void> {
    const text = '一、单项选择题\n1. Python 中定义函数使用？\nA. def\nB. function\nC. func\nD. define\n答案：1.A';
    const p = this.parse(text, 'exam');
    const list = await StoreService.loadPapers();
    list.push(p);
    await StoreService.savePapers(list);
    this.demo = `已结构化 ${p.items.length} 题`;
    this.refresh();
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('试卷作业').fontSize(17).fontWeight(FontWeight.Bold);
        Blank();
        Button('示例识别').fontSize(11).onClick(() => this.addDemo());
      }
      .width('100%');

      if (this.demo) {
        Text(this.demo).fontSize(12).fontColor($r('app.color.ok'));
      }

      ForEach(this.papers, (p: Paper) => {
        Column({ space: 4 }) {
          Text(p.name).fontSize(14).fontWeight(FontWeight.Bold);
          Text(`${p.items.length} 题 · ${p.type === 'exam' ? '试卷' : (p.type === 'hw' ? '作业' : '错题')}`)
            .fontSize(11)
            .fontColor($r('app.color.muted'));
          ForEach(p.items, (it: PaperItem) => {
            Text(`${it.no}. ${it.stem} ${it.answer ? `（答案 ${it.answer}）` : ''}`)
              .fontSize(12)
              .fontColor($r('app.color.ink'));
          }, (it: PaperItem) => `${p.id}-${it.no}`);
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor($r('app.color.soft'))
        .alignItems(HorizontalAlign.Start);
      }, (p: Paper) => p.id);
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
