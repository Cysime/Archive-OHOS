import { AppContainer } from '../../core/AppContainer';
import { BlockedCreatorItem, BlockedPostItem } from '../../data/repo/BlockedContentRepository';
import { AppEmptyState, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController, servicePlatformLabel } from '../theme/PurrColors';

/**
 * 内容屏蔽管理页（对齐上游 ui/screens/BlockedContentScreen.kt）。
 */
@ComponentV2
export struct BlockedContentScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local activeTab: number = 0;
  @Local creators: BlockedCreatorItem[] = [];
  @Local posts: BlockedPostItem[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.creators = this.container.blockedContent.listBlockedCreators();
    this.posts = this.container.blockedContent.listBlockedPosts();
  }

  build() {
    Column() {
      AppTopBar({
        title: '屏蔽管理',
        subtitle: `创作者 ${this.creators.length} · 帖子 ${this.posts.length}`,
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Row({ space: 8 }) {
        Text(`已屏蔽创作者 (${this.creators.length})`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeTab === 0 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(10)
          .backgroundColor(this.activeTab === 0 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
          .onClick(() => {
            this.activeTab = 0;
          })

        Text(`已屏蔽帖子 (${this.posts.length})`)
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

      if (this.activeTab === 0) {
        if (this.creators.length === 0) {
          AppEmptyState({ title: '没有已屏蔽的创作者', icon: $r('app.media.ic_ban') })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.creators, (item: BlockedCreatorItem) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 2 }) {
                    Text(item.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.colors.textPrimary)
                    Text(`${servicePlatformLabel(item.service)} · ${item.creatorId}`)
                      .fontSize(12)
                      .fontColor(this.theme.colors.textSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button('取消屏蔽', { type: ButtonType.Normal })
                    .height(32)
                    .borderRadius(8)
                    .fontSize(12)
                    .fontColor(this.theme.colors.primary)
                    .backgroundColor(this.theme.colors.secondaryContainer)
                    .onClick(() => {
                      this.container.blockedContent.unblockCreator(item.service, item.creatorId).then(() => {
                        this.reload();
                      });
                    })
                }
                .width('100%')
                .padding(12)
                .borderRadius(14)
                .backgroundColor(this.theme.colors.surface)
              }
            }, (item: BlockedCreatorItem) => `${item.service}:${item.creatorId}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else {
        if (this.posts.length === 0) {
          AppEmptyState({ title: '没有已屏蔽的帖子', icon: $r('app.media.ic_ban') })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.posts, (item: BlockedPostItem) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 2 }) {
                    Text(item.title)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.colors.textPrimary)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${servicePlatformLabel(item.service)} · ${item.creatorId} / #${item.postId}`)
                      .fontSize(11)
                      .fontColor(this.theme.colors.textSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button('取消屏蔽', { type: ButtonType.Normal })
                    .height(32)
                    .borderRadius(8)
                    .fontSize(12)
                    .fontColor(this.theme.colors.primary)
                    .backgroundColor(this.theme.colors.secondaryContainer)
                    .onClick(() => {
                      this.container.blockedContent.unblockPost(item.service, item.creatorId, item.postId).then(() => {
                        this.reload();
                      });
                    })
                }
                .width('100%')
                .padding(12)
                .borderRadius(14)
                .backgroundColor(this.theme.colors.surface)
              }
            }, (item: BlockedPostItem) => `${item.service}:${item.creatorId}:${item.postId}`)
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
