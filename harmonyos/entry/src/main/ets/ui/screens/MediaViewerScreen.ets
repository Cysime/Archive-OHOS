import { image } from '@kit.ImageKit';
import { AttachmentDto, AttachmentHelper, MediaKind, PostDetailDto } from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { AiImageSheet } from '../components/AiImageSheet';
import { MediaPlayerView } from '../components/MediaPlayerView';
import { ZoomableImageView } from '../components/ZoomableImageView';
import { AppButton, AppErrorState, AppIcon, AppLoadingState } from '../design/AppComponents';
import { AppRoutes } from '../navigation/AppRoutes';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 沉浸式媒体查看器（对齐上游 ui/screens/MediaViewerScreen.kt）。
 *
 * - 支持左右滑动切换当前帖子的全部图片 / 视频（HLS & MP4）/ 音频 / 附件
 * - 原图加载失败自动回退缩略图，支持双指缩放与双击放大
 * - 底部操作栏：下载当前附件、跳转下载管理（Phase 4 将在此挂载 OCR 与 AI 识图入口）
 */
@ComponentV2
export struct MediaViewerScreen {
  @Param @Require service: string;
  @Param @Require creatorId: string;
  @Param @Require postId: string;
  @Param initialIndex: number = 0;
  @Event onBack: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly container: AppContainer = AppContainer.getInstance();
  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly swiperController: SwiperController = new SwiperController();

  @Local detail?: PostDetailDto = undefined;
  @Local items: AttachmentDto[] = [];
  @Local currentIndex: number = 0;
  @Local loading: boolean = true;
  @Local errorMsg: string = '';
  @Local creatorName: string = '';
  @Local currentPixelMap?: image.PixelMap = undefined;
  @Local aiSheetVisible: boolean = false;

  aboutToAppear(): void {
    this.currentIndex = Math.max(0, this.initialIndex);
    this.loadPostMedia();
  }

