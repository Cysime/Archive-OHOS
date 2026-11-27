import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { FlexParsers } from '../../core/api/FlexParsers';
import { SettingsManager } from '../../core/store/SettingsManager';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'SearchHistoryRepo';
const PREFS_NAME: string = 'archive_search_history';
const KEY_ITEMS: string = 'history_items_json';

/**
 * 搜索历史本地持久化仓库（保留条数由 SettingsManager.searchHistoryLimit 5–50 控制）。
 */
export class SearchHistoryRepository {
  private readonly settings: SettingsManager;
  private prefs?: preferences.Preferences;
  private items: string[] = [];

  constructor(settings: SettingsManager) {
    this.settings = settings;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
      const raw = String(await this.prefs.get(KEY_ITEMS, '[]'));
      const arr = FlexParsers.asArray(JSON.parse(raw) as Object);
      const loaded: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string' && (arr[i] as string).trim().length > 0) {
          loaded.push(arr[i] as string);
        }
      }
      this.items = loaded;
    } catch (e) {
      Logger.w(TAG, `init search history failed: ${String(e)}`);
    }
  }

  list(): string[] {
    return this.items.slice();
  }

  private async persist(): Promise<void> {
    if (this.prefs !== undefined) {
      try {
        await this.prefs.put(KEY_ITEMS, JSON.stringify(this.items));
        await this.prefs.flush();
      } catch (e) {
        Logger.w(TAG, `persist search history failed: ${String(e)}`);
      }
    }
  }

  async record(query: string): Promise<void> {
    const q = query.trim();
    if (q.length === 0) {
      return;
    }
    const limit = SettingsManager.clampSearchHistoryLimit(this.settings.getSnapshot().searchHistoryLimit);
    const filtered = this.items.filter((x: string) => x.toLowerCase() !== q.toLowerCase());
    filtered.unshift(q);
    this.items = filtered.slice(0, limit);
    await this.persist();
  }

  async remove(query: string): Promise<void> {
    this.items = this.items.filter((x: string) => x !== query);
    await this.persist();
  }

  async clear(): Promise<void> {
    this.items = [];
    await this.persist();
  }
}
