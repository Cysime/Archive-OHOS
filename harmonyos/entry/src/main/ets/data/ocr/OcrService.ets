import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'OcrService';

export interface OcrResult {
  fullText: string;
  lines: string[];
}

/**
 * HarmonyOS 原生端上 OCR 服务（基于 `@kit.CoreVisionKit` `textRecognition`）。
 *
 * 替代 Android 版的 ONNX Runtime + PP-OCRv4（零额外包体积、NPU 硬件加速、离线支持简繁中英日韩）。
 */
export class OcrService {
  async recognize(pixelMap: image.PixelMap): Promise<OcrResult> {
    let initialized = false;
    try {
      initialized = await textRecognition.init();
      const visionInfo: textRecognition.VisionInfo = {
        pixelMap: pixelMap
      };
      const config: textRecognition.TextRecognitionConfiguration = {
        isDirectionDetectionSupported: true
      };
      const result = await textRecognition.recognizeText(visionInfo, config);
      const lines: string[] = [];
      for (let i = 0; i < result.blocks.length; i++) {
        const block = result.blocks[i];
        for (let j = 0; j < block.lines.length; j++) {
          const lineText = block.lines[j].value.trim();
          if (lineText.length > 0) {
            lines.push(lineText);
          }
        }
      }
      const fullText = result.value.trim().length > 0 ? result.value.trim() : lines.join('\n');
      return {
        fullText: fullText,
        lines: lines
      };
    } catch (e) {
      Logger.w(TAG, `CoreVisionKit OCR failed: ${String(e)}`);
      throw new Error(`端上 OCR 识别失败（请确认在支持 CoreVisionKit 的真机运行）：${String(e)}`);
    } finally {
      if (initialized) {
        textRecognition.release().catch(() => {});
      }
    }
  }
}
