import { LengthMetrics } from '@kit.ArkUI';
import {
  AttachmentDto,
  AttachmentHelper,
  MediaKind,
  PostCommentDto,
  PostDetailDto,
  PostSummaryDto
} from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { Fmt } from '../../core/util/Fmt';
import { HtmlContentView } from '../components/HtmlContentView';
import { NetImage } from '../components/NetImage';
import { PostTranslationBanner } from '../components/PostTranslationBanner';
import { PostTranslation } from '../../data/ai/TranslationClient';
import {
  AppButton,
  AppCard,
  AppDivider,
  AppEmptyState,
  AppErrorState,
  AppIcon,
  AppLoadingState,
  AppTopBar
} from '../design/AppComponents';
import { AppRoutes, CreatorRouteParam, PostRouteParam, ViewerRouteParam } from '../navigation/AppRoutes';
import {
  ArchiveThemeController,
  onServiceBrandColor,
  serviceBrandColor,
  servicePlatformLabel
} from '../theme/PurrColors';

/**
 * 帖子详情页（对齐上游 ui/screens/PostDetailScreen.kt）。
 *
 * - 完整正文 HTML 原生渲染、标签、上/下一篇跳转、评论区（优先 commenter_name）
 * - 封面与媒体附件列表（点击进入媒体查看器，支持 deferred 临时流提示）
 * - 自动记录浏览历史；收藏帖自动写入全文离线归档；断网自动回退离线归档阅读
 */
@ComponentV2
export struct PostDetailScreen {
  @Param @Require service: string;
  @Param @Require creatorId: string;
  @Param @Require postId: string;
  @Event onBack: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local detail?: PostDetailDto = undefined;
  @Local creatorName: string = '';
  @Local comments: PostCommentDto[] = [];
  @Local fromOfflineArchive: boolean = false;
  @Local isFavorited: boolean = false;
  @Local loading: boolean = false;
  @Local errorMsg: string = '';

  @Local translating: boolean = false;
  @Local translation?: PostTranslation = undefined;
  @Local showingTranslated: boolean = false;
  @Local translationError: string = '';

  aboutToAppear(): void {
    this.creatorName = this.container.creatorRepo.getCachedName(this.service, this.creatorId) ?? this.creatorId;
    this.isFavorited = this.container.favoriteRepo.isPostFavorited(this.service, this.creatorId, this.postId);
    this.loadDetail(false);
  }

  private async loadDetail(bypassCache: boolean): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const resolvedName = await this.container.creatorRepo.resolveCreatorName(this.service, this.creatorId);
      this.creatorName = resolvedName;
      const result = await this.container.postRepo.loadPostDetailWithOfflineFallback(
        this.service,
        this.creatorId,
        this.postId,
        bypassCache
      );
      this.detail = result.detail;
      this.fromOfflineArchive = result.fromOfflineArchive;

      const cover = result.detail.file ?? (result.detail.attachments.length > 0 ? result.detail.attachments[0] : undefined);
      await this.container.historyRepo.recordView(
        this.service,
        this.creatorId,
        this.postId,
        result.detail.title,
        cover
      );

