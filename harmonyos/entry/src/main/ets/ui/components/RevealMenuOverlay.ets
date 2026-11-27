import { AppIcon } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

export interface RevealMenuItem {
  label: string;
  icon: Resource;
  action: () => void;
}

/**
 * 全屏展开菜单浮层（对齐上游 AppNavHost.kt RevealMenuOverlay：全站搜索/浏览历史/下载管理/AI 设置/一键清理缓存）。
 */
@ComponentV2
export struct RevealMenuOverlay {
  @Param @Require visible: boolean;
  @Param @Require items: RevealMenuItem[];
  @Event onDismiss: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme.colors.scrim)
          .onClick(() => {
            this.onDismiss();
          })

        Column({ space: 10 }) {
          Row() {
            Text('快捷入口')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.colors.textPrimary)
              .layoutWeight(1)
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              AppIcon({ icon: $r('app.media.ic_close'), iconSize: 18, tint: this.theme.colors.textSecondary })
            }
            .width(34)
            .height(34)
            .backgroundColor(this.theme.colors.surfaceContainerHigh)
            .onClick(() => {
              this.onDismiss();
            })
          }
          .width('100%')
          .margin({ bottom: 4 })

          ForEach(this.items, (item: RevealMenuItem) => {
            Row({ space: 12 }) {
              AppIcon({ icon: item.icon, iconSize: 20, tint: this.theme.colors.primary })
              Text(item.label)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.colors.textPrimary)
                .layoutWeight(1)
              AppIcon({ icon: $r('app.media.ic_chevron_forward'), iconSize: 16, tint: this.theme.colors.textTertiary })
            }
            .width('100%')
            .height(48)
            .padding({ left: 14, right: 14 })
            .borderRadius(12)
            .backgroundColor(this.theme.colors.surfaceContainer)
            .onClick(() => {
              this.onDismiss();
              item.action();
            })
          }, (item: RevealMenuItem) => item.label)
        }
        .width('86%')
        .constraintSize({ maxWidth: 380 })
        .padding(18)
        .borderRadius(22)
        .backgroundColor(this.theme.colors.surface)
      }
      .width('100%')
      .height('100%')
    }
  }
}
