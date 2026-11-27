import { FlexParsers, JsonObject, JsonValue } from '../../core/api/FlexParsers';
import { ApiType, ModelProfile } from './ModelProfile';

export interface AiMessage {
  fromUser: boolean;
  text: string;
}

export interface AiHttpRequest {
  url: string;
  body: string;
  headers: Record<string, string>;
}

export interface AiReply {
  text?: string;
  reasoningChars: number;
  searchSignal: boolean;
}

/**
 * 多供应商 AI 请求装配与响应解析（100% 纯函数，对齐上游 app/data/AiProtocol.kt）。
 *
 * - 支持 OpenAI Chat Completion / OpenAI Responses / Anthropic Messages / Gemini generateContent
 * - Anthropic 自动处理 temperature 与 top_p 互斥（同时配置时仅发送 temperature）
 * - 深度思考与联网搜索开关默认关闭时不下发对应扩展字段
 */
export class AiProtocol {
  static buildRequest(
    profile: ModelProfile,
    apiKey: string,
    systemPrompt: string,
    history: AiMessage[],
    prompt: string,
    imageDataUrl?: string
  ): AiHttpRequest {
    const resolvedUrl = profile.url.trim().replace(/\{model\}/g, profile.model.trim());
    const headers = AiProtocol.buildHeaders(profile.apiType, apiKey);
    let bodyObj: Record<string, JsonValue>;

    if (profile.apiType === ApiType.RESPONSES) {
      bodyObj = AiProtocol.buildResponsesBody(profile, systemPrompt, history, prompt, imageDataUrl);
    } else if (profile.apiType === ApiType.ANTHROPIC) {
      bodyObj = AiProtocol.buildAnthropicBody(profile, systemPrompt, history, prompt, imageDataUrl);
    } else if (profile.apiType === ApiType.GEMINI) {
      bodyObj = AiProtocol.buildGeminiBody(profile, systemPrompt, history, prompt, imageDataUrl);
    } else {
      bodyObj = AiProtocol.buildChatCompletionBody(profile, systemPrompt, history, prompt, imageDataUrl);
    }

    return {
      url: resolvedUrl,
      body: JSON.stringify(bodyObj),
      headers: headers
    };
  }

  private static buildHeaders(apiType: ApiType, apiKey: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    const key = apiKey.trim();
    if (apiType === ApiType.ANTHROPIC) {
      if (key.length > 0) {
        headers['x-api-key'] = key;
      }
      headers['anthropic-version'] = '2023-06-01';
    } else if (apiType === ApiType.GEMINI) {
      if (key.length > 0) {
        headers['x-goog-api-key'] = key;
      }
    } else {
      if (key.length > 0) {
        headers['Authorization'] = `Bearer ${key}`;
      }
    }
    return headers;
  }

  private static extractDataUrlParts(dataUrl: string): [string, string] {
    const comma = dataUrl.indexOf(',');
    if (comma < 0) {
      return ['image/jpeg', dataUrl];
    }
    const meta = dataUrl.substring(0, comma);
    const b64 = dataUrl.substring(comma + 1);
    const semi = meta.indexOf(';');
    const mime = meta.startsWith('data:') && semi > 5 ? meta.substring(5, semi) : 'image/jpeg';
    return [mime, b64];
  }