      if (!result.fromOfflineArchive) {
        this.container.postRepo.loadPostComments(this.service, this.creatorId, this.postId).then((c: PostCommentDto[]) => {
          this.comments = c;
        }).catch(() => {});
      }
    } catch (e) {
      this.errorMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.loading = false;
    }
  }

  private getAllAttachments(): AttachmentDto[] {
    if (this.detail === undefined) {
      return [];
    }
    const list: AttachmentDto[] = [];
    if (this.detail.file !== undefined) {
      list.push(this.detail.file);
    }
    for (let i = 0; i < this.detail.attachments.length; i++) {
      list.push(this.detail.attachments[i]);
    }
    return list;
  }

  private async toggleFavorite(): Promise<void> {
    if (this.detail === undefined) {
      return;
    }
    const cover = this.detail.file ?? (this.detail.attachments.length > 0 ? this.detail.attachments[0] : undefined);
    const summary: PostSummaryDto = {
      service: this.service,
      creatorId: this.creatorId,
      postId: this.postId,
      title: this.detail.title,
      excerpt: this.detail.contentHtml,
      published: this.detail.published,
      cover: cover,
      previewOnly: this.detail.previewOnly
    };
    this.isFavorited = await this.container.favoriteRepo.toggleFavoritePost(summary);
    if (this.isFavorited) {
      await this.container.favoriteRepo.ensureArchived(this.detail, this.creatorName);
    }
  }

  private openViewerAt(index: number): void {
    const param: ViewerRouteParam = {
      service: this.service,
      creatorId: this.creatorId,
      postId: this.postId,
      initialIndex: index
    };
    this.onNavigate(AppRoutes.VIEWER, param);
  }

  private openSiblingPost(siblingPostId: string): void {
    const param: PostRouteParam = {
      service: this.service,
      creatorId: this.creatorId,
      postId: siblingPostId
    };
    this.onNavigate(AppRoutes.POST, param);
  }

  private openCreator(): void {
    const param: CreatorRouteParam = {
      service: this.service,
      creatorId: this.creatorId
    };
    this.onNavigate(AppRoutes.CREATOR, param);
  }

  private async runTranslate(): Promise<void> {
    if (this.detail === undefined || this.translating) {
      return;
    }
    this.translating = true;
    this.translationError = '';
    try {
      const result = await this.container.translationClient.translatePost(
        this.detail.title,
        this.detail.contentHtml
      );
      this.translation = result;
      this.showingTranslated = true;
    } catch (e) {
      this.translationError = AppError.friendlyMessage(e as Object);
    } finally {
      this.translating = false;
    }
  }

  private displayedTitle(): string {
    if (this.showingTranslated && this.translation !== undefined && this.translation.title.length > 0) {
      return this.translation.title;
    }
    const raw = this.detail?.title ?? '';
    return raw.length > 0 ? raw : '(无标题)';
  }

  private displayedHtml(): string {
    if (this.showingTranslated && this.translation !== undefined && this.translation.html.length > 0) {
      return this.translation.html;
    }
    return this.detail?.contentHtml ?? '';
  }

  @Builder
  topBarActions() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({
          icon: this.isFavorited ? $r('app.media.ic_favorites_fill') : $r('app.media.ic_favorites'),
          iconSize: 20,
          tint: this.isFavorited ? '#FFE11D48' : this.theme.colors.textPrimary
        })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.toggleFavorite();
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_ban'), iconSize: 19, tint: this.theme.colors.textSecondary })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.container.blockedContent.blockPost(
          this.service,
          this.creatorId,
          this.postId,
          this.detail?.title ?? this.postId
        ).then(() => {
          this.onBack();
        });
      })
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '帖子详情',
        subtitle: this.creatorName,
        showBack: true,
        onBack: () => {
          this.onBack();
        },
        trailing: () => {
          this.topBarActions();
        }
      })

      if (this.loading && this.detail === undefined) {
        AppLoadingState({ message: '正在加载帖子详情…' })
          .layoutWeight(1)
      } else if (this.errorMsg.length > 0 && this.detail === undefined) {
        AppErrorState({
          message: this.errorMsg,
          onRetry: () => {
            this.loadDetail(true);
          }
        })
          .layoutWeight(1)
      } else if (this.detail !== undefined) {
        Scroll() {
          Column({ space: 14 }) {
            if (this.fromOfflineArchive) {
              Row({ space: 8 }) {
                AppIcon({ icon: $r('app.media.ic_hard_drive'), iconSize: 16, tint: this.theme.colors.primary })
                Text('当前网络不可用，已自动回退至本地收藏离线归档')
                  .fontSize(12)
                  .fontColor(this.theme.colors.onSecondaryContainer)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .borderRadius(12)
              .backgroundColor(this.theme.colors.secondaryContainer)
            }

            AppCard() {
              Column({ space: 10 }) {
                Row({ space: 10 }) {
                  NetImage({
                    url: UrlProvider.iconUrl(this.container.apiClient.getBaseUrl(), this.service, this.creatorId),
                    fit: ImageFit.Cover,
                    imgRadius: 20,
                    allowBlur: false
                  })
                    .width(40)
                    .height(40)

                  Column({ space: 2 }) {
                    Text(this.creatorName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.colors.primary)
                    Row({ space: 6 }) {
                      Text(servicePlatformLabel(this.service))
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(onServiceBrandColor(serviceBrandColor(this.service) ?? this.theme.colors.primary))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(6)
                        .backgroundColor(serviceBrandColor(this.service) ?? this.theme.colors.surfaceContainerHigh)
                      Text(Fmt.shortDate(this.detail.published ?? this.detail.added))
                        .fontSize(11)
                        .fontColor(this.theme.colors.textTertiary)
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  AppIcon({ icon: $r('app.media.ic_chevron_forward'), iconSize: 16, tint: this.theme.colors.textTertiary })
                }
                .width('100%')
                .onClick(() => {
                  this.openCreator();
                })

                Text(this.displayedTitle())
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)
                  .width('100%')
                  .copyOption(CopyOptions.LocalDevice)

                PostTranslationBanner({
                  translating: this.translating,
                  hasTranslation: this.translation !== undefined,
                  showingTranslated: this.showingTranslated,
                  sourceLanguage: this.translation?.sourceLanguage ?? '',
                  errorMsg: this.translationError,
                  onTranslate: () => {
                    this.runTranslate();
                  },
                  onToggleOriginal: () => {
                    this.showingTranslated = !this.showingTranslated;
                  }
                })

                if (this.detail.tags.length > 0) {
                  Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
                    ForEach(this.detail.tags, (tag: string) => {
                      Text(`#${tag}`)
                        .fontSize(11)
                        .fontColor(this.theme.colors.primary)
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(8)
                        .backgroundColor(this.theme.colors.secondaryContainer)
                    }, (tag: string) => tag)
                  }
                  .width('100%')
                }

                if (this.displayedHtml().trim().length > 0) {
                  AppDivider()
                  HtmlContentView({ html: this.displayedHtml(), fontSize: 15 })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            if (this.getAllAttachments().length > 0) {
              AppCard() {
                Column({ space: 10 }) {
                  Row() {
                    Text(`媒体与附件 (${this.getAllAttachments().length})`)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme.colors.textPrimary)
                      .layoutWeight(1)
                    Button('全部下载', { type: ButtonType.Normal })
                      .height(30)
                      .borderRadius(8)
                      .fontSize(12)
                      .fontColor(this.theme.colors.onPrimary)
                      .backgroundColor(this.theme.colors.primary)
                      .onClick(() => {
                        if (this.detail !== undefined) {
                          this.container.downloadCenter.enqueuePostAttachments(this.detail, this.creatorName).then((added: number) => {
                            try {
                              this.getUIContext().getPromptAction().showToast({
                                message: added > 0 ? `已将 ${added} 个附件加入下载队列` : '无可新增下载附件'
                              });
                            } catch (_e) {
                              // ignore
                            }
                          });
                        }
                      })
                  }
                  .width('100%')

                  ForEach(this.getAllAttachments(), (att: AttachmentDto, idx: number) => {
                    Column({ space: 6 }) {
                      if (AttachmentHelper.kind(att) === MediaKind.IMAGE && (att.path ?? '').length > 0) {
                        NetImage({
                          url: UrlProvider.thumbnailUrl(this.container.apiClient.getBaseUrl(), att.path ?? ''),
                          fit: ImageFit.Cover,
                          imgRadius: 12,
                          allowBlur: false
                        })
                          .width('100%')
                          .height(220)
                          .onClick(() => {
                            this.openViewerAt(idx);
                          })
                      } else {
                        Row({ space: 10 }) {
                          AppIcon({
                            icon: AttachmentHelper.kind(att) === MediaKind.VIDEO
                              ? $r('app.media.ic_play')
                              : $r('app.media.ic_download'),
                            iconSize: 20,
                            tint: this.theme.colors.primary
                          })
                          Column({ space: 2 }) {
                            Text(AttachmentHelper.displayName(att))
                              .fontSize(13)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(this.theme.colors.textPrimary)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text(
                              att.deferred
                                ? (AttachmentHelper.tempLinkExpired(att) ? '临时流已过期（下拉刷新重取）' : 'HLS 临时流 / 延迟直链')
                                : AttachmentHelper.kind(att)
                            )
                              .fontSize(11)
                              .fontColor(this.theme.colors.textSecondary)
                          }
                          .layoutWeight(1)
                          .alignItems(HorizontalAlign.Start)

                          AppIcon({ icon: $r('app.media.ic_chevron_forward'), iconSize: 16, tint: this.theme.colors.textTertiary })
                        }
                        .width('100%')
                        .padding(12)
                        .borderRadius(12)
                        .backgroundColor(this.theme.colors.surfaceContainer)
                        .onClick(() => {
                          this.openViewerAt(idx);
                        })
                      }
                    }
                    .width('100%')
                  }, (att: AttachmentDto, idx: number) => `${idx}_${att.path ?? att.name ?? ''}`)
                }
                .width('100%')
              }
            }

            if ((this.detail.prev ?? '').length > 0 || (this.detail.next ?? '').length > 0) {
              Row({ space: 10 }) {
                if ((this.detail.prev ?? '').length > 0) {
                  AppButton({
                    label: '上一篇',
                    primary: false,
                    fullWidth: false,
                    onAction: () => {
                      this.openSiblingPost(this.detail?.prev ?? '');
                    }
                  })
                    .layoutWeight(1)
                }
                if ((this.detail.next ?? '').length > 0) {
                  AppButton({
                    label: '下一篇',
                    primary: false,
                    fullWidth: false,
                    onAction: () => {
                      this.openSiblingPost(this.detail?.next ?? '');
                    }
                  })
                    .layoutWeight(1)
                }
              }
              .width('100%')
            }

            AppCard() {
              Column({ space: 10 }) {
                Text(`评论 (${this.comments.length})`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)
                  .width('100%')

                if (this.comments.length === 0) {
                  Text('暂无评论')
                    .fontSize(13)
                    .fontColor(this.theme.colors.textTertiary)
                } else {
                  ForEach(this.comments, (c: PostCommentDto, idx: number) => {
                    if (idx > 0) {
                      AppDivider()
                    }
                    Column({ space: 4 }) {
                      Row() {
                        Text(c.commenter.length > 0 ? c.commenter : '匿名用户')
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.theme.colors.textPrimary)
                          .layoutWeight(1)
                        Text(Fmt.shortDate(c.published))
                          .fontSize(11)
                          .fontColor(this.theme.colors.textTertiary)
                      }
                      .width('100%')

                      Text(c.content)
                        .fontSize(13)
                        .fontColor(this.theme.colors.textSecondary)
                        .width('100%')
                    }
                    .width('100%')
                    .padding({ top: 4, bottom: 4 })
                  }, (c: PostCommentDto) => c.id)
                }
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
      } else {
        AppEmptyState({ title: '未找到帖子内容', icon: $r('app.media.ic_info') })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
