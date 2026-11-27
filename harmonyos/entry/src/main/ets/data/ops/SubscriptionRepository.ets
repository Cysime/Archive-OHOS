import { notificationManager } from '@kit.NotificationKit';
import { PawchiveApi } from '../../core/api/PawchiveApi';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'SubscriptionRepo';

export interface CreatorSubscription {
  service: string;
  creatorId: string;
  creatorName: string;
  lastPostId?: string;
  lastCheckedAt: number;
  createdAt: number;
}

export interface ContentUpdateItem {
  id: string;
  service: string;
  creatorId: string;
  creatorName: string;
  postId: string;
  postTitle: string;
  published?: string;
  isRead: boolean;
  detectedAt: number;
}

export type NotificationChangeListener = () => void;

/**
 * 创作者订阅与应用内通知中心仓库（持久化于 RDB `creator_subscriptions` & `content_updates`）。
 */
export class SubscriptionRepository {
  private readonly api: PawchiveApi;
  private readonly database: ArchiveDatabase;
  private readonly listeners: Set<NotificationChangeListener> = new Set<NotificationChangeListener>();

  constructor(api: PawchiveApi, database: ArchiveDatabase) {
    this.api = api;
    this.database = database;
  }

  subscribeListener(fn: NotificationChangeListener): void {
    this.listeners.add(fn);
  }

  unsubscribeListener(fn: NotificationChangeListener): void {
    this.listeners.delete(fn);
  }

  private emit(): void {
    this.listeners.forEach((fn: NotificationChangeListener) => {
      fn();
    });
  }

  async isSubscribed(service: string, creatorId: string): Promise<boolean> {
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT 1 FROM creator_subscriptions WHERE service = ? AND creator_id = ? LIMIT 1',
        [service, creatorId]
      );
      try {
        return rs.goToFirstRow();
      } finally {
        rs.close();
      }
    } catch (_e) {
      return false;
    }
  }

  async subscribeCreator(service: string, creatorId: string, creatorName: string): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql(
        'INSERT OR REPLACE INTO creator_subscriptions (service, creator_id, creator_name, last_post_id, last_checked_at, created_at) VALUES (?, ?, ?, NULL, 0, ?)',
        [service, creatorId, creatorName, Date.now()]
      );
      this.emit();
    } catch (e) {
      Logger.w(TAG, `subscribeCreator failed: ${String(e)}`);
    }
  }

  async unsubscribeCreator(service: string, creatorId: string): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql(
        'DELETE FROM creator_subscriptions WHERE service = ? AND creator_id = ?',
        [service, creatorId]
      );
      this.emit();
    } catch (e) {
      Logger.w(TAG, `unsubscribeCreator failed: ${String(e)}`);
    }
  }

  async listSubscriptions(): Promise<CreatorSubscription[]> {
    const out: CreatorSubscription[] = [];
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT service, creator_id, creator_name, last_post_id, last_checked_at, created_at FROM creator_subscriptions ORDER BY created_at DESC'
      );
      try {
        while (rs.goToNextRow()) {
          out.push({
            service: rs.getString(0),
            creatorId: rs.getString(1),
            creatorName: rs.getString(2),
            lastPostId: rs.isColumnNull(3) ? undefined : rs.getString(3),
            lastCheckedAt: rs.getLong(4),
            createdAt: rs.getLong(5)
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `listSubscriptions failed: ${String(e)}`);
    }
    return out;
  }

  async listUpdates(limit: number = 100): Promise<ContentUpdateItem[]> {
    const out: ContentUpdateItem[] = [];
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT id, service, creator_id, creator_name, post_id, post_title, published, is_read, detected_at FROM content_updates ORDER BY detected_at DESC LIMIT ?',
        [limit]
      );
      try {
        while (rs.goToNextRow()) {
          out.push({
            id: rs.getString(0),
            service: rs.getString(1),
            creatorId: rs.getString(2),
            creatorName: rs.getString(3),
            postId: rs.getString(4),
            postTitle: rs.getString(5),
            published: rs.isColumnNull(6) ? undefined : rs.getString(6),
            isRead: rs.getLong(7) !== 0,
            detectedAt: rs.getLong(8)
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `listUpdates failed: ${String(e)}`);
    }
    return out;
  }

  async getUnreadCount(): Promise<number> {
    try {
      const store = this.database.getStore();
      const rs = await store.querySql('SELECT COUNT(*) FROM content_updates WHERE is_read = 0');
      try {
        if (rs.goToFirstRow()) {
          return rs.getLong(0);
        }
      } finally {
        rs.close();
      }
    } catch (_e) {
      // ignore
    }
    return 0;
  }

  async markRead(id: string): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('UPDATE content_updates SET is_read = 1 WHERE id = ?', [id]);
      this.emit();
    } catch (e) {
      Logger.w(TAG, `markRead failed: ${String(e)}`);
    }
  }

  async markAllRead(): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('UPDATE content_updates SET is_read = 1 WHERE is_read = 0');
      this.emit();
    } catch (e) {
      Logger.w(TAG, `markAllRead failed: ${String(e)}`);
    }
  }

  /**
   * 检查所有已订阅创作者是否有新帖；发现新帖后写入通知中心并推送系统通知。
   */
  async checkAllSubscriptionsNow(): Promise<number> {
    const subs = await this.listSubscriptions();
    let newCount = 0;
    const store = this.database.getStore();

    for (let i = 0; i < subs.length; i++) {
      const sub = subs[i];
      try {
        const posts = await this.api.getCreatorPosts(sub.service, sub.creatorId, undefined, undefined, 0, true);
        const now = Date.now();
        if (posts.length === 0) {
          await store.executeSql(
            'UPDATE creator_subscriptions SET last_checked_at = ? WHERE service = ? AND creator_id = ?',
            [now, sub.service, sub.creatorId]
          );
          continue;
        }
        const newest = posts[0];
        if (sub.lastPostId !== undefined && sub.lastPostId !== newest.postId) {
          const updateId = `${sub.service}:${sub.creatorId}:${newest.postId}`;
          await store.executeSql(
            'INSERT OR IGNORE INTO content_updates (id, service, creator_id, creator_name, post_id, post_title, published, is_read, detected_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)',
            [
              updateId,
              sub.service,
              sub.creatorId,
              sub.creatorName,
              newest.postId,
              newest.title.length > 0 ? newest.title : '(无标题)',
              newest.published ?? null,
              now
            ]
          );
          newCount++;
          this.publishNewPostNotification(sub.creatorName, newest.title);
        }
        await store.executeSql(
          'UPDATE creator_subscriptions SET last_post_id = ?, last_checked_at = ? WHERE service = ? AND creator_id = ?',
          [newest.postId, now, sub.service, sub.creatorId]
        );
      } catch (e) {
        Logger.w(TAG, `check subscription ${sub.creatorId} failed: ${String(e)}`);
      }
    }

    if (newCount > 0) {
      this.emit();
    }
    return newCount;
  }

  private publishNewPostNotification(creatorName: string, postTitle: string): void {
    const request: notificationManager.NotificationRequest = {
      id: 7000 + Math.floor(Math.random() * 1000),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: `${creatorName} 发布了新作品`,
          text: postTitle.length > 0 ? postTitle : '点击查看详情'
        }
      }
    };
    notificationManager.publish(request).catch(() => {});
  }
}
