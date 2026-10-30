/**
 * 批量解析测试 —— 一次性跑完指定目录下的所有资料，输出每份的解析与建图结果。
 *
 * 用途：OCR / 知识图谱的回归验证（本机把测试资料推到 /data/local/tmp/pdftest/）。
 * 结果一行一条打到 hilog（TAG: BATCH），界面只给汇总，方便截图留档。
 */
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { DocService, DocResult } from './DocService';
import { KgService } from './KgService';
import { OcrService } from './OcrService';
import { SanitizeService } from './SanitizeService';
import { Book, KNode, KEdge } from '../model/Models';
import { StoreService } from './StoreService';
import { BatchWorker, HeavyResult } from './BatchWorker';

export interface BatchItem {
  name: string;
  bytes: number;
  chars: number;
  scanned: boolean;
  ocr: string;
  nodes: number;
  edges: number;
  chapters: number;
  note: string;
  bookNodes: KNode[];
  bookEdges: KEdge[];
}

export class BatchTest {
  static readonly DIR: string = '/data/local/tmp/pdftest';
  /** 宿主机静态服务（QEMU NAT 里 10.0.2.2 就是宿主机） */
  static readonly HTTP_BASE: string = 'http://10.0.2.2:8778/';
  /** 单个文件最多取这么多字节（与 PdfText.MAX_BYTES 同量级，控制流量） */
  static readonly FETCH_MAX: number = 6 * 1024 * 1024;

  /** 从 HTTP 目录取文件清单（python -m http.server 的目录页） */
  private static async listRemote(): Promise<string[]> {
    const req = http.createHttp();
    try {
      const res = await new Promise<http.HttpResponse>((resolve, reject) => {
        req.request(BatchTest.HTTP_BASE, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING
        }, (err: Error, data: http.HttpResponse) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      const html = res.result as string;
      const out: string[] = [];
      const re = /href="([^"]+)"/g;
      let m = re.exec(html);
      while (m !== null) {
        const h = decodeURIComponent(m[1]);
        const low = h.toLowerCase();
        const usable = low.endsWith('.pdf') || low.endsWith('.png') || low.endsWith('.jpg') || low.endsWith('.jpeg');
        if (usable && out.indexOf(h) < 0) {
          out.push(h);
        }
        m = re.exec(html);
      }
      out.sort();
      return out;
    } catch (e) {
      hilog.error(0x0000, 'BATCH', `取清单失败: ${(e as Error).message}`);
      return [];
    } finally {
      req.destroy();
    }
  }

