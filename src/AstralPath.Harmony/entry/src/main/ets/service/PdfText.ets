/**
 * PDF 文本抽取 —— 面向「构建知识图谱」的轻量提取器，不追求排版还原。
 *
 * 真实教材 PDF 的坑（本项目实测踩过）：
 * ① 内容流是 zlib 格式（0x78 0x9C 头）而非裸 deflate；
 * ② ToUnicode 映射表（beginbfchar / beginbfrange）也藏在压缩流里；
 * ③ 字体/图片流是二进制，里面会「碰巧」出现 BT/Tj 字节，必须按 ASCII 占比过滤；
 * ④ 文本算子是 CID 十六进制串（<001C0011...> Tj），要靠映射表还原成汉字。
 */
import { Inflate } from './Inflate';

export interface PdfExtract {
  text: string;
  chars: number;
  streams: number;
  inflated: number;
  cmaps: number;
  note: string;
}

export class PdfText {
  /** 大文件只取前这么多字节（避免 400MB 整本进内存） */
  static readonly MAX_BYTES: number = 96 * 1024 * 1024;

  static extract(bytes: Uint8Array): PdfExtract {
    // 第一遍：解压所有流，分出「映射表」与「内容流」
    const map: Map<number, string> = new Map();
    const contents: string[] = [];
    let streams = 0;
    let inflated = 0;
    let pos = 0;
    const marker = PdfText.toBytes('stream');
    const endMark = PdfText.toBytes('endstream');
    while (pos < bytes.length) {
      const s = PdfText.findStreamMarker(bytes, marker, pos);
      if (s < 0) {
        break;
      }
      let start = s + marker.length;
      if (bytes[start] === 13) {
        start += 1;
      }
      if (bytes[start] === 10) {
        start += 1;
      }
      const e = PdfText.indexOf(bytes, endMark, start);
      if (e < 0) {
        break;
      }
      pos = e;
      streams += 1;
      let body = bytes.subarray(start, e);
      try {
        body = Inflate.raw(body);
        inflated += 1;
      } catch (err) {
        // 解不动就用原始字节（未压缩流）
      }
      // 字体/图片流是二进制；只有明文流才可能是内容流或 CMap
      if (PdfText.binaryish(body)) {
        continue;
      }
      const txt = PdfText.ascii(body);
      if (txt.indexOf('beginbfchar') >= 0 || txt.indexOf('beginbfrange') >= 0) {
        PdfText.parseCMapBlock(txt, map);
      } else if (txt.indexOf('BT') >= 0 && (txt.indexOf('Tj') >= 0 || txt.indexOf('TJ') >= 0)) {
        contents.push(txt);
      }
    }
    // 第二遍：按映射表解出文字
    const chunks: string[] = [];
    for (const c of contents) {
      const t = PdfText.textFromStream(c, map);
      if (t) {
        chunks.push(t);
      }
    }
    const text = chunks.join('\n');
    const chars = text.replace(/\s/g, '').length;
    return {
      text: text,
      chars: chars,
      streams: streams,
      inflated: inflated,
      cmaps: map.size,
      note: chunks.length === 0 ? '没从内容流里取到文本（可能是扫描版）' : ''
    };
  }

  private static parseCMapBlock(seg: string, map: Map<number, string>): void {
    const b = seg.indexOf('beginbfchar');
    if (b >= 0) {
      const stop = seg.indexOf('endbfchar', b);
      PdfText.parseBfChar(seg.substring(b, stop < 0 ? seg.length : stop), map);
    }
    const r = seg.indexOf('beginbfrange');
    if (r >= 0) {
      const stop = seg.indexOf('endbfrange', r);
      PdfText.parseBfRange(seg.substring(r, stop < 0 ? seg.length : stop), map);
    }
  }

  private static parseBfChar(seg: string, map: Map<number, string>): void {
    const re = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g;
    let m = re.exec(seg);
    while (m !== null) {
      map.set(parseInt(m[1], 16), PdfText.hexToStr(m[2]));
      m = re.exec(seg);
    }
  }

