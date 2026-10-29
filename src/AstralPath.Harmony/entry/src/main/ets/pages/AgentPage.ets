/**
 * 智能体页 —— 对应 Web 版 main#p-agent：口语化提问 → 意图路由 → 本地答复 / 模型流式答复。
 *
 * 与 Web 版一致的四条红线：
 * 1) 危机词命中不作答，直接转人工求助（词表与 tools/agent-intents.json 同源，11 个）；
 * 2) 意图路由按 26 个意图的锚点词匹配，未配密钥时用本地答复兜底；
 * 3) 未配置密钥时明确标注演示模式，不假装是模型在说话；
 * 4) 模型调用失败不报错弹窗，静默回退本地答复。
 */
import { AiService, AiConfig } from '../service/AiService';
import { StoreService, AiCfg } from '../service/StoreService';
import { DemoKey } from '../common/DemoKey';

interface IntentDef {
  id: string;
  anchors: string[];
  reply: string;
}

@Component
export struct AgentPage {
  @State input: string = '';
  @State transcript: string[] = [];
  @State streaming: boolean = false;
  private cfg: AiConfig = { baseUrl: AiService.DEFAULT_BASE, key: '', model: 'mimo-7b-rl' };

  /** 危机词：与 tools/agent-intents.json 的 crisis 列表一致（11 个） */
  private static readonly CRISIS: string[] = [
    '不想活', '自杀', '轻生', '结束生命', '自残',
    '伤害自己', '跳楼', '上吊', 'suicide', 'kill myself', '活不下去'
  ];

  /** 26 个意图的锚点与本地兜底答复（无密钥时按这个答） */
  private static readonly INTENTS: IntentDef[] = [
    { id: 'debt.diagnose', anchors: ['知识债', '债边', '诊断', '红边', '薄弱', '搞不清', '漏洞', '哪里不会', '哪里薄弱', '帮我分析'],
      reply: '去「知债」页点重新诊断，会按 impact 公式算出开放红边。' },
    { id: 'debt.explain', anchors: ['解释', '为什么', '怎么来的', '公式', '讲解', '怎么回事', '什么意思', '怎么理解', '什么原理'],
      reply: '影响分 = 先修缺口 × 后续薄弱 × 边权 ×（跨课程 1.15 倍）× 级联放大，≥0.08 判为开放红边。' },
    { id: 'plan.create', anchors: ['计划', '14天', '安排', '复习计划', '做个计划', '怎么安排', '复习规划'],
      reply: '「知债」页点生成 14 天计划：先修优先，每天不超过 40 分钟，同一知识点间隔至少 1 天。' },
    { id: 'plan.rebalance', anchors: ['减负', '重排', '调整计划', '太重', '换个计划', '改一下计划'],
      reply: '计划排完可以再点一次生成，把每天时长预算压低一点就会重排。' },
    { id: 'today.tasks', anchors: ['今日', '今天做', '今日任务', '今天学什么', '现在学什么', '该学什么', '今天干什么'],
      reply: '「今日」页会按掌握度从低到高列出 5 条任务，点开始练习就行。' },
    { id: 'practice.start', anchors: ['练习', '做题', '小测', '测验', '来几道', '出几道', '出个题', '刷几道', '做几道', '练一下'],
      reply: '「今日」页点开始练习；题库来自教材解析结果，答完会更新掌握度。' },
    { id: 'progress.check', anchors: ['进度', '销账', '进展', 'streak', '学得怎么样', '看看进度', '掌握怎么样'],
      reply: '「知债」页点销账检查：连续 2 次达标且累计 3 次作答才算结清。' },
    { id: 'graph.view', anchors: ['图谱', '识网', '知识图谱', '思维导图', '关系图', '知识网', '看看图'],
      reply: '「识网」页看知识点和先修关系，点节点能看到它的先修与后续。' },
    { id: 'material.parse', anchors: ['解析资料', '上传', 'OCR', '教材', '藏书', '解析文件', '导入教材', '上传课本'],
      reply: '「藏书阁」选 PDF/TXT 解析；目前鸿蒙版先支持文本类，扫描版 OCR 还在路上。' },
    { id: 'material.list', anchors: ['列出资料', '教材列表', '藏书', '有哪些书', '书单', '几本书', '已解析教材', '有什么教材'],
      reply: '「藏书阁」列出已解析教材，点「设为当前」切换。' },
    { id: 'material.switch', anchors: ['切换教材', '换书', '切书', '切换到', '换一本', '切到', '切过去', '换个教材', '换本书'],
      reply: '「藏书阁」点某本书的「设为当前」即可切换。' },
    { id: 'kb.search', anchors: ['知识库', '检索', '什么是', '查资料', '文档', '搜索', '搜一下', '查一下', '找找', '章节', '帮我找', '找找看', '查一查', '讲一下', '知识点', '介绍', '概要', '概述', '概括'],
      reply: '可以在「识网」页按知识点名称找，或在「藏书阁」翻章节目录。' },
    { id: 'profile.view', anchors: ['画像', '我的标签', '学习画像', '我的情况'],
      reply: '「画像」页看掌握/薄弱分布和累计作答；不想被画像可以随时关掉个性化。' },
    { id: 'profile.optout', anchors: ['退出画像', '关闭画像', 'opt-out'],
      reply: '「画像」页底部开关：关掉后只按教材章节顺序安排，不依据知识债推断。' },
    { id: 'teacher.hotspots', anchors: ['热点', '班级', '共性问题', '大家的情况'],
      reply: '「教师」页是按 k=5 匿名聚合的，样本少于 3 人的薄弱点只显示「样本不足」。' },
    { id: 'consent.grant', anchors: ['授权', '同意可见', 'consent', '允许查看'],
      reply: '「账户」页有授权开关，不授权默认教师侧不可见（fail-closed）。' },
    { id: 'consent.revoke', anchors: ['撤销', '取消授权', '关闭可见'],
      reply: '「账户」页把授权开关关掉，立刻失效。注意「撤销授权」不是要授权。' },
    { id: 'whatif.simulate', anchors: ['what-if', '如果', '模拟', '假设', '假如', '要是', '试想'],
      reply: 'What-if 模拟（调前置掌握度/目标掌握度/错题频次看债边变化）还没搬到鸿蒙版。' },
    { id: 'narrative.read', anchors: ['故事', '叙事', '讲解', '讲个故事', '举个例子', '给我讲讲', '讲一讲'],
      reply: '配了模型密钥就能讲；没配的话我可以按知识点给你一段要点。' },
    { id: 'sale.check', anchors: ['销账检查', '能否销账', '销账条件', '能销账吗', '销账了没'],
      reply: '「知债」页销账检查：加权得分 ≥0.65 且正确率 ≥70%、信心 ≥3，连续 2 次才算结清。' },
    { id: 'chapter.read', anchors: ['目录', '读一下', '讲了什么', '讲了啥', '章节', '这一章', '内容是什么', '翻到', '第几章', '前几章', '本章', '这章', '有什么内容', '不明白', '不懂', '不理解', '不清楚'],
      reply: '「藏书阁」选中教材后能看到章节骨架。' },
    { id: 'graph.path', anchors: ['什么关系', '怎么联系', '有没有关', '路径', '谁先', '先后', '前置', '怎么到', '怎么学', '学习顺序', '什么联系', '有关吗', '先后顺序'],
      reply: '「识网」页点节点，能看到它的先修和后续，按顺序学就行。' },
    { id: 'meta.help', anchors: ['帮助', '怎么用', '说明', '你能干什么', '你会什么', '功能有哪些'],
      reply: '流程是：藏书阁解析教材 → 识网看关系 → 今日做题 → 知债诊断 → 生成计划 → 练熟销账。' },
    { id: 'meta.feedback', anchors: ['反馈', '建议', '不好用'],
      reply: '记下了。也可以直接告诉我哪一步不顺手。' }
  ];

