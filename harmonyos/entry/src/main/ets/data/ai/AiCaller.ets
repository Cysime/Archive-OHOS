import { rcp } from '@kit.RemoteCommunicationKit';
import { AppError, AppErrorKind } from '../../core/error/AppError';
import { AiMessage, AiProtocol, AiReply } from './AiProtocol';
import { ModelProfile } from './ModelProfile';

const AI_TIMEOUT_MS: number = 180000;

/**
 * 独立 AI HTTP 调用器（180s 读取超时，与站点 ApiClient 隔离，绝不向第三方 AI 端点泄露 Pawchive Cookie）。
 */
export class AiCaller {
  async call(
    profile: ModelProfile,
    apiKey: string,
    systemPrompt: string,
    history: AiMessage[],
    prompt: string,
    imageDataUrl?: string
  ): Promise<AiReply> {
    if (profile.url.trim().length === 0 || profile.model.trim().length === 0) {
      throw new AppError(AppErrorKind.UNKNOWN, 'AI 模型档案配置不完整（缺少接口地址或模型名）');
    }

    const built = AiProtocol.buildRequest(profile, apiKey, systemPrompt, history, prompt, imageDataUrl);
    const rcpHeaders: rcp.RequestHeaders = {};
    const headerKeys = Object.keys(built.headers);
    for (let i = 0; i < headerKeys.length; i++) {
      const k = headerKeys[i];
      rcpHeaders[k.toLowerCase()] = built.headers[k];
    }

    let session: rcp.Session | undefined = undefined;
    try {
      session = rcp.createSession({
        requestConfiguration: {
          transfer: {
            autoRedirect: true,
            timeout: {
              connectMs: 30000,
              transferMs: AI_TIMEOUT_MS
            }
          }
        }
      });
      const req = new rcp.Request(built.url, 'POST', rcpHeaders, built.body);
      const response = await session.fetch(req);
      const text = response.toString() ?? '';
      if (response.statusCode < 200 || response.statusCode >= 300) {
        const snippet = text.trim().substring(0, Math.min(200, text.trim().length));
        throw AppError.fromHttpStatus(response.statusCode, `AI 接口返回 HTTP ${response.statusCode}: ${snippet}`);
      }
      return AiProtocol.parseReply(profile.apiType, text);
    } catch (e) {
      if (e instanceof AppError) {
        throw e;
      }
      throw new AppError(AppErrorKind.NETWORK, `调用 AI 接口失败：${String(e)}`);
    } finally {
      if (session !== undefined) {
        try {
          session.close();
        } catch (_ce) {
          // ignore
        }
      }
    }
  }

  async testConnectivity(profile: ModelProfile, apiKey: string): Promise<string> {
    const reply = await this.call(
      profile,
      apiKey,
      'You are a connectivity probe.',
      [],
      'Reply with exactly: OK'
    );
    const body = (reply.text ?? '').trim();
    if (body.length === 0) {
      throw new AppError(AppErrorKind.PARSE, '接口返回成功但正文为空');
    }
    const extras: string[] = [];
    if (reply.reasoningChars > 0) {
      extras.push(`思考 ${reply.reasoningChars} 字`);
    }
    if (reply.searchSignal) {
      extras.push('联网检索已触发');
    }
    return extras.length > 0 ? `连通成功（${extras.join(' · ')}）：${body}` : `连通成功：${body}`;
  }
}
