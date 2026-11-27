import { AttachmentHelper, MediaKind, PostSummaryDto } from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { Fmt } from '../../core/util/Fmt';
import { HtmlParser } from '../../core/util/HtmlParser';
import { AppIcon } from '../design/AppComponents';
import {
  ArchiveThemeController,
  onServiceBrandColor,
  serviceBrandColor,
  servicePlatformLabel
} from '../theme/PurrColors';
import { NetImage } from './NetImage';

/**
 * 帖子摘要卡片（支持列表/网格双布局、默认走缩略图、平台品牌徽标、展示层屏蔽过滤、一键收藏与屏蔽）。
 */
@ComponentV2
export struct PostCard {
  @Param @Require post: PostSummaryDto;
  @Param gridMode: boolean = false;
  @Param isFavorited: boolean = false;
  @Param isBlocked: boolean = false;
  @Event onOpenPost: () => void = () => {};
  @Event onOpenCreator: () => void = () => {};
  @Event onToggleFavorite: () => void = () => {};
  @Event onBlockPost: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  @Local creatorDisplayName: string = '';

  aboutToAppear(): void {
    const cached = AppContainer.getInstance().creatorRepo.getCachedName(this.post.service, this.post.creatorId);
    if (cached !== undefined) {
      this.creatorDisplayName = cached;
    } else {
      this.creatorDisplayName = this.post.creatorId;
      AppContainer.getInstance().creatorRepo.resolveCreatorName(this.post.service, this.post.creatorId).then((name: string) => {
        this.creatorDisplayName = name;
      });
    }
  }

  private getCoverThumbnailUrl(): string {
    const cover = this.post.cover;
    if (cover === undefined || cover.path === undefined || cover.path.trim().length === 0) {
      return '';
    }
    const kind = AttachmentHelper.kind(cover);
    if (kind !== MediaKind.IMAGE) {
      return '';
    }
    const baseUrl = AppContainer.getInstance().apiClient.getBaseUrl();
    return UrlProvider.thumbnailUrl(baseUrl, cover.path);
  }

  private getExcerptText(): string {
    return HtmlParser.htmlToPlainText(this.post.excerpt);
  }

  build() {
    if (!this.isBlocked) {
      Column({ space: 8 }) {
        if (this.getCoverThumbnailUrl().length > 0) {
          Stack({ alignContent: Alignment.TopStart }) {
            NetImage({
              url: this.getCoverThumbnailUrl(),
              fit: ImageFit.Cover,
              imgRadius: 12,
              allowBlur: true
            })
              .width('100%')
              .height(this.gridMode ? 150 : 200)

            if (this.post.cover !== undefined && AttachmentHelper.kind(this.post.cover) === MediaKind.VIDEO) {
              Row({ space: 4 }) {
                AppIcon({ icon: $r('app.media.ic_play'), iconSize: 12, tint: '#FFFFFFFF' })
                Text('视频')
                  .fontSize(10)
                  .fontColor('#FFFFFFFF')
              }
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(8)
              .backgroundColor('#99000000')
              .margin({ left: 8, top: 8 })
            }
          }
          .width('100%')
        }

        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(servicePlatformLabel(this.post.service))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(onServiceBrandColor(serviceBrandColor(this.post.service) ?? this.theme.colors.primary))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(serviceBrandColor(this.post.service) ?? this.theme.colors.surfaceContainerHigh)

            Text(this.creatorDisplayName)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.colors.primary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .onClick(() => {
                this.onOpenCreator();
              })

            if (!this.gridMode && (this.post.published ?? '').length > 0) {
              Text(Fmt.shortDate(this.post.published))
                .fontSize(11)
                .fontColor(this.theme.colors.textTertiary)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.post.title.length > 0 ? this.post.title : '(无标题)')
            .fontSize(this.gridMode ? 13 : 15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.colors.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (!this.gridMode && this.getExcerptText().length > 0) {
            Text(this.getExcerptText())
              .fontSize(13)
              .fontColor(this.theme.colors.textSecondary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          Row({ space: 8 }) {
            if (this.gridMode) {
              Text(Fmt.shortDate(this.post.published))
                .fontSize(11)
                .fontColor(this.theme.colors.textTertiary)
                .layoutWeight(1)
            } else {
              Blank()
            }

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              AppIcon({
                icon: this.isFavorited ? $r('app.media.ic_favorites_fill') : $r('app.media.ic_favorites'),
                iconSize: 16,
                tint: this.isFavorited ? '#FFE11D48' : this.theme.colors.textSecondary
              })
            }
            .width(32)
            .height(32)
            .backgroundColor(this.theme.colors.surfaceContainer)
            .onClick(() => {
              this.onToggleFavorite();
            })

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              AppIcon({
                icon: $r('app.media.ic_ban'),
                iconSize: 15,
                tint: this.theme.colors.textTertiary
              })
            }
            .width(32)
            .height(32)
            .backgroundColor(this.theme.colors.surfaceContainer)
            .onClick(() => {
              this.onBlockPost();
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 10, top: this.getCoverThumbnailUrl().length > 0 ? 0 : 10 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.theme.colors.surface)
      .onClick(() => {
        this.onOpenPost();
      })
    }
  }
}
