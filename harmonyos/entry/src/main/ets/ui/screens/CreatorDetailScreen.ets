import {
  AnnouncementDto,
  CreatorProfileDto,
  CreatorTagDto,
  PostSummaryDto
} from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { Fmt } from '../../core/util/Fmt';
import { PostSortHelper } from '../../data/util/PostSort';
import { HtmlContentView } from '../components/HtmlContentView';
import { NetImage } from '../components/NetImage';
import { PostCard } from '../components/PostCard';
import {
  AppButton,
  AppCard,
  AppEmptyState,
  AppErrorState,
  AppIcon,
  AppLoadingState,
  AppTopBar
} from '../design/AppComponents';
import { AppRoutes, CreatorRouteParam, PostRouteParam } from '../navigation/AppRoutes';
import {
  ArchiveThemeController,
  onServiceBrandColor,
  serviceBrandColor,
  servicePlatformLabel
} from '../theme/PurrColors';

/**
 * 创作者主页（对齐上游 ui/screens/CreatorDetailScreen.kt）。
 *
 * - 横幅/头像/平台徽标/收藏/屏蔽
 * - 三分栏：作品（支持标签筛选、站内搜索、offset=50 分页）、公告（HTML 渲染）、关联账号
 */
@ComponentV2
export struct CreatorDetailScreen {
  @Param @Require service: string;
  @Param @Require creatorId: string;
  @Event onBack: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local profile?: CreatorProfileDto = undefined;
  @Local creatorName: string = '';
  @Local activeTab: number = 0;
  @Local posts: PostSummaryDto[] = [];
  @Local announcements: AnnouncementDto[] = [];
  @Local tags: CreatorTagDto[] = [];
  @Local links: CreatorProfileDto[] = [];

  @Local selectedTag: string = '';
  @Local searchText: string = '';
  @Local loading: boolean = false;
  @Local loadingMore: boolean = false;
  @Local hasMore: boolean = true;
  @Local nextOffset: number = 0;
  @Local errorMsg: string = '';
  @Local isFavorited: boolean = false;
  @Local isSubscribed: boolean = false;
  @Local isBlocked: boolean = false;
  @Local stateTick: number = 0;

  private searchTimerId: number = -1;

  aboutToAppear(): void {
    this.creatorName = this.container.creatorRepo.getCachedName(this.service, this.creatorId) ?? this.creatorId;
    this.isFavorited = this.container.favoriteRepo.isCreatorFavorited(this.service, this.creatorId);
    this.isBlocked = this.container.blockedContent.isCreatorBlocked(this.service, this.creatorId);
    this.container.subscriptionRepo.isSubscribed(this.service, this.creatorId).then((sub: boolean) => {
      this.isSubscribed = sub;
    });
    this.loadCreatorMeta();
    this.loadPostsFirstPage(false);
  }

  aboutToDisappear(): void {
    if (this.searchTimerId !== -1) {
      clearTimeout(this.searchTimerId);
      this.searchTimerId = -1;
    }
  }

  private async loadCreatorMeta(): Promise<void> {
    this.container.postRepo.loadCreatorProfile(this.service, this.creatorId).then((p: CreatorProfileDto) => {
      this.profile = p;
      this.creatorName = p.name;
    }).catch(() => {});
    this.container.postRepo.loadCreatorTags(this.service, this.creatorId).then((t: CreatorTagDto[]) => {
      this.tags = t;
    }).catch(() => {});
    this.container.postRepo.loadCreatorAnnouncements(this.service, this.creatorId).then((a: AnnouncementDto[]) => {
      this.announcements = a;
    }).catch(() => {});
    this.container.postRepo.loadCreatorLinks(this.service, this.creatorId).then((l: CreatorProfileDto[]) => {
      this.links = l;
    }).catch(() => {});
  }

