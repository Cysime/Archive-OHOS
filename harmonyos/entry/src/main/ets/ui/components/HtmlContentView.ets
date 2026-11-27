import { Want } from '@kit.AbilityKit';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { HtmlNode, HtmlNodeType, HtmlParser, HtmlSpan } from '../../core/util/HtmlParser';
import { Logger } from '../../core/util/Logger';
import { ArchiveThemeController } from '../theme/PurrColors';
import { NetImage } from './NetImage';

const TAG: string = 'HtmlContentView';

/**
 * 帖子正文 / 创作者公告的原生 ArkUI HTML 渲染器（不依赖 WebView）。
 */
@ComponentV2
export struct HtmlContentView {
  @Param @Require html: string;
  @Param fontSize: number = 15;

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  private openExternalUrl(rawUrl: string): void {
    const context = AppContainer.getInstance().getContext();
    if (context === undefined) {
      return;
    }
    const baseUrl = AppContainer.getInstance().apiClient.getBaseUrl();
    const resolved = UrlProvider.contentImageUrl(baseUrl, rawUrl);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: resolved
    };
    context.startAbility(want).catch((e: Object) => {
      Logger.w(TAG, `openExternalUrl failed: ${String(e)}`);
    });
  }

  private getNodes(): HtmlNode[] {
    return HtmlParser.parse(this.html);
  }

  build() {
    Column({ space: 10 }) {
      ForEach(this.getNodes(), (node: HtmlNode, idx: number) => {
        if (node.type === HtmlNodeType.IMAGE && node.src !== undefined) {
          NetImage({
            url: UrlProvider.contentImageUrl(AppContainer.getInstance().apiClient.getBaseUrl(), node.src),
            fit: ImageFit.Contain,
            imgRadius: 12,
            allowBlur: false
          })
            .width('100%')
            .height(220)
        } else if (node.spans !== undefined && node.spans.length > 0) {
          Text() {
            ForEach(node.spans, (sp: HtmlSpan, spIdx: number) => {
              Span(sp.text)
                .fontSize(this.fontSize)
                .fontWeight(sp.bold ? FontWeight.Bold : FontWeight.Regular)
                .fontStyle(sp.italic ? FontStyle.Italic : FontStyle.Normal)
                .fontColor(sp.link !== undefined ? this.theme.colors.primary : this.theme.colors.textPrimary)
                .decoration({
                  type: (sp.underline || sp.link !== undefined)
                    ? TextDecorationType.Underline
                    : TextDecorationType.None,
                  color: sp.link !== undefined ? this.theme.colors.primary : this.theme.colors.textPrimary
                })
                .onClick(() => {
                  if (sp.link !== undefined) {
                    this.openExternalUrl(sp.link);
                  }
                })
            }, (_sp: HtmlSpan, spIdx: number) => `${idx}_${spIdx}`)
          }
          .width('100%')
          .lineHeight(this.fontSize * 1.55)
          .copyOption(CopyOptions.LocalDevice)
        }
      }, (_node: HtmlNode, idx: number) => `${idx}_${this.html.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
