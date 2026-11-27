import { MediaKind } from '../../core/api/Dtos';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { Logger } from '../../core/util/Logger';
import { DownloadRule } from './DownloadModels';

const TAG: string = 'DownloadRuleRepo';

/**
 * 自动下载规则仓库（持久化于 RDB `download_rules` 表）。
 */
export class DownloadRuleRepository {
  private readonly database: ArchiveDatabase;

  constructor(database: ArchiveDatabase) {
    this.database = database;
  }

  private parseKinds(raw: string): MediaKind[] {
    const out: MediaKind[] = [];
    const parts = raw.split(',');
    for (let i = 0; i < parts.length; i++) {
      const k = parts[i].trim().toUpperCase();
      if (k === MediaKind.IMAGE) {
        out.push(MediaKind.IMAGE);
      } else if (k === MediaKind.VIDEO) {
        out.push(MediaKind.VIDEO);
      } else if (k === MediaKind.AUDIO) {
        out.push(MediaKind.AUDIO);
      } else if (k === MediaKind.FILE) {
        out.push(MediaKind.FILE);
      }
    }
    return out;
  }

  async listRules(): Promise<DownloadRule[]> {
    const out: DownloadRule[] = [];
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT id, name, service, creator_id, media_kinds, enabled, created_at FROM download_rules ORDER BY created_at DESC'
      );
      try {
        while (rs.goToNextRow()) {
          out.push({
            id: rs.getLong(0),
            name: rs.getString(1),
            service: rs.isColumnNull(2) ? undefined : rs.getString(2),
            creatorId: rs.isColumnNull(3) ? undefined : rs.getString(3),
            mediaKinds: this.parseKinds(rs.getString(4)),
            enabled: rs.getLong(5) !== 0,
            createdAt: rs.getLong(6)
          });
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `listRules failed: ${String(e)}`);
    }
    return out;
  }

  async addRule(
    name: string,
    service: string | undefined,
    creatorId: string | undefined,
    mediaKinds: MediaKind[]
  ): Promise<void> {
    try {
      const store = this.database.getStore();
      const kindsStr = mediaKinds.length > 0 ? mediaKinds.join(',') : `${MediaKind.IMAGE},${MediaKind.VIDEO}`;
      await store.executeSql(
        'INSERT INTO download_rules (name, service, creator_id, media_kinds, enabled, created_at) VALUES (?, ?, ?, ?, 1, ?)',
        [name.trim(), service ?? null, creatorId ?? null, kindsStr, Date.now()]
      );
    } catch (e) {
      Logger.w(TAG, `addRule failed: ${String(e)}`);
    }
  }

  async toggleRule(id: number, enabled: boolean): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('UPDATE download_rules SET enabled = ? WHERE id = ?', [enabled ? 1 : 0, id]);
    } catch (e) {
      Logger.w(TAG, `toggleRule failed: ${String(e)}`);
    }
  }

  async deleteRule(id: number): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('DELETE FROM download_rules WHERE id = ?', [id]);
    } catch (e) {
      Logger.w(TAG, `deleteRule failed: ${String(e)}`);
    }
  }
}
