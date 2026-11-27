import { ApiConstants } from './ApiConstants';

interface CacheEntry {
  body: string;
  cachedAt: number;
  path: string;
}

/**
 * GET JSON 响应内存缓存（5 分钟 TTL、200 条 LRU、按会话命名空间隔离、支持路径前缀失效）。
 * 对齐上游 core/api/ApiMemoryCache.kt。
 */
export class ApiMemoryCache {
  private readonly maxEntries: number;
  private readonly ttlMs: number;
  private readonly entries: Map<string, CacheEntry> = new Map<string, CacheEntry>();

  constructor(
    maxEntries: number = ApiConstants.MEMORY_CACHE_MAX_ENTRIES,
    ttlMs: number = ApiConstants.MEMORY_CACHE_TTL_MS
  ) {
    this.maxEntries = maxEntries;
    this.ttlMs = ttlMs;
  }

  static buildKey(sessionNamespace: string, url: string): string {
    return `${sessionNamespace}|${url}`;
  }

  get(key: string, nowMs: number = Date.now()): string | undefined {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return undefined;
    }
    if (nowMs - entry.cachedAt >= this.ttlMs) {
      this.entries.delete(key);
      return undefined;
    }
    // 刷新 LRU 顺序
    this.entries.delete(key);
    this.entries.set(key, entry);
    return entry.body;
  }

  put(key: string, path: string, body: string, nowMs: number = Date.now()): void {
    if (this.entries.has(key)) {
      this.entries.delete(key);
    } else if (this.entries.size >= this.maxEntries) {
      const oldestKey = this.entries.keys().next().value as string | undefined;
      if (oldestKey !== undefined) {
        this.entries.delete(oldestKey);
      }
    }
    const entry: CacheEntry = {
      body: body,
      cachedAt: nowMs,
      path: path
    };
    this.entries.set(key, entry);
  }

  /**
   * 写操作后失效特定路径前缀的缓存（例如 `/api/v1/account/favorites`）。
   */
  invalidateByPathPrefix(pathPrefix: string): void {
    const keysToDelete: string[] = [];
    this.entries.forEach((entry: CacheEntry, key: string) => {
      if (entry.path.startsWith(pathPrefix)) {
        keysToDelete.push(key);
      }
    });
    for (let i = 0; i < keysToDelete.length; i++) {
      this.entries.delete(keysToDelete[i]);
    }
  }

  clear(): void {
    this.entries.clear();
  }

  size(): number {
    return this.entries.size;
  }
}
