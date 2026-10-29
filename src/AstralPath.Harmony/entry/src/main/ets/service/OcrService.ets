/**
 * OCR 引擎接口 —— 扫描版 PDF / 拍照图片要走这条链。
 *
 * 当前本机 SDK（OpenHarmony 26.0.0）**没有装 Core Vision 组件**，
 * 因此默认挂的是 NoopOcrEngine（明确告诉用户不可用，不假装识别过）。
 * 启用步骤见 README：DevEco Studio → Settings → SDK 勾选 Core Vision，
 * 然后把 CoreVisionOcrEngine.ets 里注释掉的那两行打开即可生效。
 */
export interface OcrEngine {
  name(): string;
  available(): boolean;
  /** 对图片/PDF 页做文字识别，返回纯文本 */
  recognize(uri: string): Promise<string>;
}

/** 无引擎时的兜底：明确不可用，调用方据此提示用户，而不是返回空串当成功 */
export class NoopOcrEngine implements OcrEngine {
  name(): string {
    return 'none';
  }

  available(): boolean {
    return false;
  }

  async recognize(_uri: string): Promise<string> {
    throw new Error('本机没有可用的 OCR 引擎（需要 Core Vision 组件）');
  }
}

export interface OcrResult {
  text: string;
  engine: string;
  ok: boolean;
  note: string;
}

export class OcrService {
  private static engine: OcrEngine = new NoopOcrEngine();

  static use(e: OcrEngine): void {
    OcrService.engine = e;
  }

  static available(): boolean {
    return OcrService.engine.available();
  }

  static engineName(): string {
    return OcrService.engine.name();
  }

  /** 文本层稀到这个程度就认为需要 OCR（与 Web 版扫描版判定同思路） */
  static needOcr(chars: number, scanned: boolean): boolean {
    return scanned || chars < 200;
  }

  static async recognize(uri: string): Promise<OcrResult> {
    if (!OcrService.engine.available()) {
      return {
        text: '',
        engine: OcrService.engine.name(),
        ok: false,
        note: 'OCR 不可用：请在 DevEco Studio 里安装 Core Vision 组件后启用 CoreVisionOcrEngine'
      };
    }
    try {
      const text = await OcrService.engine.recognize(uri);
      return { text: text, engine: OcrService.engine.name(), ok: text.length > 0, note: '' };
    } catch (e) {
      return { text: '', engine: OcrService.engine.name(), ok: false, note: (e as Error).message };
    }
  }
}
