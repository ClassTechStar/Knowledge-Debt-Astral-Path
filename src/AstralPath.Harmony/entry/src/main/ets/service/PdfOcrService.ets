/**
 * 扫描版 PDF 的 OCR 链路 —— 「抽页图 → 逐页识别 → 拼文本」。
 *
 * 不走整页渲染（pdfium/mupdf 要 NDK 交叉编译 + 一堆依赖，代价太大），
 * 而是直接把 PDF 内嵌的页图抠出来：扫描件的一页本来就是一整张图。
 *
 * 支持的编码见 PdfImage；遇到 JBIG2 这类没有解码器的，如实返回不支持，
 * 不假装识别过。
 */
import { fileIo } from '@kit.CoreFileKit';
import { PdfImage, PdfImageInfo } from './PdfImage';
import { Inflate } from './Inflate';
import { PdfKitClient, KitResp } from './PdfKitClient';
import { OcrService, OcrResult } from './OcrService';

export interface PdfOcrResult {
  ok: boolean;
  text: string;
  pages: number;
  supported: number;
  skipped: number;
  engine: string;
  note: string;
}

export class PdfOcrService {
  /** 对一份扫描版 PDF 做 OCR：抽前 N 页的页图逐页识别 */
  static async recognize(pdfPath: string, cacheDir: string, maxPages: number): Promise<PdfOcrResult> {
    const out: PdfOcrResult = {
      ok: false, text: '', pages: 0, supported: 0, skipped: 0,
      engine: OcrService.engineName(), note: ''
    };
    if (!OcrService.available()) {
      out.note = 'OCR 引擎不可用';
      return out;
    }
    const bytes = PdfOcrService.readAll(pdfPath);
    if (bytes.length === 0) {
      out.note = '读文件失败';
      return out;
    }
    const images: PdfImageInfo[] = PdfImage.scan(bytes, maxPages);
    out.pages = images.length;
    if (images.length === 0) {
      out.note = '没找到内嵌页图';
      return out;
    }
    const chunks: string[] = [];
    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      if (!img.supported) {
        out.skipped += 1;
        continue;
      }
      // DCTDecode 的流本身就是 JPEG；FlateDecode 要先解压再包成 BMP
      let imgPath = '';
      try {
        const slice = bytes.subarray(img.start, img.end);
        if (img.filter === 'DCTDecode') {
          imgPath = `${cacheDir}/ocrpage_${i}.jpg`;
          const f = fileIo.openSync(imgPath,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          fileIo.writeSync(f.fd, slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength));
          fileIo.closeSync(f.fd);
        } else {
          const raw = Inflate.raw(slice);
          const bmp = PdfOcrService.toBmp(raw, img.width, img.height, img.colorSpace);
          imgPath = `${cacheDir}/ocrpage_${i}.bmp`;
          const f = fileIo.openSync(imgPath,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          fileIo.writeSync(f.fd, bmp.buffer);
          fileIo.closeSync(f.fd);
        }
      } catch (e) {
        out.skipped += 1;
        continue;
      }
      const jpgPath = imgPath;
      const r: OcrResult = await OcrService.recognize(jpgPath);
      if (r.ok && r.text.length > 0) {
        chunks.push(r.text);
        out.supported += 1;
      } else {
        out.skipped += 1;
        if (r.note && !out.note) {
          out.note = r.note;
        }
      }
      // OCR 失败时保留第一张页图，方便核对「图抽出来是对的、只是识别不了」
      if (r.ok || i > 0) {
        try {
          fileIo.unlinkSync(jpgPath);
        } catch (e) {
          // 忽略
        }
      }
    }
    out.text = chunks.join('\n');
    out.ok = out.text.length > 0;
    if (out.ok) {
      return out;
    }
    // 自研抽图搞不定（典型是 JBIG2）→ 交给 PDFKit 渲染，它支持全部编码
    const rendered = await PdfOcrService.viaPdfKit(pdfPath, cacheDir, maxPages);
    if (rendered.ok) {
      return rendered;
    }
    if (!out.note) {
      out.note = out.skipped > 0 ? `页图编码不受支持（如 JBIG2），PDFKit 也未取到：${rendered.note}` : '识别未产出文本';
    }
    return out;
  }

