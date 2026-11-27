import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { AiPurpose, ApiType, ApiTypeHelper, ModelProfile } from '../../data/ai/ModelProfile';
import { AppButton, AppCard, AppDivider, AppIcon, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * AI 翻译与识图设置页（对齐上游 ui/screens/TranslationSettingsScreen.kt）。
 *
 * - 多供应商档案管理（OpenAI Chat / OpenAI Responses / Anthropic / Gemini）
 * - 用途指派（翻译档案 vs 识图档案）
 * - 深度思考与联网搜索开关（默认关闭不下发）+ 连通性测试
 */
@ComponentV2
export struct TranslationSettingsScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();

  @Local profiles: ModelProfile[] = [];
  @Local translationProfileId: string = '';
  @Local visionProfileId: string = '';
  @Local targetLanguage: string = '简体中文';

  // 新建/编辑表单状态
  @Local editingId: string = '';
  @Local nameInput: string = '';
  @Local apiTypeInput: ApiType = ApiType.CHAT_COMPLETION;
  @Local urlInput: string = ApiTypeHelper.urlHint(ApiType.CHAT_COMPLETION);
  @Local modelInput: string = '';
  @Local apiKeyInput: string = '';
  @Local enableThinking: boolean = false;
  @Local enableWebSearch: boolean = false;

  @Local testing: boolean = false;
  @Local feedbackMsg: string = '';
  @Local feedbackError: boolean = false;

  aboutToAppear(): void {
    this.reloadState();
  }

  private reloadState(): void {
    const snap = this.container.aiSettings.getSnapshot();
    this.profiles = snap.profiles.slice();
    this.translationProfileId = snap.translationProfileId;
    this.visionProfileId = snap.visionProfileId;
    this.targetLanguage = snap.targetLanguage;
  }

  private resetForm(): void {
    this.editingId = '';
    this.nameInput = '';
    this.apiTypeInput = ApiType.CHAT_COMPLETION;
    this.urlInput = ApiTypeHelper.urlHint(ApiType.CHAT_COMPLETION);
    this.modelInput = '';
    this.apiKeyInput = '';
    this.enableThinking = false;
    this.enableWebSearch = false;
  }

  private async loadProfileIntoForm(profile: ModelProfile): Promise<void> {
    this.editingId = profile.id;
    this.nameInput = profile.name;
    this.apiTypeInput = profile.apiType;
    this.urlInput = profile.url;
    this.modelInput = profile.model;
    this.enableThinking = profile.enableThinking;
    this.enableWebSearch = profile.enableWebSearch;
    this.apiKeyInput = await this.container.aiSettings.getApiKey(profile.id);
  }

  private buildDraftProfile(): ModelProfile {
    const id = this.editingId.length > 0 ? this.editingId : `prof_${Date.now()}`;
    return {
      id: id,
      name: this.nameInput.trim().length > 0 ? this.nameInput.trim() : `${ApiTypeHelper.label(this.apiTypeInput)}`,
      apiType: this.apiTypeInput,
      url: this.urlInput.trim(),
      model: this.modelInput.trim(),
      enableThinking: this.enableThinking,
      enableWebSearch: this.enableWebSearch
    };
  }

  private async saveProfile(): Promise<void> {
    if (this.urlInput.trim().length === 0 || this.modelInput.trim().length === 0) {
      this.feedbackError = true;
      this.feedbackMsg = '请填写接口 URL 与模型名称。';
      return;
    }
    const draft = this.buildDraftProfile();
    await this.container.aiSettings.upsertProfile(draft, this.apiKeyInput);
    this.reloadState();
    this.resetForm();
    this.feedbackError = false;
    this.feedbackMsg = `已保存模型档案「${draft.name}」`;
  }

  private async testDraft(): Promise<void> {
    if (this.testing) {
      return;
    }
    const draft = this.buildDraftProfile();
    this.testing = true;
    this.feedbackError = false;
    this.feedbackMsg = '正在测试接口连通性…';
    try {
      const msg = await this.container.aiCaller.testConnectivity(draft, this.apiKeyInput);
      this.feedbackError = false;
      this.feedbackMsg = msg;
    } catch (e) {
      this.feedbackError = true;
      this.feedbackMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.testing = false;
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: 'AI 翻译与识图设置',
        subtitle: 'API Key 由 AssetStore 加密存储',
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          if (this.feedbackMsg.length > 0) {
            Text(this.feedbackMsg)
              .fontSize(12)
              .fontColor(this.feedbackError ? this.theme.colors.error : this.theme.colors.primary)
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.theme.colors.surface)
              .width('100%')
          }

          AppCard() {
            Column({ space: 10 }) {
              Text('翻译目标语言')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Row({ space: 6 }) {
                ForEach(['简体中文', '繁體中文', 'English', '日本語'], (lang: string) => {
                  Text(lang)
                    .fontSize(12)
                    .fontColor(this.targetLanguage === lang ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .borderRadius(10)
                    .backgroundColor(
                      this.targetLanguage === lang ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                    )
                    .onClick(() => {
                      this.targetLanguage = lang;
                      this.container.aiSettings.setTargetLanguage(lang);
                    })
                }, (lang: string) => lang)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          AppCard() {
            Column({ space: 10 }) {
              Text(this.editingId.length > 0 ? '编辑模型档案' : '新增模型档案')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              Row({ space: 6 }) {
                ForEach(
                  [ApiType.CHAT_COMPLETION, ApiType.RESPONSES, ApiType.ANTHROPIC, ApiType.GEMINI],
                  (t: ApiType) => {
                    Text(
                      t === ApiType.CHAT_COMPLETION
                        ? 'Chat'
                        : (t === ApiType.RESPONSES ? 'Responses' : (t === ApiType.ANTHROPIC ? 'Anthropic' : 'Gemini'))
                    )
                      .fontSize(12)
                      .fontColor(this.apiTypeInput === t ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(10)
                      .backgroundColor(
                        this.apiTypeInput === t ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                      )
                      .onClick(() => {
                        this.apiTypeInput = t;
                        if (this.editingId.length === 0) {
                          this.urlInput = ApiTypeHelper.urlHint(t);
                        }
                      })
                  },
                  (t: ApiType) => t
                )
              }

              TextInput({ text: this.nameInput, placeholder: '档案备注名（例如：DeepSeek / Claude / Gemini）' })
                .width('100%')
                .height(40)
                .fontSize(13)
                .fontColor(this.theme.colors.textPrimary)
                .backgroundColor(this.theme.colors.surfaceContainer)
                .borderRadius(10)
                .onChange((v: string) => {
                  this.nameInput = v;
                })

              TextInput({ text: this.urlInput, placeholder: ApiTypeHelper.urlHint(this.apiTypeInput) })
                .width('100%')
                .height(40)
                .fontSize(13)
                .fontColor(this.theme.colors.textPrimary)
                .backgroundColor(this.theme.colors.surfaceContainer)
                .borderRadius(10)
                .onChange((v: string) => {
                  this.urlInput = v;
                })

              TextInput({ text: this.modelInput, placeholder: '模型 ID（如 gpt-4o-mini / gemini-2.5-flash）' })
                .width('100%')
                .height(40)
                .fontSize(13)
                .fontColor(this.theme.colors.textPrimary)
                .backgroundColor(this.theme.colors.surfaceContainer)
                .borderRadius(10)
                .onChange((v: string) => {
                  this.modelInput = v;
                })

              TextInput({ text: this.apiKeyInput, placeholder: 'API Key（本地加密保存）' })
                .type(InputType.Password)
                .width('100%')
                .height(40)
                .fontSize(13)
                .fontColor(this.theme.colors.textPrimary)
                .backgroundColor(this.theme.colors.surfaceContainer)
                .borderRadius(10)
                .onChange((v: string) => {
                  this.apiKeyInput = v;
                })

              Row() {
                Text('深度思考（默认关）')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.enableThinking })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((v: boolean) => {
                    this.enableThinking = v;
                  })
              }
              .width('100%')

              Row() {
                Text('联网搜索（默认关）')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.enableWebSearch })
                  .selectedColor(this.theme.colors.primary)
                  .onChange((v: boolean) => {
                    this.enableWebSearch = v;
                  })
              }
              .width('100%')

              Row({ space: 8 }) {
                AppButton({
                  label: this.testing ? '测试中…' : '测试连通性',
                  primary: false,
                  fullWidth: false,
                  disabled: this.testing,
                  onAction: () => {
                    this.testDraft();
                  }
                })
                  .layoutWeight(1)

                AppButton({
                  label: '保存档案',
                  primary: true,
                  fullWidth: false,
                  onAction: () => {
                    this.saveProfile();
                  }
                })
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          AppCard() {
            Column({ space: 10 }) {
              Text(`已保存档案与用途指派 (${this.profiles.length})`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.colors.textPrimary)

              if (this.profiles.length === 0) {
                Text('尚未添加任何 AI 模型档案')
                  .fontSize(13)
                  .fontColor(this.theme.colors.textTertiary)
              } else {
                ForEach(this.profiles, (prof: ModelProfile, idx: number) => {
                  if (idx > 0) {
                    AppDivider()
                  }
                  Column({ space: 6 }) {
                    Row() {
                      Column({ space: 2 }) {
                        Text(prof.name)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.theme.colors.textPrimary)
                        Text(`${ApiTypeHelper.label(prof.apiType)} · ${prof.model}`)
                          .fontSize(11)
                          .fontColor(this.theme.colors.textSecondary)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      Button('编辑', { type: ButtonType.Normal })
                        .height(28)
                        .borderRadius(8)
                        .fontSize(11)
                        .fontColor(this.theme.colors.textPrimary)
                        .backgroundColor(this.theme.colors.surfaceContainerHigh)
                        .onClick(() => {
                          this.loadProfileIntoForm(prof);
                        })

                      Button({ type: ButtonType.Circle }) {
                        AppIcon({ icon: $r('app.media.ic_delete'), iconSize: 15, tint: this.theme.colors.error })
                      }
                      .width(28)
                      .height(28)
                      .margin({ left: 6 })
                      .backgroundColor(this.theme.colors.surfaceContainer)
                      .onClick(() => {
                        this.container.aiSettings.deleteProfile(prof.id).then(() => {
                          this.reloadState();
                        });
                      })
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Text(this.translationProfileId === prof.id ? '✓ 用于翻译' : '设为翻译档案')
                        .fontSize(11)
                        .fontColor(
                          this.translationProfileId === prof.id
                            ? this.theme.colors.onPrimary
                            : this.theme.colors.primary
                        )
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(8)
                        .backgroundColor(
                          this.translationProfileId === prof.id
                            ? this.theme.colors.primary
                            : this.theme.colors.secondaryContainer
                        )
                        .onClick(() => {
                          this.container.aiSettings.assignPurpose(AiPurpose.TRANSLATION, prof.id).then(() => {
                            this.reloadState();
                          });
                        })

                      Text(this.visionProfileId === prof.id ? '✓ 用于识图' : '设为识图档案')
                        .fontSize(11)
                        .fontColor(
                          this.visionProfileId === prof.id
                            ? this.theme.colors.onPrimary
                            : this.theme.colors.primary
                        )
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(8)
                        .backgroundColor(
                          this.visionProfileId === prof.id
                            ? this.theme.colors.primary
                            : this.theme.colors.secondaryContainer
                        )
                        .onClick(() => {
                          this.container.aiSettings.assignPurpose(AiPurpose.VISION, prof.id).then(() => {
                            this.reloadState();
                          });
                        })
                    }
                  }
                  .width('100%')
                  .padding({ top: 4, bottom: 4 })
                }, (prof: ModelProfile) => `${prof.id}_${this.translationProfileId}_${this.visionProfileId}`)
              }
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
