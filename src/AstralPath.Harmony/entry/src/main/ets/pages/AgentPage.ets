/**
 * 智能体页 —— 对应 Web 版 main#p-agent：口语化提问 → 意图路由 → 本地答复 / 模型流式答复。
 * 红线继承：危机词命中不作答、转人工提示；未配置密钥时明确标注演示模式，不假装 AI 在说话。
 */
import { AiService, AiConfig } from '../service/AiService';

@Component
export struct AgentPage {
  @State input: string = '';
  @State transcript: string[] = [];
  @State streaming: boolean = false;
  private cfg: AiConfig = { baseUrl: AiService.DEFAULT_BASE, key: '', model: 'mimo-7b-rl' };

  /** 危机词：命中即停止作答并提示求助（与 Web 版 crisis 词表一致的最小集） */
  private crisis(text: string): boolean {
    const words = ['不想活', '自杀', '轻生', '活不下去', '结束生命'];
    return words.some((w: string) => text.includes(w));
  }

  private async send(): Promise<void> {
    const q = this.input.trim();
    if (!q) {
      return;
    }
    this.input = '';
    this.transcript = [...this.transcript, `我：${q}`];
    if (this.crisis(q)) {
      this.transcript = [...this.transcript, '智能体：我不会回答这类问题。请联系学校心理辅导老师或拨打心理援助热线，有人能帮你。'];
      return;
    }
    if (!AiService.ready(this.cfg)) {
      this.transcript = [...this.transcript, '智能体：（演示模式，未配置模型密钥）按本地规则回答：先补先修知识点，再回到这道题。'];
      return;
    }
    this.streaming = true;
    let acc = '';
    await AiService.stream(this.cfg, q, (c) => {
      if (c.done) {
        this.streaming = false;
        this.transcript = [...this.transcript, `智能体：${acc}`];
      } else {
        acc += c.text;
      }
    });
  }

  build() {
    Column({ space: 10 }) {
      Text('智能体').fontSize(17).fontWeight(FontWeight.Bold);
      List() {
        ForEach(this.transcript, (line: string, idx: number) => {
          ListItem() {
            Text(line)
              .fontSize(13)
              .fontColor($r('app.color.ink'))
              .width('100%')
              .padding(8);
          }
        }, (line: string, idx: number) => `${idx}-${line.slice(0, 10)}`);
      }
      .layoutWeight(1)
      .backgroundColor($r('app.color.soft'))
      .borderRadius(14);

      Row() {
        TextInput({ placeholder: '问点什么，例如「帮我讲讲会计等式」', text: this.input })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.input = v;
          });
        Button(this.streaming ? '思考中' : '发送')
          .onClick(() => this.send());
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(16);
  }
}
