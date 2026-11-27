import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ApiClient } from '../api/ApiClient';
import { FlexParsers } from '../api/FlexParsers';
import { Logger } from '../util/Logger';

const TAG: string = 'ArchiveImageLoader';
const MAX_MEM_ENTRIES: number = 80;

/**
 * 专用图片加载器（对齐上游 Coil + sharedOkHttpClient + 256MB 磁盘缓存约束）。
 *
 * `img.pawchive.pw` 与 `file.pawchive.pw` 会拒绝默认 UA（返回 403），
 * 因此所有站点图片均通过 `ApiClient.fetchBytes` 拉取，经磁盘缓存落盘后解码为 PixelMap。
 */
export class ArchiveImageLoader {
  private readonly apiClient: ApiClient;
  private cacheDir: string = '';
  private readonly memCache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private readonly inFlight: Map<string, Promise<image.PixelMap | undefined>> =
    new Map<string, Promise<image.PixelMap | undefined>>();

  constructor(apiClient: ApiClient) {
    this.apiClient = apiClient;
  }

  init(context: common.Context): void {
    this.cacheDir = `${context.cacheDir}/image_cache`;
    try {
      if (!fileIo.accessSync(this.cacheDir)) {
        fileIo.mkdirSync(this.cacheDir, true);
      }
    } catch (e) {
      Logger.w(TAG, `mkdir image_cache failed: ${String(e)}`);
    }
  }

  private cacheFilePath(url: string): string {
    const h1 = FlexParsers.simpleHash(url);
    const h2 = FlexParsers.simpleHash(`v1:${url}:${url.length}`);
    return `${this.cacheDir}/${h1}_${h2}.bin`;
  }

  async loadPixelMap(url: string): Promise<image.PixelMap | undefined> {
    if (url.trim().length === 0) {
      return undefined;
    }
    const memHit = this.memCache.get(url);
    if (memHit !== undefined) {
      // LRU refresh
      this.memCache.delete(url);
      this.memCache.set(url, memHit);
      return memHit;
    }

    const existingJob = this.inFlight.get(url);
    if (existingJob !== undefined) {
      return existingJob;
    }

    const job: Promise<image.PixelMap | undefined> = this.fetchAndDecode(url);
    this.inFlight.set(url, job);
    try {
      return await job;
    } finally {
      this.inFlight.delete(url);
    }
  }

  private async fetchAndDecode(url: string): Promise<image.PixelMap | undefined> {
    const filePath = this.cacheFilePath(url);
    try {
      if (this.cacheDir.length > 0 && fileIo.accessSync(filePath)) {
        const fromDisk = await this.decodeFile(filePath);
        if (fromDisk !== undefined) {
          this.putMemCache(url, fromDisk);
          return fromDisk;
        }
      }
    } catch (_e) {
      // 磁盘缓存损坏则重新拉取
    }

    try {
      const bytes = await this.apiClient.fetchBytes(url);
      if (this.cacheDir.length > 0) {
        this.writeCacheFile(filePath, bytes);
      }
      const source = image.createImageSource(bytes);
      const pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      await source.release();
      this.putMemCache(url, pixelMap);
      return pixelMap;
    } catch (e) {
      Logger.w(TAG, `loadPixelMap failed for ${url}: ${String(e)}`);
      return undefined;
    }
  }

  private async decodeFile(filePath: string): Promise<image.PixelMap | undefined> {
    const source = image.createImageSource(filePath);
    try {
      return await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } finally {
      await source.release();
    }
  }

  private writeCacheFile(filePath: string, bytes: ArrayBuffer): void {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      try {
        fileIo.writeSync(file.fd, bytes);
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (e) {
      Logger.w(TAG, `writeCacheFile failed: ${String(e)}`);
    }
  }

  private putMemCache(key: string, pixelMap: image.PixelMap): void {
    if (this.memCache.size >= MAX_MEM_ENTRIES) {
      const oldestKey = this.memCache.keys().next().value as string | undefined;
      if (oldestKey !== undefined) {
        this.memCache.delete(oldestKey);
      }
    }
    this.memCache.set(key, pixelMap);
  }

  clearDiskAndMemoryCache(): void {
    this.memCache.clear();
    if (this.cacheDir.length === 0) {
      return;
    }
    try {
      const files = fileIo.listFileSync(this.cacheDir);
      for (let i = 0; i < files.length; i++) {
        try {
          fileIo.unlinkSync(`${this.cacheDir}/${files[i]}`);
        } catch (_e) {
          // ignore individual unlink error
        }
      }
    } catch (e) {
      Logger.w(TAG, `clearDiskAndMemoryCache failed: ${String(e)}`);
    }
  }
}
