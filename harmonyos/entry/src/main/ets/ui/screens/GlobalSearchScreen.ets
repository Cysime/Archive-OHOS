import { LengthMetrics } from '@kit.ArkUI';
import { CreatorDto, DiscordHitDto, PostSummaryDto } from '../../core/api/Dtos';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { Fmt } from '../../core/util/Fmt';
import { CreatorSortMode } from '../../data/repo/CreatorRepository';
import { ArchivedPostHit } from '../../data/repo/FavoriteRepository';
import { CreatorRow } from '../components/CreatorRow';
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
import { ArchiveThemeController, servicePlatformLabel } from '../theme/PurrColors';

/**
 * 全站搜索页（对齐上游 ui/screens/GlobalSearchScreen.kt）。
 *
 * - 帖子 / 创作者 / 离线归档 / 文件哈希反查（MD5 & SHA-256，支持 Discord 命中）
 * - 持久化搜索历史（5–50 条，支持单条删除与一键清空）
 */
@ComponentV2
export struct GlobalSearchScreen {
  @Event onBack: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local queryText: string = '';
  @Local activeTab: number = 0; // 0=帖子, 1=创作者, 2=离线归档, 3=哈希反查
  @Local history: string[] = [];

  @Local postResults: PostSummaryDto[] = [];
  @Local creatorResults: CreatorDto[] = [];
  @Local offlineResults: ArchivedPostHit[] = [];
  @Local hashSitePosts: PostSummaryDto[] = [];
  @Local hashDiscordHits: DiscordHitDto[] = [];

  @Local loading: boolean = false;
  @Local searched: boolean = false;
  @Local errorMsg: string = '';
  @Local expandedCreatorKey: string = '';

  aboutToAppear(): void {
    this.history = this.container.searchHistory.list();
  }

  private isHashLike(q: string): boolean {
    return /^[0-9a-fA-F]{32}$|^[0-9a-fA-F]{64}$/.test(q.trim());
  }

  private async runSearch(input?: string): Promise<void> {
    const q = (input !== undefined ? input : this.queryText).trim();
    this.queryText = q;
    if (q.length === 0) {
      return;
    }
    if (this.isHashLike(q) && this.activeTab === 0) {
      this.activeTab = 3;
    }
    await this.container.searchHistory.record(q);
    this.history = this.container.searchHistory.list();

    this.loading = true;
    this.searched = true;
    this.errorMsg = '';
    try {
      if (this.activeTab === 0) {
        const page = await this.container.postRepo.loadGlobalPosts(q, 0, true);
        this.postResults = page.items;
      } else if (this.activeTab === 1) {
        this.creatorResults = await this.container.creatorRepo.queryCreators(
          q,
          'all',
          CreatorSortMode.FAVORITED_DESC,
          80,
          0
        );
      } else if (this.activeTab === 2) {
        this.offlineResults = await this.container.favoriteRepo.searchArchivedPosts(q);
      } else {
        const res = await this.container.api.searchByHash(q);
        this.hashSitePosts = res.sitePosts;
        this.hashDiscordHits = res.discordHits;
      }
    } catch (e) {
      this.errorMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '全站搜索',
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          TextInput({
            text: this.queryText,
            placeholder: this.activeTab === 3 ? '粘贴 32/64 位文件哈希（MD5 / SHA-256）…' : '输入搜索关键词…'
          })
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor(this.theme.colors.textPrimary)
            .placeholderColor(this.theme.colors.textTertiary)
            .backgroundColor(this.theme.colors.surfaceContainer)
            .borderRadius(12)
            .onChange((v: string) => {
              this.queryText = v;
            })
            .onSubmit(() => {
              this.runSearch();
            })

          AppButton({
            label: '搜索',
            primary: true,
            fullWidth: false,
            onAction: () => {
              this.runSearch();
            }
          })
            .width(76)
        }
        .width('100%')

        Row({ space: 6 }) {
          ForEach(['帖子', '创作者', '离线归档', '哈希反查'], (label: string, idx: number) => {
            Text(label)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.activeTab === idx ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(this.activeTab === idx ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
              .onClick(() => {
                this.activeTab = idx;
                if (this.queryText.trim().length > 0) {
                  this.runSearch();
                }
              })
          }, (label: string) => label)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 8 })

      if (!this.searched && this.history.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Text('搜索历史')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.colors.textSecondary)
              .layoutWeight(1)
            Text('清空')
              .fontSize(12)
              .fontColor(this.theme.colors.error)
              .onClick(() => {
                this.container.searchHistory.clear().then(() => {
                  this.history = [];
                });
              })
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
            ForEach(this.history, (h: string) => {
              Row({ space: 6 }) {
                Text(h)
                  .fontSize(12)
                  .fontColor(this.theme.colors.textPrimary)
                  .onClick(() => {
                    this.runSearch(h);
                  })
                AppIcon({ icon: $r('app.media.ic_close'), iconSize: 12, tint: this.theme.colors.textTertiary })
                  .onClick(() => {
                    this.container.searchHistory.remove(h).then(() => {
                      this.history = this.container.searchHistory.list();
                    });
                  })
              }
              .padding({ left: 10, right: 8, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(this.theme.colors.surface)
            }, (h: string) => h)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 6 })
      }

