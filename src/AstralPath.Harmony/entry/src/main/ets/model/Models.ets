/**
 * 数据模型 —— 与单文件版 localStorage 分片（ap:meta / books / answers / plan / papers）
 * 一一对应，字段名沿用原实现，便于三端互相导入导出。
 */

/** 知识点节点 */
export interface KNode {
  id: string;
  title: string;
  body?: string;
  diff: number;
  course?: string;
  kind?: string;
  source?: string;
  kps?: string[];
}

/** 知识图谱边（先修 → 后续） */
export interface KEdge {
  a: string;
  b: string;
  w?: number;
  tg?: boolean;
}

/** 教材 */
export interface Book {
  id: string;
  name: string;
  source?: string;
  sourceText?: string;
  chapters?: Chapter[];
  nodes: KNode[];
  edges: KEdge[];
  qs?: Question[];
  created?: number;
}

export interface Chapter {
  id: string;
  title: string;
  body?: string;
  order?: number;
}

/** 题目 */
export interface Question {
  id: string;
  kp: string;
  stem: string;
  opts: string[];
  ci: number;
  diff?: number;
  src?: string;
}

/** 掌握度记录：n 作答数 / s 正确数 / c 信心 / age 距今天数 / st 连对 */
export interface Mastery {
  n: number;
  s: number;
  c: number;
  age: number;
  st: number;
}

/** 作答日志 */
export interface AnswerLog {
  qid: string;
  kp: string;
  ok: boolean;
  conf: number;
  ts: number;
}

/** 债边（开放红边） */
export interface DebtEdge {
  id: string;
  a: string;
  b: string;
  impact: number;
  why?: string;
  open: boolean;
}

/** 销账进度 */
export interface SaleState {
  streak: number;
  att: number;
  cleared?: boolean;
}

/** 计划条目 */
export interface PlanItem {
  id: string;
  day: number;
  kp: string;
  layer?: string;
  minutes: number;
  why?: string;
  // 调度器（PlanScheduler）产出的扩展字段：K3 校验用 fromKp，复盘用 st，展示用 label；
  // 旧版本存的数据没有这些字段，全部可选
  st?: string;
  fromKp?: string;
  rd?: number;
  label?: string;
}

/** 试卷/作业/错题识别结果 */
export interface Paper {
  id: string;
  name: string;
  type: 'exam' | 'hw' | 'wrong';
  items: PaperItem[];
  created?: number;
}

export interface PaperItem {
  no: number;
  section?: string;
  stem: string;
  options: string[];
  answer: string;
  qtype: string;
  kps?: string[];
}

/** 全局状态（对应 ap:meta + ap:books + ap:answers + ap:plan + ap:papers） */
export interface AppState {
  meta: MetaShard;
  books: Book[];
  mastery: Record<string, Mastery>;
  logs: AnswerLog[];
  sale: Record<string, SaleState>;
  plan: PlanItem[];
  papers: Paper[];
}

export interface MetaShard {
  userName: string;
  activeBookId: string;
  day: number;
  consent: boolean;
  optOut: boolean;
  onboard: boolean;
  kgMode?: string;
}

/** answers 分片（写最频繁）：掌握度 / 作答日志 / 销账进度 */
export interface AnswersShard {
  mastery: Record<string, Mastery>;
  logs: AnswerLog[];
  sale: Record<string, SaleState>;
}

/** 销账计算入参 */
export interface SaleInput {
  streak: number;
  att: number;
}

/** 销账计算结果 */
export interface SaleResult {
  streak: number;
  att: number;
  meets: boolean;
  cleared: boolean;
}
