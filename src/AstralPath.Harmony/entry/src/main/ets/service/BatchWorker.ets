/**
 * 批量测试的后台执行体 —— PDF 解析与建图都很重，必须放后台线程，
 * 否则会把 UI 线程冻住（实测：连跑十来个文件就触发 appfreeze）。
 *
 * 用 @Concurrent + taskpool：ArkTS 里这是把重活移出主线程的标准做法。
 */
import { taskpool } from '@kit.ArkTS';
import { PdfText } from './PdfText';
import { KgService } from './KgService';
import { Book, KNode, KEdge } from '../model/Models';
import { pdfService } from '@kit.PDFKit';

export interface HeavyResult {
  chars: number;
  scanned: boolean;
  nodes: number;
  edges: number;
  chapters: number;
  note: string;
  /** 图谱数据，供 BatchTest 存入 StoreService 让识网页展示 */
  bookNodes: KNode[];
  bookEdges: KEdge[];
}

export interface HeavyInput {
  name: string;
  bytes: ArrayBuffer;
  /** 本地路径（PDFKit 要按路径打开；为空则不做 PDFKit 提取） */
  path: string;
}

export interface KitTextResult {
  ok: boolean;
  text: string;
  pages: number;
  tried: number;
  note: string;
}

/** 后台线程里用 PDFKit 取文本：loadDocument 是同步重活，绝不能放主线程 */
@Concurrent
export function pdfKitTextInWorker(path: string, maxPages: number): KitTextResult {
  const out: KitTextResult = { ok: false, text: '', pages: 0, tried: 0, note: '' };
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    doc.loadDocument(path);
    const total = doc.getPageCount();
    out.pages = total;
    const n = Math.min(total, maxPages);
    const chunks: string[] = [];
    for (let i = 0; i < n; i++) {
      out.tried += 1;
      try {
        const t = doc.getPage(i).getTextContent();
        if (t && t.trim().length > 0) {
          chunks.push(t);
        }
      } catch (e) {
        // 单页失败跳过
      }
    }
    out.text = chunks.join('\n');
    out.ok = out.text.replace(/\s/g, '').length > 0;
    return out;
  } catch (e) {
    out.note = `PDFKit 失败：${(e as Error).message}`;
    return out;
  } finally {
    if (doc) {
      try {
        doc.releaseDocument();
      } catch (e) {
        // 忽略
      }
    }
  }
}

@Concurrent
export function processPdfInWorker(input: HeavyInput): HeavyResult {
  const name = input.name;
  const bytes = new Uint8Array(input.bytes);
  let text = '';
  let note = '';
  let chars = 0;
  if (name.toLowerCase().endsWith('.pdf')) {
    const res = PdfText.extract(bytes);
    text = res.text;
    chars = res.chars;
    note = res.note;
  } else {
    // 非 PDF：当 UTF-8 文本读（够测试用）
    const arr: string[] = [];
    const step = 65536;
    for (let i = 0; i < bytes.length; i += step) {
      const end = Math.min(i + step, bytes.length);
      const piece: string[] = new Array(end - i);
      for (let j = i; j < end; j++) {
        piece[j - i] = String.fromCharCode(bytes[j]);
      }
      arr.push(piece.join(''));
    }
    text = arr.join('');
    chars = text.replace(/\s/g, '').length;
  }
  const scanned = name.toLowerCase().endsWith('.pdf') && chars < 200;
  let nodes = 0;
  let edges = 0;
  let chapters = 0;
  if (text && text.trim().length >= 20) {
    const book = KgService.build(name, text);
    nodes = book.nodes.length;
    edges = book.edges.length;
    chapters = book.chapters ? book.chapters.length : 0;
  }
  let bookNodes: KNode[] = [];
  let bookEdges: KEdge[] = [];
  if (text && text.trim().length >= 20) {
    const book = KgService.build(name, text);
    bookNodes = book.nodes;
    bookEdges = book.edges;
  }
  const out: HeavyResult = {
    chars: chars,
    scanned: scanned,
    nodes: nodes,
    edges: edges,
    chapters: chapters,
    note: note,
    bookNodes: bookNodes,
    bookEdges: bookEdges
  };
  return out;
}

export class BatchWorker {
  static async run(input: HeavyInput): Promise<HeavyResult> {
    const task = new taskpool.Task(processPdfInWorker, input);
    const r = await taskpool.execute(task);
    return r as HeavyResult;
  }

  /** 后台线程跑 PDFKit 取文本 */
  static async kitText(path: string, maxPages: number): Promise<KitTextResult> {
    const task = new taskpool.Task(pdfKitTextInWorker, path, maxPages);
    const r = await taskpool.execute(task);
    return r as KitTextResult;
  }
}
