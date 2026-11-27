import { ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppColorMode } from '../../core/store/SettingsManager';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'ArchiveTheme';

export const DEFAULT_SEED_LIGHT: string = '#3482FF';
export const DEFAULT_SEED_DARK: string = '#5B9BFF';

export interface PurrColors {
  background: string;
  surface: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  primary: string;
  onPrimary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  divider: string;
  error: string;
  scrim: string;
}

export function purrLightColors(primary: string = DEFAULT_SEED_LIGHT): PurrColors {
  return {
    background: '#FFF6F7FB',
    surface: '#FFFFFFFF',
    surfaceContainer: '#FFF0F1F6',
    surfaceContainerHigh: '#FFE8EAF1',
    primary: primary,
    onPrimary: '#FFFFFFFF',
    secondaryContainer: '#FFE3ECFF',
    onSecondaryContainer: '#FF14345F',
    textPrimary: '#FF16181D',
    textSecondary: '#FF5C6068',
    textTertiary: '#FF90949C',
    divider: '#1F000000',
    error: '#FFB3261E',
    scrim: '#66000000'
  };
}

export function purrDarkColors(primary: string = DEFAULT_SEED_DARK): PurrColors {
  return {
    background: '#FF101216',
    surface: '#FF191B20',
    surfaceContainer: '#FF1F2228',
    surfaceContainerHigh: '#FF272A31',
    primary: primary,
    onPrimary: '#FFFFFFFF',
    secondaryContainer: '#FF2C3B55',
    onSecondaryContainer: '#FFD6E4FF',
    textPrimary: '#FFEDEFF3',
    textSecondary: '#FFA6AAB2',
    textTertiary: '#FF6F737B',
    divider: '#24FFFFFF',
    error: '#FFF2B8B5',
    scrim: '#99000000'
  };
}

export function serviceBrandColor(service?: string): string | undefined {
  const normalized = (service ?? '').trim().toLowerCase();
  if (normalized === 'patreon') {
    return '#FFF96854';
  }
  if (normalized === 'fanbox') {
    return '#FF0096FA';
  }
  return undefined;
}

export function servicePlatformLabel(service?: string): string {
  const normalized = (service ?? '').trim().toLowerCase();
  if (normalized === 'patreon') {
    return 'PATREON';
  }
  if (normalized === 'fanbox') {
    return 'FANBOX';
  }
  if (normalized.length === 0) {
    return '';
  }
  return normalized.toUpperCase();
}

export function onServiceBrandColor(_brandHex: string): string {
  return '#FFFFFFFF';
}

/**
 * 响应式主题与窗口外观控制器（零重启即时切换浅/深色与种子色，同步窗口底色防闪白、同步防截屏隐私模式）。
 */
@ObservedV2
export class ArchiveThemeController {
  private static instance?: ArchiveThemeController;

  @Trace isDark: boolean = false;
  @Trace colorMode: AppColorMode = AppColorMode.SYSTEM;
  @Trace seedColorHex: string = DEFAULT_SEED_LIGHT;
  @Trace blurThumbnails: boolean = true;
  @Trace colors: PurrColors = purrLightColors();

  private systemColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private mainWindow?: window.Window;

  static getInstance(): ArchiveThemeController {
    if (ArchiveThemeController.instance === undefined) {
      ArchiveThemeController.instance = new ArchiveThemeController();
    }
    return ArchiveThemeController.instance;
  }

  attachWindow(win: window.Window): void {
    this.mainWindow = win;
    this.syncWindowAppearance();
  }

  setSystemColorMode(mode?: ConfigurationConstant.ColorMode): void {
    if (mode !== undefined && mode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      this.systemColorMode = mode;
      this.recompute();
    }
  }

  applySettings(
    colorMode: AppColorMode,
    seedColorHex: string,
    blurThumbnails: boolean,
    preventScreenshot: boolean
  ): void {
    this.colorMode = colorMode;
    this.seedColorHex = seedColorHex.trim().length > 0 ? seedColorHex.trim() : DEFAULT_SEED_LIGHT;
    this.blurThumbnails = blurThumbnails;
    this.recompute();
    this.applyPrivacyMode(preventScreenshot);
  }

  private recompute(): void {
    let dark = false;
    if (this.colorMode === AppColorMode.DARK || this.colorMode === AppColorMode.MONET_DARK) {
      dark = true;
    } else if (this.colorMode === AppColorMode.LIGHT || this.colorMode === AppColorMode.MONET_LIGHT) {
      dark = false;
    } else {
      dark = this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }

    this.isDark = dark;
    const isCustomSeed = this.colorMode === AppColorMode.MONET_SYSTEM ||
      this.colorMode === AppColorMode.MONET_LIGHT ||
      this.colorMode === AppColorMode.MONET_DARK;
    const primary = isCustomSeed
      ? this.seedColorHex
      : (dark ? DEFAULT_SEED_DARK : DEFAULT_SEED_LIGHT);

    this.colors = dark ? purrDarkColors(primary) : purrLightColors(primary);
    this.syncWindowAppearance();
  }

  private syncWindowAppearance(): void {
    if (this.mainWindow === undefined) {
      return;
    }
    try {
      this.mainWindow.setWindowBackgroundColor(this.colors.background);
      const sysProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: this.isDark ? '#EDEFF3' : '#16181D',
        navigationBarContentColor: this.isDark ? '#EDEFF3' : '#16181D'
      };
      this.mainWindow.setWindowSystemBarProperties(sysProps).catch((e: Object) => {
        Logger.w(TAG, `setWindowSystemBarProperties failed: ${String(e)}`);
      });
    } catch (e) {
      Logger.w(TAG, `syncWindowAppearance failed: ${String(e)}`);
    }
  }

  applyPrivacyMode(enabled: boolean): void {
    if (this.mainWindow === undefined) {
      return;
    }
    this.mainWindow.setWindowPrivacyMode(enabled).catch((e: Object) => {
      Logger.w(TAG, `setWindowPrivacyMode(${enabled}) failed: ${String(e)}`);
    });
  }
}
