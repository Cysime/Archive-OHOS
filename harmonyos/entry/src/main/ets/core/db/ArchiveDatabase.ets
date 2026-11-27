import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../util/Logger';

const TAG: string = 'ArchiveDatabase';
const DB_NAME: string = 'archive_ohos.db';
const DB_VERSION: number = 1;

/**
 * 统一 RDB 数据库（整合上游 PawchiveDatabase v9 与 AppDatabase v1）。
 * 严格遵循显式版本迁移规范，禁止破坏性重建。
 */
export class ArchiveDatabase {
  private store?: relationalStore.RdbStore;

  async init(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    try {
      const rdb = await relationalStore.getRdbStore(context, config);
      await this.migrateIfNeeded(rdb);
      this.store = rdb;
      Logger.i(TAG, `RDB initialized (version=${DB_VERSION})`);
    } catch (e) {
      Logger.e(TAG, `init RDB failed: ${String(e)}`);
      throw new Error(`ArchiveDatabase init failed: ${String(e)}`);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('ArchiveDatabase has not been initialized.');
    }
    return this.store;
  }

  private async migrateIfNeeded(rdb: relationalStore.RdbStore): Promise<void> {
    const currentVersion = rdb.version;
    if (currentVersion === 0) {
      await this.createV1Schema(rdb);
      rdb.version = DB_VERSION;
    }
    // 后续版本升级在此按 if (currentVersion < N) 显式编写 ALTER / CREATE 迁移
  }

  private async createV1Schema(rdb: relationalStore.RdbStore): Promise<void> {
    const statements: string[] = [
      // 1. 9.6 万创作者全量目录
      `CREATE TABLE IF NOT EXISTS creators (
        service TEXT NOT NULL,
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        public_id TEXT,
        indexed INTEGER,
        updated INTEGER,
        favorited INTEGER NOT NULL DEFAULT 0,
        ever_imported INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (service, id)
      )`,
      `CREATE INDEX IF NOT EXISTS idx_creators_name ON creators(name)`,
      `CREATE INDEX IF NOT EXISTS idx_creators_service_updated ON creators(service, updated DESC)`,
      `CREATE INDEX IF NOT EXISTS idx_creators_favorited ON creators(favorited DESC)`,

      // 2. 本地收藏帖子（含多账号命名空间）
      `CREATE TABLE IF NOT EXISTS favorite_posts (
        account_ns TEXT NOT NULL DEFAULT 'anon',
        service TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        post_id TEXT NOT NULL,
        title TEXT NOT NULL,
        excerpt TEXT,
        published TEXT,
        cover_json TEXT,
        preview_only INTEGER NOT NULL DEFAULT 0,
        saved_at INTEGER NOT NULL,
        PRIMARY KEY (account_ns, service, creator_id, post_id)
      )`,

      // 3. 收藏帖子全文离线归档（详情页打开自动写入，离线搜索与断网回退数据源）
      `CREATE TABLE IF NOT EXISTS offline_post_archives (
        service TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        post_id TEXT NOT NULL,
        creator_name TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL,
        plain_text TEXT NOT NULL DEFAULT '',
        detail_json TEXT NOT NULL,
        byte_size INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (service, creator_id, post_id)
      )`,

      // 4. 浏览历史（含多账号命名空间）
      `CREATE TABLE IF NOT EXISTS history (
        account_ns TEXT NOT NULL DEFAULT 'anon',
        service TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        post_id TEXT NOT NULL,
        title TEXT NOT NULL,
        cover_json TEXT,
        viewed_at INTEGER NOT NULL,
        PRIMARY KEY (account_ns, service, creator_id, post_id)
      )`,
      `CREATE INDEX IF NOT EXISTS idx_history_viewed ON history(account_ns, viewed_at DESC)`,

      // 5. 下载记录与 Range 断点检查点
      `CREATE TABLE IF NOT EXISTS download_records (
        id TEXT PRIMARY KEY,
        account_ns TEXT NOT NULL DEFAULT 'anon',
        url TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        file_name TEXT NOT NULL,
        temp_path TEXT NOT NULL,
        target_uri TEXT,
        service TEXT NOT NULL DEFAULT '',
        creator_id TEXT NOT NULL DEFAULT '',
        post_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT -1,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE INDEX IF NOT EXISTS idx_download_fingerprint ON download_records(fingerprint)`,

      // 6. 自动下载规则
      `CREATE TABLE IF NOT EXISTS download_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        service TEXT,
        creator_id TEXT,
        media_kinds TEXT NOT NULL DEFAULT 'IMAGE,VIDEO',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )`,

      // 7. 创作者订阅
      `CREATE TABLE IF NOT EXISTS creator_subscriptions (
        service TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        creator_name TEXT NOT NULL DEFAULT '',
        last_post_id TEXT,
        last_checked_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (service, creator_id)
      )`,

      // 8. 应用内通知中心（内容更新记录）
      `CREATE TABLE IF NOT EXISTS content_updates (
        id TEXT PRIMARY KEY,
        service TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        creator_name TEXT NOT NULL DEFAULT '',
        post_id TEXT NOT NULL,
        post_title TEXT NOT NULL,
        published TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        detected_at INTEGER NOT NULL
      )`,
      `CREATE INDEX IF NOT EXISTS idx_updates_unread ON content_updates(is_read, detected_at DESC)`,

      // 9. 离线收藏补写队列
      `CREATE TABLE IF NOT EXISTS pending_favorite_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_ns TEXT NOT NULL,
        target_type TEXT NOT NULL,
        action_type TEXT NOT NULL,
        service TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        post_id TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )`
    ];

    for (let i = 0; i < statements.length; i++) {
      try {
        await rdb.executeSql(statements[i]);
      } catch (e) {
        Logger.e(TAG, `executeSql failed at stmt #${i}: ${String(e)}`);
        throw new Error(`executeSql failed: ${String(e)}`);
      }
    }
  }
}
