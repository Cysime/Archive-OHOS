import { PostSummaryDto, SessionFavoriteDto } from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { Fmt } from '../../core/util/Fmt';
import { NetImage } from '../components/NetImage';
import { PostCard } from '../components/PostCard';
import { AppButton, AppEmptyState, AppIcon, AppLoadingState, AppTopBar } from '../design/AppComponents';
import { AppRoutes, CreatorRouteParam, PostRouteParam } from '../navigation/AppRoutes';
import { ArchiveThemeController, servicePlatformLabel } from '../theme/PurrColors';

/**
 * 收藏页（对齐上游 ui/screens/FavoritesScreen.kt）。
 *
 * - 支持「收藏的帖子」与「收藏的创作者」双 Tab
 * - 未登录可直接查看与管理本地收藏（含全文离线归档入口）
 * - 登录后下拉同步云端收藏并自动补写离线队列
 */
@ComponentV2
export struct FavoritesScreen {
  @Event onOpenMenu: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local activeSubTab: number = 0;
  @Local favoritePosts: PostSummaryDto[] = [];
  @Local favoriteCreators: SessionFavoriteDto[] = [];
  @Local loading: boolean = false;
  @Local refreshing: boolean = false;
  @Local statusMessage: string = '';
  @Local stateTick: number = 0;

  private readonly favListener = (): void => {
    this.stateTick++;
    this.reloadLocalPostsOnly();
  };

  aboutToAppear(): void {
    this.container.favoriteRepo.subscribe(this.favListener);
    this.loadAll(false);
  }

  aboutToDisappear(): void {
    this.container.favoriteRepo.unsubscribe(this.favListener);
  }

  private async reloadLocalPostsOnly(): Promise<void> {
    const local = await this.container.favoriteRepo.listLocalFavoritePosts();
    if (!this.container.authRepo.isLoggedIn()) {
      this.favoritePosts = local;
    }
  }

  private async loadAll(isRefresh: boolean): Promise<void> {
    if (isRefresh) {
      this.refreshing = true;
    } else {
      this.loading = true;
    }
    this.statusMessage = '';
    try {
      const localPosts = await this.container.favoriteRepo.listLocalFavoritePosts();
      if (this.container.authRepo.isLoggedIn()) {
        await this.container.favoriteRepo.flushPendingActions();
        try {
          const cloudPosts = await this.container.favoriteRepo.fetchCloudFavoritePosts(0);
          // 本页整页替换并合并本地未同步项（不与旧 state 混去重）
          const seen: Set<string> = new Set<string>();
          const merged: PostSummaryDto[] = [];
          for (let i = 0; i < cloudPosts.length; i++) {
            const p = cloudPosts[i];
            const k = `${p.service}:${p.creatorId}:${p.postId}`;
            if (!seen.has(k)) {
              seen.add(k);
              merged.push(p);
            }
          }
          for (let i = 0; i < localPosts.length; i++) {
            const p = localPosts[i];
            const k = `${p.service}:${p.creatorId}:${p.postId}`;
            if (!seen.has(k)) {
              seen.add(k);
              merged.push(p);
            }
          }
          this.favoritePosts = merged;
          this.favoriteCreators = await this.container.favoriteRepo.fetchCloudFavoriteCreators();
        } catch (cloudErr) {
          this.favoritePosts = localPosts;
          this.statusMessage = `云端同步失败，当前显示本地收藏（${AppError.friendlyMessage(cloudErr as Object)}）`;
        }
      } else {
        this.favoritePosts = localPosts;
        this.favoriteCreators = [];
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  @Builder
  topBarActions() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_refresh'), iconSize: 19, tint: this.theme.colors.textPrimary })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.loadAll(true);
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_ellipsis'), iconSize: 19, tint: this.theme.colors.textPrimary })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onOpenMenu();
      })
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '收藏',
        subtitle: this.container.authRepo.isLoggedIn()
          ? `云端同步 · ${this.container.authRepo.getActiveAccount()?.username ?? ''}`
          : '本地收藏模式（无需登录）',
        trailing: () => {
          this.topBarActions();
        }
      })

      Row({ space: 8 }) {
        Text(`帖子 (${this.favoritePosts.length})`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeSubTab === 0 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(12)
          .backgroundColor(this.activeSubTab === 0 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
          .onClick(() => {
            this.activeSubTab = 0;
          })

        Text(`创作者 (${this.favoriteCreators.length})`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeSubTab === 1 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(12)
          .backgroundColor(this.activeSubTab === 1 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
          .onClick(() => {
            this.activeSubTab = 1;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .fontSize(12)
          .fontColor(this.theme.colors.error)
          .padding({ left: 16, right: 16, bottom: 8 })
          .width('100%')
      }

      if (this.loading && this.favoritePosts.length === 0 && this.favoriteCreators.length === 0) {
        AppLoadingState({ message: '正在加载收藏…' })
          .layoutWeight(1)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          if (this.activeSubTab === 0) {
            if (this.favoritePosts.length === 0) {
              AppEmptyState({
                title: '还没有收藏的帖子',
                message: '点击任意帖子卡片右下角的爱心即可收藏；打开详情页后会自动建立离线全文缓存。',
                icon: $r('app.media.ic_favorites')
              })
            } else {
              List({ space: 10 }) {
                ForEach(this.favoritePosts, (post: PostSummaryDto) => {
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
                      onOpenCreator: () => {
                        const param: CreatorRouteParam = {
                          service: post.service,
                          creatorId: post.creatorId
                        };
                        this.onNavigate(AppRoutes.CREATOR, param);
                      },
                      onToggleFavorite: () => {
                        this.container.favoriteRepo.toggleFavoritePost(post).then(() => {
                          this.loadAll(false);
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
              .width('100%')
              .height('100%')
            }
          } else {
            if (!this.container.authRepo.isLoggedIn()) {
              Column({ space: 12 }) {
                AppEmptyState({
                  title: '登录后同步云端收藏创作者',
                  message: '前往「我 → 账号管理」粘贴 Pawchive session Cookie 或通过内嵌网页登录。',
                  icon: $r('app.media.ic_mine')
                })
                AppButton({
                  label: '前往账号管理',
                  primary: true,
                  fullWidth: false,
                  onAction: () => {
                    this.onNavigate(AppRoutes.LOGIN);
                  }
                })
                  .width(180)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (this.favoriteCreators.length === 0) {
              AppEmptyState({
                title: '还没有收藏的创作者',
                message: '在发现页或作者主页点击收藏即可同步到云端。',
                icon: $r('app.media.ic_discover')
              })
            } else {
              List({ space: 8 }) {
                ForEach(this.favoriteCreators, (fav: SessionFavoriteDto) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      NetImage({
                        url: UrlProvider.iconUrl(this.container.apiClient.getBaseUrl(), fav.service, fav.id),
                        fit: ImageFit.Cover,
                        imgRadius: 22,
                        allowBlur: false
                      })
                        .width(44)
                        .height(44)

                      Column({ space: 4 }) {
                        Text(fav.name ?? fav.id)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.theme.colors.textPrimary)
                        Text(`${servicePlatformLabel(fav.service)} · 更新 ${Fmt.shortDate(fav.updated)}`)
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
                        service: fav.service,
                        creatorId: fav.id
                      };
                      this.onNavigate(AppRoutes.CREATOR, param);
                    })
                  }
                }, (fav: SessionFavoriteDto) => `${fav.service}:${fav.id}`)
              }
              .padding({ left: 12, right: 12, top: 4, bottom: 20 })
              .width('100%')
              .height('100%')
            }
          }
        }
        .onRefreshing(() => {
          this.loadAll(true);
        })
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