  private static buildChatCompletionBody(
    profile: ModelProfile,
    systemPrompt: string,
    history: AiMessage[],
    prompt: string,
    imageDataUrl?: string
  ): Record<string, JsonValue> {
    const messages: JsonValue[] = [];
    if (systemPrompt.trim().length > 0) {
      const sysMsg: Record<string, JsonValue> = { 'role': 'system', 'content': systemPrompt };
      messages.push(sysMsg);
    }
    for (let i = 0; i < history.length; i++) {
      const m = history[i];
      const item: Record<string, JsonValue> = { 'role': m.fromUser ? 'user' : 'assistant', 'content': m.text };
      messages.push(item);
    }
    if (imageDataUrl !== undefined && imageDataUrl.length > 0) {
      const imgUrlObj: Record<string, JsonValue> = { 'url': imageDataUrl };
      const imgPart: Record<string, JsonValue> = { 'type': 'image_url', 'image_url': imgUrlObj };
      const txtPart: Record<string, JsonValue> = { 'type': 'text', 'text': prompt };
      const userMsg: Record<string, JsonValue> = { 'role': 'user', 'content': [txtPart, imgPart] };
      messages.push(userMsg);
    } else {
      const userMsg: Record<string, JsonValue> = { 'role': 'user', 'content': prompt };
      messages.push(userMsg);
    }

    const body: Record<string, JsonValue> = {
      'model': profile.model.trim(),
      'messages': messages
    };
    if (profile.temperature !== undefined) {
      body['temperature'] = profile.temperature;
    }
    if (profile.topP !== undefined) {
      body['top_p'] = profile.topP;
    }
    if (profile.maxTokens !== undefined && profile.maxTokens > 0) {
      body['max_tokens'] = profile.maxTokens;
    }
    if (profile.enableThinking) {
      body['enable_thinking'] = true;
    }
    if (profile.enableWebSearch) {
      body['enable_search'] = true;
    }
    return body;
  }

  private static buildResponsesBody(
    profile: ModelProfile,
    systemPrompt: string,
    history: AiMessage[],
    prompt: string,
    imageDataUrl?: string
  ): Record<string, JsonValue> {
    const input: JsonValue[] = [];
    for (let i = 0; i < history.length; i++) {
      const m = history[i];
      const msg: Record<string, JsonValue> = { 'role': m.fromUser ? 'user' : 'assistant', 'content': m.text };
      input.push(msg);
    }
    if (imageDataUrl !== undefined && imageDataUrl.length > 0) {
      const txtPart: Record<string, JsonValue> = { 'type': 'input_text', 'text': prompt };
      const imgPart: Record<string, JsonValue> = { 'type': 'input_image', 'image_url': imageDataUrl };
      const userMsg: Record<string, JsonValue> = { 'role': 'user', 'content': [txtPart, imgPart] };
      input.push(userMsg);
    } else {
      const userMsg: Record<string, JsonValue> = { 'role': 'user', 'content': prompt };
      input.push(userMsg);
    }

    const body: Record<string, JsonValue> = {
      'model': profile.model.trim(),
      'input': input
    };
    if (systemPrompt.trim().length > 0) {
      body['instructions'] = systemPrompt;
    }
    if (profile.temperature !== undefined) {
      body['temperature'] = profile.temperature;
    }
    if (profile.topP !== undefined) {
      body['top_p'] = profile.topP;
    }
    if (profile.maxTokens !== undefined && profile.maxTokens > 0) {
      body['max_output_tokens'] = profile.maxTokens;
    }
    if (profile.enableThinking) {
      const reasoning: Record<string, JsonValue> = { 'effort': 'medium' };
      body['reasoning'] = reasoning;
    }
    if (profile.enableWebSearch) {
      const tool: Record<string, JsonValue> = { 'type': 'web_search_preview' };
      body['tools'] = [tool];
    }
    return body;
  }

  private static buildAnthropicBody(
    profile: ModelProfile,
    systemPrompt: string,
    history: AiMessage[],
    prompt: string,
    imageDataUrl?: string
  ): Record<string, JsonValue> {
    const messages: JsonValue[] = [];
    for (let i = 0; i < history.length; i++) {
      const m = history[i];
      const msg: Record<string, JsonValue> = { 'role': m.fromUser ? 'user' : 'assistant', 'content': m.text };
      messages.push(msg);
    }
    if (imageDataUrl !== undefined && imageDataUrl.length > 0) {
      const parts = AiProtocol.extractDataUrlParts(imageDataUrl);
      const srcObj: Record<string, JsonValue> = {
        'type': 'base64',
        'media_type': parts[0],
        'data': parts[1]
      };
      const imgPart: Record<string, JsonValue> = { 'type': 'image', 'source': srcObj };
      const txtPart: Record<string, JsonValue> = { 'type': 'text', 'text': prompt };
      const userMsg: Record<string, JsonValue> = { 'role': 'user', 'content': [imgPart, txtPart] };
      messages.push(userMsg);
    } else {
      const userMsg: Record<string, JsonValue> = { 'role': 'user', 'content': prompt };
      messages.push(userMsg);
    }

    const body: Record<string, JsonValue> = {
      'model': profile.model.trim(),
      'max_tokens': (profile.maxTokens !== undefined && profile.maxTokens > 0) ? profile.maxTokens : 4096,
      'messages': messages
    };
    if (systemPrompt.trim().length > 0) {
      body['system'] = systemPrompt;
    }
    // Anthropic 规范：temperature 与 top_p 互斥；深度思考开启时不允许自定义 sampling
    if (!profile.enableThinking) {
      if (profile.temperature !== undefined) {
        body['temperature'] = profile.temperature;
      } else if (profile.topP !== undefined) {
        body['top_p'] = profile.topP;
      }
    } else {
      const thinking: Record<string, JsonValue> = { 'type': 'enabled', 'budget_tokens': 2048 };
      body['thinking'] = thinking;
    }
    if (profile.enableWebSearch) {
      const tool: Record<string, JsonValue> = { 'type': 'web_search_20250305', 'name': 'web_search' };
      body['tools'] = [tool];
    }
    return body;
  }