  private static parseBfRange(seg: string, map: Map<number, string>): void {
    // <0000> <005E> <0020>   或   <0000> <0003> [<0020> <0021> <0022> <0023>]
    const re = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(\[([^\]]*)\]|<([0-9A-Fa-f]+)>)/g;
    let m = re.exec(seg);
    while (m !== null) {
      const lo = parseInt(m[1], 16);
      const hi = parseInt(m[2], 16);
      if (m[4] !== undefined) {
        const items = m[4].match(/<([0-9A-Fa-f]+)>/g) ?? [];
        for (let i = 0; i < items.length && lo + i <= hi; i++) {
          const one = items[i];
          map.set(lo + i, PdfText.hexToStr(one.substring(1, one.length - 1)));
        }
      } else if (m[5] !== undefined) {
        const base = parseInt(m[5], 16);
        const span = Math.min(hi - lo, 65535);
        for (let i = 0; i <= span; i++) {
          map.set(lo + i, String.fromCodePoint(base + i));
        }
      }
      m = re.exec(seg);
    }
  }

  /** ToUnicode 的值是 UTF-16BE */
  private static hexToStr(h: string): string {
    let out = '';
    for (let i = 0; i + 3 < h.length + 1; i += 4) {
      const code = parseInt(h.substring(i, i + 4), 16);
      if (!isNaN(code) && code !== 0) {
        out += String.fromCharCode(code);
      }
    }
    return out;
  }

  /** 从一段内容流文本里取 Tj / TJ / ' 的内容 */
  private static textFromStream(s: string, map: Map<number, string>): string {
    const out: string[] = [];
    const re = /<([0-9A-Fa-f\s]+)>\s*(?:Tj|TJ|')|\[((?:[^\[\]]|\\\])*)\]\s*TJ|\(((?:[^()\\]|\\.)*)\)\s*(?:Tj|'|")/g;
    let m = re.exec(s);
    while (m !== null) {
      if (m[1] !== undefined) {
        out.push(PdfText.decodeHex(m[1].replace(/\s/g, ''), map));
      } else if (m[2] !== undefined) {
        const inner = m[2];
        const hx = /<([0-9A-Fa-f\s]+)>/g;
        let h = hx.exec(inner);
        let line = '';
        while (h !== null) {
          line += PdfText.decodeHex(h[1].replace(/\s/g, ''), map);
          h = hx.exec(inner);
        }
        if (line) {
          out.push(line);
        }
      } else if (m[3] !== undefined) {
        out.push(PdfText.unescapePdf(m[3]));
      }
      m = re.exec(s);
    }
    return out.join('\n');
  }

  /** 十六进制 CID 串 → 文字（查不到的按 Latin-1 兜底） */
  private static decodeHex(hex: string, map: Map<number, string>): string {
    let out = '';
    const step = hex.length % 4 === 0 ? 4 : 2;
    for (let i = 0; i + step <= hex.length; i += step) {
      const cid = parseInt(hex.substring(i, i + step), 16);
      const t = map.get(cid);
      if (t !== undefined) {
        out += t;
      } else if (cid >= 32 && cid < 127) {
        out += String.fromCharCode(cid);
      }
    }
    return out;
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

  // ── 小工具 ─────────────────────────────────────────────
  private static toBytes(s: string): Uint8Array {
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) {
      out[i] = s.charCodeAt(i) & 0xff;
    }
    return out;
  }

  /**
   * 定位真正的 stream 关键字：必须后跟换行、前面是 '>' 或空白、且不是 endstream。
   * 二进制流里随机拼出的 "stream" 会被这条规则挡掉（实测踩过：不挡会切出 6000 个假流）。
   */
  private static findStreamMarker(bytes: Uint8Array, marker: Uint8Array, from: number): number {
    let pos = from;
    for (;;) {
      const s = PdfText.indexOf(bytes, marker, pos);
      if (s < 0) {
        return -1;
      }
      const prevOk = s === 0 || bytes[s - 1] === 62 || bytes[s - 1] === 9 ||
        bytes[s - 1] === 10 || bytes[s - 1] === 13 || bytes[s - 1] === 32;
      const nextOk = s + marker.length < bytes.length &&
        (bytes[s + marker.length] === 10 || bytes[s + marker.length] === 13);
      const notEnd = !(s >= 3 && bytes[s - 3] === 101 && bytes[s - 2] === 110 && bytes[s - 1] === 100);
      if (prevOk && nextOk && notEnd) {
        return s;
      }
      pos = s + marker.length;
    }
  }

  private static indexOf(hay: Uint8Array, needle: Uint8Array, from: number): number {
    const n = needle.length;
    if (n === 0) {
      return from;
    }
    for (let i = Math.max(0, from); i + n <= hay.length; i++) {
      let ok = true;
      for (let j = 0; j < n; j++) {
        if (hay[i + j] !== needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 字节转字符串。必须用「数组 + join」：
   * 逐字符 `part +=` 是 O(n²)，6MB 流会卡死在字符串拷贝上（实测踩过）。
   */
  private static ascii(b: Uint8Array): string {
    const step = 65536;
    const chunks: string[] = [];
    for (let i = 0; i < b.length; i += step) {
      const end = Math.min(i + step, b.length);
      const arr: string[] = new Array(end - i);
      for (let j = i; j < end; j++) {
        arr[j - i] = String.fromCharCode(b[j]);
      }
      chunks.push(arr.join(''));
    }
    return chunks.join('');
  }

  /** 明文流判定：内容流/CMap 是可打印 ASCII，字体与图片是二进制 */
  private static binaryish(b: Uint8Array): boolean {
    const n = Math.min(b.length, 1024);
    if (n === 0) {
      return true;
    }
    let bad = 0;
    for (let i = 0; i < n; i++) {
      const c = b[i];
      if (c === 9 || c === 10 || c === 13) {
        continue;
      }
      if (c < 32 || c > 126) {
        bad += 1;
      }
    }
    return bad > n / 8;
  }
}
