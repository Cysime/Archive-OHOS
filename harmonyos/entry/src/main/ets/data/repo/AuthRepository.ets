import { ApiClient, RawHttpResponse } from '../../core/api/ApiClient';
import { CloudflareManager } from '../../core/api/CloudflareManager';
import { PawchiveApi } from '../../core/api/PawchiveApi';
import { AppError, AppErrorKind } from '../../core/error/AppError';
import { AccountSession, SessionManager } from '../../core/store/SessionManager';
import { FavoriteRepository } from './FavoriteRepository';

export enum SessionValidity {
  UNKNOWN = 'UNKNOWN',
  CHECKING = 'CHECKING',
  VALID = 'VALID',
  INVALID = 'INVALID'
}

/**
 * 账号认证与多账号切换仓库（对齐上游 data/repository/AuthRepository.kt）。
 *
 * - 主登录方式：原生账号密码表单 POST `<baseUrl>/account/login`（autoRedirect=false，解析 302 Location 与 Set-Cookie 中的 session=）
 * - 备选方式：手动粘贴 `session` Cookie，或在白名单保护的注册 WebView 成功后自动探测并导入有效 session
 */
export class AuthRepository {
  private readonly sessionManager: SessionManager;
  private readonly apiClient: ApiClient;
  private readonly cloudflare: CloudflareManager;
  private readonly api: PawchiveApi;
  private readonly favorites: FavoriteRepository;

  constructor(
    sessionManager: SessionManager,
    apiClient: ApiClient,
    cloudflare: CloudflareManager,
    api: PawchiveApi,
    favorites: FavoriteRepository
  ) {
    this.sessionManager = sessionManager;
    this.apiClient = apiClient;
    this.cloudflare = cloudflare;
    this.api = api;
    this.favorites = favorites;
  }

  getActiveAccount(): AccountSession | undefined {
    return this.sessionManager.getActiveAccount();
  }

  getAccounts(): AccountSession[] {
    return this.sessionManager.getAccounts();
  }

  isLoggedIn(): boolean {
    return this.sessionManager.getActiveSessionCookie().length > 0;
  }

  /**
   * 账号密码直连登录（对齐上游 PawchiveLoginApi `POST /account/login`，不跟随重定向）。
   */
  async loginWithPassword(username: string, password: string): Promise<string> {
    const cleanUser = username.trim();
    if (cleanUser.length === 0 || password.length === 0) {
      throw new AppError(AppErrorKind.UNKNOWN, '请输入用户名和密码');
    }

    // 登录前先确保 Cloudflare clearance 就绪（主域可能开启托管挑战）
    await this.cloudflare.ensureClearance(false);

    const baseUrl = this.apiClient.getBaseUrl().replace(/\/+$/, '');
    const loginUrl = `${baseUrl}/account/login`;
    const formBody =
      `username=${encodeURIComponent(cleanUser)}&password=${encodeURIComponent(password)}&location=`;

    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Origin': baseUrl,
      'Referer': loginUrl
    };

    const resp = await this.apiClient.fetchRaw(loginUrl, {
      method: 'POST',
      headers: headers,
      body: formBody,
      autoRedirect: false,
      timeoutMs: 30000,
      allowCfRetry: true
    });

    if (resp.statusCode < 300 || resp.statusCode >= 400) {
      if (resp.statusCode === 403) {
        throw new AppError(AppErrorKind.CLOUDFLARE, '登录请求被安全盾拦截（403），请稍后重试或使用备选 Cookie 登录', 403);
      }
      if (resp.statusCode === 401) {
        throw new AppError(AppErrorKind.UNAUTHORIZED, '用户名或密码错误', 401);
      }
      throw AppError.fromHttpStatus(resp.statusCode, `登录失败（HTTP ${resp.statusCode}）`);
    }

    const locationHeader = this.readHeaderSingle(resp, 'location').toLowerCase();
    if (locationHeader.includes('/account/login') || locationHeader.endsWith('/login')) {
      throw new AppError(AppErrorKind.UNAUTHORIZED, '用户名或密码错误', 401);
    }

