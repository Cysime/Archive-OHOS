/**
 * AI 多供应商接口类型与模型档案定义（对齐上游 app/data/ModelProfile.kt & ApiType）。
 */
export enum ApiType {
  CHAT_COMPLETION = 'CHAT_COMPLETION',
  RESPONSES = 'RESPONSES',
  ANTHROPIC = 'ANTHROPIC',
  GEMINI = 'GEMINI'
}

export enum AiPurpose {
  TRANSLATION = 'TRANSLATION',
  VISION = 'VISION'
}

export interface ModelProfile {
  id: string;
  name: string;
  apiType: ApiType;
  url: string;
  model: string;
  temperature?: number;
  topP?: number;
  maxTokens?: number;
  enableThinking: boolean;
  enableWebSearch: boolean;
}

export interface AiSettingsSnapshot {
  profiles: ModelProfile[];
  translationProfileId: string;
  visionProfileId: string;
  targetLanguage: string;
  customSystemPrompt: string;
}

export class ApiTypeHelper {
  static label(type: ApiType): string {
    if (type === ApiType.RESPONSES) {
      return 'OpenAI Responses';
    }
    if (type === ApiType.ANTHROPIC) {
      return 'Anthropic Messages';
    }
    if (type === ApiType.GEMINI) {
      return 'Gemini generateContent';
    }
    return 'OpenAI Chat Completion';
  }

  static urlHint(type: ApiType): string {
    if (type === ApiType.RESPONSES) {
      return 'https://api.openai.com/v1/responses';
    }
    if (type === ApiType.ANTHROPIC) {
      return 'https://api.anthropic.com/v1/messages';
    }
    if (type === ApiType.GEMINI) {
      return 'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent';
    }
    return 'https://api.openai.com/v1/chat/completions';
  }

  static fromString(raw?: string): ApiType {
    if (raw === ApiType.RESPONSES) {
      return ApiType.RESPONSES;
    }
    if (raw === ApiType.ANTHROPIC) {
      return ApiType.ANTHROPIC;
    }
    if (raw === ApiType.GEMINI) {
      return ApiType.GEMINI;
    }
    return ApiType.CHAT_COMPLETION;
  }
}
