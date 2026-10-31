/**
 * 教材解析服务 —— 鸿蒙版对应 tools/kg_builder.py 的「分章 + 抽词 + 连边」，
 * 这里只做文本类（TXT / Markdown / 已提取的 PDF 文本层）：
 *   ① 按标题行切章（第N章、第N节、# 标题、1. 标题）
 *   ② 按 2–6 字中文短语的词频抽概念（无分词库，取高频且去停用）
 *   ③ 同一章内按出现顺序连先修边（靠前的作为先修）
 * 本服务只处理「已经是文本」的输入；扫描版 PDF 由 PdfText / PdfOcrService
 * 走文本层优先、扫描页抽页图转识别（Core Vision / 宿主 OCR），不经过这里。
 */
import { Book, KNode, KEdge, Chapter } from '../model/Models';

interface Cand {
  term: string;
  count: number;
  firstOrder: number;
}

export class KgService {
  private static readonly STOP: string[] = ['我们', '你们', '他们', '可以', '这个', '那个', '什么',
    '怎么', '因为', '所以', '但是', '如果', '就是', '还有', '一个', '没有', '这样', '那样'];

  /** 切章：能识别「第 N 章/节」「# 标题」「1. 标题」三种常见写法 */
  static splitChapters(text: string): Chapter[] {
    const lines = text.split('\n');
    const chapters: Chapter[] = [];
    let cur: Chapter | null = null;
    let order = 0;
    for (const raw of lines) {
      const ln = raw.trim();
      const isHead = /^#{1,4}\s+\S+/.test(ln) ||
        /^第\s*[0-9一二三四五六七八九十]+\s*[章节]\s*\S*/.test(ln) ||
        /^[0-9]+(\.[0-9]+)*\s+\S{1,40}$/.test(ln);
      if (isHead) {
        if (cur) {
          chapters.push(cur);
        }
        order += 1;
        cur = { id: `C${String(order).padStart(2, '0')}`, title: ln.replace(/^#+\s*/, ''), body: '', order: order };
        continue;
      }
      if (cur) {
        cur.body = cur.body ? `${cur.body}\n${ln}` : ln;
      }
    }
    if (cur) {
      chapters.push(cur);
    }
    if (chapters.length === 0) {
      // 完全没有标题：整篇当一章，标题取首行
      const first = text.split('\n').find((s: string) => s.trim().length > 0) ?? '全文';
      chapters.push({ id: 'C01', title: first.trim().slice(0, 30), body: text, order: 1 });
    }
    return chapters;
  }

  /** 抽概念：2–6 字中文片段按词频取前 N 个 */
  static extractTerms(chapters: Chapter[], maxTerms: number): string[] {
    const freq: Map<string, number> = new Map();
    let seq = 0;
    for (const ch of chapters) {
      const body = ch.body ?? '';
      for (let i = 0; i < body.length; i++) {
        const c = body.charAt(i);
        if (!KgService.isCjk(c)) {
          continue;
        }
        for (let len = 2; len <= 6 && i + len <= body.length; len++) {
          const sub = body.substring(i, i + len);
          if (!KgService.isCjk(sub.charAt(len - 1))) {
            break;
          }
          if (KgService.STOP.indexOf(sub) >= 0) {
            continue;
          }
          freq.set(sub, (freq.get(sub) ?? 0) + 1);
        }
      }
      seq += 1;
    }
    const cands: Cand[] = [];
    freq.forEach((count: number, term: string) => {
      // 只保留出现 2 次以上的，避免把偶发短语当概念
      if (count >= 2) {
        cands.push({ term: term, count: count, firstOrder: 0 });
      }
    });
    cands.sort((a: Cand, b: Cand) => b.count - a.count || b.term.length - a.term.length);
    // 去掉被更长高频词包含的短词（如「神经网络」吃掉「神经」）
    const picked: string[] = [];
    for (const c of cands) {
      const covered = picked.some((p: string) => p.includes(c.term));
      if (!covered) {
        picked.push(c.term);
      }
      if (picked.length >= maxTerms) {
        break;
      }
    }
    return picked;
  }

  /** 连边：同一章内，先出现的概念作为后出现概念的先修 */
  static buildEdges(chapters: Chapter[], terms: string[]): KEdge[] {
    const edges: KEdge[] = [];
    const seen: Set<string> = new Set();
    for (const ch of chapters) {
      const body = ch.body ?? '';
      const hit: string[] = [];
      for (const t of terms) {
        const pos = body.indexOf(t);
        if (pos >= 0) {
          hit.push(t);
        }
      }
      for (let i = 0; i + 1 < hit.length && i < 6; i++) {
        const key = `${hit[i]}>${hit[i + 1]}`;
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);
        edges.push({ a: KgService.idOf(hit[i]), b: KgService.idOf(hit[i + 1]), w: 0.8 });
      }
    }
    return edges;
  }

  private static idOf(term: string): string {
    let h = 0;
    for (let i = 0; i < term.length; i++) {
      h = (h * 31 + term.charCodeAt(i)) >>> 0;
    }
    return `N${h.toString(16).toUpperCase().slice(0, 6)}`;
  }

  private static isCjk(ch: string): boolean {
    const code = ch.charCodeAt(0);
    return code >= 0x4e00 && code <= 0x9fff;
  }

  /** 组装成 Book（字段名与 Web 版一致，便于互导） */
  static build(name: string, text: string, maxTerms: number = 24): Book {
    const chapters = KgService.splitChapters(text);
    const terms = KgService.extractTerms(chapters, maxTerms);
    const nodes: KNode[] = [];
    for (let i = 0; i < terms.length; i++) {
      const t: string = terms[i];
      const node: KNode = { id: KgService.idOf(t), title: t, diff: i < terms.length / 3 ? 1 : 2, course: name };
      nodes.push(node);
    }
    return {
      id: `book-${Date.now()}`,
      name: name,
      source: 'text',
      sourceText: text.slice(0, 20000),
      chapters: chapters,
      nodes: nodes,
      edges: KgService.buildEdges(chapters, terms),
      qs: [],
      created: Date.now()
    };
  }
}
