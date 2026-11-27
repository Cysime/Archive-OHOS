import { relationalStore } from '@kit.ArkData';
import { CreatorDto } from '../../core/api/Dtos';
import { PawchiveApi } from '../../core/api/PawchiveApi';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'CreatorRepository';

export enum CreatorSortMode {
  UPDATED_DESC = 'UPDATED_DESC',
  FAVORITED_DESC = 'FAVORITED_DESC',
  NAME_ASC = 'NAME_ASC'
}

export type SyncProgressCallback = (loaded: number, total: number) => void;

/**
 * 创作者目录仓库（对齐上游 CreatorRepository + CreatorNameCache）。
 *
 * - 支持全量同步 9.6 万+ 创作者并分批事务落入 RDB（`creators` 表）
 * - 支持本地秒级检索、平台（patreon / fanbox / all）筛选、排序与分页
 * - 提供内存昵称缓存，供帖子卡片直接展示作者名称
 */
export class CreatorRepository {
  private readonly api: PawchiveApi;
  private readonly database: ArchiveDatabase;
  private readonly nameCache: Map<string, string> = new Map<string, string>();
  private syncing: boolean = false;

  constructor(api: PawchiveApi, database: ArchiveDatabase) {
    this.api = api;
    this.database = database;
  }

  private cacheKey(service: string, creatorId: string): string {
    return `${service.toLowerCase()}:${creatorId}`;
  }

  isSyncing(): boolean {
    return this.syncing;
  }

  getCachedName(service: string, creatorId: string): string | undefined {
    return this.nameCache.get(this.cacheKey(service, creatorId));
  }

  rememberName(service: string, creatorId: string, name: string): void {
    if (name.trim().length > 0) {
      this.nameCache.set(this.cacheKey(service, creatorId), name.trim());
    }
  }

  async resolveCreatorName(service: string, creatorId: string): Promise<string> {
    const cached = this.getCachedName(service, creatorId);
    if (cached !== undefined) {
      return cached;
    }
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT name FROM creators WHERE service = ? AND id = ? LIMIT 1',
        [service, creatorId]
      );
      try {
        if (rs.goToFirstRow()) {
          const name = rs.getString(0);
          if (name.length > 0) {
            this.rememberName(service, creatorId, name);
            return name;
          }
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `resolveCreatorName query failed: ${String(e)}`);
    }
    return creatorId;
  }

  async getTotalCount(): Promise<number> {
    try {
      const store = this.database.getStore();
      const rs = await store.querySql('SELECT COUNT(*) FROM creators');
      try {
        if (rs.goToFirstRow()) {
          return rs.getLong(0);
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `getTotalCount failed: ${String(e)}`);
    }
    return 0;
  }

  async queryCreators(
    query: string,
    serviceFilter: string,
    sort: CreatorSortMode,
    limit: number = 50,
    offset: number = 0
  ): Promise<CreatorDto[]> {
    const whereClauses: string[] = [];
    const args: Array<relationalStore.ValueType> = [];

    const svc = serviceFilter.trim().toLowerCase();
    if (svc.length > 0 && svc !== 'all') {
      whereClauses.push('LOWER(service) = ?');
      args.push(svc);
    }

    const q = query.trim();
    if (q.length > 0) {
      const pattern = `%${q}%`;
      whereClauses.push('(name LIKE ? OR id LIKE ? OR public_id LIKE ?)');
      args.push(pattern);
      args.push(pattern);
      args.push(pattern);
    }

    let orderBy = 'updated DESC, favorited DESC';
    if (sort === CreatorSortMode.FAVORITED_DESC) {
      orderBy = 'favorited DESC, updated DESC';
    } else if (sort === CreatorSortMode.NAME_ASC) {
      orderBy = 'name COLLATE NOCASE ASC';
    }

    const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
    const sql = `SELECT service, id, name, public_id, indexed, updated, favorited, ever_imported FROM creators ${whereSql} ORDER BY ${orderBy} LIMIT ? OFFSET ?`;
    args.push(limit);
    args.push(offset);

    const out: CreatorDto[] = [];
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(sql, args);
      try {
        while (rs.goToNextRow()) {
          const service = rs.getString(0);
          const id = rs.getString(1);
          const name = rs.getString(2);
          const publicId = rs.isColumnNull(3) ? undefined : rs.getString(3);
          const indexed = rs.isColumnNull(4) ? undefined : rs.getLong(4);
          const updated = rs.isColumnNull(5) ? undefined : rs.getLong(5);
          const favorited = rs.getLong(6);
          const everImported = rs.getLong(7) !== 0;
          this.rememberName(service, id, name);
          out.push({
            service: service,
            id: id,
            name: name,
            publicId: publicId,
            indexed: indexed,
            updated: updated,
            favorited: favorited,
            everImported: everImported
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.e(TAG, `queryCreators failed: ${String(e)}`);
    }
    return out;
  }

  /**
   * 从站点同步全量创作者目录并分批事务写入 RDB。
   */
  async syncAllCreators(onProgress?: SyncProgressCallback): Promise<number> {
    if (this.syncing) {
      return this.getTotalCount();
    }
    this.syncing = true;
    try {
      const list = await this.api.getCreators();
      const total = list.length;
      if (total === 0) {
        return 0;
      }
      const store = this.database.getStore();
      const chunkSize = 800;
      const insertSql =
        'INSERT OR REPLACE INTO creators (service, id, name, public_id, indexed, updated, favorited, ever_imported) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';

      for (let start = 0; start < total; start += chunkSize) {
        const end = Math.min(total, start + chunkSize);
        try {
          store.beginTransaction();
          for (let i = start; i < end; i++) {
            const c = list[i];
            await store.executeSql(insertSql, [
              c.service,
              c.id,
              c.name,
              c.publicId ?? null,
              c.indexed ?? null,
              c.updated ?? null,
              c.favorited,
              c.everImported ? 1 : 0
            ]);
          }
          store.commit();
        } catch (txErr) {
          try {
            store.rollBack();
          } catch (_rbErr) {
            // ignore rollback error
          }
          throw new Error(`Batch insert creators failed: ${String(txErr)}`);
        }
        if (onProgress !== undefined) {
          onProgress(end, total);
        }
      }
      Logger.i(TAG, `Synced ${total} creators into RDB.`);
      return total;
    } finally {
      this.syncing = false;
    }
  }
}
