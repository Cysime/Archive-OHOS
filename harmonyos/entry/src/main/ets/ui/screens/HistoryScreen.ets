import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { HistoryEntry } from '../../data/repo/HistoryRepository';
import { NetImage } from '../components/NetImage';
import { AppEmptyState, AppIcon, AppTopBar } from '../design/AppComponents';
import { AppRoutes, PostRouteParam } from '../navigation/AppRoutes';
import { ArchiveThemeController, servicePlatformLabel } from '../theme/PurrColors';

/**
 * 浏览历史页（对齐上游 ui/screens/HistoryScreen.kt）。
 */
@ComponentV2
export struct HistoryScreen {
  @Event onBack: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local entries: HistoryEntry[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.entries = await this.container.historyRepo.listHistory(150, 0);
  }

  private formatTimestamp(ms: number): string {
    const d = new Date(ms);
    const mm = `${d.getMonth() + 1}`.padStart(2, '0');
    const dd = `${d.getDate()}`.padStart(2, '0');
    const hh = `${d.getHours()}`.padStart(2, '0');
    const mi = `${d.getMinutes()}`.padStart(2, '0');
    return `${mm}-${dd} ${hh}:${mi}`;
  }

  @Builder
  topBarActions() {
    if (this.entries.length > 0) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_delete'), iconSize: 19, tint: this.theme.colors.error })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.container.historyRepo.clearHistory().then(() => {
          this.entries = [];
        });
      })
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '浏览历史',
        subtitle: `共 ${this.entries.length} 条记录`,
        showBack: true,
        onBack: () => {
          this.onBack();
        },
        trailing: () => {
          this.topBarActions();
        }
      })

      if (this.entries.length === 0) {
        AppEmptyState({
          title: '暂无浏览历史',
          message: '打开任意帖子详情后会自动记录在这里。',
          icon: $r('app.media.ic_tasks')
        })
          .layoutWeight(1)
      } else {
        List({ space: 8 }) {
          ForEach(this.entries, (entry: HistoryEntry) => {
            ListItem() {
              Row({ space: 12 }) {
                if (entry.cover !== undefined && (entry.cover.path ?? '').length > 0) {
                  NetImage({
                    url: UrlProvider.thumbnailUrl(this.container.apiClient.getBaseUrl(), entry.cover.path ?? ''),
                    fit: ImageFit.Cover,
                    imgRadius: 10,
                    allowBlur: true
                  })
                    .width(56)
                    .height(56)
                }

                Column({ space: 4 }) {
                  Text(entry.title.length > 0 ? entry.title : '(无标题)')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.colors.textPrimary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${servicePlatformLabel(entry.service)} · ${entry.creatorId} · ${this.formatTimestamp(entry.viewedAt)}`)
                    .fontSize(11)
                    .fontColor(this.theme.colors.textTertiary)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button({ type: ButtonType.Circle }) {
                  AppIcon({ icon: $r('app.media.ic_close'), iconSize: 15, tint: this.theme.colors.textTertiary })
                }
                .width(30)
                .height(30)
                .backgroundColor(this.theme.colors.surfaceContainer)
                .onClick(() => {
                  this.container.historyRepo.removeEntry(entry.service, entry.creatorId, entry.postId).then(() => {
                    this.reload();
                  });
                })
              }
              .width('100%')
              .padding(10)
              .borderRadius(14)
              .backgroundColor(this.theme.colors.surface)
              .onClick(() => {
                const param: PostRouteParam = {
                  service: entry.service,
                  creatorId: entry.creatorId,
                  postId: entry.postId
                };
                this.onNavigate(AppRoutes.POST, param);
              })
            }
          }, (entry: HistoryEntry) => `${entry.service}:${entry.creatorId}:${entry.postId}`)
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 20 })
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
