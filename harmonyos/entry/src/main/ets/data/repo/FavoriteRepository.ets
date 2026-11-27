import { AttachmentDto, DtoParsers, PostDetailDto, PostSummaryDto, SessionFavoriteDto } from '../../core/api/Dtos';
import { JsonValue } from '../../core/api/FlexParsers';
import { PawchiveApi } from '../../core/api/PawchiveApi';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { SessionManager } from '../../core/store/SessionManager';
import { SettingsManager } from '../../core/store/SettingsManager';
import { HtmlParser } from '../../core/util/HtmlParser';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'FavoriteRepository';

export interface ArchivedPostHit {
  service: string;
  creatorId: string;
  postId: string;
  creatorName: string;
  title: string;
  excerpt: string;
  updatedAt: number;
}

export interface OfflineArchiveStats {
  count: number;
  totalBytes: number;
}

export type FavoriteChangeListener = () => void;

/**
 * 收藏与离线全文归档仓库（对齐上游 FavoriteActions + BookmarkManager + PendingFavoriteActionRepository）。
 *
 * - 本地收藏：无需登录即可收藏帖子并持久化到 RDB（按账号命名空间隔离）
 * - 全文离线归档：收藏帖在打开详情页时通过 `ensureArchived` 写入完整 PostDetail JSON，供离线搜索与断网回退阅读
 * - 云端同步：登录后写入云端并立即失效 `/api/v1/account/favorites` 缓存；断网写入 `pending_favorite_actions` 队列
 * - 收藏即订阅：若开启 `autoSubscribeOnFavorite`，收藏创作者时同步写入 `creator_subscriptions`
 */
export class FavoriteRepository {
  private readonly api: PawchiveApi;
  private readonly database: ArchiveDatabase;
  private readonly sessionManager: SessionManager;
  private readonly settings: SettingsManager;

  private favoritePostKeys: Set<string> = new Set<string>();
  private favoriteCreatorKeys: Set<string> = new Set<string>();
  private readonly listeners: Set<FavoriteChangeListener> = new Set<FavoriteChangeListener>();

  constructor(
    api: PawchiveApi,
    database: ArchiveDatabase,
    sessionManager: SessionManager,
    settings: SettingsManager
  ) {
    this.api = api;
    this.database = database;
    this.sessionManager = sessionManager;
    this.settings = settings;
  }

  static postKey(service: string, creatorId: string, postId: string): string {
    return `${service.toLowerCase()}:${creatorId}:${postId}`;
  }

  static creatorKey(service: string, creatorId: string): string {
    return `${service.toLowerCase()}:${creatorId}`;
  }

  private ns(): string {
    return this.sessionManager.getSessionNamespace();
  }

  subscribe(listener: FavoriteChangeListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: FavoriteChangeListener): void {
    this.listeners.delete(listener);
  }

  private emit(): void {
    this.listeners.forEach((fn: FavoriteChangeListener) => {
      fn();
    });
  }

