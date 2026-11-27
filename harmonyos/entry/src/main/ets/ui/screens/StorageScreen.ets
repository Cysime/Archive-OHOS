import { AppContainer } from '../../core/AppContainer';
import { Fmt } from '../../core/util/Fmt';
import { StorageSummary } from '../../data/ops/CacheRepository';
import { AppButton, AppCard, AppDivider, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 存储与缓存管理页（对齐上游 ui/screens/StorageScreen.kt）。
 */
@ComponentV2
export struct StorageScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local summary: StorageSummary = {
    imageCacheBytes: 0,
    downloadsBytes: 0,
    offlineArchiveCount: 0,
    offlineArchiveBytes: 0,
    cachedCreatorsCount: 0
  };
  @Local statusToast: string = '';

  aboutToAppear(): void {
    this.refreshStats();
  }

  private async refreshStats(): Promise<void> {
    this.summary = await this.container.cacheRepo.getSummary();
  }

  build() {
    Column() {
      AppTopBar({
        title: '存储与缓存',
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          if (this.statusToast.length > 0) {
            Text(this.statusToast)
              .fontSize(12)
              .fontColor(this.theme.colors.primary)
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.theme.colors.surface)
              .width('100%')
          }

          AppCard() {
            Column({ space: 12 }) {
              Row() {
                Text('图片与接口缓存')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Text(Fmt.bytes(this.summary.imageCacheBytes))
                  .fontSize(14)
                  .fontColor(this.theme.colors.primary)
              }
              .width('100%')

              AppDivider()

              Row() {
                Text('收藏帖子离线归档')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Text(`${this.summary.offlineArchiveCount} 篇 · ${Fmt.bytes(this.summary.offlineArchiveBytes)}`)
                  .fontSize(14)
                  .fontColor(this.theme.colors.textSecondary)
              }
              .width('100%')

              AppDivider()

              Row() {
                Text('本地创作者目录索引')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Text(`${Fmt.compactCount(this.summary.cachedCreatorsCount)} 位`)
                  .fontSize(14)
                  .fontColor(this.theme.colors.textSecondary)
              }
              .width('100%')

              AppDivider()

              Row() {
                Text('应用沙箱下载目录')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Text(Fmt.bytes(this.summary.downloadsBytes))
                  .fontSize(14)
                  .fontColor(this.theme.colors.textSecondary)
              }
              .width('100%')
            }
            .width('100%')
          }

          AppCard() {
            Column({ space: 10 }) {
              Text('维护与清理')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              AppButton({
                label: '清理图片与内存缓存（不影响下载与收藏）',
                primary: true,
                onAction: () => {
                  this.container.cacheRepo.clearImageAndApiCache();
                  this.statusToast = '图片与内存缓存已清理';
                  this.refreshStats();
                }
              })

              AppButton({
                label: '清空离线全文归档缓存',
                primary: false,
                onAction: () => {
                  this.container.cacheRepo.clearOfflineArchives().then(() => {
                    this.statusToast = '离线全文归档已清空';
                    this.refreshStats();
                  });
                }
              })

              AppButton({
                label: '清空浏览历史',
                primary: false,
                onAction: () => {
                  this.container.cacheRepo.clearHistory().then(() => {
                    this.statusToast = '浏览历史已清空';
                  });
                }
              })
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
