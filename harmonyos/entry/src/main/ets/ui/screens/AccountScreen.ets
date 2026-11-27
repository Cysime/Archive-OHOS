import { webview } from '@kit.ArkWeb';
import { UrlProvider } from '../../core/api/UrlProvider';
import { AppContainer } from '../../core/AppContainer';
import { AppError } from '../../core/error/AppError';
import { AccountSession, SessionManager } from '../../core/store/SessionManager';
import { Logger } from '../../core/util/Logger';
import { SessionValidity } from '../../data/repo/AuthRepository';
import { AppButton, AppCard, AppDivider, AppIcon, AppTopBar } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

const TAG: string = 'AccountScreen';

/**
 * 账号登录 / 注册 / 多账号管理页（对齐上游 ui/screens/AccountScreen.kt）。
 *
 * - 默认主入口：原生「账号密码登录」（直连 POST /account/login，不打开网页、彻底避免广告重定向）
 * - 注册新账号：内嵌白名单保护的 ArkWeb 加载 /account/register（拦截一切第三方广告跳转如 awhilepowershakily.com）
 * - 备选入口：「Cookie 登录（备选）」手动粘贴 session Cookie
 */
@ComponentV2
export struct AccountScreen {
  @Event onBack: () => void = () => {};

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly container: AppContainer = AppContainer.getInstance();
  private readonly registerWebController: webview.WebviewController = new webview.WebviewController();

  @Local activeMode: number = 0; // 0=账号密码登录, 1=注册新账号, 2=Cookie 备选
  @Local accounts: AccountSession[] = [];
  @Local activeUsername: string = '';
  @Local sessionValidity: SessionValidity = SessionValidity.UNKNOWN;

  // 账号密码表单
  @Local loginUsername: string = '';
  @Local loginPassword: string = '';
  @Local busy: boolean = false;

  // Cookie 备选表单
  @Local cookieAliasInput: string = '';
  @Local cookieInput: string = '';

  // 反馈提示
  @Local feedbackMsg: string = '';
  @Local feedbackError: boolean = false;
  @Local blockedRedirectHint: string = '';

  aboutToAppear(): void {
    this.reloadAccounts();
    this.probeSession();
  }

  private reloadAccounts(): void {
    this.accounts = this.container.authRepo.getAccounts();
    this.activeUsername = this.container.authRepo.getActiveAccount()?.username ?? '';
  }

  private async probeSession(): Promise<void> {
    if (!this.container.authRepo.isLoggedIn()) {
      this.sessionValidity = SessionValidity.INVALID;
      return;
    }
    this.sessionValidity = SessionValidity.CHECKING;
    this.sessionValidity = await this.container.authRepo.checkSessionValidity();
  }

  private sessionStatusText(): string {
    if (this.sessionValidity === SessionValidity.VALID) {
      return '已登录（会话有效）';
    }
    if (this.sessionValidity === SessionValidity.CHECKING) {
      return '正在检测会话状态…';
    }
    if (this.sessionValidity === SessionValidity.INVALID) {
      return '未登录或会话已失效';
    }
    return '状态未知（点击重新检测）';
  }

