import { webview } from '@kit.ArkWeb';
import { ApiConstants } from '../api/ApiConstants';
import { FlexParsers, JsonObject } from '../api/FlexParsers';
import { SecureStore } from '../store/SecureStore';
import { Logger } from '../util/Logger';

const TAG: string = 'CloudflareManager';
const ALIAS_CLEARANCE: string = 'archive_cf_clearance_v1';
const POLL_INTERVAL_MS: number = 500;

export interface ClearanceCredential {
  cookie: string;
  userAgent: string;
  savedAt: number;
}

export type ChallengeStartHandler = (targetUrl: string, userAgent: string) => void;

/**
 * Cloudflare 托管挑战管理器（对齐上游 core/api/CloudflareManager.kt）。
 *
 * - 隐藏 ArkWeb 加载目标站点执行 JS 挑战，提取 `cf_clearance` 并绑定应用专属 UA
 * - 单飞机制（inFlight Promise 复用），避免并发拉起多次过盾
 * - 剥离 `session=` 段，防止过盾凭据污染登录态
 * - 加密持久化 25 分钟 TTL
 */
export class CloudflareManager {
  private readonly secureStore: SecureStore;
  private cached?: ClearanceCredential;
  private inFlight?: Promise<boolean>;
  private challengeStartHandler?: ChallengeStartHandler;
  private challengeUrl: string = ApiConstants.MAIN_BASE_URL;

  constructor(secureStore: SecureStore) {
    this.secureStore = secureStore;
  }

  /**
   * 剥离 Cookie 字符串中的 `session=` 段（仅保留 cf_clearance 等非会话项）。
   */
  static stripSessionTokens(cookie: string): string {
    if (cookie.trim().length === 0) {
      return '';
    }
    const parts = cookie.split(';');
    const kept: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const seg = parts[i].trim();
      if (seg.length === 0) {
        continue;
      }
      if (seg.toLowerCase().startsWith('session=')) {
        continue;
      }
      kept.push(seg);
    }
    return kept.join('; ');
  }

  static containsCfClearance(cookie: string): boolean {
    return cookie.toLowerCase().includes('cf_clearance=');
  }

  async init(): Promise<void> {
    const raw = await this.secureStore.get(ALIAS_CLEARANCE);
    if (raw === undefined || raw.trim().length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(raw) as JsonObject;
      const cookie = FlexParsers.readString(parsed, 'cookie') ?? '';
      const ua = FlexParsers.readString(parsed, 'userAgent') ?? '';
      const savedAt = FlexParsers.readNumber(parsed, 'savedAt') ?? 0;
      if (cookie.length > 0 && ua.length > 0 && Date.now() - savedAt < ApiConstants.CLEARANCE_TTL_MS) {
        this.cached = {
          cookie: CloudflareManager.stripSessionTokens(cookie),
          userAgent: ua,
          savedAt: savedAt
        };
      }
    } catch (e) {
      Logger.w(TAG, `loadPersisted clearance failed: ${String(e)}`);
    }
  }

  registerWebChallengeHost(handler: ChallengeStartHandler): void {
    this.challengeStartHandler = handler;
  }

  unregisterWebChallengeHost(): void {
    this.challengeStartHandler = undefined;
  }

  setTargetBaseUrl(baseUrl: string): void {
    const trimmed = baseUrl.trim();
    if (trimmed.length > 0) {
      this.challengeUrl = trimmed.endsWith('/') ? trimmed : `${trimmed}/`;
    } else {
      this.challengeUrl = ApiConstants.MAIN_BASE_URL;
    }
  }

  getClearance(): ClearanceCredential | undefined {
    if (this.cached === undefined) {
      return undefined;
    }
    if (Date.now() - this.cached.savedAt >= ApiConstants.CLEARANCE_TTL_MS) {
      this.cached = undefined;
      return undefined;
    }
    return this.cached;
  }

  getUserAgent(): string {
    const cred = this.getClearance();
    return cred !== undefined ? cred.userAgent : ApiConstants.APP_USER_AGENT;
  }

  async clear(): Promise<void> {
    this.cached = undefined;
    await this.secureStore.remove(ALIAS_CLEARANCE);
  }

  /**
   * 尝试确保拥有有效过盾凭据；force=true 时强制重过盾（如遇 403）。
   */
  async ensureClearance(force: boolean = false): Promise<boolean> {
    if (!force && this.getClearance() !== undefined) {
      return true;
    }
    if (this.inFlight !== undefined) {
      return this.inFlight;
    }
    if (this.challengeStartHandler === undefined) {
      Logger.w(TAG, 'No ArkWeb challenge host registered yet; skipping challenge.');
      return false;
    }

    const job: Promise<boolean> = this.runChallenge();
    this.inFlight = job;
    try {
      return await job;
    } finally {
      if (this.inFlight === job) {
        this.inFlight = undefined;
      }
    }
  }

  private async runChallenge(): Promise<boolean> {
    const targetUrl = this.challengeUrl;
    const ua = ApiConstants.APP_USER_AGENT;
    try {
      if (this.challengeStartHandler !== undefined) {
        this.challengeStartHandler(targetUrl, ua);
      }
    } catch (e) {
      Logger.e(TAG, `start hidden ArkWeb challenge failed: ${String(e)}`);
      return false;
    }

    const deadline = Date.now() + ApiConstants.CHALLENGE_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const fetched = this.tryReadWebCookie(targetUrl);
      if (fetched !== undefined && CloudflareManager.containsCfClearance(fetched)) {
        await this.persist(fetched, ua);
        Logger.i(TAG, 'Cloudflare clearance acquired successfully.');
        return true;
      }
      await this.delay(POLL_INTERVAL_MS);
    }
    Logger.w(TAG, 'Cloudflare challenge timed out.');
    return false;
  }

  private tryReadWebCookie(url: string): string | undefined {
    try {
      const value = webview.WebCookieManager.fetchCookieSync(url);
      return value.length > 0 ? value : undefined;
    } catch (_e) {
      return undefined;
    }
  }

  private async persist(cookie: string, userAgent: string): Promise<void> {
    const clean = CloudflareManager.stripSessionTokens(cookie);
    const cred: ClearanceCredential = {
      cookie: clean,
      userAgent: userAgent,
      savedAt: Date.now()
    };
    this.cached = cred;
    await this.secureStore.put(ALIAS_CLEARANCE, JSON.stringify(cred));
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