  /** 下载一个文件（带 Range 上限）到缓存目录，返回本地路径 */
  private static async fetchOne(name: string, destDir: string): Promise<string> {
    const req = http.createHttp();
    try {
      const res = await new Promise<http.HttpResponse>((resolve, reject) => {
        req.request(BatchTest.HTTP_BASE + encodeURIComponent(name), {
          method: http.RequestMethod.GET,
          header: { 'Range': `bytes=0-${BatchTest.FETCH_MAX - 1}` },
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        }, (err: Error, data: http.HttpResponse) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      const buf = res.result as ArrayBuffer;
      const path = `${destDir}/${name.replace(/[/\\:*?"<>|]/g, '_')}`;
      // openSync 返回的是 File 对象，写入要用 .fd
      const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, buf);
      fileIo.closeSync(f.fd);
      return path;
    } finally {
      req.destroy();
    }
  }

  /** HTTP 模式：拉取 → 解析 → 建图（沙箱外目录读不到时用这条） */
  static async runHttp(ctx: common.UIAbilityContext): Promise<BatchItem[]> {
    const out: BatchItem[] = [];
    const dest = `${ctx.cacheDir}/btest`;
    try {
      fileIo.mkdirSync(dest, true);
    } catch (e) {
      // 已存在
    }
    const names = await BatchTest.listRemote();
    hilog.info(0x0000, 'BATCH', `HTTP 模式：清单 ${names.length} 个，逐个拉取解析`);
    const lines: string[] = [];
    for (const name of names) {
      const item: BatchItem = {
        name: name, bytes: 0, chars: 0, scanned: false, ocr: '-',
        nodes: 0, edges: 0, chapters: 0, note: '', bookNodes: [], bookEdges: []
      };
      try {
        const local = await BatchTest.fetchOne(name, dest);
        const st = fileIo.statSync(local);
        item.bytes = st.size;
        // 读出字节交给后台线程做解析+建图，主线程只做 IO（否则会 appfreeze）
        const f = fileIo.openSync(local, fileIo.OpenMode.READ_ONLY);
        const buf = new ArrayBuffer(st.size);
        fileIo.readSync(f.fd, buf);
        fileIo.closeSync(f.fd);
        const r: HeavyResult = await BatchWorker.run({ name: name, bytes: buf });
        item.chars = r.chars;
        item.scanned = r.scanned;
        item.note = r.note;
        item.nodes = r.nodes;
        item.edges = r.edges;
        item.chapters = r.chapters;
        item.bookNodes = r.bookNodes;
        item.bookEdges = r.bookEdges;
        const isImage = /\.(png|jpg|jpeg|bmp|webp)$/i.test(name);
        if (isImage) {
          // 图片直接走 OCR（扫描版 PDF 要先栅格化，这里先用图片验证引擎本身）
          const o = await OcrService.recognize(local);
          item.ocr = o.ok ? `OK(${o.engine},${o.text.length}字)` : `失败(${o.engine}): ${o.note}`;
          if (o.ok) {
            item.chars = o.text.replace(/\s/g, '').length;
            item.scanned = false;
            const book = KgService.build(name, o.text);
            item.nodes = book.nodes.length;
            item.edges = book.edges.length;
            item.chapters = book.chapters ? book.chapters.length : 0;
          }
        } else if (OcrService.needOcr(r.chars, r.scanned)) {
          const o = await OcrService.recognize(local);
          item.ocr = o.ok ? `OK(${o.engine})` : `失败(${o.engine}): ${o.note}`;
        } else {
          item.ocr = '不需要';
        }
        try {
          fileIo.unlinkSync(local);
        } catch (e) {
          // 忽略
        }
      } catch (e) {
        item.note = `异常：${(e as Error).message}`;
      }
      out.push(item);
      const line = `RESULT | ${name} | ${(item.bytes / 1048576).toFixed(1)}MB | chars=${item.chars}` +
        ` | scanned=${item.scanned} | ocr=${item.ocr} | ch=${item.chapters}` +
        ` | node=${item.nodes} | edge=${item.edges} | ${item.note}`;
      lines.push(line);
      hilog.info(0x0000, 'BATCH', line);
    }
    // 把节点最多的那份图谱存入 StoreService，识网页可直接查看
    try {
      let bestNodes: KNode[] = [];
      let bestEdges: KEdge[] = [];
      let bestName = '';
      let bestCount = 0;
      for (const it of out) {
        if (it.nodes > bestCount && it.bookNodes.length > 0) {
          bestCount = it.nodes;
          bestNodes = it.bookNodes;
          bestEdges = it.bookEdges;
          bestName = it.name;
        }
      }
      if (bestNodes.length > 0) {
        const book: Book = {
          id: `batch-${Date.now()}`,
          name: `${bestName}（批量导入）`,
          source: 'batch',
          nodes: bestNodes,
          edges: bestEdges,
          qs: [],
          created: Date.now()
        };
        const books = await StoreService.loadBooks();
        books.push(book);
        await StoreService.saveBooks(books);
        const meta = await StoreService.loadMeta();
        meta.activeBookId = book.id;
        await StoreService.saveMeta(meta);
        hilog.info(0x0000, 'BATCH', `已导入图谱：${bestName}（${bestNodes.length} 节点 ${bestEdges.length} 边）`);
      }
    } catch (e) {
      hilog.error(0x0000, 'BATCH', `导入图谱失败: ${(e as Error).message}`);
    }

    // 落文件：hilog 会被轮转，明细以文件为准
    try {
      const outPath = `${ctx.cacheDir}/btest_results.txt`;
      const f = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, lines.join('\n'));
      fileIo.closeSync(f.fd);
      hilog.info(0x0000, 'BATCH', `结果已写入 ${outPath}`);
    } catch (e) {
      hilog.error(0x0000, 'BATCH', `写结果文件失败: ${(e as Error).message}`);
    }
    return out;
  }

  static async run(ctx: common.UIAbilityContext): Promise<BatchItem[]> {
    const out: BatchItem[] = [];
    const lines: string[] = [];
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(BatchTest.DIR);
    } catch (e) {
      hilog.error(0x0000, 'BATCH', `读目录失败 ${BatchTest.DIR}: ${(e as Error).message}`);
      return out;
    }
    names.sort();
    for (const name of names) {
      const uri = `${BatchTest.DIR}/${name}`;
      const item: BatchItem = {
        name: name,
        bytes: 0,
        chars: 0,
        scanned: false,
        ocr: '-',
        nodes: 0,
        edges: 0,
        chapters: 0,
        note: '',
        bookNodes: [],
        bookEdges: []
      };
      try {
        const st = fileIo.statSync(uri);
        item.bytes = st.size;
        const doc: DocResult = await DocService.parse(uri, name, ctx.cacheDir);
        item.chars = doc.chars;
        item.scanned = doc.scanned;
        item.note = doc.note;
        let text = SanitizeService.mask(doc.text);
        if (OcrService.needOcr(doc.chars, doc.scanned)) {
          const r = await OcrService.recognize(uri);
          item.ocr = r.ok ? `OK(${r.engine})` : `不可用(${r.engine})`;
          if (r.ok) {
            text = SanitizeService.mask(r.text);
          }
        } else {
          item.ocr = '不需要';
        }
        if (text && text.trim().length >= 20) {
          const book: Book = KgService.build(name, text);
          item.nodes = book.nodes.length;
          item.edges = book.edges.length;
          item.chapters = book.chapters ? book.chapters.length : 0;
        }
      } catch (e) {
        item.note = `异常：${(e as Error).message}`;
      }
      out.push(item);
      const line = `RESULT | ${name} | ${(item.bytes / 1048576).toFixed(1)}MB | chars=${item.chars}` +
        ` | scanned=${item.scanned} | ocr=${item.ocr} | ch=${item.chapters}` +
        ` | node=${item.nodes} | edge=${item.edges} | ${item.note}`;
      lines.push(line);
      hilog.info(0x0000, 'BATCH', line);
    }
    // 把节点最多的那份图谱存入 StoreService，识网页可直接查看
    try {
      let bestNodes: KNode[] = [];
      let bestEdges: KEdge[] = [];
      let bestName = '';
      let bestCount = 0;
      for (const it of out) {
        if (it.nodes > bestCount && it.bookNodes.length > 0) {
          bestCount = it.nodes;
          bestNodes = it.bookNodes;
          bestEdges = it.bookEdges;
          bestName = it.name;
        }
      }
      if (bestNodes.length > 0) {
        const book: Book = {
          id: `batch-${Date.now()}`,
          name: `${bestName}（批量导入）`,
          source: 'batch',
          nodes: bestNodes,
          edges: bestEdges,
          qs: [],
          created: Date.now()
        };
        const books = await StoreService.loadBooks();
        books.push(book);
        await StoreService.saveBooks(books);
        const meta = await StoreService.loadMeta();
        meta.activeBookId = book.id;
        await StoreService.saveMeta(meta);
        hilog.info(0x0000, 'BATCH', `已导入图谱：${bestName}（${bestNodes.length} 节点 ${bestEdges.length} 边）`);
      }
    } catch (e) {
      hilog.error(0x0000, 'BATCH', `导入图谱失败: ${(e as Error).message}`);
    }

    // 落文件：hilog 会被轮转，明细以文件为准
    try {
      const outPath = `${ctx.cacheDir}/btest_results.txt`;
      const f = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, lines.join('\n'));
      fileIo.closeSync(f.fd);
      hilog.info(0x0000, 'BATCH', `结果已写入 ${outPath}`);
    } catch (e) {
      hilog.error(0x0000, 'BATCH', `写结果文件失败: ${(e as Error).message}`);
    }
    return out;
  }
}
