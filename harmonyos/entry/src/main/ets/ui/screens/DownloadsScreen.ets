import { MediaKind } from '../../core/api/Dtos';
import { AppContainer } from '../../core/AppContainer';
import { Fmt } from '../../core/util/Fmt';
import { DownloadExportHelper } from '../../data/download/DownloadExportHelper';
import { DownloadRecord, DownloadRule, DownloadStatus } from '../../data/download/DownloadModels';
import { AppButton, AppCard, AppEmptyState, AppIcon, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 下载管理页（对齐上游 ui/screens/DownloadsScreen.kt）。
 *
 * - 进行中 / 已完成 / 自动规则三 Tab
 * - 实时进度条、速度显示、断点暂停/恢复、失败重试、取消、系统文件选择器导出
 */
@ComponentV2
export struct DownloadsScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local activeTab: number = 0;
  @Local allRecords: DownloadRecord[] = [];
  @Local rules: DownloadRule[] = [];
  @Local newRuleName: string = '';
  @Local newRuleService: string = '';

  private readonly listener = (list: DownloadRecord[]): void => {
    this.allRecords = list;
  };

  aboutToAppear(): void {
    this.allRecords = this.container.downloadCenter.listRecords();
    this.container.downloadCenter.subscribe(this.listener);
    this.reloadRules();
  }

  aboutToDisappear(): void {
    this.container.downloadCenter.unsubscribe(this.listener);
  }

  private async reloadRules(): Promise<void> {
    this.rules = await this.container.downloadRules.listRules();
  }

  private activeRecords(): DownloadRecord[] {
    return this.allRecords.filter((r: DownloadRecord) => r.status !== DownloadStatus.COMPLETED);
  }

  private completedRecords(): DownloadRecord[] {
    return this.allRecords.filter((r: DownloadRecord) => r.status === DownloadStatus.COMPLETED);
  }

  private statusLabel(rec: DownloadRecord): string {
    if (rec.status === DownloadStatus.RUNNING) {
      const speed = rec.speedBytesPerSec > 0 ? ` · ${Fmt.bytes(rec.speedBytesPerSec)}/s` : '';
      return `下载中${speed}`;
    }
    if (rec.status === DownloadStatus.QUEUED) {
      return '排队中';
    }
    if (rec.status === DownloadStatus.WAITING_WIFI) {
      return '等待 Wi-Fi';
    }
    if (rec.status === DownloadStatus.PAUSED) {
      return '已暂停（支持断点续传）';
    }
    if (rec.status === DownloadStatus.COMPLETED) {
      return '已完成';
    }
    if (rec.status === DownloadStatus.CANCELLED) {
      return '已取消';
    }
    return `失败：${rec.errorMessage ?? '未知错误'}`;
  }

  private progressPercent(rec: DownloadRecord): number {
    if (rec.status === DownloadStatus.COMPLETED) {
      return 100;
    }
    if (rec.totalBytes <= 0) {
      return 0;
    }
    return Math.min(100, Math.floor((rec.downloadedBytes * 100) / rec.totalBytes));
  }

  private async exportRecord(rec: DownloadRecord): Promise<void> {
    const context = this.container.getContext();
    if (context === undefined || rec.targetUri === undefined) {
      return;
    }
    const saved = await DownloadExportHelper.exportFileWithPicker(context, rec.targetUri, rec.fileName);
    try {
      this.getUIContext().getPromptAction().showToast({
        message: saved !== undefined ? '文件已导出到系统目录' : '已取消或导出失败'
      });
    } catch (_e) {
      // ignore
    }
  }

  private async addRule(): Promise<void> {
    const name = this.newRuleName.trim();
    if (name.length === 0) {
      return;
    }
    const svc = this.newRuleService.trim().length > 0 ? this.newRuleService.trim().toLowerCase() : undefined;
    await this.container.downloadRules.addRule(name, svc, undefined, [MediaKind.IMAGE, MediaKind.VIDEO]);
    this.newRuleName = '';
    this.newRuleService = '';
    await this.reloadRules();
  }

  @Builder
  recordCard(rec: DownloadRecord) {
    AppCard({ cardPadding: 12 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(rec.fileName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(`${this.progressPercent(rec)}%`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.colors.primary)
        }
        .width('100%')

        Progress({ value: this.progressPercent(rec), total: 100, type: ProgressType.Linear })
          .width('100%')
          .color(rec.status === DownloadStatus.FAILED ? this.theme.colors.error : this.theme.colors.primary)

        Row() {
          Text(this.statusLabel(rec))
            .fontSize(11)
            .fontColor(rec.status === DownloadStatus.FAILED ? this.theme.colors.error : this.theme.colors.textSecondary)
            .layoutWeight(1)

          Text(
            rec.totalBytes > 0
              ? `${Fmt.bytes(rec.downloadedBytes)} / ${Fmt.bytes(rec.totalBytes)}`
              : Fmt.bytes(rec.downloadedBytes)
          )
            .fontSize(11)
            .fontColor(this.theme.colors.textTertiary)
        }
        .width('100%')

        Row({ space: 8 }) {
          if (rec.status === DownloadStatus.RUNNING || rec.status === DownloadStatus.QUEUED) {
            Button('暂停', { type: ButtonType.Normal })
              .height(30)
              .borderRadius(8)
              .fontSize(12)
              .fontColor(this.theme.colors.textPrimary)
              .backgroundColor(this.theme.colors.surfaceContainerHigh)
              .onClick(() => {
                this.container.downloadCenter.pause(rec.id);
              })
          } else if (
            rec.status === DownloadStatus.PAUSED ||
            rec.status === DownloadStatus.FAILED ||
            rec.status === DownloadStatus.WAITING_WIFI
          ) {
            Button(rec.status === DownloadStatus.FAILED ? '重试' : '继续', { type: ButtonType.Normal })
              .height(30)
              .borderRadius(8)
              .fontSize(12)
              .fontColor(this.theme.colors.onPrimary)
              .backgroundColor(this.theme.colors.primary)
              .onClick(() => {
                this.container.downloadCenter.resume(rec.id);
              })
          } else if (rec.status === DownloadStatus.COMPLETED) {
            Button('导出到文件管理', { type: ButtonType.Normal })
              .height(30)
              .borderRadius(8)
              .fontSize(12)
              .fontColor(this.theme.colors.onPrimary)
              .backgroundColor(this.theme.colors.primary)
              .onClick(() => {
                this.exportRecord(rec);
              })
          }

          Blank()

          Button({ type: ButtonType.Circle }) {
            AppIcon({ icon: $r('app.media.ic_delete'), iconSize: 15, tint: this.theme.colors.error })
          }
          .width(30)
          .height(30)
          .backgroundColor(this.theme.colors.surfaceContainer)
          .onClick(() => {
            this.container.downloadCenter.removeRecord(rec.id);
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '下载管理',
        subtitle: `并发上限 ${this.container.settings.getSnapshot().downloadConcurrency} · Range 断点续传`,
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Row({ space: 8 }) {
        ForEach(
          [`进行中 (${this.activeRecords().length})`, `已完成 (${this.completedRecords().length})`, `规则 (${this.rules.length})`],
          (label: string, idx: number) => {
            Text(label)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.activeTab === idx ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .borderRadius(10)
              .backgroundColor(this.activeTab === idx ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
              .onClick(() => {
                this.activeTab = idx;
              })
          },
          (label: string) => label
        )
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 8 })

      if (this.activeTab === 0) {
        if (this.activeRecords().length === 0) {
          AppEmptyState({
            title: '没有进行中的下载',
            message: '可在帖子详情页或媒体查看器点击下载附件。',
            icon: $r('app.media.ic_downloads')
          })
            .layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.activeRecords(), (rec: DownloadRecord) => {
              ListItem() {
                this.recordCard(rec)
              }
            }, (rec: DownloadRecord) => `${rec.id}_${rec.status}_${rec.downloadedBytes}`)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else if (this.activeTab === 1) {
        if (this.completedRecords().length === 0) {
          AppEmptyState({ title: '尚无已完成的下载', icon: $r('app.media.ic_folder') })
            .layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.completedRecords(), (rec: DownloadRecord) => {
              ListItem() {
                this.recordCard(rec)
              }
            }, (rec: DownloadRecord) => rec.id)
          }
          .padding({ left: 12, right: 12, bottom: 20 })
          .layoutWeight(1)
          .width('100%')
        }
      } else {
        Scroll() {
          Column({ space: 12 }) {
            AppCard() {
              Column({ space: 8 }) {
                Text('新建自动下载规则')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)
                TextInput({ text: this.newRuleName, placeholder: '规则名称（如：Patreon 图片与视频）' })
                  .width('100%')
                  .height(40)
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.newRuleName = v;
                  })
                TextInput({ text: this.newRuleService, placeholder: '限定平台（可选：patreon / fanbox，留空不限）' })
                  .width('100%')
                  .height(40)
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.newRuleService = v;
                  })
                AppButton({
                  label: '添加规则',
                  primary: true,
                  onAction: () => {
                    this.addRule();
                  }
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            ForEach(this.rules, (rule: DownloadRule) => {
              AppCard({ cardPadding: 12 }) {
                Row({ space: 10 }) {
                  Column({ space: 2 }) {
                    Text(rule.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.colors.textPrimary)
                    Text(`平台：${rule.service ?? '全部'} · 类型：${rule.mediaKinds.join(', ')}`)
                      .fontSize(11)
                      .fontColor(this.theme.colors.textSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
                    .selectedColor(this.theme.colors.primary)
                    .onChange((isOn: boolean) => {
                      this.container.downloadRules.toggleRule(rule.id, isOn).then(() => {
                        this.reloadRules();
                      });
                    })

                  Button({ type: ButtonType.Circle }) {
                    AppIcon({ icon: $r('app.media.ic_delete'), iconSize: 15, tint: this.theme.colors.error })
                  }
                  .width(30)
                  .height(30)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .onClick(() => {
                    this.container.downloadRules.deleteRule(rule.id).then(() => {
                      this.reloadRules();
                    });
                  })
                }
                .width('100%')
              }
            }, (rule: DownloadRule) => `${rule.id}_${rule.enabled}`)
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
