import { image } from '@kit.ImageKit';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { AiMessage } from '../../data/ai/AiProtocol';
import { AppButton, AppIcon } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 媒体查看器内置的端上 OCR（CoreVisionKit）与 AI 识图问答底部面板。
 */
@ComponentV2
export struct AiImageSheet {
  @Param @Require visible: boolean;
  @Param @Require cacheKey: string;
  @Param pixelMap?: image.PixelMap = undefined;
  @Event onDismiss: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local activeTab: number = 0; // 0=端上 OCR, 1=AI 识图
  @Local ocrLoading: boolean = false;
  @Local ocrText: string = '';
  @Local ocrError: string = '';

  @Local visionLoading: boolean = false;
  @Local visionAnswer: string = '';
  @Local visionError: string = '';
  @Local questionInput: string = '';
  private visionHistory: AiMessage[] = [];

  @Monitor('visible')
  onVisibleChanged(): void {
    if (this.visible && this.activeTab === 0 && this.ocrText.length === 0 && this.pixelMap !== undefined) {
      this.runOcr();
    }
  }

  private async runOcr(): Promise<void> {
    if (this.pixelMap === undefined || this.ocrLoading) {
      return;
    }
    this.ocrLoading = true;
    this.ocrError = '';
    try {
      const res = await this.container.ocrService.recognize(this.pixelMap);
      this.ocrText = res.fullText.length > 0 ? res.fullText : '未在图片中识别到文字';
    } catch (e) {
      this.ocrError = AppError.friendlyMessage(e as Object);
    } finally {
      this.ocrLoading = false;
    }
  }

  private async runVision(customQuestion: string = ''): Promise<void> {
    if (this.pixelMap === undefined || this.visionLoading) {
      return;
    }
    this.visionLoading = true;
    this.visionError = '';
    try {
      const ans = await this.container.visionClient.askImage(
        this.cacheKey,
        this.pixelMap,
        customQuestion,
        this.visionHistory
      );
      if (customQuestion.trim().length > 0) {
        this.visionHistory.push({ fromUser: true, text: customQuestion.trim() });
        this.visionHistory.push({ fromUser: false, text: ans });
        this.questionInput = '';
      }
      this.visionAnswer = ans;
    } catch (e) {
      this.visionError = AppError.friendlyMessage(e as Object);
    } finally {
      this.visionLoading = false;
    }
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#77000000')
          .onClick(() => {
            this.onDismiss();
          })

        Column({ space: 12 }) {
          Row() {
            Row({ space: 8 }) {
              Text('端上 OCR')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.activeTab === 0 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(10)
                .backgroundColor(this.activeTab === 0 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
                .onClick(() => {
                  this.activeTab = 0;
                  if (this.ocrText.length === 0) {
                    this.runOcr();
                  }
                })

              Text('AI 识图')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.activeTab === 1 ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(10)
                .backgroundColor(this.activeTab === 1 ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh)
                .onClick(() => {
                  this.activeTab = 1;
                  if (this.visionAnswer.length === 0) {
                    this.runVision('');
                  }
                })
            }
            .layoutWeight(1)

            Button({ type: ButtonType.Circle }) {
              AppIcon({ icon: $r('app.media.ic_close'), iconSize: 16, tint: this.theme.colors.textSecondary })
            }
            .width(32)
            .height(32)
            .backgroundColor(this.theme.colors.surfaceContainerHigh)
            .onClick(() => {
              this.onDismiss();
            })
          }
          .width('100%')

          if (this.activeTab === 0) {
            if (this.ocrLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(20).height(20).color(this.theme.colors.primary)
                Text('正在调用 CoreVisionKit 离线识别文字…')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textSecondary)
              }
              .padding(16)
            } else if (this.ocrError.length > 0) {
              Text(this.ocrError)
                .fontSize(13)
                .fontColor(this.theme.colors.error)
                .width('100%')
            } else {
              Scroll() {
                Text(this.ocrText)
                  .fontSize(14)
                  .lineHeight(22)
                  .fontColor(this.theme.colors.textPrimary)
                  .copyOption(CopyOptions.LocalDevice)
                  .width('100%')
              }
              .constraintSize({ maxHeight: 240 })
              .width('100%')

              AppButton({
                label: '重新识别',
                primary: false,
                onAction: () => {
                  this.runOcr();
                }
              })
            }
          } else {
            if (this.visionLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(20).height(20).color(this.theme.colors.primary)
                Text('正在调用 AI 模型解析图片…')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textSecondary)
              }
              .padding(16)
            } else if (this.visionError.length > 0) {
              Text(this.visionError)
                .fontSize(13)
                .fontColor(this.theme.colors.error)
                .width('100%')
            } else if (this.visionAnswer.length > 0) {
              Scroll() {
                Text(this.visionAnswer)
                  .fontSize(14)
                  .lineHeight(22)
                  .fontColor(this.theme.colors.textPrimary)
                  .copyOption(CopyOptions.LocalDevice)
                  .width('100%')
              }
              .constraintSize({ maxHeight: 220 })
              .width('100%')
            }

            Row({ space: 8 }) {
              TextInput({ text: this.questionInput, placeholder: '针对这张图继续提问…' })
                .layoutWeight(1)
                .height(40)
                .fontSize(13)
                .fontColor(this.theme.colors.textPrimary)
                .backgroundColor(this.theme.colors.surfaceContainer)
                .borderRadius(10)
                .onChange((v: string) => {
                  this.questionInput = v;
                })
              AppButton({
                label: '发送',
                primary: true,
                fullWidth: false,
                disabled: this.visionLoading,
                onAction: () => {
                  this.runVision(this.questionInput);
                }
              })
                .width(72)
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 24 })
        .borderRadius({ topLeft: 20, topRight: 20 })
        .backgroundColor(this.theme.colors.surface)
      }
      .width('100%')
      .height('100%')
    }
  }
}
