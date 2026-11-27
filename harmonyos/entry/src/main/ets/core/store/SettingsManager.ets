import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ApiConstants } from '../api/ApiConstants';
import { Logger } from '../util/Logger';

const TAG: string = 'SettingsManager';
const PREFS_NAME: string = 'archive_app_settings';

/** 6 态配色模式（对齐上游 AppColorMode）。 */
export enum AppColorMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK',
  MONET_SYSTEM = 'MONET_SYSTEM',
  MONET_LIGHT = 'MONET_LIGHT',
  MONET_DARK = 'MONET_DARK'
}

export enum StartupTab {
  HOME = 0,
  DISCOVER = 1,
  FAVORITES = 2,
  MINE = 3
}

export enum UpdateChannel {
  STABLE = 'STABLE',
  BETA = 'BETA'
}

export enum PostLayoutMode {
  LIST = 'LIST',
  GRID = 'GRID'
}

export interface AppSettingsSnapshot {
  ageConfirmed: boolean;
  colorMode: AppColorMode;
  seedColorHex: string;
  languageTag: string;
  baseUrl: string;
  blurThumbnails: boolean;
  preventScreenshot: boolean;
  startupTab: number;
  postLayoutMode: PostLayoutMode;
  homeDeduplicateCreator: boolean;
  homeHideFavoritedCreators: boolean;
  downloadConcurrency: number;
  downloadMaxRetries: number;
  downloadWifiOnly: boolean;
  fileNamingFormat: string;
  syncIntervalMinutes: number;
  autoSubscribeOnFavorite: boolean;
  updateChannel: UpdateChannel;
  ignoredUpdateVersion: string;
  browserOpenedVersion: string;
  searchHistoryLimit: number;
  autoBackupEnabled: boolean;
  cacheCleanLimitMb: number;
}

export type SettingsListener = (snapshot: AppSettingsSnapshot) => void;

export class SettingsManager {
  private prefs?: preferences.Preferences;
  private snapshot: AppSettingsSnapshot = SettingsManager.defaultSnapshot();
  private readonly listeners: Set<SettingsListener> = new Set<SettingsListener>();

  static defaultSnapshot(): AppSettingsSnapshot {
    return {
      ageConfirmed: false,
      colorMode: AppColorMode.SYSTEM,
      seedColorHex: '#3482FF',
      languageTag: 'system',
      baseUrl: ApiConstants.DEFAULT_BASE_URL,
      blurThumbnails: true,
      preventScreenshot: false,
      startupTab: StartupTab.FAVORITES,
      postLayoutMode: PostLayoutMode.LIST,
      homeDeduplicateCreator: false,
      homeHideFavoritedCreators: false,
      downloadConcurrency: 3,
      downloadMaxRetries: 2,
      downloadWifiOnly: false,
      fileNamingFormat: '{creator}_{post_id}_{index}_{name}',
      syncIntervalMinutes: 30,
      autoSubscribeOnFavorite: false,
      updateChannel: UpdateChannel.STABLE,
      ignoredUpdateVersion: '',
      browserOpenedVersion: '',
      searchHistoryLimit: 20,
      autoBackupEnabled: false,
      cacheCleanLimitMb: 512
    };
  }

  static clampConcurrency(value: number): number {
    return Math.min(5, Math.max(1, Math.trunc(value)));
  }

  static clampRetries(value: number): number {
    return Math.min(3, Math.max(1, Math.trunc(value)));
  }

  static clampSyncInterval(value: number): number {
    return Math.max(15, Math.trunc(value));
  }