  async refreshLocalCache(): Promise<void> {
    this.favoritePostKeys.clear();
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT service, creator_id, post_id FROM favorite_posts WHERE account_ns = ?',
        [this.ns()]
      );
      try {
        while (rs.goToNextRow()) {
          this.favoritePostKeys.add(
            FavoriteRepository.postKey(rs.getString(0), rs.getString(1), rs.getString(2))
          );
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `refreshLocalCache failed: ${String(e)}`);
    }
    this.emit();
  }

  isPostFavorited(service: string, creatorId: string, postId: string): boolean {
    return this.favoritePostKeys.has(FavoriteRepository.postKey(service, creatorId, postId));
  }

  isCreatorFavorited(service: string, creatorId: string): boolean {
    return this.favoriteCreatorKeys.has(FavoriteRepository.creatorKey(service, creatorId));
  }

  getFavoritedCreatorKeysSnapshot(): Set<string> {
    return new Set<string>(this.favoriteCreatorKeys);
  }

  async listLocalFavoritePosts(): Promise<PostSummaryDto[]> {
    const out: PostSummaryDto[] = [];
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT service, creator_id, post_id, title, excerpt, published, cover_json, preview_only FROM favorite_posts WHERE account_ns = ? ORDER BY saved_at DESC',
        [this.ns()]
      );
      try {
        while (rs.goToNextRow()) {
          const coverJson = rs.isColumnNull(6) ? '' : rs.getString(6);
          let cover: AttachmentDto | undefined = undefined;
          if (coverJson.length > 0) {
            try {
              cover = DtoParsers.parseAttachment(JSON.parse(coverJson) as JsonValue);
            } catch (_pe) {
              cover = undefined;
            }
          }
          out.push({
            service: rs.getString(0),
            creatorId: rs.getString(1),
            postId: rs.getString(2),
            title: rs.getString(3),
            excerpt: rs.isColumnNull(4) ? undefined : rs.getString(4),
            published: rs.isColumnNull(5) ? undefined : rs.getString(5),
            cover: cover,
            previewOnly: rs.getLong(7) !== 0
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `listLocalFavoritePosts failed: ${String(e)}`);
    }
    return out;
  }

  async toggleFavoritePost(post: PostSummaryDto): Promise<boolean> {
    const key = FavoriteRepository.postKey(post.service, post.creatorId, post.postId);
    const currentlyFav = this.favoritePostKeys.has(key);
    const store = this.database.getStore();

    if (currentlyFav) {
      this.favoritePostKeys.delete(key);
      try {
        await store.executeSql(
          'DELETE FROM favorite_posts WHERE account_ns = ? AND service = ? AND creator_id = ? AND post_id = ?',
          [this.ns(), post.service, post.creatorId, post.postId]
        );
      } catch (e) {
        Logger.w(TAG, `delete favorite_posts failed: ${String(e)}`);
      }
      this.emit();
      await this.syncPostCloudAction('REMOVE', post.service, post.creatorId, post.postId);
      return false;
    }

    this.favoritePostKeys.add(key);
    try {
      const coverJson = post.cover !== undefined ? JSON.stringify(post.cover) : null;
      await store.executeSql(
        'INSERT OR REPLACE INTO favorite_posts (account_ns, service, creator_id, post_id, title, excerpt, published, cover_json, preview_only, saved_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          this.ns(),
          post.service,
          post.creatorId,
          post.postId,
          post.title,
          post.excerpt ?? null,
          post.published ?? null,
          coverJson,
          post.previewOnly ? 1 : 0,
          Date.now()
        ]
      );
    } catch (e) {
      Logger.w(TAG, `insert favorite_posts failed: ${String(e)}`);
    }
    this.emit();
    await this.syncPostCloudAction('ADD', post.service, post.creatorId, post.postId);
    return true;
  }

  async toggleFavoriteCreator(service: string, creatorId: string, creatorName: string): Promise<boolean> {
    const key = FavoriteRepository.creatorKey(service, creatorId);
    const currentlyFav = this.favoriteCreatorKeys.has(key);
    if (currentlyFav) {
      this.favoriteCreatorKeys.delete(key);
      this.emit();
      await this.syncCreatorCloudAction('REMOVE', service, creatorId);
      return false;
    }

    this.favoriteCreatorKeys.add(key);
    if (this.settings.getSnapshot().autoSubscribeOnFavorite) {
      await this.subscribeCreatorLocal(service, creatorId, creatorName);
    }
    this.emit();
    await this.syncCreatorCloudAction('ADD', service, creatorId);
    return true;
  }

  private async subscribeCreatorLocal(service: string, creatorId: string, creatorName: string): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql(
        'INSERT OR IGNORE INTO creator_subscriptions (service, creator_id, creator_name, last_post_id, last_checked_at, created_at) VALUES (?, ?, ?, NULL, 0, ?)',
        [service, creatorId, creatorName, Date.now()]
      );
    } catch (e) {
      Logger.w(TAG, `autoSubscribeOnFavorite insert failed: ${String(e)}`);
    }
  }

  /**
   * 收藏帖打开详情页时补建全文离线归档（供离线搜索与断网回退阅读）。
   */
  async ensureArchived(detail: PostDetailDto, creatorName: string): Promise<void> {
    if (!this.isPostFavorited(detail.service, detail.creatorId, detail.postId)) {
      return;
    }
    try {
      const json = JSON.stringify(detail);
      const plain = HtmlParser.htmlToPlainText(detail.contentHtml);
      const byteSize = json.length * 2;
      const store = this.database.getStore();
      await store.executeSql(
        'INSERT OR REPLACE INTO offline_post_archives (service, creator_id, post_id, creator_name, title, plain_text, detail_json, byte_size, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          detail.service,
          detail.creatorId,
          detail.postId,
          creatorName,
          detail.title,
          plain,
          json,
          byteSize,
          Date.now()
        ]
      );
    } catch (e) {
      Logger.w(TAG, `ensureArchived failed: ${String(e)}`);
    }
  }

  async getArchivedPost(service: string, creatorId: string, postId: string): Promise<PostDetailDto | undefined> {
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT detail_json FROM offline_post_archives WHERE service = ? AND creator_id = ? AND post_id = ? LIMIT 1',
        [service, creatorId, postId]
      );
      try {
        if (rs.goToFirstRow()) {
          const json = rs.getString(0);
          return JSON.parse(json) as PostDetailDto;
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `getArchivedPost failed: ${String(e)}`);
    }
    return undefined;
  }

  async searchArchivedPosts(query: string): Promise<ArchivedPostHit[]> {
    const q = query.trim();
    const out: ArchivedPostHit[] = [];
    try {
      const store = this.database.getStore();
      const sql = q.length > 0
        ? 'SELECT service, creator_id, post_id, creator_name, title, plain_text, updated_at FROM offline_post_archives WHERE title LIKE ? OR creator_name LIKE ? OR plain_text LIKE ? ORDER BY updated_at DESC LIMIT 100'
        : 'SELECT service, creator_id, post_id, creator_name, title, plain_text, updated_at FROM offline_post_archives ORDER BY updated_at DESC LIMIT 100';
      const pattern = `%${q}%`;
      const rs = q.length > 0
        ? await store.querySql(sql, [pattern, pattern, pattern])
        : await store.querySql(sql);
      try {
        while (rs.goToNextRow()) {
          const plain = rs.getString(5);
          out.push({
            service: rs.getString(0),
            creatorId: rs.getString(1),
            postId: rs.getString(2),
            creatorName: rs.getString(3),
            title: rs.getString(4),
            excerpt: plain.substring(0, Math.min(160, plain.length)),
            updatedAt: rs.getLong(6)
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `searchArchivedPosts failed: ${String(e)}`);
    }
    return out;
  }

  async getArchiveStats(): Promise<OfflineArchiveStats> {
    try {
      const store = this.database.getStore();
      const rs = await store.querySql('SELECT COUNT(*), COALESCE(SUM(byte_size), 0) FROM offline_post_archives');
      try {
        if (rs.goToFirstRow()) {
          return {
            count: rs.getLong(0),
            totalBytes: rs.getLong(1)
          };
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `getArchiveStats failed: ${String(e)}`);
    }
    return { count: 0, totalBytes: 0 };
  }

  /**
   * 拉取云端收藏的帖子列表（强制 bypassCache，并在本页内独立去重，不与旧状态混去重）。
   */
  async fetchCloudFavoritePosts(offset: number = 0): Promise<PostSummaryDto[]> {
    if (this.sessionManager.getActiveSessionCookie().length === 0) {
      return [];
    }
    const items = await this.api.getAccountFavorites('post', offset, true);
    const seen: Set<string> = new Set<string>();
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < items.length; i++) {
      const fav = items[i];
      const creatorId = fav.user ?? fav.id;
      const key = FavoriteRepository.postKey(fav.service, creatorId, fav.id);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      this.favoritePostKeys.add(key);
      out.push({
        service: fav.service,
        creatorId: creatorId,
        postId: fav.id,
        title: fav.title ?? fav.name ?? `Post #${fav.id}`,
        published: fav.updated,
        previewOnly: false
      });
    }
    this.emit();
    return out;
  }

  async fetchCloudFavoriteCreators(): Promise<SessionFavoriteDto[]> {
    if (this.sessionManager.getActiveSessionCookie().length === 0) {
      return [];
    }
    const items = await this.api.getAccountFavorites('artist', 0, true);
    const seen: Set<string> = new Set<string>();
    const out: SessionFavoriteDto[] = [];
    this.favoriteCreatorKeys.clear();
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const key = FavoriteRepository.creatorKey(item.service, item.id);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      this.favoriteCreatorKeys.add(key);
      out.push(item);
    }
    this.emit();
    return out;
  }

  private async syncPostCloudAction(
    action: 'ADD' | 'REMOVE',
    service: string,
    creatorId: string,
    postId: string
  ): Promise<void> {
    if (this.sessionManager.getActiveSessionCookie().length === 0) {
      return;
    }
    try {
      if (action === 'ADD') {
        await this.api.addFavoritePost(service, creatorId, postId);
      } else {
        await this.api.removeFavoritePost(service, creatorId, postId);
      }
    } catch (e) {
      Logger.w(TAG, `cloud favorite post ${action} failed, queuing offline: ${String(e)}`);
      await this.enqueuePendingAction('POST', action, service, creatorId, postId);
    }
  }

  private async syncCreatorCloudAction(
    action: 'ADD' | 'REMOVE',
    service: string,
    creatorId: string
  ): Promise<void> {
    if (this.sessionManager.getActiveSessionCookie().length === 0) {
      return;
    }
    try {
      if (action === 'ADD') {
        await this.api.addFavoriteCreator(service, creatorId);
      } else {
        await this.api.removeFavoriteCreator(service, creatorId);
      }
    } catch (e) {
      Logger.w(TAG, `cloud favorite creator ${action} failed, queuing offline: ${String(e)}`);
      await this.enqueuePendingAction('CREATOR', action, service, creatorId, '');
    }
  }

  private async enqueuePendingAction(
    targetType: 'POST' | 'CREATOR',
    actionType: 'ADD' | 'REMOVE',
    service: string,
    creatorId: string,
    postId: string
  ): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql(
        'INSERT INTO pending_favorite_actions (account_ns, target_type, action_type, service, creator_id, post_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [this.ns(), targetType, actionType, service, creatorId, postId, Date.now()]
      );
    } catch (e) {
      Logger.w(TAG, `enqueuePendingAction failed: ${String(e)}`);
    }
  }

  async flushPendingActions(): Promise<number> {
    if (this.sessionManager.getActiveSessionCookie().length === 0) {
      return 0;
    }
    let flushed = 0;
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT id, target_type, action_type, service, creator_id, post_id FROM pending_favorite_actions WHERE account_ns = ? ORDER BY id ASC',
        [this.ns()]
      );
      const idsToDelete: number[] = [];
      try {
        while (rs.goToNextRow()) {
          const id = rs.getLong(0);
          const targetType = rs.getString(1);
          const actionType = rs.getString(2);
          const service = rs.getString(3);
          const creatorId = rs.getString(4);
          const postId = rs.getString(5);
          try {
            if (targetType === 'POST') {
              if (actionType === 'ADD') {
                await this.api.addFavoritePost(service, creatorId, postId);
              } else {
                await this.api.removeFavoritePost(service, creatorId, postId);
              }
            } else {
              if (actionType === 'ADD') {
                await this.api.addFavoriteCreator(service, creatorId);
              } else {
                await this.api.removeFavoriteCreator(service, creatorId);
              }
            }
            idsToDelete.push(id);
            flushed++;
          } catch (_e) {
            break;
          }
        }
      } finally {
        rs.close();
      }
      for (let i = 0; i < idsToDelete.length; i++) {
        await store.executeSql('DELETE FROM pending_favorite_actions WHERE id = ?', [idsToDelete[i]]);
      }
    } catch (e) {
      Logger.w(TAG, `flushPendingActions failed: ${String(e)}`);
    }
    return flushed;
  }
}