      if (this.loading) {
        AppLoadingState({ message: '正在搜索…' })
          .layoutWeight(1)
      } else if (this.errorMsg.length > 0) {
        AppErrorState({
          message: this.errorMsg,
          onRetry: () => {
            this.runSearch();
          }
        })
          .layoutWeight(1)
      } else if (!this.searched) {
        AppEmptyState({
          title: '精准搜索',
          message: '支持帖子全文、本地 9.6 万创作者、断网可用离线归档与 MD5/SHA-256 哈希反查。',
          icon: $r('app.media.ic_search')
        })
          .layoutWeight(1)
      } else if (this.activeTab === 0) {
        if (this.postResults.length === 0) {
          AppEmptyState({ title: '未找到相关帖子', icon: $r('app.media.ic_search') }).layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.postResults, (post: PostSummaryDto) => {
              ListItem() {
                PostCard({
                  post: post,
                  gridMode: false,
                  isFavorited: this.container.favoriteRepo.isPostFavorited(post.service, post.creatorId, post.postId),
                  isBlocked: this.container.blockedContent.isPostBlocked(post.service, post.creatorId, post.postId),
                  onOpenPost: () => {
                    const param: PostRouteParam = { service: post.service, creatorId: post.creatorId, postId: post.postId };
                    this.onNavigate(AppRoutes.POST, param);
                  },
                  onOpenCreator: () => {
                    const param: CreatorRouteParam = { service: post.service, creatorId: post.creatorId };
                    this.onNavigate(AppRoutes.CREATOR, param);
                  },
                  onToggleFavorite: () => {
                    this.container.favoriteRepo.toggleFavoritePost(post);
                  },
                  onBlockPost: () => {
                    this.container.blockedContent.blockPost(post.service, post.creatorId, post.postId, post.title);
                  }
                })
              }
            }, (post: PostSummaryDto) => `${post.service}:${post.creatorId}:${post.postId}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else if (this.activeTab === 1) {
        if (this.creatorResults.length === 0) {
          AppEmptyState({ title: '本地创作者库无匹配项', message: '请先在发现页同步创作者库或更换关键词。', icon: $r('app.media.ic_discover') })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.creatorResults, (creator: CreatorDto) => {
              ListItem() {
                CreatorRow({
                  creator: creator,
                  expanded: this.expandedCreatorKey === `${creator.service}:${creator.id}`,
                  onToggleExpand: () => {
                    const k = `${creator.service}:${creator.id}`;
                    this.expandedCreatorKey = this.expandedCreatorKey === k ? '' : k;
                  },
                  onOpenDetail: () => {
                    const param: CreatorRouteParam = { service: creator.service, creatorId: creator.id };
                    this.onNavigate(AppRoutes.CREATOR, param);
                  }
                })
              }
            }, (creator: CreatorDto) => `${creator.service}:${creator.id}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else if (this.activeTab === 2) {
        if (this.offlineResults.length === 0) {
          AppEmptyState({ title: '离线归档无匹配项', message: '收藏帖子并打开详情页后会自动建立离线全文归档。', icon: $r('app.media.ic_hard_drive') })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.offlineResults, (hit: ArchivedPostHit) => {
              ListItem() {
                AppCard({ cardPadding: 12 }) {
                  Column({ space: 4 }) {
                    Text(hit.title.length > 0 ? hit.title : '(无标题)')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.colors.textPrimary)
                    Text(`${servicePlatformLabel(hit.service)} · ${hit.creatorName}`)
                      .fontSize(12)
                      .fontColor(this.theme.colors.primary)
                    if (hit.excerpt.length > 0) {
                      Text(hit.excerpt)
                        .fontSize(12)
                        .fontColor(this.theme.colors.textSecondary)
                        .maxLines(3)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => {
                    const param: PostRouteParam = { service: hit.service, creatorId: hit.creatorId, postId: hit.postId };
                    this.onNavigate(AppRoutes.POST, param);
                  })
                }
              }
            }, (hit: ArchivedPostHit) => `${hit.service}:${hit.creatorId}:${hit.postId}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else {
        if (this.hashSitePosts.length === 0 && this.hashDiscordHits.length === 0) {
          AppEmptyState({ title: '哈希反查无结果', message: '未在 Pawchive 找到该文件哈希的出处记录。', icon: $r('app.media.ic_search') })
            .layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.hashSitePosts, (post: PostSummaryDto) => {
              ListItem() {
                PostCard({
                  post: post,
                  gridMode: false,
                  isFavorited: this.container.favoriteRepo.isPostFavorited(post.service, post.creatorId, post.postId),
                  isBlocked: false,
                  onOpenPost: () => {
                    const param: PostRouteParam = { service: post.service, creatorId: post.creatorId, postId: post.postId };
                    this.onNavigate(AppRoutes.POST, param);
                  },
                  onOpenCreator: () => {
                    const param: CreatorRouteParam = { service: post.service, creatorId: post.creatorId };
                    this.onNavigate(AppRoutes.CREATOR, param);
                  },
                  onToggleFavorite: () => {
                    this.container.favoriteRepo.toggleFavoritePost(post);
                  },
                  onBlockPost: () => {
                    this.container.blockedContent.blockPost(post.service, post.creatorId, post.postId, post.title);
                  }
                })
              }
            }, (post: PostSummaryDto) => `hash_${post.service}:${post.creatorId}:${post.postId}`)

            ForEach(this.hashDiscordHits, (hit: DiscordHitDto) => {
              ListItem() {
                AppCard({ cardPadding: 12 }) {
                  Column({ space: 4 }) {
                    Text(`Discord · Server ${hit.server} / #${hit.channel}`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.theme.colors.primary)
                    if ((hit.excerpt ?? '').length > 0) {
                      Text(hit.excerpt ?? '')
                        .fontSize(13)
                        .fontColor(this.theme.colors.textPrimary)
                    }
                    if ((hit.published ?? '').length > 0) {
                      Text(Fmt.shortDate(hit.published))
                        .fontSize(11)
                        .fontColor(this.theme.colors.textTertiary)
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
              }
            }, (hit: DiscordHitDto) => `discord_${hit.id}`)
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
