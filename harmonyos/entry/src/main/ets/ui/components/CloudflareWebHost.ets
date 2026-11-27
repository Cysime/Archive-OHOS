import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../../core/AppContainer';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'CloudflareWebHost';

/**
 * 隐藏的 ArkWeb 宿主组件，用于在后台静默执行 Cloudflare Managed Challenge 并提取 cf_clearance。
 * 挂载在 ArchiveRoot 顶层（1vp x 1vp、不可交互、透明），不干扰前台页面。
 */
@ComponentV2
export struct CloudflareWebHost {
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private webReady: boolean = false;
  private pendingUrl: string = '';
  private pendingUa: string = '';

  aboutToAppear(): void {
    AppContainer.getInstance().cloudflare.registerWebChallengeHost((targetUrl: string, userAgent: string) => {
      this.startLoad(targetUrl, userAgent);
    });
  }

  aboutToDisappear(): void {
    AppContainer.getInstance().cloudflare.unregisterWebChallengeHost();
  }

  private startLoad(targetUrl: string, userAgent: string): void {
    if (!this.webReady) {
      this.pendingUrl = targetUrl;
      this.pendingUa = userAgent;
      return;
    }
    try {
      this.controller.setCustomUserAgent(userAgent);
      this.controller.loadUrl(targetUrl);
    } catch (e) {
      Logger.w(TAG, `loadUrl failed: ${String(e)}`);
    }
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(1)
      .height(1)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onControllerAttached(() => {
        this.webReady = true;
        if (this.pendingUrl.length > 0) {
          const url = this.pendingUrl;
          const ua = this.pendingUa;
          this.pendingUrl = '';
          this.pendingUa = '';
          this.startLoad(url, ua);
        }
      })
  }
}