  private async submitPasswordLogin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.feedbackMsg = '';
    this.feedbackError = false;
    try {
      const user = await this.container.authRepo.loginWithPassword(this.loginUsername, this.loginPassword);
      this.loginPassword = '';
      this.feedbackError = false;
      this.feedbackMsg = `登录成功，欢迎回来 ${user}`;
      this.reloadAccounts();
      await this.probeSession();
    } catch (e) {
      this.feedbackError = true;
      this.feedbackMsg = AppError.friendlyMessage(e as Object);
    } finally {
      this.busy = false;
    }
  }

  private async submitCookieLogin(): Promise<void> {
    if (this.busy) {
      return;
    }
    const extracted = SessionManager.extractSessionCookie(this.cookieInput);
    if (extracted.length === 0) {
      this.feedbackError = true;
      this.feedbackMsg = '未检测到有效的 session Cookie，请粘贴完整 Cookie 或 session 值。';
      return;
    }
    this.busy = true;
    try {
      const name = this.cookieAliasInput.trim().length > 0
        ? this.cookieAliasInput.trim()
        : `账号 ${this.accounts.length + 1}`;
      const ok = await this.container.authRepo.loginWithCookie(name, extracted);
      if (ok) {
        this.cookieAliasInput = '';
        this.cookieInput = '';
        this.feedbackError = false;
        this.feedbackMsg = `已保存并切换至账号「${name}」`;
        this.reloadAccounts();
        await this.probeSession();
      } else {
        this.feedbackError = true;
        this.feedbackMsg = '保存会话失败，请重试。';
      }
    } finally {
      this.busy = false;
    }
  }

  private async tryImportRegisterWebSession(): Promise<void> {
    const baseUrl = this.container.apiClient.getBaseUrl();
    try {
      const raw = webview.WebCookieManager.fetchCookieSync(baseUrl);
      const imported = await this.container.authRepo.importSessionFromWebIfValid(raw, 'Pawchive 用户');
      if (imported) {
        this.feedbackError = false;
        this.feedbackMsg = '已自动从注册页导入有效登录会话';
        this.activeMode = 0;
        this.reloadAccounts();
        await this.probeSession();
      }
    } catch (_e) {
      // 未拿到有效登录态时静默等待用户完成操作
    }
  }

  private registerPageUrl(): string {
    return `${this.container.apiClient.getBaseUrl().replace(/\/+$/, '')}/account/register`;
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

      Scroll() {
        Column({ space: 14 }) {
          // 当前登录状态卡
          AppCard({ cardPadding: 14 }) {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.Center }) {
                Text((this.activeUsername.length > 0 ? this.activeUsername.substring(0, 1) : 'A').toUpperCase())
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.primary)
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor(this.theme.colors.secondaryContainer)

              Column({ space: 4 }) {
                Text(this.activeUsername.length > 0 ? this.activeUsername : '未登录')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)
                Row({ space: 6 }) {
                  Column()
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(
                      this.sessionValidity === SessionValidity.VALID
                        ? this.theme.colors.primary
                        : (this.sessionValidity === SessionValidity.INVALID
                          ? this.theme.colors.error
                          : this.theme.colors.textTertiary)
                    )
                  Text(`${this.sessionStatusText()} · 点击检测`)
                    .fontSize(12)
                    .fontColor(this.theme.colors.textSecondary)
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .onClick(() => {
              this.probeSession();
            })
          }

          if (this.feedbackMsg.length > 0) {
            Text(this.feedbackMsg)
              .fontSize(13)
              .fontColor(this.feedbackError ? this.theme.colors.error : this.theme.colors.primary)
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.theme.colors.surface)
              .width('100%')
          }

          // 三模式切换：账号密码登录（主） / 注册新账号 / Cookie（备选）
          Row({ space: 8 }) {
            ForEach(['账号密码登录', '注册新账号', 'Cookie (备选)'], (label: string, idx: number) => {
              Text(label)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.activeMode === idx ? this.theme.colors.onPrimary : this.theme.colors.textPrimary)
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .borderRadius(10)
                .backgroundColor(
                  this.activeMode === idx ? this.theme.colors.primary : this.theme.colors.surfaceContainerHigh
                )
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  this.activeMode = idx;
                  this.blockedRedirectHint = '';
                })
            }, (label: string) => label)
          }
          .width('100%')

          if (this.activeMode === 0) {
            AppCard() {
              Column({ space: 10 }) {
                Text('直接登录 Pawchive 账号')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)

                TextInput({ text: this.loginUsername, placeholder: '用户名' })
                  .width('100%')
                  .height(44)
                  .fontSize(14)
                  .fontColor(this.theme.colors.textPrimary)
                  .placeholderColor(this.theme.colors.textTertiary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.loginUsername = v;
                  })

                TextInput({ text: this.loginPassword, placeholder: '密码' })
                  .type(InputType.Password)
                  .width('100%')
                  .height(44)
                  .fontSize(14)
                  .fontColor(this.theme.colors.textPrimary)
                  .placeholderColor(this.theme.colors.textTertiary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.loginPassword = v;
                  })
                  .onSubmit(() => {
                    this.submitPasswordLogin();
                  })

                AppButton({
                  label: this.busy ? '正在登录…' : '登录',
                  primary: true,
                  disabled: this.busy || this.loginUsername.trim().length === 0 || this.loginPassword.length === 0,
                  onAction: () => {
                    this.submitPasswordLogin();
                  }
                })

                Text('直连站点登录表单提交，不加载网页第三方脚本；登录会话通过 HarmonyOS AssetStore 本地加密存储，多账号数据完全隔离。')
                  .fontSize(12)
                  .fontColor(this.theme.colors.textTertiary)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          } else if (this.activeMode === 1) {
            AppCard({ cardPadding: 10 }) {
              Column({ space: 8 }) {
                Text('站点注册需要完成人机验证码，已启用域名白名单保护并自动拦截第三方广告跳转。')
                  .fontSize(12)
                  .fontColor(this.theme.colors.textSecondary)

                if (this.blockedRedirectHint.length > 0) {
                  Text(this.blockedRedirectHint)
                    .fontSize(11)
                    .fontColor(this.theme.colors.primary)
                }

                Web({
                  src: this.registerPageUrl(),
                  controller: this.registerWebController
                })
                  .width('100%')
                  .height(420)
                  .borderRadius(12)
                  .javaScriptAccess(true)
                  .domStorageAccess(true)
                  .multiWindowAccess(false)
                  .allowWindowOpenMethod(false)
                  .onControllerAttached(() => {
                    try {
                      this.registerWebController.setCustomUserAgent(this.container.cloudflare.getUserAgent());
                      const cf = this.container.cloudflare.getClearance();
                      if (cf !== undefined && cf.cookie.length > 0) {
                        webview.WebCookieManager.configCookieSync(this.registerPageUrl(), cf.cookie);
                      }
                    } catch (e) {
                      Logger.w(TAG, `register web init failed: ${String(e)}`);
                    }
                  })
                  .onLoadIntercept((event) => {
                    const reqUrl = event.data.getRequestUrl();
                    const baseUrl = this.container.apiClient.getBaseUrl();
                    const allowed = UrlProvider.isAllowedWebViewUrl(reqUrl, baseUrl);
                    if (!allowed) {
                      Logger.w(TAG, `Blocked third-party ad redirect: ${reqUrl}`);
                      this.blockedRedirectHint = `已拦截第三方广告跳转：${UrlProvider.extractHost(reqUrl)}`;
                    }
                    return !allowed;
                  })
                  .onPageEnd(() => {
                    this.tryImportRegisterWebSession();
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          } else {
            AppCard() {
              Column({ space: 10 }) {
                Text('手动导入 Session Cookie（备选方案）')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.colors.textPrimary)

                Text('当账号密码登录受限或需导入浏览器已有会话时，可粘贴含 session= 的 Cookie。')
                  .fontSize(12)
                  .fontColor(this.theme.colors.textSecondary)

                TextInput({ text: this.cookieAliasInput, placeholder: '账号备注名称（例如：主号）' })
                  .width('100%')
                  .height(42)
                  .fontSize(14)
                  .fontColor(this.theme.colors.textPrimary)
                  .placeholderColor(this.theme.colors.textTertiary)
                  .backgroundColor(this.theme.colors.surfaceContainer)
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.cookieAliasInput = v;
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
                  label: '保存并启用该 Cookie 会话',
                  primary: true,
                  disabled: this.busy,
                  onAction: () => {
                    this.submitCookieLogin();
                  }
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }

          // 已保存的多账号列表
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
                      Text('会话凭据已本地加密存储')
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
                            this.probeSession();
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
                        this.probeSession();
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
        .padding({ left: 14, right: 14, top: 4, bottom: 24 + this.theme.bottomSafeVp })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.colors.background)
  }
}
