import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { FlexParsers, JsonObject } from '../../core/api/FlexParsers';
import { SecureStore } from '../../core/store/SecureStore';
import { Logger } from '../../core/util/Logger';
import { AiPurpose, AiSettingsSnapshot, ApiTypeHelper, ModelProfile } from './ModelProfile';

const TAG: string = 'TranslationSettingsRepo';
const PREFS_NAME: string = 'archive_ai_settings';
const KEY_SNAPSHOT: string = 'ai_settings_v1';

/**
 * AI 多模型档案与用途指派仓库（配置存 Preferences，API Key 加密存 AssetStore/SecureStore）。
 */
export class TranslationSettingsRepository {
  private readonly secureStore: SecureStore;
  private prefs?: preferences.Preferences;
  private snapshot: AiSettingsSnapshot = TranslationSettingsRepository.defaultSnapshot();

  constructor(secureStore: SecureStore) {
    this.secureStore = secureStore;
  }

  static defaultSnapshot(): AiSettingsSnapshot {
    return {
      profiles: [],
      translationProfileId: '',
      visionProfileId: '',
      targetLanguage: '简体中文',
      customSystemPrompt: ''
    };
  }

  private apiKeyAlias(profileId: string): string {
    return `archive_ai_apikey_${profileId}`;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
      const raw = String(await this.prefs.get(KEY_SNAPSHOT, ''));
      if (raw.trim().length > 0) {
        const obj = FlexParsers.asObject(JSON.parse(raw) as Object);
        if (obj !== undefined) {
          const profilesArr = FlexParsers.asArray(obj['profiles']);
          const profiles: ModelProfile[] = [];
          for (let i = 0; i < profilesArr.length; i++) {
            const pObj = FlexParsers.asObject(profilesArr[i]);
            if (pObj === undefined) {
              continue;
            }
            const id = FlexParsers.readString(pObj, 'id') ?? '';
            if (id.length === 0) {
              continue;
            }
            profiles.push({
              id: id,
              name: FlexParsers.readString(pObj, 'name') ?? '未命名档案',
              apiType: ApiTypeHelper.fromString(FlexParsers.readString(pObj, 'apiType')),
              url: FlexParsers.readString(pObj, 'url') ?? '',
              model: FlexParsers.readString(pObj, 'model') ?? '',
              temperature: FlexParsers.readNumber(pObj, 'temperature'),
              topP: FlexParsers.readNumber(pObj, 'topP'),
              maxTokens: FlexParsers.readNumber(pObj, 'maxTokens'),
              enableThinking: FlexParsers.readBoolean(pObj, 'enableThinking', false),
              enableWebSearch: FlexParsers.readBoolean(pObj, 'enableWebSearch', false)
            });
          }
          this.snapshot = {
            profiles: profiles,
            translationProfileId: FlexParsers.readString(obj, 'translationProfileId') ?? '',
            visionProfileId: FlexParsers.readString(obj, 'visionProfileId') ?? '',
            targetLanguage: FlexParsers.readString(obj, 'targetLanguage') ?? '简体中文',
            customSystemPrompt: FlexParsers.readString(obj, 'customSystemPrompt') ?? ''
          };
        }
      }
    } catch (e) {
      Logger.w(TAG, `init AI settings failed: ${String(e)}`);
    }
  }

  getSnapshot(): AiSettingsSnapshot {
    return this.snapshot;
  }

  getProfileForPurpose(purpose: AiPurpose): ModelProfile | undefined {
    const targetId = purpose === AiPurpose.VISION
      ? this.snapshot.visionProfileId
      : this.snapshot.translationProfileId;
    if (targetId.length > 0) {
      for (let i = 0; i < this.snapshot.profiles.length; i++) {
        if (this.snapshot.profiles[i].id === targetId) {
          return this.snapshot.profiles[i];
        }
      }
    }
    return this.snapshot.profiles.length > 0 ? this.snapshot.profiles[0] : undefined;
  }

  async getApiKey(profileId: string): Promise<string> {
    return (await this.secureStore.get(this.apiKeyAlias(profileId))) ?? '';
  }

  private async persist(): Promise<void> {
    if (this.prefs !== undefined) {
      try {
        await this.prefs.put(KEY_SNAPSHOT, JSON.stringify(this.snapshot));
        await this.prefs.flush();
      } catch (e) {
        Logger.w(TAG, `persist AI settings failed: ${String(e)}`);
      }
    }
  }

  async upsertProfile(profile: ModelProfile, apiKey?: string): Promise<void> {
    const list = this.snapshot.profiles.slice();
    let replaced = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === profile.id) {
        list[i] = profile;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      list.push(profile);
    }
    this.snapshot.profiles = list;
    if (this.snapshot.translationProfileId.length === 0) {
      this.snapshot.translationProfileId = profile.id;
    }
    if (this.snapshot.visionProfileId.length === 0) {
      this.snapshot.visionProfileId = profile.id;
    }
    if (apiKey !== undefined) {
      await this.secureStore.put(this.apiKeyAlias(profile.id), apiKey.trim());
    }
    await this.persist();
  }

  async deleteProfile(profileId: string): Promise<void> {
    this.snapshot.profiles = this.snapshot.profiles.filter((p: ModelProfile) => p.id !== profileId);
    if (this.snapshot.translationProfileId === profileId) {
      this.snapshot.translationProfileId = this.snapshot.profiles.length > 0 ? this.snapshot.profiles[0].id : '';
    }
    if (this.snapshot.visionProfileId === profileId) {
      this.snapshot.visionProfileId = this.snapshot.profiles.length > 0 ? this.snapshot.profiles[0].id : '';
    }
    await this.secureStore.remove(this.apiKeyAlias(profileId));
    await this.persist();
  }

  async assignPurpose(purpose: AiPurpose, profileId: string): Promise<void> {
    if (purpose === AiPurpose.VISION) {
      this.snapshot.visionProfileId = profileId;
    } else {
      this.snapshot.translationProfileId = profileId;
    }
    await this.persist();
  }

  async setTargetLanguage(lang: string): Promise<void> {
    this.snapshot.targetLanguage = lang.trim().length > 0 ? lang.trim() : '简体中文';
    await this.persist();
  }
}
