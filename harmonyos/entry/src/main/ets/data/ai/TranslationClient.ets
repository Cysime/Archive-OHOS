import { AiCaller } from './AiCaller';
import { AiPurpose } from './ModelProfile';
import {
  HTML_CLOSE,
  HTML_OPEN,
  PLACEHOLDER_HTML,
  PLACEHOLDER_TITLE,
  PostTranslation,
  TITLE_CLOSE,
  TITLE_OPEN,
  TranslationParser
} from './TranslationParser';
import { TranslationSettingsRepository } from './TranslationSettingsRepository';

export { PostTranslation, TranslationParser };

export class TranslationClient {
  private readonly settingsRepo: TranslationSettingsRepository;
  private readonly caller: AiCaller;

  constructor(settingsRepo: TranslationSettingsRepository, caller: AiCaller) {
    this.settingsRepo = settingsRepo;
    this.caller = caller;
  }

  async translatePost(title: string, html: string): Promise<PostTranslation> {
    const profile = this.settingsRepo.getProfileForPurpose(AiPurpose.TRANSLATION);
    if (profile === undefined) {
      throw new Error('请先在「AI 设置」中配置翻译模型档案');
    }
    const apiKey = await this.settingsRepo.getApiKey(profile.id);
    const targetLang = this.settingsRepo.getSnapshot().targetLanguage;
    const customPrompt = this.settingsRepo.getSnapshot().customSystemPrompt.trim();

    const systemPrompt = customPrompt.length > 0
      ? customPrompt
      : `你是专业翻译助手。将用户提供的帖子标题与 HTML 正文准确翻译为${targetLang}，严格保留原有 HTML 标签结构与链接地址。必须严格按以下哨兵格式输出，并将尖括号占位符替换为真实译文：\n${TITLE_OPEN}\n${PLACEHOLDER_TITLE}\n${TITLE_CLOSE}\n${HTML_OPEN}\n${PLACEHOLDER_HTML}\n${HTML_CLOSE}`;

    const userPrompt = `标题：\n${title}\n\n正文 HTML：\n${html}`;
    const reply = await this.caller.call(profile, apiKey, systemPrompt, [], userPrompt);
    const rawText = reply.text ?? '';
    if (rawText.trim().length === 0) {
      throw new Error('AI 未返回译文内容');
    }
    return TranslationParser.parsePostTranslation(rawText, title, html);
  }
}
