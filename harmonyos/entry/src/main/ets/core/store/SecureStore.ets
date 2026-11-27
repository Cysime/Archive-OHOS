import { asset } from '@kit.AssetStoreKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../util/Logger';

const TAG: string = 'SecureStore';
const FALLBACK_PREFS: string = 'archive_secure_fallback';

/**
 * 敏感凭据安全存储（优先使用 HarmonyOS AssetStoreKit；若设备/模拟器环境不支持则安全降级至应用私有 Preferences）。
 * 用于保存：多账号 Session Cookie、Cloudflare cf_clearance、AI API Key。
 */
export class SecureStore {
  private readonly encoder: util.TextEncoder = new util.TextEncoder();
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private fallbackPrefs?: preferences.Preferences;

  async init(context: common.Context): Promise<void> {
    try {
      this.fallbackPrefs = await preferences.getPreferences(context, FALLBACK_PREFS);
    } catch (e) {
      Logger.w(TAG, `init fallback preferences failed: ${String(e)}`);
    }
  }

  private toBytes(text: string): Uint8Array {
    return this.encoder.encodeInto(text);
  }

  private fromBytes(bytes: Uint8Array): string {
    return this.decoder.decodeToString(bytes);
  }

  async put(alias: string, secret: string): Promise<void> {
    const aliasBytes = this.toBytes(alias);
    const secretBytes = this.toBytes(secret);
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, aliasBytes);
      const attrs: asset.AssetMap = new Map();
      attrs.set(asset.Tag.SECRET, secretBytes);
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      try {
        await asset.update(query, attrs);
      } catch (_updateErr) {
        const addMap: asset.AssetMap = new Map();
        addMap.set(asset.Tag.ALIAS, aliasBytes);
        addMap.set(asset.Tag.SECRET, secretBytes);
        addMap.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        await asset.add(addMap);
      }
      return;
    } catch (e) {
      Logger.w(TAG, `AssetStore put(${alias}) unavailable, using fallback: ${String(e)}`);
    }

    if (this.fallbackPrefs !== undefined) {
      try {
        await this.fallbackPrefs.put(alias, secret);
        await this.fallbackPrefs.flush();
      } catch (e) {
        Logger.w(TAG, `fallback put(${alias}) failed: ${String(e)}`);
      }
    }
  }

  async get(alias: string): Promise<string | undefined> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, this.toBytes(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length > 0) {
        const rawSecret = results[0].get(asset.Tag.SECRET);
        if (rawSecret instanceof Uint8Array) {
          return this.fromBytes(rawSecret);
        }
      }
    } catch (_e) {
      // Asset 未找到或服务不可用时继续尝试降级存储
    }

    if (this.fallbackPrefs !== undefined) {
      try {
        const val = await this.fallbackPrefs.get(alias, '');
        if (typeof val === 'string' && val.length > 0) {
          return val;
        }
      } catch (e) {
        Logger.w(TAG, `fallback get(${alias}) failed: ${String(e)}`);
      }
    }
    return undefined;
  }

  async remove(alias: string): Promise<void> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, this.toBytes(alias));
      await asset.remove(query);
    } catch (_e) {
      // ignore if absent
    }

    if (this.fallbackPrefs !== undefined) {
      try {
        await this.fallbackPrefs.delete(alias);
        await this.fallbackPrefs.flush();
      } catch (e) {
        Logger.w(TAG, `fallback remove(${alias}) failed: ${String(e)}`);
      }
    }
  }
}
