import { Want } from '@kit.AbilityKit';
import { AppContainer } from '../../core/AppContainer';
import { Logger } from '../../core/util/Logger';
import { AppButton, AppIcon } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

const TAG: string = 'AgeGateScreen';
const PAWCHIVE_HOME_URL: string = 'https://pawchive.pw/';

/**
 * 首次启动的 18+ 年龄确认页（对齐上游 ui/screens/AgeGateScreen.kt）。
 */
@ComponentV2
export struct AgeGateScreen {
  @Event onConfirm: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  private readonly bulletLines: string[] = [
    '站点内容来自 Patreon / Fanbox 等平台，可能包含成人内容（18+）。',
    '继续使用即表示你确认已年满 18 周岁，且在所在地浏览此类内容合法。',
    '仅作为客户端展示内容：不内置、不转存任何内容，不上传用户数据，不含统计 SDK。'
  ];

  private openOfficialSite(): void {
    const context = AppContainer.getInstance().getContext();
    if (context === undefined) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: PAWCHIVE_HOME_URL
    };
    context.startAbility(want).catch((e: Object) => {
      Logger.w(TAG, `openOfficialSite failed: ${String(e)}`);
    });
  }

  private exitApp(): void {
    const context = AppContainer.getInstance().getContext();
    if (context !== undefined) {
      context.terminateSelf().catch((e: Object) => {
        Logger.w(TAG, `terminateSelf failed: ${String(e)}`);
      });
    }
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Image($r('app.media.app_icon'))
            .width(72)
            .height(72)
            .borderRadius(20)
            .objectFit(ImageFit.Cover)

          Text('Archive')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.colors.textPrimary)
            .margin({ top: 16 })

          Text('18+')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.colors.primary)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(8)
            .backgroundColor(this.theme.colors.surfaceContainerHigh)
            .margin({ top: 8 })

          Text('成人内容提示')
            .fontSize(14)
            .fontColor(this.theme.colors.textSecondary)
            .margin({ top: 20 })

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              AppIcon({ icon: $r('app.media.ic_check'), iconSize: 16, tint: this.theme.colors.primary })
                .margin({ top: 3 })
              Text() {
                Span('本应用是 ')
                  .fontColor(this.theme.colors.textPrimary)
                Span('Pawchive')
                  .fontColor(this.theme.colors.primary)
                  .decoration({ type: TextDecorationType.Underline, color: this.theme.colors.primary })
                  .onClick(() => {
                    this.openOfficialSite();
                  })
                Span(' 的第三方客户端。')
                  .fontColor(this.theme.colors.textPrimary)
              }
              .fontSize(14)
              .lineHeight(20)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            ForEach(this.bulletLines, (line: string) => {
              Row({ space: 10 }) {
                AppIcon({ icon: $r('app.media.ic_check'), iconSize: 16, tint: this.theme.colors.primary })
                  .margin({ top: 3 })
                Text(line)
                  .fontSize(14)
                  .lineHeight(20)
                  .fontColor(this.theme.colors.textSecondary)
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (line: string) => line)
          }
          .width('100%')
          .margin({ top: 18 })

          AppButton({
            label: '我已年满 18 周岁，继续',
            primary: true,
            onAction: () => {
              this.onConfirm();
            }
          })
            .margin({ top: 28 })

          AppButton({
            label: '未满 18 周岁，退出',
            primary: false,
            onAction: () => {
              this.exitApp();
            }
          })
            .margin({ top: 10 })
        }
        .width('100%')
        .constraintSize({ maxWidth: 460 })
        .padding({
          left: 28,
          right: 28,
          top: 32 + this.theme.topSafeVp,
          bottom: 32 + this.theme.bottomSafeVp
        })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
