import { CreatorDto } from '../../core/api/Dtos';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { Fmt } from '../../core/util/Fmt';
import { CreatorSortMode } from '../../data/repo/CreatorRepository';
import { CreatorRow } from '../components/CreatorRow';
import { AppButton, AppEmptyState, AppIcon, AppTopBar } from '../design/AppComponents';
import { AppRoutes, CreatorRouteParam } from '../navigation/AppRoutes';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 发现页（对齐上游 ui/screens/CreatorsScreen.kt）。
 *
 * - 9.6 万+ 创作者全量同步至 RDB（带进度提示）
 * - 本地瞬时关键词搜索、Patreon / Fanbox 平台筛选、按更新/收藏/名称排序
 * - 点击行内原地展开详情面板并直达创作者主页
 */
@ComponentV2
export struct CreatorsScreen {
  @Event onOpenMenu: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local creators: CreatorDto[] = [];
  @Local totalCount: number = 0;
  @Local queryText: string = '';
  @Local serviceFilter: string = 'all';
  @Local sortMode: CreatorSortMode = CreatorSortMode.UPDATED_DESC;
  @Local expandedKey: string = '';

  @Local syncing: boolean = false;
  @Local syncProgressText: string = '';
  @Local syncError: string = '';
  @Local hasMore: boolean = true;
  @Local queryOffset: number = 0;

  private searchTimerId: number = -1;

  aboutToAppear(): void {
    this.reloadCountAndList();
  }

  aboutToDisappear(): void {
    if (this.searchTimerId !== -1) {
      clearTimeout(this.searchTimerId);
      this.searchTimerId = -1;
    }
  }

  private async reloadCountAndList(): Promise<void> {
    this.totalCount = await this.container.creatorRepo.getTotalCount();
    await this.queryFirstPage();
  }

  private async queryFirstPage(): Promise<void> {
    this.queryOffset = 0;
    const page = await this.container.creatorRepo.queryCreators(
      this.queryText,
      this.serviceFilter,
      this.sortMode,
      50,
      0
    );
    this.creators = page;
    this.queryOffset = page.length;
    this.hasMore = page.length >= 50;
  }

  private async loadMore(): Promise<void> {
    if (!this.hasMore) {
      return;
    }
    const page = await this.container.creatorRepo.queryCreators(
      this.queryText,
      this.serviceFilter,
      this.sortMode,
      50,
      this.queryOffset
    );
    if (page.length > 0) {
      this.creators = this.creators.concat(page);
      this.queryOffset += page.length;
    }
    this.hasMore = page.length >= 50;
  }

  private scheduleQuery(text: string): void {
    this.queryText = text;
    if (this.searchTimerId !== -1) {
      clearTimeout(this.searchTimerId);
    }
    this.searchTimerId = setTimeout(() => {
      this.searchTimerId = -1;
      this.queryFirstPage();
    }, 220);
  }

  private async startSync(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    this.syncError = '';
    this.syncProgressText = '正在拉取创作者全量索引…';
    try {
      const count = await this.container.creatorRepo.syncAllCreators((loaded: number, total: number) => {
        this.syncProgressText = `已写入 ${loaded} / ${total}`;
      });
      this.totalCount = count;
      this.syncProgressText = `已同步 ${Fmt.compactCount(count)} 位创作者`;
      await this.queryFirstPage();
    } catch (e) {
      this.syncError = AppError.friendlyMessage(e as Object);
    } finally {
      this.syncing = false;
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
      .enabled(!this.syncing)
      .onClick(() => {
        this.startSync();
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
        title: '发现',
        subtitle: this.totalCount > 0 ? `本地已缓存 ${Fmt.compactCount(this.totalCount)} 位创作者` : '尚未同步本地创作者库',
        trailing: () => {
          this.topBarActions();
        }
      })

      Column({ space: 8 }) {
        TextInput({ text: this.queryText, placeholder: '本地搜索创作者名称或 ID…' })
          .width('100%')
          .height(40)
          .fontSize(14)
          .fontColor(this.theme.colors.textPrimary)
          .placeholderColor(this.theme.colors.textTertiary)
          .backgroundColor(this.theme.colors.surfaceContainer)
          .borderRadius(12)
          .onChange((val: string) => {
            this.scheduleQuery(val);
          })

        Row({ space: 8 }) {
          ForEach(['all', 'patreon', 'fanbox'], (svc: string) => {
            Text(svc === 'all' ? '全部平台' : svc.toUpperCase())
              .fontSize(12)
              .fontColor(this.serviceFilter === svc ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor(
                this.serviceFilter === svc ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
              )
              .onClick(() => {
                this.serviceFilter = svc;
                this.queryFirstPage();
              })
          }, (svc: string) => svc)

          Blank()

          Text(
            this.sortMode === CreatorSortMode.UPDATED_DESC
              ? '按更新'
              : (this.sortMode === CreatorSortMode.FAVORITED_DESC ? '按收藏' : '按名称')
          )
            .fontSize(12)
            .fontColor(this.theme.colors.primary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor(this.theme.colors.secondaryContainer)
            .onClick(() => {
              if (this.sortMode === CreatorSortMode.UPDATED_DESC) {
                this.sortMode = CreatorSortMode.FAVORITED_DESC;
              } else if (this.sortMode === CreatorSortMode.FAVORITED_DESC) {
                this.sortMode = CreatorSortMode.NAME_ASC;
              } else {
                this.sortMode = CreatorSortMode.UPDATED_DESC;
              }
              this.queryFirstPage();
            })
        }
        .width('100%')

        if (this.syncing || this.syncError.length > 0) {
          Row({ space: 8 }) {
            if (this.syncing) {
              LoadingProgress().width(18).height(18).color(this.theme.colors.primary)
            }
            Text(this.syncError.length > 0 ? this.syncError : this.syncProgressText)
              .fontSize(12)
              .fontColor(this.syncError.length > 0 ? this.theme.colors.error : this.theme.colors.textSecondary)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(10)
          .backgroundColor(this.theme.colors.surfaceContainer)
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 8 })

      if (this.totalCount === 0 && !this.syncing) {
        Column({ space: 14 }) {
          AppEmptyState({
            title: '本地创作者库为空',
            message: '点击下方按钮一次性拉取全部 9.6 万+ 创作者并建立 RDB 索引，之后即可离线瞬时搜索。',
            icon: $r('app.media.ic_discover')
          })
          AppButton({
            label: '立即同步创作者库',
            primary: true,
            fullWidth: false,
            onAction: () => {
              this.startSync();
            }
          })
            .width(200)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.creators.length === 0) {
        AppEmptyState({
          title: '未找到匹配的创作者',
          message: '尝试更换关键词或切换平台筛选',
          icon: $r('app.media.ic_search')
        })
          .layoutWeight(1)
      } else {
        List({ space: 8 }) {
          ForEach(this.creators, (creator: CreatorDto) => {
            ListItem() {
              CreatorRow({
                creator: creator,
                expanded: this.expandedKey === `${creator.service}:${creator.id}`,
                onToggleExpand: () => {
                  const key = `${creator.service}:${creator.id}`;
                  this.expandedKey = this.expandedKey === key ? '' : key;
                },
                onOpenDetail: () => {
                  const param: CreatorRouteParam = {
                    service: creator.service,
                    creatorId: creator.id
                  };
                  this.onNavigate(AppRoutes.CREATOR, param);
                }
              })
            }
          }, (creator: CreatorDto) => `${creator.service}:${creator.id}`)
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 20 })
        .layoutWeight(1)
        .width('100%')
        .onReachEnd(() => {
          this.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
