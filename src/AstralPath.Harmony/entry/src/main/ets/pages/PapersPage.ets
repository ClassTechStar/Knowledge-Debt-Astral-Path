/**
 * 试卷作业 —— 对应 Web 版 main#p-papers：拍照 / 选图 → OCR → 结构化（题头、选项、答案）。
 * 结构化规则与 shared/exam.js 同源；拍照走 cameraPicker，识别走 OcrService
 * （本机没装 Core Vision 时会明确提示不可用，不假装识别成功）。
 * 入库前用 SanitizeService 脱敏：手机号 / 身份证 / 邮箱这类一律打码。
 */
import cameraPicker from '@ohos.multimedia.cameraPicker';
import camera from '@ohos.multimedia.camera';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Paper, PaperItem } from '../model/Models';
import { StoreService } from '../service/StoreService';
import { OcrService } from '../service/OcrService';
import { SanitizeService } from '../service/SanitizeService';

interface AnswerPair {
  no: number | null;
  text: string;
}

@Component
export struct PapersPage {
  @State papers: Paper[] = [];
  @State demo: string = '';
  @State busy: boolean = false;

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
    const ansPool: AnswerPair[] = [];
    let cur: PaperItem | null = null;
    for (const ln of lines) {
      const qh = /^(\d+)\s*[.、．)]\s*(.+)$/.exec(ln);
      if (qh) {
        if (cur) {
          items.push(cur);
        }
        const head: PaperItem = { no: items.length + 1, stem: qh[2], options: [], answer: '', qtype: 'solve' };
        cur = head;
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
          const pair: AnswerPair = { no: Number(mm[1]), text: mm[2].toUpperCase() };
          ansPool.push(pair);
          mm = re.exec(body);
          hit = true;
        }
        if (!hit && cur) {
          cur.answer = body;
          if (body === '正确' || body === '错误' || body === '对' || body === '错' || body === '√' || body === '×') {
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
      if (a.no === null) {
        continue;
      }
      const it = items.find((x: PaperItem) => x.no === a.no);
      if (it) {
        it.answer = a.text;
      }
    }
    return {
      id: `paper-${Date.now()}`,
      name: `识别结果 ${new Date().toLocaleDateString()}`,
      type: type,
      items: items,
      created: Date.now()
    };
  }

  /** 拍照识别：相机 → OCR → 脱敏 → 结构化 */
  private async shoot(): Promise<void> {
    this.busy = true;
    this.demo = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      // PickerProfile 是 class，ArkTS 里必须 new 出来再赋值
      const profile = new cameraPicker.PickerProfile();
      profile.cameraPosition = camera.CameraPosition.CAMERA_POSITION_BACK;
      const res: cameraPicker.PickerResult = await cameraPicker.pick(ctx,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      const uri = res.resultUri;
      if (!uri) {
        this.busy = false;
        return;
      }
      const ocr = await OcrService.recognize(uri);
      if (!ocr.ok) {
        this.demo = ocr.note;
        this.busy = false;
        return;
      }
      const hits = SanitizeService.hits(ocr.text);
      const p = this.parse(SanitizeService.mask(ocr.text), 'exam');
      const list = await StoreService.loadPapers();
      list.push(p);
      await StoreService.savePapers(list);
      this.demo = `识别 ${p.items.length} 题${hits.length > 0 ? `（已脱敏 ${hits.length} 处）` : ''}`;
      this.refresh();
    } catch (e) {
      this.demo = `拍照识别失败：${(e as Error).message}`;
    }
    this.busy = false;
  }

  /** 从文件里选一张图识别 */
  private async pickImage(): Promise<void> {
    this.busy = true;
    try {
      const docPicker = new picker.DocumentViewPicker();
      const uris: string[] = await docPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.jpg', '.png', '.jpeg']
      });
      if (uris.length === 0) {
        this.busy = false;
        return;
      }
      const ocr = await OcrService.recognize(uris[0]);
      if (!ocr.ok) {
        this.demo = ocr.note;
        this.busy = false;
        return;
      }
      const p = this.parse(SanitizeService.mask(ocr.text), 'hw');
      const list = await StoreService.loadPapers();
      list.push(p);
      await StoreService.savePapers(list);
      this.demo = `识别 ${p.items.length} 题`;
      this.refresh();
    } catch (e) {
      this.demo = `识别失败：${(e as Error).message}`;
    }
    this.busy = false;
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
      Row({ space: 6 }) {
        Text('试卷作业').fontSize(17).fontWeight(FontWeight.Bold);
        Blank();
        Button(this.busy ? '识别中' : '拍照识别').fontSize(11).onClick(() => this.shoot());
        Button('选图识别').fontSize(11).onClick(() => this.pickImage());
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