  private async loadPostMedia(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.creatorName = await this.container.creatorRepo.resolveCreatorName(this.service, this.creatorId);
      const result = await this.container.postRepo.loadPostDetailWithOfflineFallback(
        this.service,
        this.creatorId,
        this.postId,
        false
      );
      this.detail = result.detail;
      const list: AttachmentDto[] = [];
      if (result.detail.file !== undefined) {
        list.push(result.detail.file);
      }
      for (let i = 0; i < result.detail.attachments.length; i++) {
        list.push(result.detail.attachments[i]);
      }
      this.items = list;
      if (this.currentIndex >= list.length) {
        this.currentIndex = 0;
      }
    } catch (e) {
      this.errorMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.loading = false;
    }
  }

  private currentAttachment(): AttachmentDto | undefined {
    if (this.currentIndex >= 0 && this.currentIndex < this.items.length) {
      return this.items[this.currentIndex];
    }
    return undefined;
  }

  private async downloadCurrent(): Promise<void> {
    if (this.detail === undefined) {
      return;
    }
    const added = await this.container.downloadCenter.enqueuePostAttachments(
      this.detail,
      this.creatorName,
      [this.currentIndex]
    );
    try {
      this.getUIContext().getPromptAction().showToast({
        message: added > 0 ? '已加入下载队列' : '该附件无法下载或已在队列中'
      });
    } catch (_e) {
      // ignore toast error
    }
  }

  build() {
    Stack() {
      Column() {
      // 顶栏
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          AppIcon({ icon: $r('app.media.ic_back'), iconSize: 20, tint: '#FFFFFFFF' })
        }
        .width(40)
        .height(40)
        .backgroundColor('#33FFFFFF')
        .onClick(() => {
          this.onBack();
        })

        Column({ space: 2 }) {
          Text(
            this.items.length > 0
              ? `${this.currentIndex + 1} / ${this.items.length}`
              : '媒体查看器'
          )
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFFFF')
          if (this.currentAttachment() !== undefined) {
            Text(AttachmentHelper.displayName(this.currentAttachment() as AttachmentDto))
              .fontSize(11)
              .fontColor('#B3FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          AppIcon({ icon: $r('app.media.ic_downloads'), iconSize: 19, tint: '#FFFFFFFF' })
        }
        .width(40)
        .height(40)
        .backgroundColor('#33FFFFFF')
        .onClick(() => {
          this.onNavigate(AppRoutes.DOWNLOADS);
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 + this.theme.topSafeVp, bottom: 8 })
      .backgroundColor('#CC000000')

      if (this.loading) {
        AppLoadingState({ message: '正在加载媒体…' })
          .layoutWeight(1)
      } else if (this.errorMsg.length > 0) {
        AppErrorState({
          message: this.errorMsg,
          onRetry: () => {
            this.loadPostMedia();
          }
        })
          .layoutWeight(1)
      } else if (this.items.length === 0) {
        Column() {
          Text('该帖子没有可预览的媒体附件')
            .fontSize(14)
            .fontColor('#CCFFFFFF')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Swiper(this.swiperController) {
          ForEach(this.items, (att: AttachmentDto, idx: number) => {
            Stack() {
              if (AttachmentHelper.kind(att) === MediaKind.IMAGE) {
                ZoomableImageView({
                  originalUrl: UrlProvider.playbackUrl(this.container.apiClient.getBaseUrl(), att.path, att.tempUrl) ?? '',
                  fallbackThumbUrl: (att.path ?? '').length > 0
                    ? UrlProvider.thumbnailUrl(this.container.apiClient.getBaseUrl(), att.path ?? '')
                    : '',
                  onPixelMapReady: (pm: image.PixelMap) => {
                    if (idx === this.currentIndex) {
                      this.currentPixelMap = pm;
                    }
                  }
                })
              } else if (AttachmentHelper.kind(att) === MediaKind.VIDEO || AttachmentHelper.kind(att) === MediaKind.AUDIO) {
                if (AttachmentHelper.hasPlayableSource(att)) {
                  MediaPlayerView({
                    url: UrlProvider.playbackUrl(this.container.apiClient.getBaseUrl(), att.path, att.tempUrl) ?? '',
                    isAudioOnly: AttachmentHelper.kind(att) === MediaKind.AUDIO,
                    title: AttachmentHelper.displayName(att)
                  })
                } else {
                  Column({ space: 10 }) {
                    Text(AttachmentHelper.tempLinkExpired(att) ? '临时播放链接已过期，请返回刷新详情' : '无可用播放地址')
                      .fontSize(14)
                      .fontColor('#CCFFFFFF')
                  }
                  .width('100%')
                  .height('100%')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                }
              } else {
                Column({ space: 14 }) {
                  AppIcon({ icon: $r('app.media.ic_download'), iconSize: 42, tint: '#FFFFFFFF' })
                  Text(AttachmentHelper.displayName(att))
                    .fontSize(15)
                    .fontColor('#FFFFFFFF')
                    .textAlign(TextAlign.Center)
                  AppButton({
                    label: '下载该文件',
                    primary: true,
                    fullWidth: false,
                    onAction: () => {
                      this.downloadCurrent();
                    }
                  })
                    .width(180)
                }
                .width('100%')
                .height('100%')
                .padding(24)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .height('100%')
          }, (att: AttachmentDto, idx: number) => `${idx}_${att.path ?? att.name ?? ''}`)
        }
        .index(this.currentIndex)
        .indicator(false)
        .loop(false)
        .onChange((index: number) => {
          this.currentIndex = index;
          this.currentPixelMap = undefined;
        })
        .layoutWeight(1)
        .width('100%')
      }

      // 底部操作栏
      Row({ space: 10 }) {
        AppButton({
          label: '下载当前附件',
          primary: true,
          fullWidth: false,
          onAction: () => {
            this.downloadCurrent();
          }
        })
          .layoutWeight(1)

        if (this.currentPixelMap !== undefined) {
          AppButton({
            label: 'OCR / AI 识图',
            primary: false,
            fullWidth: false,
            onAction: () => {
              this.aiSheetVisible = true;
            }
          })
            .width(136)
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 12 + this.theme.bottomSafeVp })
      .backgroundColor('#CC000000')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FF000000')

      AiImageSheet({
        visible: this.aiSheetVisible,
        cacheKey: `${this.service}:${this.creatorId}:${this.postId}:${this.currentIndex}`,
        pixelMap: this.currentPixelMap,
        onDismiss: () => {
          this.aiSheetVisible = false;
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
