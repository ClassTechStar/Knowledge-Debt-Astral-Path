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
    // 文本层太稀（平均每页不到 50 字）就当作扫描版
    const scanned = chars < 200 && (kind === 'pdf');
    return { kind: kind, text: text, chars: chars, scanned: scanned, note: note };
  }

  private static async parseZip(kind: DocKind, uri: string, outDir: string): Promise<DocResult> {
    try {
      fileIo.mkdirSync(outDir, true);
      await zlib.unzipFile(uri, outDir, {});
      const parts: string[] = [];
      DocService.collect(outDir, parts);
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
   * PDF 文本层抽取：找 stream 块，对未压缩的取 Tj/TJ 里的字符串；
   * 遇到 FlateDecode 的压缩流，鸿蒙侧没有裸 inflate，只能跳过（记为压缩）。
   */
  private static async parsePdf(uri: string): Promise<DocResult> {
    let raw = '';
    try {
      raw = DocService.readAllText(uri);
    } catch (e) {
      return DocService.wrap('pdf', '', '读文件失败');
    }
    const out: string[] = [];
    let compressed = 0;
    const re = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
    let m = re.exec(raw);
    while (m !== null) {
      const body = m[1];
      if (/[^\x20-\x7e\r\n]/.test(body) && !/\((?:[^()\\]|\\.)*\)/.test(body)) {
        // 看起来是二进制（压缩过）的流
        compressed += 1;
        m = re.exec(raw);
        continue;
      }
      const t = DocService.textFromContentStream(body);
      if (t) {
        out.push(t);
      }
      m = re.exec(raw);
    }
    const text = out.join('\n');
    const note = compressed > 0 ? `有 ${compressed} 段压缩流没解（鸿蒙侧无裸 inflate），文本可能不全` : '';
    return DocService.wrap('pdf', text, note);
  }

  /** 从 PDF 内容流里取文本算子 Tj / TJ / ' 的内容，含 UTF-16BE 与转义 */
  private static textFromContentStream(body: string): string {
    const out: string[] = [];
    const re = /\(((?:[^()\\]|\\.)*)\)\s*(?:Tj|'|")|(TJ)/g;
    const arrRe = /\[([\s\S]*?)\]\s*TJ/g;
    let am = arrRe.exec(body);
    while (am !== null) {
      const inner = am[1];
      const strRe = /\(((?:[^()\\]|\\.)*)\)/g;
      let sm = strRe.exec(inner);
      let line = '';
      while (sm !== null) {
        line += DocService.unescapePdf(sm[1]);
        sm = strRe.exec(inner);
      }
      if (line.trim()) {
        out.push(line.trim());
      }
      am = arrRe.exec(body);
    }
    let m = re.exec(body);
    while (m !== null) {
      if (m[1] !== undefined && !m[2]) {
        const s = DocService.unescapePdf(m[1]);
        if (s.trim()) {
          out.push(s.trim());
        }
      }
      m = re.exec(body);
    }
    return out.join('\n');
  }

  private static unescapePdf(s: string): string {
    let r = '';
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      if (c !== '\\') {
        r += c;
        continue;
      }
      const n = s.charAt(i + 1);
      const map: Record<string, string> = { 'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f' };
      if (map[n] !== undefined) {
        r += map[n];
        i += 1;
      } else if (/[0-7]/.test(n)) {
        let oct = n;
        let k = 1;
        while (k < 3 && /[0-7]/.test(s.charAt(i + 1 + k))) {
          oct += s.charAt(i + 1 + k);
          k += 1;
        }
        r += String.fromCharCode(parseInt(oct, 8));
        i += k;
      } else {
        r += n;
        i += 1;
      }
    }
    return r;
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
