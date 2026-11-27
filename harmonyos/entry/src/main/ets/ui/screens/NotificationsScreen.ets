import { AppContainer } from '../../core/AppContainer';
import { Fmt } from '../../core/util/Fmt';
import { ContentUpdateItem, CreatorSubscription } from '../../data/ops/SubscriptionRepository';
import { AppButton, AppCard, AppEmptyState, AppIcon, AppTopBar } from '../design/AppComponents';
import { AppRoutes, CreatorRouteParam, PostRouteParam } from '../navigation/AppRoutes';
import { ArchiveThemeController, servicePlatformLabel } from '../theme/PurrColors';

/**
 * 应用内通知中心与订阅管理页（对齐上游 ui/screens/NotificationsScreen.kt）。
 */
@ComponentV2
export struct NotificationsScreen {
  @Event onBack: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local activeTab: number = 0; // 0=通知列表, 1=订阅管理
  @Local updates: ContentUpdateItem[] = [];
  @Local subscriptions: CreatorSubscription[] = [];
  @Local unreadCount: number = 0;
  @Local checking: boolean = false;
  @Local checkStatus: string = '';

  aboutToAppear(): void {
    this.reloadAll();
  }

  private async reloadAll(): Promise<void> {
    this.updates = await this.container.subscriptionRepo.listUpdates(100);
    this.subscriptions = await this.container.subscriptionRepo.listSubscriptions();
    this.unreadCount = await this.container.subscriptionRepo.getUnreadCount();
  }

  private async checkNow(): Promise<void> {
    if (this.checking) {
      return;
    }
    this.checking = true;
    this.checkStatus = '正在检查订阅更新…';
    try {
      const found = await this.container.subscriptionRepo.checkAllSubscriptionsNow();
      this.checkStatus = found > 0 ? `发现 ${found} 条新作品更新` : '所有订阅均为最新';
      await this.reloadAll();
    } finally {
      this.checking = false;
    }
  }

  @Builder
  topBarActions() {
    Row({ space: 6 }) {
      if (this.unreadCount > 0) {
        Button('全部已读', { type: ButtonType.Normal })
          .height(30)
          .borderRadius(8)
          .fontSize(12)
          .fontColor(this.theme.colors.primary)
          .backgroundColor(this.theme.colors.secondaryContainer)
          .onClick(() => {
            this.container.subscriptionRepo.markAllRead().then(() => {
              this.reloadAll();
            });
          })
      }

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        AppIcon({ icon: $r('app.media.ic_refresh'), iconSize: 19, tint: this.theme.colors.textPrimary })
      }
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .enabled(!this.checking)
      .onClick(() => {
        this.checkNow();
      })
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '通知中心',
        subtitle: this.unreadCount > 0 ? `${this.unreadCount} 条未读更新` : `已订阅 ${this.subscriptions.length} 位创作者`,
        showBack: true,
        onBack: () => {
          this.onBack();
        },
        trailing: () => {
          this.topBarActions();
        }
      })

      Row({ space: 8 }) {
        Text(`更新通知 (${this.updates.length})`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeTab === 0 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(10)
          .backgroundColor(this.activeTab === 0 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
          .onClick(() => {
            this.activeTab = 0;
          })

        Text(`订阅管理 (${this.subscriptions.length})`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeTab === 1 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(10)
          .backgroundColor(this.activeTab === 1 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
          .onClick(() => {
            this.activeTab = 1;
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 8 })

      if (this.checkStatus.length > 0) {
        Text(this.checkStatus)
          .fontSize(12)
          .fontColor(this.theme.colors.primary)
          .padding({ left: 16, right: 16, bottom: 6 })
          .width('100%')
      }

      if (this.activeTab === 0) {
        if (this.updates.length === 0) {
          Column({ space: 12 }) {
            AppEmptyState({
              title: '暂无更新通知',
              message: '在创作者主页点击订阅，新作品发布后将推送到这里。',
              icon: $r('app.media.ic_alarm')
            })
            if (this.subscriptions.length > 0) {
              AppButton({
                label: this.checking ? '检查中…' : '立即检查订阅更新',
                primary: true,
                fullWidth: false,
                disabled: this.checking,
                onAction: () => {
                  this.checkNow();
                }
              })
                .width(190)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.updates, (item: ContentUpdateItem) => {
              ListItem() {
                AppCard({ cardPadding: 12 }) {
                  Row({ space: 10 }) {
                    if (!item.isRead) {
                      Column()
                        .width(8)
                        .height(8)
                        .borderRadius(4)
                        .backgroundColor(this.theme.colors.primary)
                    }
                    Column({ space: 4 }) {
                      Text(item.postTitle)
                        .fontSize(14)
                        .fontWeight(item.isRead ? FontWeight.Regular : FontWeight.Bold)
                        .fontColor(this.theme.colors.textPrimary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${item.creatorName} · ${servicePlatformLabel(item.service)} · ${Fmt.shortDate(item.published)}`)
                        .fontSize(11)
                        .fontColor(this.theme.colors.textSecondary)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .onClick(() => {
                    this.container.subscriptionRepo.markRead(item.id).then(() => {
                      this.reloadAll();
                    });
                    const param: PostRouteParam = {
                      service: item.service,
                      creatorId: item.creatorId,
                      postId: item.postId
                    };
                    this.onNavigate(AppRoutes.POST, param);
                  })
                }
              }
            }, (item: ContentUpdateItem) => `${item.id}_${item.isRead}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else {
        if (this.subscriptions.length === 0) {
          AppEmptyState({
            title: '尚未订阅任何创作者',
            message: '前往任意创作者主页点击「订阅更新」，或在设置中开启「收藏即订阅」。',
            icon: $r('app.media.ic_discover')
          })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.subscriptions, (sub: CreatorSubscription) => {
              ListItem() {
                AppCard({ cardPadding: 12 }) {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text(sub.creatorName.length > 0 ? sub.creatorName : sub.creatorId)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.theme.colors.textPrimary)
                      Text(`${servicePlatformLabel(sub.service)} · ${sub.creatorId}`)
                        .fontSize(12)
                        .fontColor(this.theme.colors.textSecondary)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .onClick(() => {
                      const param: CreatorRouteParam = { service: sub.service, creatorId: sub.creatorId };
                      this.onNavigate(AppRoutes.CREATOR, param);
                    })

                    Button('退订', { type: ButtonType.Normal })
                      .height(30)
                      .borderRadius(8)
                      .fontSize(12)
                      .fontColor(this.theme.colors.error)
                      .backgroundColor(this.theme.colors.surfaceContainerHigh)
                      .onClick(() => {
                        this.container.subscriptionRepo.unsubscribeCreator(sub.service, sub.creatorId).then(() => {
                          this.reloadAll();
                        });
                      })
                  }
                  .width('100%')
                }
              }
            }, (sub: CreatorSubscription) => `${sub.service}:${sub.creatorId}`)
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