  private static buildGeminiBody(
    profile: ModelProfile,
    systemPrompt: string,
    history: AiMessage[],
    prompt: string,
    imageDataUrl?: string
  ): Record<string, JsonValue> {
    const contents: JsonValue[] = [];
    for (let i = 0; i < history.length; i++) {
      const m = history[i];
      const part: Record<string, JsonValue> = { 'text': m.text };
      const item: Record<string, JsonValue> = { 'role': m.fromUser ? 'user' : 'model', 'parts': [part] };
      contents.push(item);
    }
    const userParts: JsonValue[] = [];
    const textPart: Record<string, JsonValue> = { 'text': prompt };
    userParts.push(textPart);
    if (imageDataUrl !== undefined && imageDataUrl.length > 0) {
      const parts = AiProtocol.extractDataUrlParts(imageDataUrl);
      const inlineData: Record<string, JsonValue> = { 'mime_type': parts[0], 'data': parts[1] };
      const imgPart: Record<string, JsonValue> = { 'inline_data': inlineData };
      userParts.push(imgPart);
    }
    const userTurn: Record<string, JsonValue> = { 'role': 'user', 'parts': userParts };
    contents.push(userTurn);

    const body: Record<string, JsonValue> = { 'contents': contents };
    if (systemPrompt.trim().length > 0) {
      const sysPart: Record<string, JsonValue> = { 'text': systemPrompt };
      const sysInst: Record<string, JsonValue> = { 'parts': [sysPart] };
      body['system_instruction'] = sysInst;
    }

    const genCfg: Record<string, JsonValue> = {};
    let hasGenCfg = false;
    if (profile.temperature !== undefined) {
      genCfg['temperature'] = profile.temperature;
      hasGenCfg = true;
    }
    if (profile.topP !== undefined) {
      genCfg['topP'] = profile.topP;
      hasGenCfg = true;
    }
    if (profile.maxTokens !== undefined && profile.maxTokens > 0) {
      genCfg['maxOutputTokens'] = profile.maxTokens;
      hasGenCfg = true;
    }
    if (profile.enableThinking) {
      const thinkingCfg: Record<string, JsonValue> = { 'thinkingBudget': 2048 };
      genCfg['thinkingConfig'] = thinkingCfg;
      hasGenCfg = true;
    }
    if (hasGenCfg) {
      body['generationConfig'] = genCfg;
    }
    if (profile.enableWebSearch) {
      const emptyObj: Record<string, JsonValue> = {};
      const searchTool: Record<string, JsonValue> = { 'google_search': emptyObj };
      body['tools'] = [searchTool];
    }
    return body;
  }

