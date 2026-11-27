import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * Archive 统一设计系统组件抽象（对齐上游 ui/design/DesignComponents.kt & AppComponents.kt）。
 * 业务页面只依赖这些 App* 组件与 PurrColors 令牌。
 */

@ComponentV2
export struct AppIcon {
  @Param @Require icon: Resource;
  @Param iconSize: number = 22;
  @Param tint: string = '';

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Image(this.icon)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.tint.length > 0 ? this.tint : this.theme.colors.textPrimary)
  }
}

@ComponentV2
export struct AppButton {
  @Param @Require label: string;
  @Param primary: boolean = true;
  @Param fullWidth: boolean = true;
  @Param disabled: boolean = false;
  @Event onAction: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Button(this.label, { type: ButtonType.Normal, stateEffect: true })
      .width(this.fullWidth ? '100%' : undefined)
      .height(48)
      .borderRadius(14)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.primary ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
      .backgroundColor(this.primary ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
      .opacity(this.disabled ? 0.5 : 1)
      .enabled(!this.disabled)
      .onClick(() => {
        this.onAction();
      })
  }
}

@ComponentV2
export struct AppTopBar {
  @Param @Require title: string;
  @Param subtitle: string = '';
  @Param showBack: boolean = false;
  @Event onBack: () => void = () => {};
  @BuilderParam trailing?: () => void;

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Row({ space: 8 }) {
      if (this.showBack) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          AppIcon({ icon: $r('app.media.ic_back'), iconSize: 20, tint: this.theme.colors.textPrimary })
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onBack();
        })
      }

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(this.theme.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.trailing !== undefined) {
        this.trailing()
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: this.showBack ? 8 : 16, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.theme.colors.background)
  }
}

@ComponentV2
export struct AppCard {
  @Param cardPadding: number = 16;
  @BuilderParam content: () => void = this.emptyContent;

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.cardPadding)
    .borderRadius(16)
    .backgroundColor(this.theme.colors.surface)
  }
}

@ComponentV2
export struct AppDivider {
  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Divider()
      .strokeWidth(0.5)
      .color(this.theme.colors.divider)
  }
}

@ComponentV2
export struct AppEmptyState {
  @Param @Require title: string;
  @Param message: string = '';
  @Param icon: Resource = $r('app.media.ic_info');

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Column({ space: 10 }) {
      AppIcon({ icon: this.icon, iconSize: 36, tint: this.theme.colors.textTertiary })
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.colors.textPrimary)
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(13)
          .fontColor(this.theme.colors.textSecondary)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

@ComponentV2
export struct AppErrorState {
  @Param @Require message: string;
  @Param retryLabel: string = '重试';
  @Event onRetry: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Column({ space: 14 }) {
      AppIcon({ icon: $r('app.media.ic_info'), iconSize: 36, tint: this.theme.colors.error })
      Text(this.message)
        .fontSize(14)
        .fontColor(this.theme.colors.textSecondary)
        .textAlign(TextAlign.Center)
      AppButton({
        label: this.retryLabel,
        primary: true,
        fullWidth: false,
        onAction: () => {
          this.onRetry();
        }
      })
        .width(140)
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

@ComponentV2
export struct AppLoadingState {
  @Param message: string = '加载中…';

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(this.theme.colors.primary)
      Text(this.message)
        .fontSize(13)
        .fontColor(this.theme.colors.textSecondary)
    }
    .width('100%')
    .padding(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
