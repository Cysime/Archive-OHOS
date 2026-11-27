import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { AiCaller } from './AiCaller';
import { AiMessage } from './AiProtocol';
import { AiPurpose } from './ModelProfile';
import { TranslationSettingsRepository } from './TranslationSettingsRepository';

/**
 * AI 图片理解与多轮问答客户端（对齐上游 app/data/VisionClient.kt）。
 */
export class VisionClient {
  private readonly settingsRepo: TranslationSettingsRepository;
  private readonly caller: AiCaller;
  private readonly summaryCache: Map<string, string> = new Map<string, string>();
  private readonly base64Helper: util.Base64Helper = new util.Base64Helper();

  constructor(settingsRepo: TranslationSettingsRepository, caller: AiCaller) {
    this.settingsRepo = settingsRepo;
    this.caller = caller;
  }

  private async pixelMapToDataUrl(pixelMap: image.PixelMap): Promise<string> {
    const packer = image.createImagePacker();
    try {
      const buf = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 82
      });
      const b64 = this.base64Helper.encodeToStringSync(new Uint8Array(buf));
      return `data:image/jpeg;base64,${b64}`;
    } catch (e) {
      throw new Error(`图片编码失败：${String(e)}`);
    } finally {
      await packer.release();
    }
  }

  async askImage(
    cacheKey: string,
    pixelMap: image.PixelMap,
    question: string,
    history: AiMessage[] = []
  ): Promise<string> {
    const isDefaultSummary = history.length === 0 && question.trim().length === 0;
    if (isDefaultSummary && this.summaryCache.has(cacheKey)) {
      return this.summaryCache.get(cacheKey) as string;
    }

    const profile = this.settingsRepo.getProfileForPurpose(AiPurpose.VISION);
    if (profile === undefined) {
      throw new Error('请先在「AI 设置」中配置识图模型档案');
    }
    const apiKey = await this.settingsRepo.getApiKey(profile.id);
    const targetLang = this.settingsRepo.getSnapshot().targetLanguage;
    const dataUrl = await this.pixelMapToDataUrl(pixelMap);
    const prompt = question.trim().length > 0
      ? question.trim()
      : `请用${targetLang}简洁描述这张图片的内容，并翻译画面中的主要文字（如有）。`;

    const reply = await this.caller.call(
      profile,
      apiKey,
      `你是多模态图片理解助手，请使用${targetLang}清晰作答。`,
      history,
      prompt,
      dataUrl
    );
    const answer = (reply.text ?? '').trim();
    if (answer.length === 0) {
      throw new Error('AI 未返回识图结果');
    }
    if (isDefaultSummary) {
      this.summaryCache.set(cacheKey, answer);
    }
    return answer;
  }
}
