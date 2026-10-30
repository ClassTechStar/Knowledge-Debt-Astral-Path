/**
 * Core Vision OCR 引擎 —— 用系统 OCR 能力识别文字，不往包里塞引擎（包体积友好）。
 *
 * 说明：Core Vision 属 HarmonyOS（HMS）能力，随 DevEco Studio 的
 * `sdk/default/hms` 一起提供，**不在** OpenHarmony 公共 SDK 里。
 * 构建时把 HOS_SDK_HOME 指向 `<DevEco>/sdk` 即可编译（README 第 9 节）。
 * 运行期若设备没有该能力，recognizeText 会抛错，由 OcrService 兜底成「不可用」。
 */
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

import { OcrEngine } from './OcrService';

export class CoreVisionOcrEngine implements OcrEngine {
  name(): string {
    return 'core-vision';
  }

  available(): boolean {
    return true;
  }

  async recognize(uri: string): Promise<string> {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      const pm = await source.createPixelMap();
      const info: textRecognition.VisionInfo = { pixelMap: pm };
      const res = await textRecognition.recognizeText(info);
      return res.value ?? '';
    } finally {
      fileIo.closeSync(file.fd);
    }
  }
}
