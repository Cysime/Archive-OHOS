import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ApiClient } from '../../core/api/ApiClient';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { ArchiveImageLoader } from '../../core/media/ArchiveImageLoader';
import { CreatorRepository } from '../repo/CreatorRepository';
import { FavoriteRepository } from '../repo/FavoriteRepository';
import { HistoryRepository } from '../repo/HistoryRepository';

export interface StorageSummary {
  imageCacheBytes: number;
  downloadsBytes: number;
  offlineArchiveCount: number;
  offlineArchiveBytes: number;
  cachedCreatorsCount: number;
}

/**
 * 存储空间统计与分项清理仓库（对齐上游 data/repository/CacheRepository.kt）。
 */
export class CacheRepository {
  private readonly apiClient: ApiClient;
  private readonly imageLoader: ArchiveImageLoader;
  private readonly database: ArchiveDatabase;
  private readonly creatorRepo: CreatorRepository;
  private readonly favoriteRepo: FavoriteRepository;
  private readonly historyRepo: HistoryRepository;

  private cacheDir: string = '';
  private filesDir: string = '';

  constructor(
    apiClient: ApiClient,
    imageLoader: ArchiveImageLoader,
    database: ArchiveDatabase,
    creatorRepo: CreatorRepository,
    favoriteRepo: FavoriteRepository,
    historyRepo: HistoryRepository
  ) {
    this.apiClient = apiClient;
    this.imageLoader = imageLoader;
    this.database = database;
    this.creatorRepo = creatorRepo;
    this.favoriteRepo = favoriteRepo;
    this.historyRepo = historyRepo;
  }

  init(context: common.Context): void {
    this.cacheDir = context.cacheDir;
    this.filesDir = context.filesDir;
  }

  private computeDirSize(dirPath: string): number {
    if (dirPath.length === 0) {
      return 0;
    }
    let total = 0;
    try {
      if (!fileIo.accessSync(dirPath)) {
        return 0;
      }
      const entries = fileIo.listFileSync(dirPath);
      for (let i = 0; i < entries.length; i++) {
        const full = `${dirPath}/${entries[i]}`;
        try {
          const stat = fileIo.statSync(full);
          if (stat.isDirectory()) {
            total += this.computeDirSize(full);
          } else {
            total += stat.size;
          }
        } catch (_se) {
          // ignore individual file stat error
        }
      }
    } catch (_e) {
      // ignore missing dir
    }
    return total;
  }

  async getSummary(): Promise<StorageSummary> {
    const imgBytes = this.computeDirSize(`${this.cacheDir}/image_cache`);
    const dlBytes = this.computeDirSize(`${this.filesDir}/downloads`);
    const archiveStats = await this.favoriteRepo.getArchiveStats();
    const creatorsCount = await this.creatorRepo.getTotalCount();
    return {
      imageCacheBytes: imgBytes,
      downloadsBytes: dlBytes,
      offlineArchiveCount: archiveStats.count,
      offlineArchiveBytes: archiveStats.totalBytes,
      cachedCreatorsCount: creatorsCount
    };
  }

  clearImageAndApiCache(): void {
    this.apiClient.clearMemoryCache();
    this.imageLoader.clearDiskAndMemoryCache();
  }

  async clearOfflineArchives(): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('DELETE FROM offline_post_archives');
    } catch (_e) {
      // ignore
    }
  }

  async clearHistory(): Promise<void> {
    await this.historyRepo.clearHistory();
  }
}
