import { LengthMetrics } from '@kit.ArkUI';
import { PostSummaryDto } from '../../core/api/Dtos';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { PostLayoutMode } from '../../core/store/SettingsManager';
import { PostSortHelper, PostSortMode } from '../../data/util/PostSort';
import { PostCard } from '../components/PostCard';
import { AppEmptyState, AppErrorState, AppIcon, AppLoadingState, AppTopBar } from '../design/AppComponents';
import { AppRoutes, CreatorRouteParam, PostRouteParam } from '../navigation/AppRoutes';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 首页信息流（对齐上游 ui/screens/HomeScreen.kt）。
 *
 * - offset=50 按需分页（首屏 1 页，滚到底部自动拉下一页）
 * - 关键词防抖搜索（350ms）
 * - 列表 / 网格双布局即时切换
 * - 排序切换 + 「同作者仅显示一条」 + 「隐藏已收藏创作者」
 * - 展示层屏蔽过滤（取消屏蔽不丢已加载条目）
 */
@ComponentV2
export struct HomeScreen {
  @Event onOpenMenu: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local rawPosts: PostSummaryDto[] = [];
  @Local loading: boolean = false;
  @Local refreshing: boolean = false;
  @Local loadingMore: boolean = false;
  @Local hasMore: boolean = true;
  @Local nextOffset: number = 0;
  @Local errorMsg: string = '';

  @Local searchVisible: boolean = false;
  @Local searchText: string = '';
  @Local gridMode: boolean = false;
  @Local sortMode: PostSortMode = PostSortMode.PUBLISHED_DESC;
  @Local dedupeCreator: boolean = false;
  @Local hideFavCreators: boolean = false;
  @Local filterPanelOpen: boolean = false;
  @Local stateTick: number = 0;

  private searchTimerId: number = -1;
  private readonly favListener = (): void => {
    this.stateTick++;
  };
  private readonly blockListener = (): void => {
    this.stateTick++;
  };

  aboutToAppear(): void {
    const snap = this.container.settings.getSnapshot();
    this.gridMode = snap.postLayoutMode === PostLayoutMode.GRID;
    this.dedupeCreator = snap.homeDeduplicateCreator;
    this.hideFavCreators = snap.homeHideFavoritedCreators;
    this.container.favoriteRepo.subscribe(this.favListener);
    this.container.blockedContent.subscribe(this.blockListener);
    this.loadFirstPage(false);
  }

  aboutToDisappear(): void {
    if (this.searchTimerId !== -1) {
      clearTimeout(this.searchTimerId);
      this.searchTimerId = -1;
    }
    this.container.favoriteRepo.unsubscribe(this.favListener);
    this.container.blockedContent.unsubscribe(this.blockListener);
  }

