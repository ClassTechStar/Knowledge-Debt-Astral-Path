/**
 * 帮助面板 —— 对应 Web 版「帮助中心」：3 步上手 + 术语词典。
 * 用覆盖层实现（不引入 CustomDialog 控制器），折叠/展开态都能铺满内容区。
 */

interface GlossItem {
  term: string;
  desc: string;
}

@Component
export struct HelpPanel {
  onClose: () => void = () => {};

  private readonly guide: string[] = [
    '① 藏书阁：选一份教材（TXT/MD/Word/PPT/EPUB/PDF 文本层），解析出章节与知识点；也可以先「导入示例资料」看效果。',
    '② 识网：看知识点之间的先修关系，点节点能看到它的先修和后续。',
    '③ 今日：按掌握度从低到高做题；做错、或先修不稳的知识点，会在「知债」页亮红边。'
  ];

  private readonly glossary: GlossItem[] = [
    { term: '知识债', desc: '先修知识没掌握牢、拖累后续学习的状态；系统用可解释公式量化它。' },
    { term: '红色债边（红边）', desc: '一条「先修 → 后续」关系亮红：先修存在缺口且已影响后续。' },
    { term: '先修', desc: '学习顺序上必须先掌握的前置知识点。' },
    { term: '掌握度（score）', desc: '由作答正确率、信心等输入经本地公式 score-v2 算出的 0–1 数值。' },
    { term: '影响分（impact）', desc: '衡量一条债边拖累程度的本地公式值；≥0.08 判为开放红边。' },
    { term: '销账', desc: '同一债边连续 2 次达标练习、累计 ≥3 次作答后自动结清。' },
    { term: 'K1–K5', desc: '修复计划的五条约束：单日时长预算 / 先修有序 / 说明含先修 / 间隔≥1 天 / 开放债边全覆盖。' },
    { term: '演示模式', desc: '未配置模型密钥时，AI 入口由本地规则按同一链路生成结果并明确标注。' },
    { term: 'k-匿名', desc: '聚合视图里同一薄弱点样本 <3 人时只显示「样本不足」，保护学生隐私。' },
    { term: 'fail-closed', desc: '未获授权时默认「不可见」；授权后随时可撤销并立即失效。' }
  ];

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('帮助中心').fontSize(16).fontWeight(FontWeight.Bold);
        Blank();
        Button('关闭').fontSize(12).onClick(() => this.onClose());
      }
      .width('100%');

      Scroll() {
        Column({ space: 10 }) {
          Text('3 步上手').fontSize(14).fontWeight(FontWeight.Bold);
          ForEach(this.guide, (g: string) => {
            Text(g).fontSize(12).fontColor($r('app.color.ink'));
          }, (g: string) => g.slice(0, 8));

          Text('术语词典').fontSize(14).fontWeight(FontWeight.Bold).margin({ top: 8 });
          ForEach(this.glossary, (t: GlossItem) => {
            Column({ space: 2 }) {
              Text(t.term).fontSize(12).fontWeight(FontWeight.Bold);
              Text(t.desc).fontSize(11).fontColor($r('app.color.muted'));
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ bottom: 6 });
          }, (t: GlossItem) => t.term);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);
      }
      .layoutWeight(1);
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'));
  }
}
