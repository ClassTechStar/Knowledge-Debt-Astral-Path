/**
 * PDFKit Worker 客户端 —— 主线程只负责收发消息。
 * 用独立 Worker（不是 taskpool）：taskpool 里 HMS 原生模块是 undefined。
 */
import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';

export interface KitReq {
  cmd: string;
  path: string;
  maxPages: number;
  outDir: string;
}

export interface KitResp {
  ok: boolean;
  text: string;
  pages: number;
  note: string;
  files: string[];
}

export class PdfKitClient {
  private static readonly URL: string = 'entry/ets/workers/PdfKitWorker.ets';

  private static run(req: KitReq, timeoutMs: number): Promise<KitResp> {
    return new Promise<KitResp>((resolve) => {
      let done = false;
      let w: worker.ThreadWorker | null = null;
      const finish = (r: KitResp) => {
        if (done) {
          return;
        }
        done = true;
        try {
          if (w) {
            w.terminate();
          }
        } catch (e) {
          // 忽略
        }
        resolve(r);
      };
      try {
        w = new worker.ThreadWorker(PdfKitClient.URL);
      } catch (e) {
        resolve({ ok: false, text: '', pages: 0, note: `Worker 创建失败：${(e as Error).message}`, files: [] });
        return;
      }
      w.onmessage = (e: MessageEvents) => {
        finish(e.data as KitResp);
      };
      w.onerror = (e: ErrorEvent) => {
        finish({ ok: false, text: '', pages: 0, note: `Worker 错误：${e.message}`, files: [] });
      };
      try {
        w.postMessage(req);
      } catch (e) {
        finish({ ok: false, text: '', pages: 0, note: `postMessage 失败：${(e as Error).message}`, files: [] });
        return;
      }
      setTimeout(() => {
        finish({ ok: false, text: '', pages: 0, note: 'Worker 超时', files: [] });
      }, timeoutMs);
    });
  }

  /** 取文本（超时 25s） */
  static text(path: string, maxPages: number): Promise<KitResp> {
    const req: KitReq = { cmd: 'text', path: path, maxPages: maxPages, outDir: '' };
    return PdfKitClient.run(req, 25000);
  }

  /** 渲染页图（超时 40s） */
  static render(path: string, maxPages: number, outDir: string): Promise<KitResp> {
    const req: KitReq = { cmd: 'render', path: path, maxPages: maxPages, outDir: outDir };
    return PdfKitClient.run(req, 40000);
  }
}