  static parseReply(apiType: ApiType, rawJson: string): AiReply {
    const root = FlexParsers.asObject(JSON.parse(rawJson) as JsonValue);
    if (root === undefined) {
      return { text: undefined, reasoningChars: 0, searchSignal: false };
    }

    if (apiType === ApiType.RESPONSES) {
      const output = FlexParsers.asArray(root['output']);
      const chunks: string[] = [];
      let reasoningChars = 0;
      let searchSignal = root['search_info'] !== undefined;
      for (let i = 0; i < output.length; i++) {
        const item = FlexParsers.asObject(output[i]);
        if (item === undefined) {
          continue;
        }
        const typeStr = FlexParsers.readString(item, 'type') ?? '';
        if (typeStr.includes('search')) {
          searchSignal = true;
        }
        if (typeStr === 'message') {
          const contentArr = FlexParsers.asArray(item['content']);
          for (let j = 0; j < contentArr.length; j++) {
            const cObj = FlexParsers.asObject(contentArr[j]);
            const t = FlexParsers.readString(cObj, 'text');
            if (t !== undefined && t.length > 0) {
              chunks.push(t);
            }
          }
        } else if (typeStr === 'reasoning') {
          const summaryArr = FlexParsers.asArray(item['summary']);
          for (let j = 0; j < summaryArr.length; j++) {
            const sObj = FlexParsers.asObject(summaryArr[j]);
            reasoningChars += (FlexParsers.readString(sObj, 'text') ?? '').length;
          }
        }
      }
      const joined = chunks.join('\n').trim();
      return { text: joined.length > 0 ? joined : undefined, reasoningChars: reasoningChars, searchSignal: searchSignal };
    }

    if (apiType === ApiType.ANTHROPIC) {
      const contentArr = FlexParsers.asArray(root['content']);
      const chunks: string[] = [];
      let reasoningChars = 0;
      let searchSignal = false;
      for (let i = 0; i < contentArr.length; i++) {
        const block = FlexParsers.asObject(contentArr[i]);
        if (block === undefined) {
          continue;
        }
        const bType = FlexParsers.readString(block, 'type') ?? '';
        if (bType === 'text') {
          const t = FlexParsers.readString(block, 'text');
          if (t !== undefined && t.length > 0) {
            chunks.push(t);
          }
        } else if (bType === 'thinking') {
          reasoningChars += (FlexParsers.readString(block, 'thinking') ?? '').length;
        } else if (bType.includes('search')) {
          searchSignal = true;
        }
      }
      const joined = chunks.join('\n').trim();
      return { text: joined.length > 0 ? joined : undefined, reasoningChars: reasoningChars, searchSignal: searchSignal };
    }

    if (apiType === ApiType.GEMINI) {
      const candidates = FlexParsers.asArray(root['candidates']);
      const firstCand = candidates.length > 0 ? FlexParsers.asObject(candidates[0]) : undefined;
      const content = firstCand !== undefined ? FlexParsers.asObject(firstCand['content']) : undefined;
      const parts = content !== undefined ? FlexParsers.asArray(content['parts']) : [];
      const chunks: string[] = [];
      let reasoningChars = 0;
      for (let i = 0; i < parts.length; i++) {
        const pObj = FlexParsers.asObject(parts[i]);
        if (pObj === undefined) {
          continue;
        }
        const isThought = FlexParsers.readBoolean(pObj, 'thought', false);
        const text = FlexParsers.readString(pObj, 'text') ?? '';
        if (isThought) {
          reasoningChars += text.length;
        } else if (text.length > 0) {
          chunks.push(text);
        }
      }
      const searchSignal = firstCand !== undefined && firstCand['groundingMetadata'] !== undefined;
      const joined = chunks.join('\n').trim();
      return { text: joined.length > 0 ? joined : undefined, reasoningChars: reasoningChars, searchSignal: searchSignal };
    }

    // OpenAI Chat Completion
    const choices = FlexParsers.asArray(root['choices']);
    const firstChoice = choices.length > 0 ? FlexParsers.asObject(choices[0]) : undefined;
    const msg = firstChoice !== undefined ? FlexParsers.asObject(firstChoice['message']) : undefined;
    const contentText = FlexParsers.readString(msg, 'content');
    const reasoning = FlexParsers.readString(msg, 'reasoning_content') ?? '';
    const searchSignal = (msg !== undefined && (msg['search_info'] !== undefined || msg['tool_calls'] !== undefined)) ||
      root['search_info'] !== undefined;
    return {
      text: contentText !== undefined && contentText.trim().length > 0 ? contentText : undefined,
      reasoningChars: reasoning.length,
      searchSignal: searchSignal
    };
  }
}