  private async loadPostsFirstPage(bypassCache: boolean): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const page = await this.container.postRepo.loadCreatorPosts(
        this.service,
        this.creatorId,
        this.searchText,
        this.selectedTag,
        0,
        bypassCache
      );
      this.posts = PostSortHelper.deduplicatePosts(page.items);
      this.hasMore = page.hasMore;
      this.nextOffset = page.nextOffset;
    } catch (e) {
      this.errorMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.loading = false;
    }
  }

  private async loadMorePosts(): Promise<void> {
    if (this.loading || this.loadingMore || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const page = await this.container.postRepo.loadCreatorPosts(
        this.service,
        this.creatorId,
        this.searchText,
        this.selectedTag,
        this.nextOffset,
        false
      );
      this.posts = PostSortHelper.deduplicatePosts(this.posts.concat(page.items));
      this.hasMore = page.hasMore;
      this.nextOffset = page.nextOffset;
    } catch (_e) {
      // keep existing posts
    } finally {
      this.loadingMore = false;
    }
  }

  private scheduleSearch(text: string): void {
    this.searchText = text;
    if (this.searchTimerId !== -1) {
      clearTimeout(this.searchTimerId);
    }
    this.searchTimerId = setTimeout(() => {
      this.searchTimerId = -1;
      this.loadPostsFirstPage(false);
    }, 350);
  }

  private async toggleFavCreator(): Promise<void> {
    this.isFavorited = await this.container.favoriteRepo.toggleFavoriteCreator(
      this.service,
      this.creatorId,
      this.creatorName
    );
  }

  private async toggleSubscribeCreator(): Promise<void> {
    if (this.isSubscribed) {
      await this.container.subscriptionRepo.unsubscribeCreator(this.service, this.creatorId);
      this.isSubscribed = false;
    } else {
      await this.container.subscriptionRepo.subscribeCreator(this.service, this.creatorId, this.creatorName);
      this.isSubscribed = true;
    }
  }

  private async toggleBlockCreator(): Promise<void> {
    if (this.isBlocked) {
      await this.container.blockedContent.unblockCreator(this.service, this.creatorId);
      this.isBlocked = false;
    } else {
      await this.container.blockedContent.blockCreator(this.service, this.creatorId, this.creatorName);
      this.isBlocked = true;
    }
  }

  @Builder
  headerCard() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        NetImage({
          url: UrlProvider.bannerUrl(this.container.apiClient.getBaseUrl(), this.service, this.creatorId),
          fit: ImageFit.Cover,
          imgRadius: 16,
          allowBlur: false
        })
          .width('100%')
          .height(120)

        Row({ space: 12 }) {
          NetImage({
            url: UrlProvider.iconUrl(this.container.apiClient.getBaseUrl(), this.service, this.creatorId),
            fit: ImageFit.Cover,
            imgRadius: 28,
            allowBlur: false
          })
            .width(56)
            .height(56)

          Column({ space: 4 }) {
            Text(this.creatorName)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(servicePlatformLabel(this.service))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(onServiceBrandColor(serviceBrandColor(this.service) ?? this.theme.colors.primary))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(serviceBrandColor(this.service) ?? this.theme.colors.primary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#66000000')
        .borderRadius({ bottomLeft: 16, bottomRight: 16 })
      }
      .width('100%')

      Row({ space: 8 }) {
        AppButton({
          label: this.isFavorited ? '已收藏' : '收藏',
          primary: !this.isFavorited,
          fullWidth: false,
          onAction: () => {
            this.toggleFavCreator();
          }
        })
          .layoutWeight(1)

        AppButton({
          label: this.isSubscribed ? '已订阅' : '订阅更新',
          primary: false,
          fullWidth: false,
          onAction: () => {
            this.toggleSubscribeCreator();
          }
        })
          .layoutWeight(1)

        AppButton({
          label: this.isBlocked ? '取消屏蔽' : '屏蔽',
          primary: false,
          fullWidth: false,
          onAction: () => {
            this.toggleBlockCreator();
          }
        })
          .width(88)
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(['作品', `公告 (${this.announcements.length})`, `关联 (${this.links.length})`], (label: string, idx: number) => {
          Text(label)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.activeTab === idx ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(10)
            .backgroundColor(this.activeTab === idx ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
            .onClick(() => {
              this.activeTab = idx;
            })
        }, (label: string) => label)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, bottom: 10 })
  }

  build() {
    Column() {
      AppTopBar({
        title: this.creatorName,
        subtitle: `${servicePlatformLabel(this.service)} · ${this.creatorId}`,
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      this.headerCard()

      if (this.activeTab === 0) {
        Column({ space: 8 }) {
          TextInput({ text: this.searchText, placeholder: '在作者作品内搜索…' })
            .width('100%')
            .height(38)
            .fontSize(13)
            .fontColor(this.theme.colors.textPrimary)
            .placeholderColor(this.theme.colors.textTertiary)
            .backgroundColor(this.theme.colors.surfaceContainer)
            .borderRadius(10)
            .onChange((val: string) => {
              this.scheduleSearch(val);
            })

          if (this.tags.length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                Text('全部标签')
                  .fontSize(12)
                  .fontColor(this.selectedTag.length === 0 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .borderRadius(10)
                  .backgroundColor(
                    this.selectedTag.length === 0 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                  )
                  .onClick(() => {
                    this.selectedTag = '';
                    this.loadPostsFirstPage(false);
                  })

                ForEach(this.tags.slice(0, 30), (t: CreatorTagDto) => {
                  Text(`${t.tag} (${t.postCount})`)
                    .fontSize(12)
                    .fontColor(this.selectedTag === t.tag ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(10)
                    .backgroundColor(
                      this.selectedTag === t.tag ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                    )
                    .onClick(() => {
                      this.selectedTag = this.selectedTag === t.tag ? '' : t.tag;
                      this.loadPostsFirstPage(false);
                    })
                }, (t: CreatorTagDto) => t.tag)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 8 })

        if (this.loading && this.posts.length === 0) {
          AppLoadingState({ message: '正在加载作品…' })
            .layoutWeight(1)
        } else if (this.errorMsg.length > 0 && this.posts.length === 0) {
          AppErrorState({
            message: this.errorMsg,
            onRetry: () => {
              this.loadPostsFirstPage(true);
            }
          })
            .layoutWeight(1)
        } else if (this.posts.length === 0) {
          AppEmptyState({ title: '暂无作品', icon: $r('app.media.ic_home') })
            .layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.posts, (post: PostSummaryDto) => {
              ListItem() {
                PostCard({
                  post: post,
                  gridMode: false,
                  isFavorited: this.container.favoriteRepo.isPostFavorited(post.service, post.creatorId, post.postId),
                  isBlocked: false,
                  onOpenPost: () => {
                    const param: PostRouteParam = {
                      service: post.service,
                      creatorId: post.creatorId,
                      postId: post.postId
                    };
                    this.onNavigate(AppRoutes.POST, param);
                  },
                  onToggleFavorite: () => {
                    this.container.favoriteRepo.toggleFavoritePost(post).then(() => {
                      this.stateTick++;
                    });
                  },
                  onBlockPost: () => {
                    this.container.blockedContent.blockPost(post.service, post.creatorId, post.postId, post.title);
                  }
                })
              }
            }, (post: PostSummaryDto) => `${post.service}:${post.creatorId}:${post.postId}:${this.stateTick}`)
          }
          .padding({ left: 12, right: 12, top: 4, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
          .onReachEnd(() => {
            this.loadMorePosts();
          })
        }
      } else if (this.activeTab === 1) {
        if (this.announcements.length === 0) {
          AppEmptyState({ title: '暂无公告', icon: $r('app.media.ic_messages') })
            .layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.announcements, (ann: AnnouncementDto, idx: number) => {
              ListItem() {
                AppCard() {
                  Column({ space: 8 }) {
                    if ((ann.added ?? '').length > 0) {
                      Text(Fmt.shortDate(ann.added))
                        .fontSize(11)
                        .fontColor(this.theme.colors.textTertiary)
                    }
                    HtmlContentView({ html: ann.content, fontSize: 14 })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
              }
            }, (ann: AnnouncementDto, idx: number) => `${idx}_${ann.added ?? ''}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else {
        if (this.links.length === 0) {
          AppEmptyState({ title: '暂无关联账号', icon: $r('app.media.ic_link') })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.links, (lnk: CreatorProfileDto) => {
              ListItem() {
                Row({ space: 12 }) {
                  NetImage({
                    url: UrlProvider.iconUrl(this.container.apiClient.getBaseUrl(), lnk.service, lnk.id),
                    fit: ImageFit.Cover,
                    imgRadius: 20,
                    allowBlur: false
                  })
                    .width(40)
                    .height(40)

                  Column({ space: 2 }) {
                    Text(lnk.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.colors.textPrimary)
                    Text(`${servicePlatformLabel(lnk.service)} · ${lnk.id}`)
                      .fontSize(12)
                      .fontColor(this.theme.colors.textSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  AppIcon({ icon: $r('app.media.ic_chevron_forward'), iconSize: 16, tint: this.theme.colors.textTertiary })
                }
                .width('100%')
                .padding(12)
                .borderRadius(14)
                .backgroundColor(this.theme.colors.surface)
                .onClick(() => {
                  const param: CreatorRouteParam = {
                    service: lnk.service,
                    creatorId: lnk.id
                  };
                  this.onNavigate(AppRoutes.CREATOR, param);
                })
              }
            }, (lnk: CreatorProfileDto) => `${lnk.service}:${lnk.id}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
