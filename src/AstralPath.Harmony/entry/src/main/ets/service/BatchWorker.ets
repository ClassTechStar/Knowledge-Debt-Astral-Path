/**
 * 批量测试的后台执行体 —— PDF 解析与建图都很重，必须放后台线程，
 * 否则会把 UI 线程冻住（实测：连跑十来个文件就触发 appfreeze）。
 *
 * 用 @Concurrent + taskpool：ArkTS 里这是把重活移出主线程的标准做法。
 */
import { taskpool } from '@kit.ArkTS';
import { PdfText } from './PdfText';
import { KgService } from './KgService';

export interface HeavyResult {
  chars: number;
  scanned: boolean;
  nodes: number;
  edges: number;
  chapters: number;
  note: string;
}

export interface HeavyInput {
  name: string;
  bytes: ArrayBuffer;
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
  const out: HeavyResult = {
    chars: chars,
    scanned: scanned,
    nodes: nodes,
    edges: edges,
    chapters: chapters,
    note: note
  };
  return out;
}

export class BatchWorker {
  static async run(input: HeavyInput): Promise<HeavyResult> {
    const task = new taskpool.Task(processPdfInWorker, input);
    const r = await taskpool.execute(task);
    return r as HeavyResult;
  }
}
