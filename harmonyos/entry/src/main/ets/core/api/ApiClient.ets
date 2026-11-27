import { rcp } from '@kit.RemoteCommunicationKit';
import { ApiConstants } from './ApiConstants';
import { ApiMemoryCache } from './ApiMemoryCache';
import { CloudflareManager } from './CloudflareManager';
import { UrlProvider } from './UrlProvider';
import { AppError, AppErrorKind } from '../error/AppError';
import { SessionManager } from '../store/SessionManager';
import { SettingsManager } from '../store/SettingsManager';
import { Logger } from '../util/Logger';

const TAG: string = 'ApiClient';

export interface RequestOptions {
  method?: rcp.HttpMethod;
  headers?: Record<string, string>;
  body?: string;
  bypassCache?: boolean;
  autoRedirect?: boolean;
  timeoutMs?: number;
  allowCfRetry?: boolean;
}

export interface RawHttpResponse {
  statusCode: number;
  bodyText: string;
  bodyBytes?: ArrayBuffer;
  headers: rcp.ResponseHeaders;
  cookies: rcp.ResponseCookie[];
}

/**
 * 统一网络客户端（基于 HarmonyOS `@kit.RemoteCommunicationKit` rcp）。
 *
 * 承担上游 `ApiClient` + `BaseUrlInterceptor` + `SessionInterceptor` +
 * `ClearanceInterceptor` + `ClearanceRetryInterceptor` + `ApiMemoryCache` 的全部职责：
 * - 自动注入自定义非浏览器 User-Agent（file/img/t1 子域必需）
 * - 自动合并 `cf_clearance` 与登录 `session=` Cookie
 * - 403 自动触发 CloudflareManager 单飞过盾并重试一次
 * - GET JSON 响应 5 分钟 / 200 条 LRU 内存缓存（支持 `bypassCache` 与路径前缀失效）
 */
export class ApiClient {
  private readonly settings: SettingsManager;
  private readonly sessionManager: SessionManager;
  private readonly cloudflare: CloudflareManager;
  private readonly memoryCache: ApiMemoryCache = new ApiMemoryCache();
  private sharedSession?: rcp.Session;

  constructor(
    settings: SettingsManager,
    sessionManager: SessionManager,
    cloudflare: CloudflareManager
  ) {
    this.settings = settings;
    this.sessionManager = sessionManager;
    this.cloudflare = cloudflare;
  }

  private getSession(): rcp.Session {
    if (this.sharedSession === undefined) {
      const config: rcp.SessionConfiguration = {
        requestConfiguration: {
          transfer: {
            autoRedirect: true,
            timeout: {
              connectMs: 20000,
              transferMs: 60000
            }
          }
        }
      };
      try {
        this.sharedSession = rcp.createSession(config);
      } catch (e) {
        throw new AppError(AppErrorKind.NETWORK, `创建 HTTP 会话失败：${String(e)}`);
      }
    }
    return this.sharedSession;
  }

  getBaseUrl(): string {
    return this.settings.getSnapshot().baseUrl || ApiConstants.DEFAULT_BASE_URL;
  }

  getMemoryCache(): ApiMemoryCache {
    return this.memoryCache;
  }

  invalidateCachePrefix(pathPrefix: string): void {
    this.memoryCache.invalidateByPathPrefix(pathPrefix);
  }

  clearMemoryCache(): void {
    this.memoryCache.clear();
  }