  static clampSearchHistoryLimit(value: number): number {
    return Math.min(50, Math.max(5, Math.trunc(value)));
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
      await this.reload();
    } catch (e) {
      Logger.e(TAG, `init settings preferences failed: ${String(e)}`);
    }
  }

  private async reload(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const def = SettingsManager.defaultSnapshot();
    try {
      const colorModeRaw = String(await this.prefs.get('colorMode', def.colorMode));
      const layoutRaw = String(await this.prefs.get('postLayoutMode', def.postLayoutMode));
      const channelRaw = String(await this.prefs.get('updateChannel', def.updateChannel));
      this.snapshot = {
        ageConfirmed: Boolean(await this.prefs.get('ageConfirmed', def.ageConfirmed)),
        colorMode: this.parseColorMode(colorModeRaw),
        seedColorHex: String(await this.prefs.get('seedColorHex', def.seedColorHex)),
        languageTag: String(await this.prefs.get('languageTag', def.languageTag)),
        baseUrl: String(await this.prefs.get('baseUrl', def.baseUrl)),
        blurThumbnails: Boolean(await this.prefs.get('blurThumbnails', def.blurThumbnails)),
        preventScreenshot: Boolean(await this.prefs.get('preventScreenshot', def.preventScreenshot)),
        startupTab: Number(await this.prefs.get('startupTab', def.startupTab)),
        postLayoutMode: layoutRaw === PostLayoutMode.GRID ? PostLayoutMode.GRID : PostLayoutMode.LIST,
        homeDeduplicateCreator: Boolean(await this.prefs.get('homeDeduplicateCreator', def.homeDeduplicateCreator)),
        homeHideFavoritedCreators: Boolean(
          await this.prefs.get('homeHideFavoritedCreators', def.homeHideFavoritedCreators)
        ),
        downloadConcurrency: SettingsManager.clampConcurrency(
          Number(await this.prefs.get('downloadConcurrency', def.downloadConcurrency))
        ),
        downloadMaxRetries: SettingsManager.clampRetries(
          Number(await this.prefs.get('downloadMaxRetries', def.downloadMaxRetries))
        ),
        downloadWifiOnly: Boolean(await this.prefs.get('downloadWifiOnly', def.downloadWifiOnly)),
        fileNamingFormat: String(await this.prefs.get('fileNamingFormat', def.fileNamingFormat)),
        syncIntervalMinutes: SettingsManager.clampSyncInterval(
          Number(await this.prefs.get('syncIntervalMinutes', def.syncIntervalMinutes))
        ),
        autoSubscribeOnFavorite: Boolean(
          await this.prefs.get('autoSubscribeOnFavorite', def.autoSubscribeOnFavorite)
        ),
        updateChannel: channelRaw === UpdateChannel.BETA ? UpdateChannel.BETA : UpdateChannel.STABLE,
        ignoredUpdateVersion: String(await this.prefs.get('ignoredUpdateVersion', def.ignoredUpdateVersion)),
        browserOpenedVersion: String(await this.prefs.get('browserOpenedVersion', def.browserOpenedVersion)),
        searchHistoryLimit: SettingsManager.clampSearchHistoryLimit(
          Number(await this.prefs.get('searchHistoryLimit', def.searchHistoryLimit))
        ),
        autoBackupEnabled: Boolean(await this.prefs.get('autoBackupEnabled', def.autoBackupEnabled)),
        cacheCleanLimitMb: Math.max(64, Number(await this.prefs.get('cacheCleanLimitMb', def.cacheCleanLimitMb)))
      };
      this.emit();
    } catch (e) {
      Logger.e(TAG, `reload settings failed: ${String(e)}`);
    }
  }

  private parseColorMode(raw: string): AppColorMode {
    if (raw === AppColorMode.LIGHT) {
      return AppColorMode.LIGHT;
    }
    if (raw === AppColorMode.DARK) {
      return AppColorMode.DARK;
    }
    if (raw === AppColorMode.MONET_SYSTEM) {
      return AppColorMode.MONET_SYSTEM;
    }
    if (raw === AppColorMode.MONET_LIGHT) {
      return AppColorMode.MONET_LIGHT;
    }
    if (raw === AppColorMode.MONET_DARK) {
      return AppColorMode.MONET_DARK;
    }
    return AppColorMode.SYSTEM;
  }

  getSnapshot(): AppSettingsSnapshot {
    return this.snapshot;
  }

  subscribe(listener: SettingsListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: SettingsListener): void {
    this.listeners.delete(listener);
  }

  private emit(): void {
    this.listeners.forEach((fn: SettingsListener) => {
      fn(this.snapshot);
    });
  }

  private async persistAndEmit(key: string, value: preferences.ValueType): Promise<void> {
    if (this.prefs !== undefined) {
      try {
        await this.prefs.put(key, value);
        await this.prefs.flush();
      } catch (e) {
        Logger.e(TAG, `persist setting ${key} failed: ${String(e)}`);
      }
    }
    this.emit();
  }

  async setAgeConfirmed(confirmed: boolean): Promise<void> {
    this.snapshot.ageConfirmed = confirmed;
    await this.persistAndEmit('ageConfirmed', confirmed);
  }

  async setColorMode(mode: AppColorMode): Promise<void> {
    this.snapshot.colorMode = mode;
    await this.persistAndEmit('colorMode', mode);
  }

  async setSeedColorHex(hex: string): Promise<void> {
    this.snapshot.seedColorHex = hex;
    await this.persistAndEmit('seedColorHex', hex);
  }

  async setLanguageTag(tag: string): Promise<void> {
    this.snapshot.languageTag = tag;
    await this.persistAndEmit('languageTag', tag);
  }

  async setBaseUrl(url: string): Promise<void> {
    const cleaned = url.trim().length > 0 ? url.trim() : ApiConstants.DEFAULT_BASE_URL;
    this.snapshot.baseUrl = cleaned;
    await this.persistAndEmit('baseUrl', cleaned);
  }

  async setBlurThumbnails(blur: boolean): Promise<void> {
    this.snapshot.blurThumbnails = blur;
    await this.persistAndEmit('blurThumbnails', blur);
  }

  async setPreventScreenshot(enabled: boolean): Promise<void> {
    this.snapshot.preventScreenshot = enabled;
    await this.persistAndEmit('preventScreenshot', enabled);
  }

  async setPostLayoutMode(mode: PostLayoutMode): Promise<void> {
    this.snapshot.postLayoutMode = mode;
    await this.persistAndEmit('postLayoutMode', mode);
  }

  async setDownloadConcurrency(value: number): Promise<void> {
    const clamped = SettingsManager.clampConcurrency(value);
    this.snapshot.downloadConcurrency = clamped;
    await this.persistAndEmit('downloadConcurrency', clamped);
  }

  async setDownloadMaxRetries(value: number): Promise<void> {
    const clamped = SettingsManager.clampRetries(value);
    this.snapshot.downloadMaxRetries = clamped;
    await this.persistAndEmit('downloadMaxRetries', clamped);
  }

  async setDownloadWifiOnly(wifiOnly: boolean): Promise<void> {
    this.snapshot.downloadWifiOnly = wifiOnly;
    await this.persistAndEmit('downloadWifiOnly', wifiOnly);
  }

  async setStartupTab(tabIndex: number): Promise<void> {
    const clamped = Math.min(3, Math.max(0, Math.trunc(tabIndex)));
    this.snapshot.startupTab = clamped;
    await this.persistAndEmit('startupTab', clamped);
  }

  async setFileNamingFormat(format: string): Promise<void> {
    const cleaned = format.trim().length > 0 ? format.trim() : '{creator}_{post_id}_{index}_{name}';
    this.snapshot.fileNamingFormat = cleaned;
    await this.persistAndEmit('fileNamingFormat', cleaned);
  }

  async setSyncIntervalMinutes(minutes: number): Promise<void> {
    const clamped = SettingsManager.clampSyncInterval(minutes);
    this.snapshot.syncIntervalMinutes = clamped;
    await this.persistAndEmit('syncIntervalMinutes', clamped);
  }

  async setAutoSubscribeOnFavorite(enabled: boolean): Promise<void> {
    this.snapshot.autoSubscribeOnFavorite = enabled;
    await this.persistAndEmit('autoSubscribeOnFavorite', enabled);
  }

  async setUpdateChannel(channel: UpdateChannel): Promise<void> {
    this.snapshot.updateChannel = channel;
    await this.persistAndEmit('updateChannel', channel);
  }
}
