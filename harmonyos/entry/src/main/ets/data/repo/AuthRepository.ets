import { ApiClient } from '../../core/api/ApiClient';
import { AccountSession, SessionManager } from '../../core/store/SessionManager';
import { FavoriteRepository } from './FavoriteRepository';

/**
 * 账号认证与多账号切换仓库（对齐上游 data/repository/AuthRepository.kt）。
 *
 * - 支持粘贴 `session` Cookie 或通过内置 ArkWeb 登录后自动提取 `session=`
 * - 切号 / 登出时立即清空 GET 内存缓存并刷新本地收藏快照
 */
export class AuthRepository {
  private readonly sessionManager: SessionManager;
  private readonly apiClient: ApiClient;
  private readonly favorites: FavoriteRepository;

  constructor(
    sessionManager: SessionManager,
    apiClient: ApiClient,
    favorites: FavoriteRepository
  ) {
    this.sessionManager = sessionManager;
    this.apiClient = apiClient;
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