  private async loadFirstPage(bypassCache: boolean): Promise<void> {
    if (bypassCache) {
      this.refreshing = true;
    } else {
      this.loading = true;
    }
    this.errorMsg = '';
    try {
      const page = await this.container.postRepo.loadGlobalPosts(this.searchText, 0, bypassCache);
      this.rawPosts = PostSortHelper.deduplicatePosts(page.items);
      this.hasMore = page.hasMore;
      this.nextOffset = page.nextOffset;
    } catch (e) {
      this.errorMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private async loadNextPage(): Promise<void> {
    if (this.loading || this.loadingMore || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const page = await this.container.postRepo.loadGlobalPosts(this.searchText, this.nextOffset, false);
      const merged = this.rawPosts.concat(page.items);
      this.rawPosts = PostSortHelper.deduplicatePosts(merged);
      this.hasMore = page.hasMore;
      this.nextOffset = page.nextOffset;
    } catch (_e) {
      // 下一页失败保留已加载内容
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
      this.loadFirstPage(false);
    }, 350);
  }

  private getDisplayedPosts(): PostSummaryDto[] {
    const _tick = this.stateTick;
    let list = PostSortHelper.sortPosts(this.rawPosts, this.sortMode);
    if (this.dedupeCreator) {
      list = PostSortHelper.deduplicateByCreator(list);
    }
    if (this.hideFavCreators) {
      list = PostSortHelper.filterOutCreators(list, this.container.favoriteRepo.getFavoritedCreatorKeysSnapshot());
    }
    return _tick >= 0 ? list : list;
  }

  private toggleLayout(): void {
    this.gridMode = !this.gridMode;
    this.container.settings.setPostLayoutMode(this.gridMode ? PostLayoutMode.GRID : PostLayoutMode.LIST);
  }

  private openPost(post: PostSummaryDto): void {
    const param: PostRouteParam = {
      service: post.service,
      creatorId: post.creatorId,
      postId: post.postId
    };
    this.onNavigate(AppRoutes.POST, param);
  }

  private openCreator(post: PostSummaryDto): void {
    const param: CreatorRouteParam = {
      service: post.service,
      creatorId: post.creatorId
    };
    this.onNavigate(AppRoutes.CREATOR, param);
  }

  @Builder
  topBarActions() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_search'), iconSize: 19, tint: this.theme.colors.textPrimary })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.searchVisible = !this.searchVisible;
        if (!this.searchVisible && this.searchText.length > 0) {
          this.searchText = '';
          this.loadFirstPage(false);
        }
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({
          icon: this.gridMode ? $r('app.media.ic_list_view') : $r('app.media.ic_grid_view'),
          iconSize: 19,
          tint: this.theme.colors.textPrimary
        })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.toggleLayout();
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({
          icon: $r('app.media.ic_settings'),
          iconSize: 19,
          tint: this.filterPanelOpen ? this.theme.colors.primary : this.theme.colors.textPrimary
        })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.filterPanelOpen = !this.filterPanelOpen;
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_alarm'), iconSize: 19, tint: this.theme.colors.textPrimary })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onNavigate(AppRoutes.NOTIFICATIONS);
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

  @Builder
  filterPanel() {
    Column({ space: 10 }) {
      Text('排序方式')
        .fontSize(12)
        .fontColor(this.theme.colors.textSecondary)

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(
          [
            PostSortMode.PUBLISHED_DESC,
            PostSortMode.PUBLISHED_ASC,
            PostSortMode.TITLE_ASC,
            PostSortMode.TITLE_DESC
          ],
          (mode: PostSortMode) => {
            Text(PostSortHelper.label(mode))
              .fontSize(12)
              .fontColor(this.sortMode === mode ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(
                this.sortMode === mode ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
              )
              .onClick(() => {
                this.sortMode = mode;
              })
          },
          (mode: PostSortMode) => mode
        )
      }

      Row() {
        Text('同作者仅显示一条')
          .fontSize(13)
          .fontColor(this.theme.colors.textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.dedupeCreator })
          .selectedColor(this.theme.colors.primary)
          .onChange((isOn: boolean) => {
            this.dedupeCreator = isOn;
          })
      }
      .width('100%')

      Row() {
        Text('隐藏已收藏创作者')
          .fontSize(13)
          .fontColor(this.theme.colors.textPrimary)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.hideFavCreators })
          .selectedColor(this.theme.colors.primary)
          .onChange((isOn: boolean) => {
            this.hideFavCreators = isOn;
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .margin({ left: 12, right: 12, bottom: 8 })
    .borderRadius(14)
    .backgroundColor(this.theme.colors.surface)
  }

  build() {
    Column() {
      AppTopBar({
        title: 'Archive',
        subtitle: this.searchText.length > 0 ? `搜索: ${this.searchText}` : '',
        trailing: () => {
          this.topBarActions();
        }
      })

      if (this.searchVisible) {
        Row({ space: 8 }) {
          TextInput({ text: this.searchText, placeholder: '搜索帖子标题或关键词（≥3 字符走服务端）' })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(this.theme.colors.textPrimary)
            .placeholderColor(this.theme.colors.textTertiary)
            .backgroundColor(this.theme.colors.surfaceContainer)
            .borderRadius(12)
            .onChange((val: string) => {
              this.scheduleSearch(val);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.filterPanelOpen) {
        this.filterPanel()
      }

      if (this.loading && this.rawPosts.length === 0) {
        AppLoadingState({ message: '正在加载最新帖子…' })
          .layoutWeight(1)
      } else if (this.errorMsg.length > 0 && this.rawPosts.length === 0) {
        AppErrorState({
          message: this.errorMsg,
          onRetry: () => {
            this.loadFirstPage(true);
          }
        })
          .layoutWeight(1)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          if (this.getDisplayedPosts().length === 0) {
            AppEmptyState({
              title: '暂无可展示帖子',
              message: '下拉刷新或调整筛选条件重试',
              icon: $r('app.media.ic_home')
            })
          } else if (this.gridMode) {
            Grid() {
              ForEach(this.getDisplayedPosts(), (post: PostSummaryDto) => {
                GridItem() {
                  PostCard({
                    post: post,
                    gridMode: true,
                    isFavorited: this.container.favoriteRepo.isPostFavorited(post.service, post.creatorId, post.postId),
                    isBlocked: this.container.blockedContent.isPostBlocked(post.service, post.creatorId, post.postId),
                    onOpenPost: () => {
                      this.openPost(post);
                    },
                    onOpenCreator: () => {
                      this.openCreator(post);
                    },
                    onToggleFavorite: () => {
                      this.container.favoriteRepo.toggleFavoritePost(post);
                    },
                    onBlockPost: () => {
                      this.container.blockedContent.blockPost(post.service, post.creatorId, post.postId, post.title);
                    }
                  })
                }
              }, (post: PostSummaryDto) => `${post.service}:${post.creatorId}:${post.postId}:${this.stateTick}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .padding({ left: 12, right: 12, top: 4, bottom: 20 })
            .width('100%')
            .height('100%')
            .onReachEnd(() => {
              this.loadNextPage();
            })
          } else {
            List({ space: 10 }) {
              ForEach(this.getDisplayedPosts(), (post: PostSummaryDto) => {
                ListItem() {
                  PostCard({
                    post: post,
                    gridMode: false,
                    isFavorited: this.container.favoriteRepo.isPostFavorited(post.service, post.creatorId, post.postId),
                    isBlocked: this.container.blockedContent.isPostBlocked(post.service, post.creatorId, post.postId),
                    onOpenPost: () => {
                      this.openPost(post);
                    },
                    onOpenCreator: () => {
                      this.openCreator(post);
                    },
                    onToggleFavorite: () => {
                      this.container.favoriteRepo.toggleFavoritePost(post);
                    },
                    onBlockPost: () => {
                      this.container.blockedContent.blockPost(post.service, post.creatorId, post.postId, post.title);
                    }
                  })
                }
              }, (post: PostSummaryDto) => `${post.service}:${post.creatorId}:${post.postId}:${this.stateTick}`)

              if (this.loadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(24).height(24).color(this.theme.colors.primary)
                  }
                  .width('100%')
                  .padding(16)
                  .justifyContent(FlexAlign.Center)
                }
              }
            }
            .padding({ left: 12, right: 12, top: 4, bottom: 20 })
            .width('100%')
            .height('100%')
            .onReachEnd(() => {
              this.loadNextPage();
            })
          }
        }
        .onRefreshing(() => {
          this.loadFirstPage(true);
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
