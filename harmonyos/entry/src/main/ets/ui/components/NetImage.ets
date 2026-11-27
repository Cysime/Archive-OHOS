import { image } from '@kit.ImageKit';
import { AppContainer } from '../../core/AppContainer';
import { ArchiveThemeController } from '../theme/PurrColors';

/**
 * 站点专用网络图片组件：
 * - 统一走 `ArchiveImageLoader`（携带自定义 UA + cf_clearance + session Cookie，防止 img/file 403）
 * - 支持「缩略图模糊」隐私模式（开启时默认高斯模糊，点击单张切换显示/隐藏）
 */
@ComponentV2
export struct NetImage {
  @Param @Require url: string;
  @Param fit: ImageFit = ImageFit.Cover;
  @Param imgRadius: number = 0;
  @Param allowBlur: boolean = false;

  @Local pixelMap?: image.PixelMap = undefined;
  @Local loading: boolean = false;
  @Local failed: boolean = false;
  @Local revealed: boolean = false;

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private loadedUrl: string = '';

  aboutToAppear(): void {
    this.triggerLoad();
  }

  @Monitor('url')
  onUrlChanged(): void {
    this.revealed = false;
    this.triggerLoad();
  }

  private triggerLoad(): void {
    const target = this.url.trim();
    if (target.length === 0) {
      this.pixelMap = undefined;
      this.loading = false;
      this.failed = false;
      this.loadedUrl = '';
      return;
    }
    if (target === this.loadedUrl && this.pixelMap !== undefined) {
      return;
    }
    this.loadedUrl = target;
    this.loading = true;
    this.failed = false;
    AppContainer.getInstance().imageLoader.loadPixelMap(target).then((pm?: image.PixelMap) => {
      if (this.loadedUrl !== target) {
        return;
      }
      this.loading = false;
      if (pm !== undefined) {
        this.pixelMap = pm;
        this.failed = false;
      } else {
        this.pixelMap = undefined;
        this.failed = true;
      }
    }).catch(() => {
      if (this.loadedUrl === target) {
        this.loading = false;
        this.failed = true;
      }
    });
  }

  private isBlurred(): boolean {
    return this.allowBlur && this.theme.blurThumbnails && !this.revealed;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .blur(this.isBlurred() ? 22 : 0)
      } else if (this.loading) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(this.theme.colors.textTertiary)
      } else if (this.failed) {
        Text('图片加载失败')
          .fontSize(11)
          .fontColor(this.theme.colors.textTertiary)
      }

      if (this.pixelMap !== undefined && this.isBlurred()) {
        Text('点击显示缩略图')
          .fontSize(11)
          .fontColor('#FFFFFFFF')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(10)
          .backgroundColor('#88000000')
          .onClick(() => {
            this.revealed = true;
          })
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.imgRadius)
    .clip(true)
    .backgroundColor(this.theme.colors.surfaceContainer)
  }
}
