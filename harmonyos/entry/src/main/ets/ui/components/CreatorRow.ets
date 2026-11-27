import { CreatorDto } from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { Fmt } from '../../core/util/Fmt';
import { AppButton, AppIcon } from '../design/AppComponents';
import {
  ArchiveThemeController,
  onServiceBrandColor,
  serviceBrandColor,
  servicePlatformLabel
} from '../theme/PurrColors';
import { NetImage } from './NetImage';

/**
 * 发现页创作者行组件（支持行内点击原地展开详情面板，对齐上游 CreatorsScreen 体验）。
 */
@ComponentV2
export struct CreatorRow {
  @Param @Require creator: CreatorDto;
  @Param expanded: boolean = false;
  @Event onToggleExpand: () => void = () => {};
  @Event onOpenDetail: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();

  private formatUnix(sec?: number): string {
    if (sec === undefined || sec <= 0) {
      return '未知';
    }
    const d = new Date(sec * 1000);
    const yyyy = d.getFullYear();
    const mm = `${d.getMonth() + 1}`.padStart(2, '0');
    const dd = `${d.getDate()}`.padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        NetImage({
          url: UrlProvider.iconUrl(
            AppContainer.getInstance().apiClient.getBaseUrl(),
            this.creator.service,
            this.creator.id
          ),
          fit: ImageFit.Cover,
          imgRadius: 22,
          allowBlur: false
        })
          .width(44)
          .height(44)

        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(this.creator.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.colors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(servicePlatformLabel(this.creator.service))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(onServiceBrandColor(serviceBrandColor(this.creator.service) ?? this.theme.colors.primary))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(serviceBrandColor(this.creator.service) ?? this.theme.colors.surfaceContainerHigh)
          }
          .width('100%')

          Row({ space: 12 }) {
            Text(`收藏 ${Fmt.compactCount(this.creator.favorited)}`)
              .fontSize(12)
              .fontColor(this.theme.colors.textSecondary)
            Text(`更新 ${this.formatUnix(this.creator.updated)}`)
              .fontSize(12)
              .fontColor(this.theme.colors.textTertiary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        AppIcon({
          icon: this.expanded ? $r('app.media.ic_expander') : $r('app.media.ic_chevron_forward'),
          iconSize: 16,
          tint: this.theme.colors.textTertiary
        })
      }
      .width('100%')
      .onClick(() => {
        this.onToggleExpand();
      })

      if (this.expanded) {
        Column({ space: 8 }) {
          Row({ space: 12 }) {
            Text(`ID: ${this.creator.id}`)
              .fontSize(12)
              .fontColor(this.theme.colors.textSecondary)
            Text(`收录: ${this.formatUnix(this.creator.indexed)}`)
              .fontSize(12)
              .fontColor(this.theme.colors.textSecondary)
          }
          .width('100%')

          AppButton({
            label: '进入创作者主页',
            primary: true,
            onAction: () => {
              this.onOpenDetail();
            }
          })
        }
        .width('100%')
        .padding({ top: 6 })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.theme.colors.surface)
  }
}
