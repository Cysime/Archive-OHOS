import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FlexParsers, JsonObject, JsonValue } from '../../core/api/FlexParsers';
import { AppColorMode, SettingsManager } from '../../core/store/SettingsManager';
import { Logger } from '../../core/util/Logger';
import { BlockedContentRepository } from '../repo/BlockedContentRepository';
import { FavoriteRepository } from '../repo/FavoriteRepository';
import { SubscriptionRepository } from './SubscriptionRepository';

const TAG: string = 'BackupManager';
export const BACKUP_SCHEMA_VERSION: number = 1;

export interface BackupImportResult {
  favoritesRestored: number;
  blockedCreatorsRestored: number;
  blockedPostsRestored: number;
  subscriptionsRestored: number;
}

/**
 * JSON v1 备份与恢复管理器（对齐上游 data/repository/BackupManager.kt）。
 *
 * - `schemaVersion = 1`（与 Android Archive 互通；版本号不匹配拒绝导入）
 * - 导出收藏、屏蔽、订阅与非敏感设置
 * - **永不导出**会话 Cookie、AI API Key 与搜索历史
 */
export class BackupManager {
  private readonly settings: SettingsManager;
  private readonly favorites: FavoriteRepository;
  private readonly blocked: BlockedContentRepository;
  private readonly subscriptions: SubscriptionRepository;
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  constructor(
    settings: SettingsManager,
    favorites: FavoriteRepository,
    blocked: BlockedContentRepository,
    subscriptions: SubscriptionRepository
  ) {
    this.settings = settings;
    this.favorites = favorites;
    this.blocked = blocked;
    this.subscriptions = subscriptions;
  }

  async buildBackupJson(): Promise<string> {
    const favPosts = await this.favorites.listLocalFavoritePosts();
    const subs = await this.subscriptions.listSubscriptions();
    const blockedCreators = this.blocked.listBlockedCreators();
    const blockedPosts = this.blocked.listBlockedPosts();
    const snap = this.settings.getSnapshot();

    const safeSettings: Record<string, JsonValue> = {
      'colorMode': snap.colorMode,
      'seedColorHex': snap.seedColorHex,
      'languageTag': snap.languageTag,
      'baseUrl': snap.baseUrl,
      'blurThumbnails': snap.blurThumbnails,
      'preventScreenshot': snap.preventScreenshot,
      'downloadConcurrency': snap.downloadConcurrency,
      'downloadMaxRetries': snap.downloadMaxRetries,
      'downloadWifiOnly': snap.downloadWifiOnly,
      'fileNamingFormat': snap.fileNamingFormat,
      'syncIntervalMinutes': snap.syncIntervalMinutes,
      'autoSubscribeOnFavorite': snap.autoSubscribeOnFavorite
    };

    const bundle: Record<string, JsonValue> = {
      'schemaVersion': BACKUP_SCHEMA_VERSION,
      'exportedAt': Date.now(),
      'platform': 'HarmonyOS',
      'favorites': favPosts as Object,
      'blockedCreators': blockedCreators as Object,
      'blockedPosts': blockedPosts as Object,
      'subscriptions': subs as Object,
      'settings': safeSettings
    };
    return JSON.stringify(bundle, null, 2);
  }

