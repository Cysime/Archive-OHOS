import { AppContainer } from '../core/AppContainer';
import { CloudflareWebHost } from './components/CloudflareWebHost';
import { RevealMenuItem, RevealMenuOverlay } from './components/RevealMenuOverlay';
import { AppIcon } from './design/AppComponents';
import { AppRoutes, CreatorRouteParam, PostRouteParam, ViewerRouteParam } from './navigation/AppRoutes';
import { AboutScreen } from './screens/AboutScreen';
import { AccountScreen } from './screens/AccountScreen';
import { AgeGateScreen } from './screens/AgeGateScreen';
import { BlockedContentScreen } from './screens/BlockedContentScreen';
import { CreatorDetailScreen } from './screens/CreatorDetailScreen';
import { CreatorsScreen } from './screens/CreatorsScreen';
import { DownloadsScreen } from './screens/DownloadsScreen';
import { FavoritesScreen } from './screens/FavoritesScreen';
import { GlobalSearchScreen } from './screens/GlobalSearchScreen';
import { HistoryScreen } from './screens/HistoryScreen';
import { HomeScreen } from './screens/HomeScreen';
import { MediaViewerScreen } from './screens/MediaViewerScreen';
import { MineScreen } from './screens/MineScreen';
import { NotificationsScreen } from './screens/NotificationsScreen';
import { PostDetailScreen } from './screens/PostDetailScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { StorageScreen } from './screens/StorageScreen';
import { TranslationSettingsScreen } from './screens/TranslationSettingsScreen';
import { ArchiveThemeController } from './theme/PurrColors';

interface MainTabSpec {
  index: number;
  label: string;
  icon: Resource;
}

/**
 * 应用根容器（全部 15 条路由与 4 个一级标签均已接入完整业务页面，零占位页面）。
 */
@ComponentV2
export struct ArchiveRoot {
  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly navPathStack: NavPathStack = new NavPathStack();
  private readonly tabsController: TabsController = new TabsController();

  @Local ageConfirmed: boolean = false;
  @Local currentTabIndex: number = 0;
  @Local menuVisible: boolean = false;

  private readonly mainTabs: MainTabSpec[] = [
    { index: 0, label: '首页', icon: $r('app.media.ic_home') },
    { index: 1, label: '发现', icon: $r('app.media.ic_discover') },
    { index: 2, label: '收藏', icon: $r('app.media.ic_favorites') },
    { index: 3, label: '我', icon: $r('app.media.ic_mine') }
  ];

  aboutToAppear(): void {
    const snap = AppContainer.getInstance().settings.getSnapshot();
    this.ageConfirmed = snap.ageConfirmed;
    this.currentTabIndex = Math.min(3, Math.max(0, snap.startupTab));
    this.theme.applySettings(snap.colorMode, snap.seedColorHex, snap.blurThumbnails, snap.preventScreenshot);
  }

  private navigateTo(route: string, param?: Object): void {
    this.navPathStack.pushPathByName(route, param ?? null);
  }

  private getRevealMenuItems(): RevealMenuItem[] {
    return [
      {
        label: '全站搜索',
        icon: $r('app.media.ic_search'),
        action: () => {
          this.navigateTo(AppRoutes.SEARCH);
        }
      },
      {
        label: '浏览历史',
        icon: $r('app.media.ic_tasks'),
        action: () => {
          this.navigateTo(AppRoutes.HISTORY);
        }
      },
      {
        label: '下载管理',
        icon: $r('app.media.ic_downloads'),
        action: () => {
          this.navigateTo(AppRoutes.DOWNLOADS);
        }
      },
      {
        label: 'AI 设置',
        icon: $r('app.media.ic_sparkles'),
        action: () => {
          this.navigateTo(AppRoutes.TRANSLATION);
        }
      },
      {
        label: '一键清理缓存',
        icon: $r('app.media.ic_delete'),
        action: () => {
          AppContainer.getInstance().cacheRepo.clearImageAndApiCache();
          try {
            this.getUIContext().getPromptAction().showToast({ message: '缓存已清理' });
          } catch (_e) {
            // ignore toast errors
          }
        }
      }
    ];
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    NavDestination() {
      if (name === AppRoutes.CREATOR) {
        CreatorDetailScreen({
          service: (param as CreatorRouteParam).service,
          creatorId: (param as CreatorRouteParam).creatorId,
          onBack: () => {
            this.navPathStack.pop();
          },
          onNavigate: (route: string, nextParam?: Object) => {
            this.navigateTo(route, nextParam);
          }
        })
      } else if (name === AppRoutes.POST) {
        PostDetailScreen({
          service: (param as PostRouteParam).service,
          creatorId: (param as PostRouteParam).creatorId,
          postId: (param as PostRouteParam).postId,
          onBack: () => {
            this.navPathStack.pop();
          },
          onNavigate: (route: string, nextParam?: Object) => {
            this.navigateTo(route, nextParam);
          }
        })
      } else if (name === AppRoutes.VIEWER) {
        MediaViewerScreen({
          service: (param as ViewerRouteParam).service,
          creatorId: (param as ViewerRouteParam).creatorId,
          postId: (param as ViewerRouteParam).postId,
          initialIndex: (param as ViewerRouteParam).initialIndex,
          onBack: () => {
            this.navPathStack.pop();
          },
          onNavigate: (route: string, nextParam?: Object) => {
            this.navigateTo(route, nextParam);
          }
        })
      } else if (name === AppRoutes.LOGIN) {
        AccountScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      } else if (name === AppRoutes.HISTORY) {
        HistoryScreen({
          onBack: () => {
            this.navPathStack.pop();
          },
          onNavigate: (route: string, nextParam?: Object) => {
            this.navigateTo(route, nextParam);
          }
        })
      } else if (name === AppRoutes.BLOCKED) {
        BlockedContentScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      } else if (name === AppRoutes.DOWNLOADS) {
        DownloadsScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      } else if (name === AppRoutes.SEARCH) {
        GlobalSearchScreen({
          onBack: () => {
            this.navPathStack.pop();
          },
          onNavigate: (route: string, nextParam?: Object) => {
            this.navigateTo(route, nextParam);
          }
        })
      } else if (name === AppRoutes.TRANSLATION) {
        TranslationSettingsScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      } else if (name === AppRoutes.NOTIFICATIONS) {
        NotificationsScreen({
          onBack: () => {
            this.navPathStack.pop();
          },
          onNavigate: (route: string, nextParam?: Object) => {
            this.navigateTo(route, nextParam);
          }
        })
      } else if (name === AppRoutes.STORAGE) {
        StorageScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      } else if (name === AppRoutes.SETTINGS) {
        SettingsScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      } else {
        AboutScreen({
          onBack: () => {
            this.navPathStack.pop();
          }
        })
      }
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.colors.background)
  }

