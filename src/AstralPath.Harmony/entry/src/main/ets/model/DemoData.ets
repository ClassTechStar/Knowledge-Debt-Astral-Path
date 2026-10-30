/**
 * 示例教材 —— 对齐单文件版「导入示例教材」的演示数据（Python 入门教材骨架）。
 * 真机解析 PDF/TXT 由 KgService 负责；这里只保证首次启动就有可演示的图谱、题目与债边。
 */
import { Book, KNode, KEdge, Question, Mastery, AnswerLog } from '../model/Models';

interface QuestionSeed {
  kp: string;
  stem: string;
  opts: string[];
  ci: number;
}

export class DemoData {
  static build(): Book {
    const nodes: KNode[] = [
      { id: 'P01', title: '变量与类型', diff: 1, course: 'Python' },
      { id: 'P02', title: '运算符与表达式', diff: 1, course: 'Python' },
      { id: 'P03', title: '条件分支', diff: 2, course: 'Python' },
      { id: 'P04', title: '循环结构', diff: 2, course: 'Python' },
      { id: 'P05', title: '函数定义', diff: 2, course: 'Python' },
      { id: 'P06', title: '列表与切片', diff: 2, course: 'Python' },
      { id: 'P07', title: '字典与集合', diff: 3, course: 'Python' },
      { id: 'P08', title: '异常处理', diff: 3, course: 'Python' },
      { id: 'P09', title: '文件读写', diff: 3, course: 'Python' },
      { id: 'P10', title: '类与对象', diff: 3, course: 'Python' },
      { id: 'D01', title: '神经元与激活函数', diff: 2, course: '深度学习' },
      { id: 'D02', title: '损失函数', diff: 3, course: '深度学习' },
      { id: 'D03', title: '梯度下降', diff: 3, course: '深度学习' },
      { id: 'D04', title: '反向传播', diff: 4, course: '深度学习' }
    ];
    const edges: KEdge[] = [
      { a: 'P01', b: 'P02', w: 1.0 },
      { a: 'P02', b: 'P03', w: 0.9 },
      { a: 'P03', b: 'P04', w: 0.9 },
      { a: 'P04', b: 'P05', w: 0.8 },
      { a: 'P01', b: 'P06', w: 0.8 },
      { a: 'P06', b: 'P07', w: 0.7 },
      { a: 'P05', b: 'P08', w: 0.7 },
      { a: 'P08', b: 'P09', w: 0.6 },
      { a: 'P05', b: 'P10', w: 0.8 },
      { a: 'P01', b: 'D01', w: 0.5, tg: true },
      { a: 'D01', b: 'D02', w: 0.9 },
      { a: 'D02', b: 'D03', w: 0.9 },
      { a: 'D03', b: 'D04', w: 0.9 }
    ];
    return {
      id: 'demo-python',
      name: 'Python 从入门到实践（示例）',
      source: 'demo',
      nodes: nodes,
      edges: edges,
      qs: DemoData.questions(),
      created: Date.now()
    };
  }

  private static questions(): Question[] {
    const seeds: QuestionSeed[] = [
      { kp: 'P01', stem: '下面哪个是合法的变量名？', opts: ['1a', '_a', 'for', 'a-b'], ci: 1 },
      { kp: 'P02', stem: '表达式 7 // 2 的结果是？', opts: ['3', '3.5', '4', '3.0'], ci: 0 },
      { kp: 'P03', stem: '条件分支使用的关键字是？', opts: ['if', 'switch', 'when', 'case'], ci: 0 },
      { kp: 'P04', stem: 'for 循环常用于？', opts: ['遍历序列', '定义函数', '捕获异常', '声明类'], ci: 0 },
      { kp: 'P05', stem: '定义函数使用？', opts: ['def', 'function', 'lambda', 'func'], ci: 0 },
      { kp: 'P06', stem: 'lst[1:3] 的切片结果是？', opts: ['第 1 到第 3 个', '第 2 到第 3 个', '第 1 到第 2 个', '全部'], ci: 1 },
      { kp: 'P07', stem: '字典的键必须？', opts: ['可哈希', '有序', '可变', '数字'], ci: 0 },
      { kp: 'P08', stem: '捕获异常使用？', opts: ['try/except', 'do/catch', 'if/else', 'throw'], ci: 0 },
      { kp: 'P09', stem: '打开文件使用？', opts: ['open()', 'read()', 'file()', 'load()'], ci: 0 },
      { kp: 'P10', stem: '定义类使用？', opts: ['class', 'struct', 'type', 'def class'], ci: 0 },
      { kp: 'D01', stem: '神经元的输出经过？', opts: ['激活函数', '损失函数', '优化器', '池化'], ci: 0 },
      { kp: 'D02', stem: '分类任务常用损失是？', opts: ['交叉熵', 'MSE', 'MAE', 'Huber'], ci: 0 },
      { kp: 'D03', stem: '梯度下降用于？', opts: ['最小化损失', '最大化损失', '数据增强', '归一化'], ci: 0 },
      { kp: 'D04', stem: '反向传播的本质是？', opts: ['链式法则求梯度', '前向传播', '随机初始化', '正则化'], ci: 0 }
    ];
    const out: Question[] = [];
    for (let i = 0; i < seeds.length; i++) {
      const s: QuestionSeed = seeds[i];
      out.push({
        id: `Q${String(i + 1).padStart(3, '0')}`,
        kp: s.kp,
        stem: s.stem,
        opts: s.opts,
        ci: s.ci,
        diff: 2,
        src: 'bank'
      });
    }
    return out;
  }

  /**
   * 演示学情：让 3 个「后续」知识点带着错题（先修还算正常）。
   * 为什么需要：全默认掌握度时按 impact-v2 算出来约 0.0798，正好卡在 0.08 阈值下，
   * 演示数据就成了「零红边」，看不出这套东西在干嘛。
   */
  static seedMastery(): Record<string, Mastery> {
    const m: Record<string, Mastery> = {};
    m['P02'] = { n: 3, s: 0, c: 2, age: 6, st: 0 };
    m['P06'] = { n: 2, s: 0, c: 1, age: 8, st: 0 };
    m['D02'] = { n: 2, s: 0, c: 1, age: 5, st: 0 };
    return m;
  }

  /** 对应的错题日志（impact 里的 freq / down 两个因子要它） */
  static seedLogs(): AnswerLog[] {
    const now = Date.now();
    const out: AnswerLog[] = [];
    const push = (kp: string, times: number) => {
      for (let i = 0; i < times; i++) {
        out.push({ qid: `seed-${kp}-${i}`, kp: kp, ok: false, conf: 2, ts: now - i * 86400000 });
      }
    };
    push('P02', 3);
    push('P06', 2);
    push('D02', 2);
    return out;
  }
}
