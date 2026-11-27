import { AppIcon } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * X 风格帖子翻译横幅（「文A 翻译自{源语言} · 显示原文」）。
 */
@ComponentV2
export struct PostTranslationBanner {
  @Param translating: boolean = false;
  @Param hasTranslation: boolean = false;
  @Param showingTranslated: boolean = false;
  @Param sourceLanguage: string = '';
  @Param errorMsg: string = '';
  @Event onTranslate: () => void = () => {};
  @Event onToggleOriginal: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        AppIcon({ icon: $r('app.media.ic_languages'), iconSize: 16, tint: this.theme.colors.primary })

        if (this.translating) {
          LoadingProgress().width(14).height(14).color(this.theme.colors.primary)
          Text('正在结构保真翻译…')
            .fontSize(12)
            .fontColor(this.theme.colors.textSecondary)
            .layoutWeight(1)
        } else if (this.hasTranslation) {
          Text(this.showingTranslated ? `翻译自${this.sourceLanguage}` : '当前显示原文')
            .fontSize(12)
            .fontColor(this.theme.colors.textSecondary)
          Text('·')
            .fontSize(12)
            .fontColor(this.theme.colors.textTertiary)
          Text(this.showingTranslated ? '显示原文' : '显示译文')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.colors.primary)
            .onClick(() => {
              this.onToggleOriginal();
            })
        } else {
          Text('翻译本帖')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.colors.primary)
            .onClick(() => {
              this.onTranslate();
            })
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor(this.theme.colors.surfaceContainer)

      if (this.errorMsg.length > 0) {
        Row({ space: 8 }) {
          Text(this.errorMsg)
            .fontSize(11)
            .fontColor(this.theme.colors.error)
            .layoutWeight(1)
          Text('重试')
            .fontSize(11)
            .fontColor(this.theme.colors.primary)
            .onClick(() => {
              this.onTranslate();
            })
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
  }
}