    const sessionCookie = this.extractSessionFromResponse(resp);
    if (sessionCookie.length === 0) {
      throw new AppError(AppErrorKind.SERVER, '登录失败：服务器未返回 session Cookie');
    }

    const saved = await this.sessionManager.saveSession(cleanUser, sessionCookie);
    if (!saved) {
      throw new AppError(AppErrorKind.STORAGE, '保存登录会话失败');
    }
    this.apiClient.clearMemoryCache();
    await this.favorites.refreshLocalCache();
    return cleanUser;
  }

  private readHeaderSingle(resp: RawHttpResponse, nameLower: string): string {
    const val = resp.headers[nameLower];
    if (val === undefined) {
      return '';
    }
    if (Array.isArray(val)) {
      return val.length > 0 ? val[0] : '';
    }
    return val;
  }

  private extractSessionFromResponse(resp: RawHttpResponse): string {
    // 1. 优先从 rcp 解析好的 cookies 数组提取
    for (let i = 0; i < resp.cookies.length; i++) {
      const c = resp.cookies[i];
      const val = (c.value ?? '').trim();
      if (c.name.toLowerCase() === 'session' && val.length > 0) {
        return `session=${val}`;
      }
    }

    // 2. 兜底从原始 Set-Cookie 响应头提取
    const rawSetCookie = resp.headers['set-cookie'];
    if (rawSetCookie !== undefined) {
      const list: string[] = Array.isArray(rawSetCookie) ? rawSetCookie : [rawSetCookie];
      for (let i = 0; i < list.length; i++) {
        const extracted = SessionManager.extractSessionCookie(list[i]);
        if (extracted.length > 0) {
          return extracted;
        }
      }
    }
    return '';
  }

  /**
   * 探测当前会话是否有效（对齐上游 AccountViewModel.checkSession：请求 /api/v1/account/favorites?type=artist）。
   */
  async checkSessionValidity(): Promise<SessionValidity> {
    if (!this.isLoggedIn()) {
      return SessionValidity.INVALID;
    }
    try {
      await this.api.getAccountFavorites('artist', 0, true);
      return SessionValidity.VALID;
    } catch (e) {
      if (e instanceof AppError && e.statusCode === 401) {
        return SessionValidity.INVALID;
      }
      return SessionValidity.UNKNOWN;
    }
  }

  /**
   * 从内嵌注册页获取到的 cookie 先探测有效性再落库，防止把未登录匿名 session 当成已登录。
   */
  async importSessionFromWebIfValid(rawCookie: string, fallbackName: string = 'Pawchive 用户'): Promise<boolean> {
    const extracted = SessionManager.extractSessionCookie(rawCookie);
    if (extracted.length === 0) {
      return false;
    }
    const prevActive = this.sessionManager.getActiveAccount();
    const ok = await this.sessionManager.saveSession(fallbackName, extracted);
    if (!ok) {
      return false;
    }
    this.apiClient.clearMemoryCache();
    const state = await this.checkSessionValidity();
    if (state === SessionValidity.VALID) {
      await this.favorites.refreshLocalCache();
      return true;
    }
    // 匿名会话：回退清理
    await this.sessionManager.removeAccount(fallbackName);
    if (prevActive !== undefined) {
      await this.sessionManager.switchAccount(prevActive.username);
    }
    return false;
  }

  async loginWithCookie(username: string, rawCookie: string): Promise<boolean> {
    const ok = await this.sessionManager.saveSession(username, rawCookie);
    if (ok) {
      this.apiClient.clearMemoryCache();
      await this.favorites.refreshLocalCache();
    }
    return ok;
  }

  async switchAccount(username: string): Promise<boolean> {
    const ok = await this.sessionManager.switchAccount(username);
    if (ok) {
      this.apiClient.clearMemoryCache();
      await this.favorites.refreshLocalCache();
    }
    return ok;
  }

  async removeAccount(username: string): Promise<void> {
    await this.sessionManager.removeAccount(username);
    this.apiClient.clearMemoryCache();
    await this.favorites.refreshLocalCache();
  }

  async logoutCurrent(): Promise<void> {
    await this.sessionManager.logoutCurrent();
    this.apiClient.clearMemoryCache();
    await this.favorites.refreshLocalCache();
  }
}
