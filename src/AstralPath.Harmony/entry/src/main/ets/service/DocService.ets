/**
 * 文档解析服务 —— 对应 Web 版的多格式导入（PDF 文本层、Word、PPT、EPUB、HTML、MD、TXT）。
 *
 * 实现取舍（鸿蒙侧没有 pdf.js，也没有内置 OCR）：
 * - TXT / Markdown：直接读文本
 * - HTML：去标签
 * - DOCX / PPTX / EPUB：本质是 zip，用 @ohos.zlib 的 unzipFile 解到缓存目录，
 *   再取 word/document.xml、ppt/slides/slide*.xml、OEBPS 下的 html/xhtml 去标签
 * - PDF：解析内容流里的 Tj / TJ 文本算子（未压缩或部分压缩可解）；
 *   解不出文本层就判定为「扫描版」，交给 OCR 链路（OcrService）
 *
 * 抽取到的正文统一交给 KgService 分章建图谱，与 Web 版流程一致。
 */
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { PdfText } from './PdfText';

export type DocKind = 'txt' | 'md' | 'html' | 'docx' | 'pptx' | 'epub' | 'pdf' | 'unknown';

export interface DocResult {
  kind: DocKind;
  text: string;
  /** 抽取到的字符数（用于判断文本层是否够用） */
  chars: number;
  /** 是否疑似扫描版（没有可用文本层） */
  scanned: boolean;
  note: string;
}

export class DocService {
  static kindOf(name: string): DocKind {
    const n = name.toLowerCase();
    if (n.endsWith('.pdf')) {
      return 'pdf';
    }
    if (n.endsWith('.docx')) {
      return 'docx';
    }
    if (n.endsWith('.pptx')) {
      return 'pptx';
    }
    if (n.endsWith('.epub')) {
      return 'epub';
    }
    if (n.endsWith('.html') || n.endsWith('.htm')) {
      return 'html';
    }
    if (n.endsWith('.md') || n.endsWith('.markdown')) {
      return 'md';
    }
    if (n.endsWith('.txt')) {
      return 'txt';
    }
    return 'unknown';
  }

  /** 入口：按扩展名分派 */
  static async parse(uri: string, name: string, cacheDir: string): Promise<DocResult> {
    const kind = DocService.kindOf(name);
    if (kind === 'unknown') {
      return { kind: kind, text: '', chars: 0, scanned: false, note: '暂不支持这种格式' };
    }
    if (kind === 'docx' || kind === 'pptx' || kind === 'epub') {
      const out = `${cacheDir}/${Date.now()}_${kind}`;
      return DocService.parseZip(kind, uri, out);
    }
    if (kind === 'pdf') {
      return DocService.parsePdf(uri);
    }
    const raw = DocService.readAllText(uri);
    const text = kind === 'html' ? DocService.stripTags(raw) : raw;
    return DocService.wrap(kind, text, '');
  }

  private static readAllText(uri: string): string {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const size = fileIo.statSync(file.fd).size;
    const buf = new ArrayBuffer(size);
    fileIo.readSync(file.fd, buf);
    fileIo.closeSync(file);
    return new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
  }

  private static wrap(kind: DocKind, text: string, note: string): DocResult {
    const chars = text.replace(/\s/g, '').length;
    // PDF 取不出正文就当扫描版，交给 OCR 链路
    const scanned = chars < 200 && (kind === 'pdf');
    return { kind: kind, text: text, chars: chars, scanned: scanned, note: note };
  }

  private static async parseZip(kind: DocKind, uri: string, outDir: string): Promise<DocResult> {
    try {
      fileIo.mkdirSync(outDir, true);
      // 选择器给的是 URI，unzipFile 只认沙箱路径，先拷一份到缓存目录
      const ext = kind === 'docx' ? '.docx' : (kind === 'pptx' ? '.pptx' : '.epub');
      const local = `${outDir}/src${ext}`;
      fileIo.copyFileSync(uri, local);
      await zlib.unzipFile(local, `${outDir}/unzipped`, {});
      const parts: string[] = [];
      DocService.collect(`${outDir}/unzipped`, parts);
      let xmlFiles: string[] = [];
      if (kind === 'docx') {
        xmlFiles = parts.filter((p: string) => p.endsWith('word/document.xml'));
      } else if (kind === 'pptx') {
        xmlFiles = parts.filter((p: string) => /ppt\/slides\/slide\d+\.xml$/.test(p))
          .sort((a: string, b: string) => DocService.slideNo(a) - DocService.slideNo(b));
      } else {
        xmlFiles = parts.filter((p: string) => /\.(html|xhtml|opf)$/i.test(p) && !/\.(ncx)$/i.test(p))
          .sort((a: string, b: string) => a.length - b.length);
      }
      if (xmlFiles.length === 0) {
        return DocService.wrap(kind, '', '压缩包里没找到正文文件');
      }
      const chunks: string[] = [];
      for (const f of xmlFiles) {
        const t = DocService.readAllText(f);
        chunks.push(DocService.stripTags(t));
      }
      return DocService.wrap(kind, chunks.join('\n\n'), '');
    } catch (e) {
      return DocService.wrap(kind, '', `解压失败：${(e as Error).message}`);
    }
  }

  private static slideNo(p: string): number {
    const m = /slide(\d+)\.xml$/.exec(p);
    return m ? Number(m[1]) : 0;
  }

  /** 递归收集解出来的文件（只收可解析的 xml/html） */
  private static collect(dir: string, out: string[]): void {
    let list: string[] = [];
    try {
      list = fileIo.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of list) {
      const p = `${dir}/${name}`;
      try {
        const st = fileIo.statSync(p);
        if (st.isDirectory()) {
          DocService.collect(p, out);
        } else if (/\.(xml|html|xhtml|opf)$/i.test(p)) {
          out.push(p);
        }
      } catch (e) {
        // 跳过读不到的条目
      }
    }
  }

  /**
   * PDF 文本层抽取：交给 PdfText（Flate 解压 + CID 十六进制 Tj + ToUnicode 映射）。
   * 大文件只读前 PdfText.MAX_BYTES，避免 400MB 整本进内存。
   */
  private static async parsePdf(uri: string): Promise<DocResult> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const st = fileIo.statSync(file.fd);
      const want = Math.min(st.size, PdfText.MAX_BYTES);
      const buf = new ArrayBuffer(want);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);
      const res = PdfText.extract(new Uint8Array(buf));
      const note = st.size > PdfText.MAX_BYTES
        ? `文件 ${(st.size / 1048576).toFixed(0)}MB，只解析了前 ${(PdfText.MAX_BYTES / 1048576).toFixed(0)}MB`
        : res.note;
      return DocService.wrap('pdf', res.text, note);
    } catch (e) {
      return DocService.wrap('pdf', '', `读文件失败：${(e as Error).message}`);
    }
  }

  /** 去 HTML/XML 标签，保留文本 */
  static stripTags(html: string): string {
    let s = html.replace(/<script[\s\S]*?<\/script>/gi, ' ');
    s = s.replace(/<style[\s\S]*?<\/style>/gi, ' ');
    s = s.replace(/<[^>]+>/g, '\n');
    s = s.replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
    s = s.replace(/\n{3,}/g, '\n\n');
    return s.trim();
  }
}
