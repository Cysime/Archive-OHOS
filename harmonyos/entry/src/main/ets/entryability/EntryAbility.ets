import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppContainer } from '../core/AppContainer';
import { Logger } from '../core/util/Logger';
import { ArchiveThemeController } from '../ui/theme/PurrColors';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private initPromise?: Promise<void>;

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const theme = ArchiveThemeController.getInstance();
    theme.setSystemColorMode(this.context.config.colorMode);
    this.initPromise = AppContainer.getInstance().init(this.context).then(() => {
      const snap = AppContainer.getInstance().settings.getSnapshot();
      theme.applySettings(snap.colorMode, snap.seedColorHex, snap.blurThumbnails, snap.preventScreenshot);
    }).catch((e: Object) => {
      Logger.e(TAG, `AppContainer init failed: ${String(e)}`);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    ArchiveThemeController.getInstance().setSystemColorMode(newConfig.colorMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const startLoad = (): void => {
      try {
        const mainWin = windowStage.getMainWindowSync();
        const theme = ArchiveThemeController.getInstance();
        theme.attachWindow(mainWin);
        const snap = AppContainer.getInstance().settings.getSnapshot();
        theme.applyPrivacyMode(snap.preventScreenshot);
      } catch (e) {
        Logger.w(TAG, `attachWindow failed: ${String(e)}`);
      }
      windowStage.loadContent('pages/Index', (err) => {
        if (err && err.code) {
          Logger.e(TAG, `loadContent failed: code=${err.code}, msg=${err.message}`);
          return;
        }
        ArchiveThemeController.getInstance().refreshSafeInsets();
      });
    };

    if (this.initPromise !== undefined) {
      this.initPromise.finally(() => {
        startLoad();
      });
    } else {
      startLoad();
    }
  }

  onDestroy(): void {
    AppContainer.getInstance().destroy();
  }
}
