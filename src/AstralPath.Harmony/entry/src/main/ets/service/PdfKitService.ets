/**
 * PDF Kit 服务 —— 用 HarmonyOS 自带的 PDF 引擎（PDFKit）取文本 / 渲染页图。
 *
 * 为什么加这一层：自己写的 PDF 解析器只能覆盖「文本层 + Flate/DCT 图」，
 * 遇到 JBIG2 扫描件、对象流里的文本就无能为力。PDFKit 是华为自带的完整
 * 实现（JBIG2/CCITT/字体/对象流全支持），直接调它最稳，且不增加包体积。
 *
 * 注意：PDFKit 属 HMS 能力，构建时 HOS_SDK_HOME 要指向 <DevEco>/sdk。
 */
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

export interface PdfKitText {
  ok: boolean;
  text: string;
  pages: number;
  tried: number;
  note: string;
}

export class PdfKitService {
  /** 取前 maxPages 页的文本；PDFKit 不可用或解析失败时 ok=false */
  static extractText(path: string, maxPages: number): PdfKitText {
    const out: PdfKitText = { ok: false, text: '', pages: 0, tried: 0, note: '' };
    let doc: pdfService.PdfDocument | null = null;
    try {
      doc = new pdfService.PdfDocument();
      doc.loadDocument(path);
      const total = doc.getPageCount();
      out.pages = total;
      if (total <= 0) {
        out.note = 'PDFKit 解析出 0 页';
        return out;
      }
      const n = Math.min(total, maxPages);
      const chunks: string[] = [];
      for (let i = 0; i < n; i++) {
        out.tried += 1;
        try {
          const page = doc.getPage(i);
          const t = page.getTextContent();
          if (t && t.trim().length > 0) {
            chunks.push(t);
          }
        } catch (e) {
          // 单页失败不影响其他页
        }
      }
      out.text = chunks.join('\n');
      out.ok = out.text.replace(/\s/g, '').length > 0;
      if (!out.ok) {
        out.note = 'PDFKit 取到 0 字（可能是扫描版）';
      }
      return out;
    } catch (e) {
      out.note = `PDFKit 不可用：${(e as Error).message}`;
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

  /** 渲染某一页为 PNG 落盘（给 OCR 用；能处理 JBIG2 等自研解析器不支持的编码） */
  static renderPageToPng(path: string, pageIndex: number, outPath: string): boolean {
    let doc: pdfService.PdfDocument | null = null;
    try {
      doc = new pdfService.PdfDocument();
      doc.loadDocument(path);
      if (pageIndex < 0 || pageIndex >= doc.getPageCount()) {
        return false;
      }
      const page = doc.getPage(pageIndex);
      const pm: image.PixelMap = page.getPagePixelMap();
      return PdfKitService.savePng(pm, outPath);
    } catch (e) {
      return false;
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

  /** 多页一次性渲染（放大 2 倍便于 OCR 识别小字） */
  static async renderPagesToPng(path: string, pageIndices: number[], scale: number,
    outDir: string): Promise<string[]> {
    const outs: string[] = [];
    let doc: pdfService.PdfDocument | null = null;
    try {
      doc = new pdfService.PdfDocument();
      doc.loadDocument(path);
      const total = doc.getPageCount();
      for (let k = 0; k < pageIndices.length; k++) {
        const idx = pageIndices[k];
        if (idx < 0 || idx >= total) {
          continue;
        }
        try {
          const page = doc.getPage(idx);
          const pm: image.PixelMap = page.getPagePixelMap();
          const out = `${outDir}/pdfpage_${idx}.png`;
          if (PdfKitService.savePng(pm, out)) {
            outs.push(out);
          }
        } catch (e) {
          // 跳过坏页
        }
      }
      return outs;
    } catch (e) {
      return outs;
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

  private static async savePngAsync(pm: image.PixelMap, outPath: string): Promise<boolean> {
    try {
      const packer = image.createImagePacker();
      const buf = await packer.packing(pm, { format: 'image/png', quality: 100 });
      const f = fileIo.openSync(outPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, buf);
      fileIo.closeSync(f.fd);
      packer.release();
      return true;
    } catch (e) {
      return false;
    }
  }

  private static savePng(pm: image.PixelMap, outPath: string): boolean {
    // createImagePacker 是异步的，这里用「先起任务再等」不可行（同步 API 上下文），
    // 所以把 PixelMap 先转成 RGBA 字节，直接写 PNG 太复杂 —— 改为同步写 BMP。
    try {
      const info = pm.getImageInfoSync();
      const w = info.size.width;
      const h = info.size.height;
      const buf = new ArrayBuffer(w * h * 4);
      // readPixelsToBufferSync 拿到 RGBA
      pm.readPixelsToBufferSync(buf);
      const rgba = new Uint8Array(buf);
      const bmp = PdfKitService.rgbaToBmp(rgba, w, h);
      const p = outPath.endsWith('.png') ? `${outPath}.bmp` : `${outPath}.bmp`;
      const f = fileIo.openSync(p,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, bmp.buffer);
      fileIo.closeSync(f.fd);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** RGBA → 24 位 BMP（BGR、自下而上） */
  private static rgbaToBmp(rgba: Uint8Array, w: number, h: number): Uint8Array {
    const rowRaw = w * 3;
    const rowSize = (rowRaw + 3) & ~3;
    const pixelSize = rowSize * h;
    const offset = 54;
    const total = offset + pixelSize;
    const out = new Uint8Array(total);
    const dv = new DataView(out.buffer);
    out[0] = 0x42;
    out[1] = 0x4d;
    dv.setUint32(2, total, true);
    dv.setUint32(10, offset, true);
    dv.setUint32(14, 40, true);
    dv.setInt32(18, w, true);
    dv.setInt32(22, h, true);
    dv.setUint16(26, 1, true);
    dv.setUint16(28, 24, true);
    dv.setUint32(34, pixelSize, true);
    for (let y = 0; y < h; y++) {
      const srcRow = (h - 1 - y) * w * 4;
      const dstRow = offset + y * rowSize;
      for (let x = 0; x < w; x++) {
        const s = srcRow + x * 4;
        // 白底合成：扫描件常带 alpha
        const a = rgba[s + 3];
        const r = a === 255 ? rgba[s] : Math.round(rgba[s] * a / 255 + 255 * (1 - a / 255));
        const g = a === 255 ? rgba[s + 1] : Math.round(rgba[s + 1] * a / 255 + 255 * (1 - a / 255));
        const b = a === 255 ? rgba[s + 2] : Math.round(rgba[s + 2] * a / 255 + 255 * (1 - a / 255));
        out[dstRow + x * 3] = b;
        out[dstRow + x * 3 + 1] = g;
        out[dstRow + x * 3 + 2] = r;
      }
    }
    return out;
  }

  static async savePngPublic(pm: image.PixelMap, outPath: string): Promise<boolean> {
    return PdfKitService.savePngAsync(pm, outPath);
  }
}
