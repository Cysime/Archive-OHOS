import { AppContainer } from '../../core/AppContainer';
import { AppColorMode } from '../../core/store/SettingsManager';
import { Fmt } from '../../core/util/Fmt';
import { AppButton, AppCard, AppDivider, AppIcon, AppTopBar } from '../design/AppComponents';
import { AppRoutes } from '../navigation/AppRoutes';
import { ArchiveThemeController } from '../theme/PurrColors';

interface MineMenuRowSpec {
  title: string;
  subtitle: string;
  icon: Resource;
  route: string;
}

/**
 * 「我」个人中心页（对齐上游 ui/screens/MineScreen.kt）。
 *
 * - 多账号登录卡片（当前登录态与快速切换入口）
 * - 浏览历史 / 下载管理 / 通知中心 / 屏蔽管理 / AI 翻译 / 存储 / 设置 / 关于全入口
 * - 快速切换浅/深色主题与防截屏隐私模式
 */
@ComponentV2
export struct MineScreen {
  @Event onOpenMenu: () => void = () => {};
  @Event onNavigate: (route: string, param?: Object) => void = (_route: string, _param?: Object) => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local activeUsername: string = '';
  @Local accountCount: number = 0;
  @Local archiveSummary: string = '';
  @Local preventScreenshot: boolean = false;

  private readonly sessionListener = (): void => {
    this.refreshState();
  };

  aboutToAppear(): void {
    this.container.sessionManager.subscribe(this.sessionListener);
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.container.sessionManager.unsubscribe(this.sessionListener);
  }

  private async refreshState(): Promise<void> {
    const active = this.container.authRepo.getActiveAccount();
    this.activeUsername = active !== undefined ? active.username : '';
    this.accountCount = this.container.authRepo.getAccounts().length;
    this.preventScreenshot = this.container.settings.getSnapshot().preventScreenshot;
    const stats = await this.container.favoriteRepo.getArchiveStats();
    this.archiveSummary = stats.count > 0
      ? `已离线归档 ${stats.count} 篇（${Fmt.bytes(stats.totalBytes)}）`
      : '收藏帖打开详情后自动归档';
  }

  private switchColorMode(mode: AppColorMode): void {
    const settings = this.container.settings;
    settings.setColorMode(mode).then(() => {
      const snap = settings.getSnapshot();
      this.theme.applySettings(snap.colorMode, snap.seedColorHex, snap.blurThumbnails, snap.preventScreenshot);
    });
  }

  private getContentMenuRows(): MineMenuRowSpec[] {
    return [
      { title: '全站搜索', subtitle: '帖子 / 创作者 / 离线归档 / 文件哈希反查', icon: $r('app.media.ic_search'), route: AppRoutes.SEARCH },
      { title: '浏览历史', subtitle: '按账号隔离的本地浏览记录', icon: $r('app.media.ic_tasks'), route: AppRoutes.HISTORY },
      { title: '下载管理', subtitle: 'HTTP Range 断点续传与下载规则', icon: $r('app.media.ic_downloads'), route: AppRoutes.DOWNLOADS },
      { title: '通知中心', subtitle: '创作者订阅与新帖更新提醒', icon: $r('app.media.ic_alarm'), route: AppRoutes.NOTIFICATIONS },
      { title: '屏蔽管理', subtitle: '查看或取消已屏蔽的创作者与帖子', icon: $r('app.media.ic_ban'), route: AppRoutes.BLOCKED }
    ];
  }

  private getSystemMenuRows(): MineMenuRowSpec[] {
    return [
      { title: 'AI 翻译与识图', subtitle: 'OpenAI / Anthropic / Gemini 多模型档案', icon: $r('app.media.ic_sparkles'), route: AppRoutes.TRANSLATION },
      { title: '存储与缓存', subtitle: this.archiveSummary, icon: $r('app.media.ic_hard_drive'), route: AppRoutes.STORAGE },
      { title: '设置', subtitle: '外观、语言、隐私、下载与备份恢复', icon: $r('app.media.ic_settings'), route: AppRoutes.SETTINGS },
      { title: '关于 Archive', subtitle: 'GPL-3.0 · 检查更新（Cysime/Archive-OHOS）', icon: $r('app.media.ic_info'), route: AppRoutes.ABOUT }
    ];
  }