  async exportToPicker(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const json = await this.buildBackupJson();
      const now = new Date();
      const stamp = `${now.getFullYear()}${`${now.getMonth() + 1}`.padStart(2, '0')}${`${now.getDate()}`.padStart(2, '0')}`;
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`archive_backup_${stamp}.json`];
      const docPicker = new picker.DocumentViewPicker(context);
      const uris = await docPicker.save(options);
      if (uris.length === 0) {
        return false;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, json);
      } finally {
        fileIo.closeSync(file.fd);
      }
      return true;
    } catch (e) {
      Logger.w(TAG, `exportToPicker failed: ${String(e)}`);
      return false;
    }
  }

  async importFromPicker(context: common.UIAbilityContext): Promise<BackupImportResult | undefined> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json'];
      const docPicker = new picker.DocumentViewPicker(context);
      const uris = await docPicker.select(options);
      if (uris.length === 0) {
        return undefined;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      let rawText = '';
      try {
        const stat = fileIo.statSync(file.fd);
        const buf = new ArrayBuffer(Math.max(1, stat.size));
        const readLen = fileIo.readSync(file.fd, buf);
        rawText = this.decoder.decodeToString(new Uint8Array(buf, 0, readLen));
      } finally {
        fileIo.closeSync(file.fd);
      }
      return this.restoreFromJson(rawText);
    } catch (e) {
      Logger.w(TAG, `importFromPicker failed: ${String(e)}`);
      throw new Error(`导入备份失败：${String(e)}`);
    }
  }

  async restoreFromJson(rawJson: string): Promise<BackupImportResult> {
    const root = FlexParsers.asObject(JSON.parse(rawJson) as JsonValue);
    if (root === undefined) {
      throw new Error('备份文件格式非法');
    }
    const schemaVersion = FlexParsers.readNumber(root, 'schemaVersion') ?? -1;
    if (schemaVersion !== BACKUP_SCHEMA_VERSION) {
      throw new Error(`不支持的备份版本（schemaVersion=${schemaVersion}，仅支持 v${BACKUP_SCHEMA_VERSION}）`);
    }

    let favoritesRestored = 0;
    const favArr = FlexParsers.asArray(root['favorites']);
    for (let i = 0; i < favArr.length; i++) {
      const obj = FlexParsers.asObject(favArr[i]);
      if (obj === undefined) {
        continue;
      }
      const service = FlexParsers.readString(obj, 'service') ?? '';
      const creatorId = FlexParsers.readString(obj, 'creatorId') ?? '';
      const postId = FlexParsers.readString(obj, 'postId') ?? '';
      if (service.length > 0 && creatorId.length > 0 && postId.length > 0) {
        if (!this.favorites.isPostFavorited(service, creatorId, postId)) {
          await this.favorites.toggleFavoritePost({
            service: service,
            creatorId: creatorId,
            postId: postId,
            title: FlexParsers.readString(obj, 'title') ?? '',
            excerpt: FlexParsers.readString(obj, 'excerpt'),
            published: FlexParsers.readString(obj, 'published'),
            previewOnly: FlexParsers.readBoolean(obj, 'previewOnly', false)
          });
        }
        favoritesRestored++;
      }
    }

    let blockedCreatorsRestored = 0;
    const bcArr = FlexParsers.asArray(root['blockedCreators']);
    for (let i = 0; i < bcArr.length; i++) {
      const obj = FlexParsers.asObject(bcArr[i]);
      if (obj === undefined) {
        continue;
      }
      const service = FlexParsers.readString(obj, 'service') ?? '';
      const creatorId = FlexParsers.readString(obj, 'creatorId') ?? '';
      if (service.length > 0 && creatorId.length > 0) {
        await this.blocked.blockCreator(service, creatorId, FlexParsers.readString(obj, 'name') ?? creatorId);
        blockedCreatorsRestored++;
      }
    }

    let blockedPostsRestored = 0;
    const bpArr = FlexParsers.asArray(root['blockedPosts']);
    for (let i = 0; i < bpArr.length; i++) {
      const obj = FlexParsers.asObject(bpArr[i]);
      if (obj === undefined) {
        continue;
      }
      const service = FlexParsers.readString(obj, 'service') ?? '';
      const creatorId = FlexParsers.readString(obj, 'creatorId') ?? '';
      const postId = FlexParsers.readString(obj, 'postId') ?? '';
      if (service.length > 0 && creatorId.length > 0 && postId.length > 0) {
        await this.blocked.blockPost(service, creatorId, postId, FlexParsers.readString(obj, 'title') ?? postId);
        blockedPostsRestored++;
      }
    }

    let subscriptionsRestored = 0;
    const subArr = FlexParsers.asArray(root['subscriptions']);
    for (let i = 0; i < subArr.length; i++) {
      const obj = FlexParsers.asObject(subArr[i]);
      if (obj === undefined) {
        continue;
      }
      const service = FlexParsers.readString(obj, 'service') ?? '';
      const creatorId = FlexParsers.readString(obj, 'creatorId') ?? '';
      if (service.length > 0 && creatorId.length > 0) {
        await this.subscriptions.subscribeCreator(
          service,
          creatorId,
          FlexParsers.readString(obj, 'creatorName') ?? creatorId
        );
        subscriptionsRestored++;
      }
    }

    const sObj = FlexParsers.asObject(root['settings']);
    if (sObj !== undefined) {
      const baseUrl = FlexParsers.readString(sObj, 'baseUrl');
      if (baseUrl !== undefined && baseUrl.trim().length > 0) {
        await this.settings.setBaseUrl(baseUrl);
      }
      const colorRaw = FlexParsers.readString(sObj, 'colorMode');
      if (colorRaw === AppColorMode.LIGHT || colorRaw === AppColorMode.DARK || colorRaw === AppColorMode.SYSTEM ||
        colorRaw === AppColorMode.MONET_LIGHT || colorRaw === AppColorMode.MONET_DARK || colorRaw === AppColorMode.MONET_SYSTEM) {
        await this.settings.setColorMode(colorRaw as AppColorMode);
      }
      if (sObj['blurThumbnails'] !== undefined) {
        await this.settings.setBlurThumbnails(FlexParsers.readBoolean(sObj, 'blurThumbnails', true));
      }
      if (sObj['preventScreenshot'] !== undefined) {
        await this.settings.setPreventScreenshot(FlexParsers.readBoolean(sObj, 'preventScreenshot', false));
      }
      const conc = FlexParsers.readNumber(sObj, 'downloadConcurrency');
      if (conc !== undefined) {
        await this.settings.setDownloadConcurrency(conc);
      }
      const retries = FlexParsers.readNumber(sObj, 'downloadMaxRetries');
      if (retries !== undefined) {
        await this.settings.setDownloadMaxRetries(retries);
      }
      if (sObj['downloadWifiOnly'] !== undefined) {
        await this.settings.setDownloadWifiOnly(FlexParsers.readBoolean(sObj, 'downloadWifiOnly', false));
      }
    }

    return {
      favoritesRestored: favoritesRestored,
      blockedCreatorsRestored: blockedCreatorsRestored,
      blockedPostsRestored: blockedPostsRestored,
      subscriptionsRestored: subscriptionsRestored
    };
  }
}
