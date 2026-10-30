/**
 * PDF 页图抽取 —— 扫描版 PDF 的每一页其实就是一张图，不必渲染整页，
 * 直接把内嵌图像流抠出来交给 OCR 就行。
 *
 * 支持情况（按实测的教材扫描件）：
 * - DCTDecode（JPEG）：流本身就是完整 JPEG 文件，落盘即可解码 → 主路径
 * - FlateDecode + 8bit RGB/Gray：解压得到原始像素，交给 image.createPixelMap
 * - JBIG2Decode / CCITTFaxDecode / JPXDecode：需要专门的解码器，鸿蒙侧没有 → 明确不支持
 *
 * 取舍：只取每页第一张大图（扫描页就是一整页图），最多取 maxPages 页。
 */

export interface PdfImageInfo {
  xrefLike: number;
  filter: string;
  width: number;
  height: number;
  bpc: number;
  colorSpace: string;
  /** 在原始字节里的起止位置 */
  start: number;
  end: number;
  supported: boolean;
}

export class PdfImage {
  /** 每份 PDF 最多处理这么多页，控制耗时 */
  static readonly MAX_PAGES: number = 12;

  /** 扫描内嵌图像对象（靠 /Subtype/Image 定位） */
  static scan(bytes: Uint8Array, maxPages: number): PdfImageInfo[] {
    const out: PdfImageInfo[] = [];
    const text = PdfImage.latin1(bytes);
    const re = /\/Subtype\s*\/Image/g;
    let m = re.exec(text);
    while (m !== null && out.length < maxPages) {
      // 字典起点必须锚在最近的「<<」上：用固定窗口会把上一个对象的
      // /Filter 读进来（实测踩过：DCTDecode 的图被误判成 JBIG2）
      const before = text.substring(Math.max(0, m.index - 4096), m.index);
      const openIdx = before.lastIndexOf('<<');
      const dictStart = openIdx >= 0 ? Math.max(0, m.index - 4096) + openIdx : Math.max(0, m.index - 512);
      const dict = text.substring(dictStart, Math.min(text.length, m.index + 2048));
      const sIdx = dict.indexOf('stream', m.index - dictStart);
      if (sIdx < 0) {
        m = re.exec(text);
        continue;
      }
      const absStream = dictStart + sIdx;
      let bodyStart = absStream + 6;
      if (bytes[bodyStart] === 13) {
        bodyStart += 1;
      }
      if (bytes[bodyStart] === 10) {
        bodyStart += 1;
      }
      const endIdx = PdfImage.indexOf(bytes, PdfImage.toBytes('endstream'), bodyStart);
      if (endIdx < 0) {
        break;
      }
      const filter = PdfImage.pick(dict, /\/Filter\s*\/(\w+)/) ||
        PdfImage.pick(dict, /\/Filter\s*\[\s*\/(\w+)/) || 'none';
      const width = Number(PdfImage.pick(dict, /\/Width\s+(\d+)/) || '0');
      const height = Number(PdfImage.pick(dict, /\/Height\s+(\d+)/) || '0');
      const bpc = Number(PdfImage.pick(dict, /\/BitsPerComponent\s+(\d+)/) || '8');
      const csRaw = PdfImage.pick(dict, /\/ColorSpace\s*\/(\w+)/) || 'DeviceRGB';
      const big = width * height >= 200000; // 约 450x450 以上才算整页图
      const supported = big && (filter === 'DCTDecode' ||
        (filter === 'FlateDecode' && bpc === 8 &&
          (csRaw === 'DeviceRGB' || csRaw === 'DeviceGray')));
      out.push({
        xrefLike: m.index,
        filter: filter,
        width: width,
        height: height,
        bpc: bpc,
        colorSpace: csRaw,
        start: bodyStart,
        end: endIdx,
        supported: supported
      });
      m = re.exec(text);
    }
    return out;
  }

  private static pick(s: string, re: RegExp): string {
    const m = re.exec(s);
    return m ? m[1] : '';
  }

  private static toBytes(s: string): Uint8Array {
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) {
      out[i] = s.charCodeAt(i) & 0xff;
    }
    return out;
  }

  private static indexOf(hay: Uint8Array, needle: Uint8Array, from: number): number {
    const n = needle.length;
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

  /** 按字节读成 latin1 字符串（只为定位结构，不做编码转换） */
  private static latin1(b: Uint8Array): string {
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
}