  @Builder
  menuGroup(rows: MineMenuRowSpec[]) {
    AppCard({ cardPadding: 6 }) {
      Column() {
        ForEach(rows, (row: MineMenuRowSpec, idx: number) => {
          if (idx > 0) {
            AppDivider()
          }
          Row({ space: 12 }) {
            AppIcon({ icon: row.icon, iconSize: 20, tint: this.theme.colors.primary })
            Column({ space: 2 }) {
              Text(row.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.colors.textPrimary)
              Text(row.subtitle)
                .fontSize(12)
                .fontColor(this.theme.colors.textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            AppIcon({ icon: $r('app.media.ic_chevron_forward'), iconSize: 16, tint: this.theme.colors.textTertiary })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 12, bottom: 12 })
          .onClick(() => {
            this.onNavigate(row.route);
          })
        }, (row: MineMenuRowSpec) => row.route)
      }
      .width('100%')
    }
  }

  build() {
    Column() {
      AppTopBar({ title: '我' })

      Scroll() {
        Column({ space: 14 }) {
          AppCard() {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.Center }) {
                AppIcon({ icon: $r('app.media.ic_mine'), iconSize: 24, tint: this.theme.colors.primary })
              }
              .width(48)
              .height(48)
              .borderRadius(24)
              .backgroundColor(this.theme.colors.secondaryContainer)

              Column({ space: 4 }) {
                Text(this.activeUsername.length > 0 ? this.activeUsername : '未登录（游客模式）')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)
                Text(
                  this.accountCount > 0
                    ? `已保存 ${this.accountCount} 个账号 · 点击切换或管理`
                    : '点击账号密码登录、注册或管理多账号'
                )
                  .fontSize(12)
                  .fontColor(this.theme.colors.textSecondary)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              AppIcon({ icon: $r('app.media.ic_chevron_forward'), iconSize: 16, tint: this.theme.colors.textTertiary })
            }
            .width('100%')
            .onClick(() => {
              this.onNavigate(AppRoutes.LOGIN);
            })
          }

          this.menuGroup(this.getContentMenuRows())
          this.menuGroup(this.getSystemMenuRows())

          AppCard() {
            Column({ space: 12 }) {
              Text('快速外观与隐私')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.colors.textPrimary)

              Row({ space: 8 }) {
                AppButton({
                  label: '跟随系统',
                  primary: this.theme.colorMode === AppColorMode.SYSTEM,
                  fullWidth: false,
                  onAction: () => {
                    this.switchColorMode(AppColorMode.SYSTEM);
                  }
                })
                  .layoutWeight(1)
                AppButton({
                  label: '浅色',
                  primary: this.theme.colorMode === AppColorMode.LIGHT,
                  fullWidth: false,
                  onAction: () => {
                    this.switchColorMode(AppColorMode.LIGHT);
                  }
                })
                  .layoutWeight(1)
                AppButton({
                  label: '深色',
                  primary: this.theme.colorMode === AppColorMode.DARK,
                  fullWidth: false,
                  onAction: () => {
                    this.switchColorMode(AppColorMode.DARK);
                  }
                })
                  .layoutWeight(1)
              }
              .width('100%')

              Row() {
                Text('禁止截屏（窗口隐私模式）')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.preventScreenshot })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((isOn: boolean) => {
                    this.preventScreenshot = isOn;
                    this.container.settings.setPreventScreenshot(isOn).then(() => {
                      this.theme.applyPrivacyMode(isOn);
                    });
                  })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
