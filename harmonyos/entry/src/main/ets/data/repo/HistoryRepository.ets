import { AttachmentDto, DtoParsers } from '../../core/api/Dtos';
import { JsonValue } from '../../core/api/FlexParsers';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { SessionManager } from '../../core/store/SessionManager';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'HistoryRepository';

export interface HistoryEntry {
  service: string;
  creatorId: string;
  postId: string;
  title: string;
  cover?: AttachmentDto;
  viewedAt: number;
}

/**
 * 浏览历史仓库（按账号命名空间隔离，持久化于 RDB `history` 表）。
 */
export class HistoryRepository {
  private readonly database: ArchiveDatabase;
  private readonly sessionManager: SessionManager;

  constructor(database: ArchiveDatabase, sessionManager: SessionManager) {
    this.database = database;
    this.sessionManager = sessionManager;
  }

  private ns(): string {
    return this.sessionManager.getSessionNamespace();
  }

  async recordView(
    service: string,
    creatorId: string,
    postId: string,
    title: string,
    cover?: AttachmentDto
  ): Promise<void> {
    try {
      const store = this.database.getStore();
      const coverJson = cover !== undefined ? JSON.stringify(cover) : null;
      await store.executeSql(
        'INSERT OR REPLACE INTO history (account_ns, service, creator_id, post_id, title, cover_json, viewed_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [this.ns(), service, creatorId, postId, title, coverJson, Date.now()]
      );
    } catch (e) {
      Logger.w(TAG, `recordView failed: ${String(e)}`);
    }
  }

  async listHistory(limit: number = 100, offset: number = 0): Promise<HistoryEntry[]> {
    const out: HistoryEntry[] = [];
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT service, creator_id, post_id, title, cover_json, viewed_at FROM history WHERE account_ns = ? ORDER BY viewed_at DESC LIMIT ? OFFSET ?',
        [this.ns(), limit, offset]
      );
      try {
        while (rs.goToNextRow()) {
          const coverJson = rs.isColumnNull(4) ? '' : rs.getString(4);
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
            cover: cover,
            viewedAt: rs.getLong(5)
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `listHistory failed: ${String(e)}`);
    }
    return out;
  }

  async removeEntry(service: string, creatorId: string, postId: string): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql(
        'DELETE FROM history WHERE account_ns = ? AND service = ? AND creator_id = ? AND post_id = ?',
        [this.ns(), service, creatorId, postId]
      );
    } catch (e) {
      Logger.w(TAG, `removeEntry failed: ${String(e)}`);
    }
  }

  async clearHistory(): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('DELETE FROM history WHERE account_ns = ?', [this.ns()]);
    } catch (e) {
      Logger.w(TAG, `clearHistory failed: ${String(e)}`);
    }
  }
}