  aboutToAppear(): void {
    this.loadCfg();
  }

  private async loadCfg(): Promise<void> {
    const c: AiCfg = await StoreService.loadAiCfg();
    // 用户自己的 key 优先；没有就用资源里的演示密钥（默认为空）
    const key = c.key && c.key.length > 0 ? c.key : DemoKey.value();
    this.cfg = {
      baseUrl: c.baseUrl || AiService.DEFAULT_BASE,
      key: key,
      model: c.model || 'mimo-7b-rl'
    };
  }

  private crisis(text: string): boolean {
    const low = text.toLowerCase();
    for (const w of AgentPage.CRISIS) {
      if (low.includes(w.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /** 本地意图路由：按锚点命中最多的意图命中 */
  private route(text: string): IntentDef | null {
    let best: IntentDef | null = null;
    let bestHit = 0;
    for (const it of AgentPage.INTENTS) {
      let hit = 0;
      for (const a of it.anchors) {
        if (text.includes(a)) {
          hit += 1;
        }
      }
      if (hit > bestHit) {
        bestHit = hit;
        best = it;
      }
    }
    return best;
  }

  private async send(): Promise<void> {
    const q = this.input.trim();
    if (!q) {
      return;
    }
    this.input = '';
    this.transcript = [...this.transcript, `我：${q}`];

    // 红线 1：危机词优先，不作答
    if (this.crisis(q)) {
      this.transcript = [...this.transcript,
        '智能体：这类问题我不回答。请联系学校心理辅导老师，或拨打心理援助热线，有人能帮你。'];
      return;
    }

    if (!AiService.ready(this.cfg)) {
      const it = this.route(q);
      const local = it ? it.reply : '（演示模式，未配置模型密钥）先补先修知识点，再回到这道题。';
      this.transcript = [...this.transcript, `智能体：${local}`];
      return;
    }

    this.streaming = true;
    let acc = '';
    await AiService.stream(this.cfg, q, (c) => {
      if (c.done) {
        this.streaming = false;
        this.transcript = [...this.transcript, `智能体：${acc || '（模型没有返回内容）'}`];
      } else {
        acc += c.text;
      }
    });
    if (this.streaming) {
      this.streaming = false;
    }
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
