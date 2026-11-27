import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../../core/AppContainer';
import { AccountSession, SessionManager } from '../../core/store/SessionManager';
import { AppButton, AppCard, AppDivider, AppIcon, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 账号与多账号切换页（对齐上游 ui/screens/AccountScreen.kt）。
 *
 * - 支持粘贴 Pawchive `session` Cookie（自动按分号拆段精准提取 `session=`）
 * - 支持内置 ArkWeb 打开网页登录并一键提取登录后的 `session=` Cookie
 * - 多账号独立保存、一键切换、删除与登出
 */
@ComponentV2
export struct AccountScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();
  private readonly webController: webview.WebviewController = new webview.WebviewController();

  @Local accounts: AccountSession[] = [];
  @Local activeUsername: string = '';
  @Local usernameInput: string = '';
  @Local cookieInput: string = '';
  @Local feedbackMsg: string = '';
  @Local feedbackError: boolean = false;
  @Local webLoginVisible: boolean = false;

  aboutToAppear(): void {
    this.reloadAccounts();
  }

  private reloadAccounts(): void {
    this.accounts = this.container.authRepo.getAccounts();
    this.activeUsername = this.container.authRepo.getActiveAccount()?.username ?? '';
  }

  private async saveCookieAccount(): Promise<void> {
    const extracted = SessionManager.extractSessionCookie(this.cookieInput);
    if (extracted.length === 0) {
      this.feedbackError = true;
      this.feedbackMsg = '未检测到有效的 session Cookie，请粘贴完整 Cookie 或 session 值。';
      return;
    }
    const name = this.usernameInput.trim().length > 0 ? this.usernameInput.trim() : `账号 ${this.accounts.length + 1}`;
    const ok = await this.container.authRepo.loginWithCookie(name, extracted);
    if (ok) {
      this.usernameInput = '';
      this.cookieInput = '';
      this.feedbackError = false;
      this.feedbackMsg = `已保存并切换至账号「${name}」`;
      this.reloadAccounts();
    } else {
      this.feedbackError = true;
      this.feedbackMsg = '保存会话失败，请重试。';
    }
  }

  private captureWebSessionCookie(): void {
    const baseUrl = this.container.apiClient.getBaseUrl();
    try {
      const raw = webview.WebCookieManager.fetchCookieSync(baseUrl);
      const extracted = SessionManager.extractSessionCookie(raw);
      if (extracted.length === 0) {
        this.feedbackError = true;
        this.feedbackMsg = '当前网页尚未检测到 session Cookie，请先完成登录再点击提取。';
        return;
      }
      this.cookieInput = extracted;
      this.webLoginVisible = false;
      this.feedbackError = false;
      this.feedbackMsg = '已自动提取网页登录 session，请填写备注昵称后点击保存。';
    } catch (e) {
      this.feedbackError = true;
      this.feedbackMsg = `提取 Cookie 失败：${String(e)}`;
    }
  }

  build() {
    Column() {
      AppTopBar({
        title: '账号管理',
        subtitle: this.activeUsername.length > 0 ? `当前账号：${this.activeUsername}` : '游客模式',
        showBack: true,
        onBack: () => {
          this.onBack();
        }
      })

      if (this.webLoginVisible) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            AppButton({
              label: '登录完成后提取 Session',
              primary: true,
              fullWidth: false,
              onAction: () => {
                this.captureWebSessionCookie();
              }
            })
              .layoutWeight(1)
            AppButton({
              label: '关闭',
              primary: false,
              fullWidth: false,
              onAction: () => {
                this.webLoginVisible = false;
              }
            })
              .width(84)
          }
          .width('100%')
          .padding({ left: 12, right: 12 })

          Web({
            src: `${this.container.apiClient.getBaseUrl()}/account/login`,
            controller: this.webController
          })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .layoutWeight(1)
            .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Scroll() {
          Column({ space: 14 }) {
            if (this.feedbackMsg.length > 0) {
              Text(this.feedbackMsg)
                .fontSize(13)
                .fontColor(this.feedbackError ? this.theme.colors.error : this.theme.colors.primary)
                .padding(12)
                .borderRadius(12)
                .backgroundColor(this.theme.colors.surface)
                .width('100%')
            }

            AppCard() {
              Column({ space: 10 }) {
                Text('添加 / 更新 Pawchive 账号')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)

                Text('Pawchive 站点使用 Cookie 会话鉴权（cookie 名为 session）。你可以直接粘贴浏览器 Cookie，或打开内置网页登录后自动提取。')
                  .fontSize(12)
                  .fontColor(this.theme.colors.textSecondary)

                TextInput({ text: this.usernameInput, placeholder: '账号备注名称（例如：主号）' })
                  .width('100%')
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.theme.colors.textPrimary)
                  .placeholderColor(this.theme.colors.textTertiary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.usernameInput = v;
                  })

                TextArea({ text: this.cookieInput, placeholder: '粘贴完整 Cookie 头或 session 值…' })
                  .width('100%')
                  .height(92)
                  .fontSize(13)
                  .fontColor(this.theme.colors.textPrimary)
                  .placeholderColor(this.theme.colors.textTertiary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.cookieInput = v;
                  })

                AppButton({
                  label: '保存并启用该账号',
                  primary: true,
                  onAction: () => {
                    this.saveCookieAccount();
                  }
                })

                AppButton({
                  label: '打开内置网页登录并提取 Session',
                  primary: false,
                  onAction: () => {
                    this.webLoginVisible = true;
                  }
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            AppCard() {
              Column({ space: 10 }) {
                Text(`已保存账号 (${this.accounts.length})`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)

                if (this.accounts.length === 0) {
                  Text('尚未保存任何账号')
                    .fontSize(13)
                    .fontColor(this.theme.colors.textTertiary)
                } else {
                  ForEach(this.accounts, (acc: AccountSession, idx: number) => {
                    if (idx > 0) {
                      AppDivider()
                    }
                    Row({ space: 10 }) {
                      Column({ space: 2 }) {
                        Row({ space: 6 }) {
                          Text(acc.username)
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(this.theme.colors.textPrimary)
                          if (acc.username === this.activeUsername) {
                            Text('当前')
                              .fontSize(10)
                              .fontColor(this.theme.colors.onPrimary)
                              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                              .borderRadius(6)
                              .backgroundColor(this.theme.colors.primary)
                          }
                        }
                        Text('会话凭据已安全存储（AssetStore）')
                          .fontSize(11)
                          .fontColor(this.theme.colors.textTertiary)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      if (acc.username !== this.activeUsername) {
                        Button('切换', { type: ButtonType.Normal })
                          .height(32)
                          .borderRadius(8)
                          .fontSize(12)
                          .fontColor(this.theme.colors.primary)
                          .backgroundColor(this.theme.colors.secondaryContainer)
                          .onClick(() => {
                            this.container.authRepo.switchAccount(acc.username).then(() => {
                              this.reloadAccounts();
                            });
                          })
                      }

                      Button({ type: ButtonType.Circle }) {
                        AppIcon({ icon: $r('app.media.ic_delete'), iconSize: 16, tint: this.theme.colors.error })
                      }
                      .width(32)
                      .height(32)
                      .backgroundColor(this.theme.colors.surfaceContainer)
                      .onClick(() => {
                        this.container.authRepo.removeAccount(acc.username).then(() => {
                          this.reloadAccounts();
                        });
                      })
                    }
                    .width('100%')
                    .padding({ top: 6, bottom: 6 })
                  }, (acc: AccountSession) => acc.username)
                }
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
