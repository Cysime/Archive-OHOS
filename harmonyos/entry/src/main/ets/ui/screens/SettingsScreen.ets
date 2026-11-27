import { i18n } from '@kit.LocalizationKit';
import { LengthMetrics } from '@kit.ArkUI';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { AppColorMode, SettingsManager } from '../../core/store/SettingsManager';
import { AppButton, AppCard, AppDivider, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

interface LanguageOption {
  tag: string;
  label: string;
}

interface SeedOption {
  name: string;
  hex: string;
}

/**
 * 完整个性化与维护设置页（对齐上游 ui/screens/SettingsScreen.kt）。
 *
 * - 外观 6 态（System/Light/Dark/Monet×3）+ 种子色即时无重启生效
 * - 12 语言切换（含阿拉伯语 RTL）
 * - 隐私安全（缩略图模糊 / 禁止截屏）、站点 Base URL
 * - 下载参数（并发 1–5、重试 1–3、仅 Wi-Fi、命名模板）
 * - 订阅设置（收藏即订阅、同步间隔 ≥15min）与 JSON v1 备份导出/导入
 */
@ComponentV2
export struct SettingsScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  private readonly languageOptions: LanguageOption[] = [
    { tag: 'system', label: '跟随系统' },
    { tag: 'zh-Hans', label: '简体中文' },
    { tag: 'zh-Hant', label: '繁體中文' },
    { tag: 'en', label: 'English' },
    { tag: 'ja', label: '日本語' },
    { tag: 'ko', label: '한국어' },
    { tag: 'de', label: 'Deutsch' },
    { tag: 'es', label: 'Español' },
    { tag: 'fr', label: 'Français' },
    { tag: 'id', label: 'Indonesia' },
    { tag: 'ru', label: 'Русский' },
    { tag: 'tr', label: 'Türkçe' },
    { tag: 'ar', label: 'العربية (RTL)' }
  ];

  private readonly seedPresets: SeedOption[] = [
    { name: '海蓝', hex: '#3482FF' },
    { name: '紫罗兰', hex: '#7C3AED' },
    { name: '珊瑚', hex: '#F96854' },
    { name: '翡翠', hex: '#10B981' },
    { name: '琥珀', hex: '#F59E0B' },
    { name: '玫瑰', hex: '#EC4899' }
  ];

  @Local colorMode: AppColorMode = AppColorMode.SYSTEM;
  @Local seedColorHex: string = '#3482FF';
  @Local languageTag: string = 'system';
  @Local blurThumbnails: boolean = true;
  @Local preventScreenshot: boolean = false;
  @Local baseUrlInput: string = '';
  @Local concurrency: number = 3;
  @Local maxRetries: number = 2;
  @Local wifiOnly: boolean = false;
  @Local fileNamingInput: string = '';
  @Local autoSubscribe: boolean = false;
  @Local syncIntervalMinutes: number = 30;
  @Local statusMessage: string = '';
  @Local statusError: boolean = false;

  aboutToAppear(): void {
    this.loadSnapshot();
  }

  private loadSnapshot(): void {
    const snap = this.container.settings.getSnapshot();
    this.colorMode = snap.colorMode;
    this.seedColorHex = snap.seedColorHex;
    this.languageTag = snap.languageTag;
    this.blurThumbnails = snap.blurThumbnails;
    this.preventScreenshot = snap.preventScreenshot;
    this.baseUrlInput = snap.baseUrl;
    this.concurrency = snap.downloadConcurrency;
    this.maxRetries = snap.downloadMaxRetries;
    this.wifiOnly = snap.downloadWifiOnly;
    this.fileNamingInput = snap.fileNamingFormat;
    this.autoSubscribe = snap.autoSubscribeOnFavorite;
    this.syncIntervalMinutes = snap.syncIntervalMinutes;
  }

  private applyThemeNow(): void {
    const snap = this.container.settings.getSnapshot();
    this.theme.applySettings(snap.colorMode, snap.seedColorHex, snap.blurThumbnails, snap.preventScreenshot);
  }

  private applyLanguage(tag: string): void {
    this.languageTag = tag;
    this.container.settings.setLanguageTag(tag);
    try {
      i18n.System.setAppPreferredLanguage(tag === 'system' ? 'default' : tag);
      this.statusError = false;
      this.statusMessage = tag === 'ar'
        ? '已切换至 العربية（支持 RTL 镜像布局）'
        : `界面语言已设置为：${tag}`;
    } catch (e) {
      this.statusError = false;
      this.statusMessage = `已记录语言偏好（${tag}），重启应用后生效`;
    }
  }

  private async exportBackup(): Promise<void> {
    const ctx = this.container.getContext();
    if (ctx === undefined) {
      return;
    }
    const ok = await this.container.backupManager.exportToPicker(ctx);
    this.statusError = !ok;
    this.statusMessage = ok
      ? '已导出 JSON v1 备份（兼容 Android 版，不含 Cookie 与搜索历史）'
      : '已取消导出或导出失败';
  }

  private async importBackup(): Promise<void> {
    const ctx = this.container.getContext();
    if (ctx === undefined) {
      return;
    }
    try {
      const res = await this.container.backupManager.importFromPicker(ctx);
      if (res === undefined) {
        return;
      }
      this.loadSnapshot();
      this.applyThemeNow();
      this.statusError = false;
      this.statusMessage =
        `恢复成功：收藏 ${res.favoritesRestored} · 屏蔽作者 ${res.blockedCreatorsRestored} · 屏蔽帖 ${res.blockedPostsRestored} · 订阅 ${res.subscriptionsRestored}`;
    } catch (e) {
      this.statusError = true;
      this.statusMessage = AppError.friendlyMessage(e as Object);
    }
  }

  private colorModeLabel(mode: AppColorMode): string {
    if (mode === AppColorMode.LIGHT) {
      return '浅色';
    }
    if (mode === AppColorMode.DARK) {
      return '深色';
    }
    if (mode === AppColorMode.MONET_SYSTEM) {
      return '种子·系统';
    }
    if (mode === AppColorMode.MONET_LIGHT) {
      return '种子·浅色';
    }
    if (mode === AppColorMode.MONET_DARK) {
      return '种子·深色';
    }
    return '跟随系统';
  }

  build() {
    Column() {
      AppTopBar({
        title: '设置',
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .fontSize(12)
              .fontColor(this.statusError ? this.theme.colors.error : this.theme.colors.primary)
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.theme.colors.surface)
              .width('100%')
          }

          // 外观设置（6 态 + 种子色）
          AppCard() {
            Column({ space: 10 }) {
              Text('外观配色（即时切换，不重启）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
                ForEach(
                  [
                    AppColorMode.SYSTEM,
                    AppColorMode.LIGHT,
                    AppColorMode.DARK,
                    AppColorMode.MONET_SYSTEM,
                    AppColorMode.MONET_LIGHT,
                    AppColorMode.MONET_DARK
                  ],
                  (m: AppColorMode) => {
                    Text(this.colorModeLabel(m))
                      .fontSize(12)
                      .fontColor(this.colorMode === m ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(10)
                      .backgroundColor(
                        this.colorMode === m ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                      )
                      .onClick(() => {
                        this.colorMode = m;
                        this.container.settings.setColorMode(m).then(() => {
                          this.applyThemeNow();
                        });
                      })
                  },
                  (m: AppColorMode) => m
                )
              }

              Text('种子强调色')
                .fontSize(12)
                .fontColor(this.theme.colors.textSecondary)

              Row({ space: 8 }) {
                ForEach(this.seedPresets, (preset: SeedOption) => {
                  Column()
                    .width(28)
                    .height(28)
                    .borderRadius(14)
                    .backgroundColor(preset.hex)
                    .border({
                      width: this.seedColorHex === preset.hex ? 3 : 0,
                      color: this.theme.colors.textPrimary
                    })
                    .onClick(() => {
                      this.seedColorHex = preset.hex;
                      this.container.settings.setSeedColorHex(preset.hex).then(() => {
                        this.applyThemeNow();
                      });
                    })
                }, (preset: SeedOption) => preset.hex)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 多语言（12 语言 + RTL）
          AppCard() {
            Column({ space: 10 }) {
              Text('界面语言（12 语言 · 含阿拉伯语 RTL）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
                ForEach(this.languageOptions, (opt: LanguageOption) => {
                  Text(opt.label)
                    .fontSize(12)
                    .fontColor(this.languageTag === opt.tag ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .borderRadius(10)
                    .backgroundColor(
                      this.languageTag === opt.tag ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                    )
                    .onClick(() => {
                      this.applyLanguage(opt.tag);
                    })
                }, (opt: LanguageOption) => opt.tag)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 隐私与站点
          AppCard() {
            Column({ space: 10 }) {
              Text('隐私与安全')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Row() {
                Text('默认模糊列表缩略图（点击显示）')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.blurThumbnails })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((v: boolean) => {
                    this.blurThumbnails = v;
                    this.container.settings.setBlurThumbnails(v).then(() => {
                      this.applyThemeNow();
                    });
                  })
              }
              .width('100%')

              AppDivider()

              Row() {
                Text('禁止截屏与录屏（PRIVACY_WINDOW）')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.preventScreenshot })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((v: boolean) => {
                    this.preventScreenshot = v;
                    this.container.settings.setPreventScreenshot(v).then(() => {
                      this.theme.applyPrivacyMode(v);
                    });
                  })
              }
              .width('100%')

              AppDivider()

              Text('站点 Base URL')
                .fontSize(12)
                .fontColor(this.theme.colors.textSecondary)

              Row({ space: 8 }) {
                TextInput({ text: this.baseUrlInput, placeholder: 'https://pawchive.pw' })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.baseUrlInput = v;
                  })
                AppButton({
                  label: '保存',
                  primary: true,
                  fullWidth: false,
                  onAction: () => {
                    this.container.settings.setBaseUrl(this.baseUrlInput).then(() => {
                      this.container.cloudflare.setTargetBaseUrl(this.container.settings.getSnapshot().baseUrl);
                      this.statusError = false;
                      this.statusMessage = '已更新站点 Base URL';
                    });
                  }
                })
                  .width(72)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 下载与订阅参数
          AppCard() {
            Column({ space: 10 }) {
              Text('下载与订阅策略')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Row() {
                Text(`下载并发上限（1–5）：${this.concurrency}`)
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Row({ space: 6 }) {
                  Button('-', { type: ButtonType.Normal })
                    .width(34)
                    .height(30)
                    .borderRadius(8)
                    .backgroundColor(this.theme.colors.surfaceContainerHigh)
                    .fontColor(this.theme.colors.textPrimary)
                    .onClick(() => {
                      const next = SettingsManager.clampConcurrency(this.concurrency - 1);
                      this.concurrency = next;
                      this.container.settings.setDownloadConcurrency(next);
                    })
                  Button('+', { type: ButtonType.Normal })
                    .width(34)
                    .height(30)
                    .borderRadius(8)
                    .backgroundColor(this.theme.colors.surfaceContainerHigh)
                    .fontColor(this.theme.colors.textPrimary)
                    .onClick(() => {
                      const next = SettingsManager.clampConcurrency(this.concurrency + 1);
                      this.concurrency = next;
                      this.container.settings.setDownloadConcurrency(next);
                    })
                }
              }
              .width('100%')

              Row() {
                Text(`失败重试次数（1–3）：${this.maxRetries}`)
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Row({ space: 6 }) {
                  Button('-', { type: ButtonType.Normal })
                    .width(34)
                    .height(30)
                    .borderRadius(8)
                    .backgroundColor(this.theme.colors.surfaceContainerHigh)
                    .fontColor(this.theme.colors.textPrimary)
                    .onClick(() => {
                      const next = SettingsManager.clampRetries(this.maxRetries - 1);
                      this.maxRetries = next;
                      this.container.settings.setDownloadMaxRetries(next);
                    })
                  Button('+', { type: ButtonType.Normal })
                    .width(34)
                    .height(30)
                    .borderRadius(8)
                    .backgroundColor(this.theme.colors.surfaceContainerHigh)
                    .fontColor(this.theme.colors.textPrimary)
                    .onClick(() => {
                      const next = SettingsManager.clampRetries(this.maxRetries + 1);
                      this.maxRetries = next;
                      this.container.settings.setDownloadMaxRetries(next);
                    })
                }
              }
              .width('100%')

              Row() {
                Text('仅在 Wi-Fi 下下载')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.wifiOnly })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((v: boolean) => {
                    this.wifiOnly = v;
                    this.container.settings.setDownloadWifiOnly(v);
                  })
              }
              .width('100%')

              AppDivider()

              Row() {
                Text('收藏创作者时自动订阅更新')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.autoSubscribe })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((v: boolean) => {
                    this.autoSubscribe = v;
                    this.container.settings.setAutoSubscribeOnFavorite(v);
                  })
              }
              .width('100%')

              Row({ space: 6 }) {
                Text('订阅检查间隔：')
                  .fontSize(12)
                  .fontColor(this.theme.colors.textSecondary)
                ForEach([15, 30, 60, 120], (min: number) => {
                  Text(`${min}分`)
                    .fontSize(11)
                    .fontColor(this.syncIntervalMinutes === min ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(8)
                    .backgroundColor(
                      this.syncIntervalMinutes === min ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                    )
                    .onClick(() => {
                      this.syncIntervalMinutes = min;
                      this.container.settings.setSyncIntervalMinutes(min);
                    })
                }, (min: number) => `${min}`)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 备份与恢复（schema v1）
          AppCard() {
            Column({ space: 10 }) {
              Text('数据备份与恢复（JSON v1 · 兼容 Android）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Text('导出内容包含收藏、屏蔽名单、订阅与偏好设置；会话 Cookie、AI API Key 与搜索历史永不导出。')
                .fontSize(12)
                .fontColor(this.theme.colors.textSecondary)

              Row({ space: 8 }) {
                AppButton({
                  label: '导出备份',
                  primary: true,
                  fullWidth: false,
                  onAction: () => {
                    this.exportBackup();
                  }
                })
                  .layoutWeight(1)

                AppButton({
                  label: '导入恢复',
                  primary: false,
                  fullWidth: false,
                  onAction: () => {
                    this.importBackup();
                  }
                })
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 28 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