  /** 用 PDFKit 渲染页图再 OCR（JBIG2/CCITT 都能渲染） */
  private static async viaPdfKit(pdfPath: string, cacheDir: string, maxPages: number): Promise<PdfOcrResult> {
    const out: PdfOcrResult = {
      ok: false, text: '', pages: 0, supported: 0, skipped: 0,
      engine: OcrService.engineName(), note: ''
    };
    const kr: KitResp = await PdfKitClient.render(pdfPath, maxPages, cacheDir);
    const files: string[] = kr.files;
    out.pages = files.length;
    if (files.length === 0) {
      out.note = 'PDFKit 渲染失败';
      return out;
    }
    const chunks: string[] = [];
    for (const f of files) {
      const r: OcrResult = await OcrService.recognize(f);
      if (r.ok && r.text.length > 0) {
        chunks.push(r.text);
        out.supported += 1;
      } else {
        out.skipped += 1;
        if (r.note && !out.note) {
          out.note = r.note;
        }
      }
    }
    out.text = chunks.join('\n');
    out.ok = out.text.length > 0;
    return out;
  }

  /** 把原始像素包成 BMP（24 位 RGB 或 8 位灰度），鸿蒙 image 能直接解 */
  private static toBmp(raw: Uint8Array, w: number, h: number, cs: string): Uint8Array {
    const gray = cs !== 'DeviceRGB';
    const bytesPP = gray ? 1 : 3;
    const rowRaw = w * bytesPP;
    const rowSize = (rowRaw + 3) & ~3;
    const pixelSize = rowSize * h;
    const paletteSize = gray ? 1024 : 0;
    const offset = 54 + paletteSize;
    const total = offset + pixelSize;
    const out = new Uint8Array(total);
    const dv = new DataView(out.buffer);
    // BITMAPFILEHEADER
    out[0] = 0x42; out[1] = 0x4d;
    dv.setUint32(2, total, true);
    dv.setUint32(10, offset, true);
    // BITMAPINFOHEADER
    dv.setUint32(14, 40, true);
    dv.setInt32(18, w, true);
    dv.setInt32(22, h, true);
    dv.setUint16(26, 1, true);
    dv.setUint16(28, gray ? 8 : 24, true);
    dv.setUint32(34, pixelSize, true);
    dv.setUint32(46, gray ? 256 : 0, true);
    if (gray) {
      for (let i = 0; i < 256; i++) {
        out[54 + i * 4] = i;
        out[54 + i * 4 + 1] = i;
        out[54 + i * 4 + 2] = i;
      }
    }
    // BMP 是自下而上、BGR 顺序
    for (let y = 0; y < h; y++) {
      const srcRow = (h - 1 - y) * rowRaw;
      const dstRow = offset + y * rowSize;
      if (gray) {
        for (let x = 0; x < w; x++) {
          out[dstRow + x] = raw[srcRow + x];
        }
      } else {
        for (let x = 0; x < w; x++) {
          const s0 = srcRow + x * 3;
          out[dstRow + x * 3] = raw[s0 + 2];
          out[dstRow + x * 3 + 1] = raw[s0 + 1];
          out[dstRow + x * 3 + 2] = raw[s0];
        }
      }
    }
    return out;
  }

  private static readAll(path: string): Uint8Array {
    try {
      const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const st = fileIo.statSync(f.fd);
      const want = Math.min(st.size, 96 * 1024 * 1024);
      const buf = new ArrayBuffer(want);
      fileIo.readSync(f.fd, buf);
      fileIo.closeSync(f.fd);
      return new Uint8Array(buf);
    } catch (e) {
      return new Uint8Array(0);
    }
  }
}
