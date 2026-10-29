/**
 * Core Vision OCR 引擎 —— 用系统能力做文字识别，不往包里塞引擎（包体积友好）。
 *
 * 启用前提：DevEco Studio → Settings → SDK → 勾选 **Core Vision** 组件并安装。
 * 本机 SDK 26.0.0 目前没装，所以下面的 import 与调用是注释状态（否则编译不过）。
 * 装好组件后：① 取消 import 的注释；② 取消 recognize 里的注释；
 * ③ 把 available() 改成 return true。
 *
 * 接口对齐 OcrService.OcrEngine：recognize(uri) → 文本。
 */

// import { textRecognition } from '@kit.CoreVisionKit';
// import { image } from '@kit.ImageKit';
// import { fileIo } from '@kit.CoreFileKit';

import { OcrEngine } from './OcrService';

export class CoreVisionOcrEngine implements OcrEngine {
  name(): string {
    return 'core-vision';
  }

  available(): boolean {
    // 装好组件后改成：return true;
    return false;
  }

  async recognize(_uri: string): Promise<string> {
    // 装好组件后取消以下实现注释（思路：把文件读成 PixelMap → 调 textRecognition → 拼 value）
    //
    // const file = fileIo.openSync(_uri, fileIo.OpenMode.READ_ONLY);
    // const source = image.createImageSource(file.fd);
    // const pm = await source.createPixelMap();
    // const visionInfo: textRecognition.VisionInfo = { pixelMap: pm };
    // const res = await textRecognition.recognizeText(visionInfo);
    // fileIo.closeSync(file);
    // return res.value ?? '';
    throw new Error('Core Vision 组件未安装，OCR 引擎不可用');
  }
}
