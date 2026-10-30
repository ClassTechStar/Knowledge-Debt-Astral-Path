/**
 * PDFKit 专用 Worker —— taskpool 里 `pdfService` 是 undefined（HMS 原生模块
 * 不会注入 taskpool 上下文）；独立 Worker 有自己的模块注册表，可以正常加载。
 *
 * 只做两件事：取文本、渲染页图。都通过 postMessage 把结果回传，
 * 主线程只负责收发消息，避免 loadDocument 把 UI 线程堵死（THREAD_BLOCK 6s）。
 */
import { worker, ThreadWorkerGlobalScope, MessageEvents } from '@kit.ArkTS';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

interface Req {
  cmd: 'text' | 'render';
  path: string;
  maxPages: number;
  outDir: string;
}

interface Resp {
  ok: boolean;
  text: string;
  pages: number;
  note: string;
  files: string[];
}

function doText(path: string, maxPages: number): Resp {
  const r: Resp = { ok: false, text: '', pages: 0, note: '', files: [] };
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    doc.loadDocument(path);
    const total = doc.getPageCount();
    r.pages = total;
    const n = Math.min(total, maxPages);
    const chunks: string[] = [];
    for (let i = 0; i < n; i++) {
      try {
        const t = doc.getPage(i).getTextContent();
        if (t && t.trim().length > 0) {
          chunks.push(t);
        }
      } catch (e) {
        // 单页失败跳过
      }
    }
    r.text = chunks.join('\n');
    r.ok = r.text.replace(/\s/g, '').length > 0;
    return r;
  } catch (e) {
    r.note = `PDFKit 失败：${(e as Error).message}`;
    return r;
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

function doRender(path: string, maxPages: number, outDir: string): Resp {
  const r: Resp = { ok: false, text: '', pages: 0, note: '', files: [] };
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    doc.loadDocument(path);
    const total = doc.getPageCount();
    r.pages = total;
    const n = Math.min(total, maxPages);
    for (let i = 0; i < n; i++) {
      try {
        const pm: image.PixelMap = doc.getPage(i).getPagePixelMap();
        const info = pm.getImageInfoSync();
        const w = info.size.width;
        const h = info.size.height;
        const buf = new ArrayBuffer(w * h * 4);
        pm.readPixelsToBufferSync(buf);
        const bmp = rgbaToBmp(new Uint8Array(buf), w, h);
        const out = `${outDir}/pdfpage_${i}.bmp`;
        const f = fileIo.openSync(out,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(f.fd, bmp.buffer);
        fileIo.closeSync(f.fd);
        r.files.push(out);
      } catch (e) {
        // 跳过坏页
      }
    }
    r.ok = r.files.length > 0;
    if (!r.ok) {
      r.note = '渲染 0 页';
    }
    return r;
  } catch (e) {
    r.note = `PDFKit 渲染失败：${(e as Error).message}`;
    return r;
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

/** RGBA → 24 位 BMP（BGR、自下而上、白底合成） */
function rgbaToBmp(rgba: Uint8Array, w: number, h: number): Uint8Array {
  const rowRaw = w * 3;
  const rowSize = (rowRaw + 3) & ~3;
  const pixelSize = rowSize * h;
  const total = 54 + pixelSize;
  const out = new Uint8Array(total);
  const dv = new DataView(out.buffer);
  out[0] = 0x42;
  out[1] = 0x4d;
  dv.setUint32(2, total, true);
  dv.setUint32(10, 54, true);
  dv.setUint32(14, 40, true);
  dv.setInt32(18, w, true);
  dv.setInt32(22, h, true);
  dv.setUint16(26, 1, true);
  dv.setUint16(28, 24, true);
  dv.setUint32(34, pixelSize, true);
  for (let y = 0; y < h; y++) {
    const srcRow = (h - 1 - y) * w * 4;
    const dstRow = 54 + y * rowSize;
    for (let x = 0; x < w; x++) {
      const s = srcRow + x * 4;
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

workerPort.onmessage = (e: MessageEvents) => {
  const req = e.data as Req;
  let resp: Resp;
  if (req.cmd === 'text') {
    resp = doText(req.path, req.maxPages);
  } else {
    resp = doRender(req.path, req.maxPages, req.outDir);
  }
  workerPort.postMessage(resp);
};
