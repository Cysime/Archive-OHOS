import { Want } from '@kit.AbilityKit';
import { ApiConstants } from '../../core/api/ApiConstants';
import { AppContainer } from '../../core/AppContainer';
import { UpdateChannel } from '../../core/store/SettingsManager';
import { Logger } from '../../core/util/Logger';
import { CURRENT_APP_VERSION, UpdateCheckResult, UpdateCheckStatus } from '../../data/ops/UpdateChecker';
import { AppButton, AppCard, AppDivider, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

const TAG: string = 'AboutScreen';

/**
 * 关于页与应用内更新检查（指向本 Fork 仓库 `Cysime/Archive-OHOS`，支持 API + releases.atom 降级）。
 */
@ComponentV2
export struct AboutScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local updateChannel: UpdateChannel = UpdateChannel.STABLE;
  @Local checking: boolean = false;
  @Local checkResult?: UpdateCheckResult = undefined;

  aboutToAppear(): void {
    this.updateChannel = this.container.settings.getSnapshot().updateChannel;
  }

  private openUrl(url: string): void {
    const ctx = this.container.getContext();
    if (ctx === undefined) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url
    };
    ctx.startAbility(want).catch((e: Object) => {
      Logger.w(TAG, `openUrl failed: ${String(e)}`);
    });
  }

  private async runCheck(): Promise<void> {
    if (this.checking) {
      return;
    }
    this.checking = true;
    try {
      this.checkResult = await this.container.updateChecker.check(this.updateChannel);
    } finally {
      this.checking = false;
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '关于 Archive',
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          AppCard() {
            Column({ space: 10 }) {
              Image($r('app.media.app_icon'))
                .width(68)
                .height(68)
                .borderRadius(18)

              Text('Archive for HarmonyOS NEXT')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Text(`版本 v${CURRENT_APP_VERSION} · GNU GPL-3.0`)
                .fontSize(13)
                .fontColor(this.theme.colors.textSecondary)

              Text('非官方第三方客户端，与 Pawchive 官方无隶属关系；移植自 Aerunox/Archive，仅限开源交流学习使用。')
                .fontSize(12)
                .fontColor(this.theme.colors.textTertiary)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }

          AppCard() {
            Column({ space: 10 }) {
              Text(`检查更新（${ApiConstants.GITHUB_OWNER}/${ApiConstants.GITHUB_REPO}）`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Row({ space: 8 }) {
                Text('更新通道：')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textSecondary)
                ForEach([UpdateChannel.STABLE, UpdateChannel.BETA], (ch: UpdateChannel) => {
                  Text(ch === UpdateChannel.STABLE ? '正式版 (STABLE)' : '测试版 (BETA)')
                    .fontSize(12)
                    .fontColor(this.updateChannel === ch ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(8)
                    .backgroundColor(
                      this.updateChannel === ch ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                    )
                    .onClick(() => {
                      this.updateChannel = ch;
                      this.container.settings.setUpdateChannel(ch);
                    })
                }, (ch: UpdateChannel) => ch)
              }

              AppButton({
                label: this.checking ? '正在检查…' : '立即检查更新',
                primary: true,
                disabled: this.checking,
                onAction: () => {
                  this.runCheck();
                }
              })

              if (this.checkResult !== undefined) {
                Column({ space: 6 }) {
                  Text(this.checkResult.message)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(
                      this.checkResult.status === UpdateCheckStatus.UPDATE_AVAILABLE
                        ? this.theme.colors.primary
                        : (this.checkResult.status === UpdateCheckStatus.UP_TO_DATE
                          ? this.theme.colors.textPrimary
                          : this.theme.colors.error)
                    )

                  if (this.checkResult.latest !== undefined && this.checkResult.latest.notes.length > 0) {
                    Text(this.checkResult.latest.notes)
                      .fontSize(12)
                      .fontColor(this.theme.colors.textSecondary)
                  }

                  if (this.checkResult.status === UpdateCheckStatus.UPDATE_AVAILABLE) {
                    AppButton({
                      label: '在浏览器中前往 Release 页面',
                      primary: false,
                      onAction: () => {
                        const target = this.checkResult?.latest?.htmlUrl ?? ApiConstants.GITHUB_RELEASES_URL;
                        this.openUrl(target.length > 0 ? target : ApiConstants.GITHUB_RELEASES_URL);
                      }
                    })
                  }
                }
                .width('100%')
                .padding(10)
                .borderRadius(10)
                .backgroundColor(this.theme.colors.surfaceContainer)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          AppCard() {
            Column({ space: 10 }) {
              Text('项目与致谢')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Row() {
                Text('HarmonyOS 移植仓库（Fork）')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Text('Cysime/Archive-OHOS')
                  .fontSize(12)
                  .fontColor(this.theme.colors.primary)
              }
              .width('100%')
              .onClick(() => {
                this.openUrl(`https://github.com/${ApiConstants.GITHUB_OWNER}/${ApiConstants.GITHUB_REPO}`);
              })

              AppDivider()

              Row() {
                Text('上游 Android 原项目')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Text('Aerunox/Archive')
                  .fontSize(12)
                  .fontColor(this.theme.colors.primary)
              }
              .width('100%')
              .onClick(() => {
                this.openUrl('https://github.com/Aerunox/Archive');
              })
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