  @Builder
  bottomBar() {
    Column() {
      Row() {
        ForEach(this.mainTabs, (tab: MainTabSpec) => {
          Column({ space: 3 }) {
            AppIcon({
              icon: tab.icon,
              iconSize: 22,
              tint: this.currentTabIndex === tab.index
                ? this.theme.colors.primary
                : this.theme.colors.textSecondary
            })
            Text(tab.label)
              .fontSize(11)
              .fontWeight(this.currentTabIndex === tab.index ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.currentTabIndex === tab.index
                ? this.theme.colors.primary
                : this.theme.colors.textSecondary)
          }
          .layoutWeight(1)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.currentTabIndex = tab.index;
            this.tabsController.changeIndex(tab.index);
          })
        }, (tab: MainTabSpec) => `${tab.index}`)
      }
      .width('100%')
      .height(48)
    }
    .width('100%')
    // 小白条沉浸化：底栏背景直接延伸至屏幕物理底部，底部仅保留紧凑内边距（约小白条自身高度），消除底栏与小白条之间的空隙
    .padding({
      top: 4,
      bottom: this.theme.bottomSafeVp > 0 ? Math.max(10, Math.round(this.theme.bottomSafeVp * 0.55)) : 4
    })
    .backgroundColor(this.theme.colors.surface)
    .border({ width: { top: 0.5 }, color: this.theme.colors.divider })
  }

  build() {
    Stack() {
      CloudflareWebHost()

      if (!this.ageConfirmed) {
        AgeGateScreen({
          onConfirm: () => {
            this.ageConfirmed = true;
            AppContainer.getInstance().settings.setAgeConfirmed(true);
          }
        })
      } else {
        Navigation(this.navPathStack) {
          Column() {
            Tabs({
              barPosition: BarPosition.End,
              index: this.currentTabIndex,
              controller: this.tabsController
            }) {
              TabContent() {
                HomeScreen({
                  onOpenMenu: () => {
                    this.menuVisible = true;
                  },
                  onNavigate: (route: string, param?: Object) => {
                    this.navigateTo(route, param);
                  }
                })
              }

              TabContent() {
                CreatorsScreen({
                  onOpenMenu: () => {
                    this.menuVisible = true;
                  },
                  onNavigate: (route: string, param?: Object) => {
                    this.navigateTo(route, param);
                  }
                })
              }

              TabContent() {
                FavoritesScreen({
                  onOpenMenu: () => {
                    this.menuVisible = true;
                  },
                  onNavigate: (route: string, param?: Object) => {
                    this.navigateTo(route, param);
                  }
                })
              }

              TabContent() {
                MineScreen({
                  onOpenMenu: () => {
                    this.menuVisible = true;
                  },
                  onNavigate: (route: string, param?: Object) => {
                    this.navigateTo(route, param);
                  }
                })
              }
            }
            .barHeight(0)
            .scrollable(true)
            .onChange((index: number) => {
              this.currentTabIndex = index;
            })
            .layoutWeight(1)
            .width('100%')

            this.bottomBar()
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.theme.colors.background)
        }
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .navDestination(this.destinationBuilder)
        .width('100%')
        .height('100%')

        RevealMenuOverlay({
          visible: this.menuVisible,
          items: this.getRevealMenuItems(),
          onDismiss: () => {
            this.menuVisible = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