  /**
   * 构造请求头（供图片加载器、AVPlayer MediaSource 及下载器共用）。
   */
  buildSiteHeaders(url: string, extraHeaders?: Record<string, string>): Record<string, string> {
    const out: Record<string, string> = {};
    const baseUrl = this.getBaseUrl();
    if (UrlProvider.isTargetSiteUrl(url, baseUrl)) {
      out['User-Agent'] = this.cloudflare.getUserAgent();
      const cookieParts: string[] = [];
      const clearance = this.cloudflare.getClearance();
      if (clearance !== undefined && clearance.cookie.length > 0) {
        cookieParts.push(clearance.cookie);
      }
      const sessionCookie = this.sessionManager.getActiveSessionCookie();
      if (sessionCookie.length > 0) {
        cookieParts.push(sessionCookie);
      }
      if (cookieParts.length > 0) {
        out['Cookie'] = cookieParts.join('; ');
      }
    }
    if (extraHeaders !== undefined) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        out[k] = extraHeaders[k];
      }
    }
    return out;
  }

  async requestApiJson(apiPath: string, options: RequestOptions = {}): Promise<string> {
    const cleanPath = apiPath.startsWith('/') ? apiPath : `/${apiPath}`;
    const fullUrl = `${UrlProvider.apiV1(this.getBaseUrl())}${cleanPath}`;
    const method: rcp.HttpMethod = options.method ?? 'GET';
    const useCache = method === 'GET' && !(options.bypassCache ?? false);
    const cacheKey = ApiMemoryCache.buildKey(this.sessionManager.getSessionNamespace(), fullUrl);

    if (useCache) {
      const cached = this.memoryCache.get(cacheKey);
      if (cached !== undefined) {
        return cached;
      }
    }

    const resp = await this.fetchRaw(fullUrl, {
      method: method,
      headers: options.headers,
      body: options.body,
      autoRedirect: options.autoRedirect ?? true,
      timeoutMs: options.timeoutMs ?? 60000,
      allowCfRetry: options.allowCfRetry ?? true
    });

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (useCache) {
        this.memoryCache.put(cacheKey, `/api/v1${cleanPath}`, resp.bodyText);
      }
      return resp.bodyText;
    }

    throw AppError.fromHttpStatus(resp.statusCode, this.extractErrorDetail(resp.bodyText, resp.statusCode));
  }

  async fetchBytes(url: string, timeoutMs: number = 60000): Promise<ArrayBuffer> {
    const resp = await this.fetchRaw(url, {
      method: 'GET',
      timeoutMs: timeoutMs,
      allowCfRetry: true
    });
    if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes !== undefined) {
      return resp.bodyBytes;
    }
    throw AppError.fromHttpStatus(resp.statusCode);
  }

  async fetchRaw(url: string, options: RequestOptions = {}): Promise<RawHttpResponse> {
    const method: rcp.HttpMethod = options.method ?? 'GET';
    const allowCfRetry = options.allowCfRetry ?? true;
    const result = await this.executeOnce(url, method, options);

    if (
      result.statusCode === 403 &&
      allowCfRetry &&
      UrlProvider.isTargetSiteUrl(url, this.getBaseUrl())
    ) {
      Logger.w(TAG, `HTTP 403 on ${url}; refreshing Cloudflare clearance and retrying once.`);
      const refreshed = await this.cloudflare.ensureClearance(true);
      if (refreshed) {
        return this.executeOnce(url, method, options);
      }
    }

    return result;
  }

  private async executeOnce(
    url: string,
    method: rcp.HttpMethod,
    options: RequestOptions
  ): Promise<RawHttpResponse> {
    const mergedHeaders = this.buildSiteHeaders(url, options.headers);
    const rcpHeaders: rcp.RequestHeaders = {};
    const headerKeys = Object.keys(mergedHeaders);
    for (let i = 0; i < headerKeys.length; i++) {
      const key = headerKeys[i];
      rcpHeaders[key.toLowerCase()] = mergedHeaders[key];
    }

    const timeoutMs = options.timeoutMs ?? 60000;
    const reqConfig: rcp.Configuration = {
      transfer: {
        autoRedirect: options.autoRedirect ?? true,
        timeout: {
          connectMs: Math.min(20000, timeoutMs),
          transferMs: timeoutMs
        }
      }
    };

    const req = new rcp.Request(url, method, rcpHeaders, options.body, undefined, undefined, reqConfig);
    try {
      const response = await this.getSession().fetch(req);
      const text = response.toString() ?? '';
      return {
        statusCode: response.statusCode,
        bodyText: text,
        bodyBytes: response.body,
        headers: response.headers,
        cookies: response.cookies ?? []
      };
    } catch (e) {
      const msg = String(e);
      if (msg.toLowerCase().includes('timeout')) {
        throw new AppError(AppErrorKind.TIMEOUT, `请求超时：${msg}`);
      }
      throw new AppError(AppErrorKind.NETWORK, `网络请求失败：${msg}`);
    }
  }

  private extractErrorDetail(bodyText: string, statusCode: number): string | undefined {
    const trimmed = bodyText.trim();
    if (trimmed.length === 0 || !trimmed.startsWith('{')) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object | string | undefined>;
      const errVal = parsed['error'];
      if (typeof errVal === 'string' && errVal.trim().length > 0) {
        return `${errVal} (${statusCode})`;
      }
    } catch (_e) {
      // ignore non-json error body
    }
    return undefined;
  }

  close(): void {
    if (this.sharedSession !== undefined) {
      this.sharedSession.close();
      this.sharedSession = undefined;
    }
  }
}
