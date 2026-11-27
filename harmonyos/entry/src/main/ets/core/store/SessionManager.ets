import { ApiConstants } from '../api/ApiConstants';
import { FlexParsers, JsonObject, JsonValue } from '../api/FlexParsers';
import { SecureStore } from './SecureStore';
import { Logger } from '../util/Logger';

const TAG: string = 'SessionManager';
const ALIAS_ACCOUNTS: string = 'archive_session_accounts_v1';

export interface AccountSession {
  username: string;
  sessionCookie: string;
  savedAt: number;
}

export type SessionListener = (active?: AccountSession) => void;

/**
 * 多账号会话管理器（对齐上游 core/store/SessionManager.kt）。
 *
 * - 支持从完整 Cookie 头中精准提取 `session=` 段
 * - 多账号隔离切换
 * - 60 秒登录宽限期，防止刚登录时偶发 401 误踢出
 */
export class SessionManager {
  private readonly secureStore: SecureStore;
  private accounts: AccountSession[] = [];
  private activeUsername: string = '';
  private lastLoginAt: number = 0;
  private readonly listeners: Set<SessionListener> = new Set<SessionListener>();

  constructor(secureStore: SecureStore) {
    this.secureStore = secureStore;
  }

  /**
   * 从手动粘贴的完整 Cookie 字符串或纯 session 值中提取标准 `session=<value>`。
   */
  static extractSessionCookie(raw: string): string {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (!trimmed.includes('=')) {
      return `session=${trimmed}`;
    }
    const parts = trimmed.split(';');
    for (let i = 0; i < parts.length; i++) {
      const seg = parts[i].trim();
      if (seg.toLowerCase().startsWith('session=')) {
        const val = seg.substring('session='.length).trim();
        return val.length > 0 ? `session=${val}` : '';
      }
    }
    return '';
  }

  async init(): Promise<void> {
    const raw = await this.secureStore.get(ALIAS_ACCOUNTS);
    if (raw === undefined || raw.trim().length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(raw) as JsonObject;
      this.activeUsername = FlexParsers.readString(parsed, 'activeUsername') ?? '';
      const rawList = FlexParsers.asArray(parsed['accounts']);
      const loaded: AccountSession[] = [];
      for (let i = 0; i < rawList.length; i++) {
        const item = FlexParsers.asObject(rawList[i]);
        if (item === undefined) {
          continue;
        }
        const username = FlexParsers.readString(item, 'username') ?? '';
        const cookie = FlexParsers.readString(item, 'sessionCookie') ?? '';
        if (username.length > 0 && cookie.length > 0) {
          loaded.push({
            username: username,
            sessionCookie: cookie,
            savedAt: FlexParsers.readNumber(item, 'savedAt') ?? 0
          });
        }
      }
      this.accounts = loaded;
    } catch (e) {
      Logger.w(TAG, `Failed to decode persisted sessions: ${String(e)}`);
      this.accounts = [];
      this.activeUsername = '';
    }
  }

  getActiveAccount(): AccountSession | undefined {
    if (this.activeUsername.length === 0) {
      return undefined;
    }
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].username === this.activeUsername) {
        return this.accounts[i];
      }
    }
    return undefined;
  }

  getActiveSessionCookie(): string {
    const active = this.getActiveAccount();
    return active !== undefined ? active.sessionCookie : '';
  }

  getSessionNamespace(): string {
    return FlexParsers.simpleHash(this.getActiveSessionCookie());
  }

  getAccounts(): AccountSession[] {
    return this.accounts.slice();
  }

  isWithinLoginGracePeriod(nowMs: number = Date.now()): boolean {
    return this.lastLoginAt > 0 && (nowMs - this.lastLoginAt) < ApiConstants.LOGIN_GRACE_PERIOD_MS;
  }

  subscribe(listener: SessionListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: SessionListener): void {
    this.listeners.delete(listener);
  }

  private emit(): void {
    const active = this.getActiveAccount();
    this.listeners.forEach((fn: SessionListener) => {
      fn(active);
    });
  }

  private async persist(): Promise<void> {
    const payload: Record<string, JsonValue> = {
      'activeUsername': this.activeUsername,
      'accounts': this.accounts as Object
    };
    await this.secureStore.put(ALIAS_ACCOUNTS, JSON.stringify(payload));
  }

  async saveSession(username: string, rawCookie: string): Promise<boolean> {
    const cookie = SessionManager.extractSessionCookie(rawCookie);
    const cleanUser = username.trim().length > 0 ? username.trim() : 'Account';
    if (cookie.length === 0) {
      return false;
    }
    const now = Date.now();
    let updated = false;
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].username === cleanUser) {
        this.accounts[i] = {
          username: cleanUser,
          sessionCookie: cookie,
          savedAt: now
        };
        updated = true;
        break;
      }
    }
    if (!updated) {
      this.accounts.push({
        username: cleanUser,
        sessionCookie: cookie,
        savedAt: now
      });
    }
    this.activeUsername = cleanUser;
    this.lastLoginAt = now;
    await this.persist();
    this.emit();
    return true;
  }

  async switchAccount(username: string): Promise<boolean> {
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].username === username) {
        this.activeUsername = username;
        await this.persist();
        this.emit();
        return true;
      }
    }
    return false;
  }

  async removeAccount(username: string): Promise<void> {
    this.accounts = this.accounts.filter((acc: AccountSession) => acc.username !== username);
    if (this.activeUsername === username) {
      this.activeUsername = this.accounts.length > 0 ? this.accounts[0].username : '';
    }
    await this.persist();
    this.emit();
  }

  async logoutCurrent(): Promise<void> {
    if (this.activeUsername.length > 0) {
      await this.removeAccount(this.activeUsername);
    }
  }
}
