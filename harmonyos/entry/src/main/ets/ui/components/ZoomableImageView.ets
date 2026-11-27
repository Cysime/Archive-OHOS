import { image } from '@kit.ImageKit';
import { AppContainer } from '../../core/AppContainer';

/**
 * 沉浸式可缩放图片查看组件（优先加载原图，加载中/缺失时自动无感回退缩略图，支持双指缩放与双击还原）。
 */
@ComponentV2
export struct ZoomableImageView {
  @Param @Require originalUrl: string;
  @Param fallbackThumbUrl: string = '';
  @Event onPixelMapReady: (pm: image.PixelMap) => void = (_pm: image.PixelMap) => {};

  @Local pixelMap?: image.PixelMap = undefined;
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local usingFallback: boolean = false;
  @Local scaleFactor: number = 1;
  @Local baseScale: number = 1;
  @Local panX: number = 0;
  @Local panY: number = 0;

  private activeUrl: string = '';

  aboutToAppear(): void {
    this.loadBestImage();
  }

  @Monitor('originalUrl')
  onOriginalChanged(): void {
    this.scaleFactor = 1;
    this.baseScale = 1;
    this.panX = 0;
    this.panY = 0;
    this.loadBestImage();
  }

  private async loadBestImage(): Promise<void> {
    const target = this.originalUrl.trim();
    this.activeUrl = target;
    this.loading = true;
    this.failed = false;
    this.usingFallback = false;

    const loader = AppContainer.getInstance().imageLoader;
    // 先尝试快速展示已缓存缩略图，再无缝升级到原图
    if (this.fallbackThumbUrl.trim().length > 0) {
      const thumb = await loader.loadPixelMap(this.fallbackThumbUrl);
      if (this.activeUrl !== target) {
        return;
      }
      if (thumb !== undefined) {
        this.pixelMap = thumb;
        this.usingFallback = true;
      }
    }

    if (target.length > 0) {
      const orig = await loader.loadPixelMap(target);
      if (this.activeUrl !== target) {
        return;
      }
      if (orig !== undefined) {
        this.pixelMap = orig;
        this.usingFallback = false;
        this.loading = false;
        this.failed = false;
        this.onPixelMapReady(orig);
        return;
      }
    }

    this.loading = false;
    if (this.pixelMap !== undefined) {
      this.onPixelMapReady(this.pixelMap);
    } else {
      this.failed = true;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.scaleFactor, y: this.scaleFactor })
          .translate({ x: this.panX, y: this.panY })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.baseScale = this.scaleFactor;
                })
                .onActionUpdate((event: GestureEvent) => {
                  const next = this.baseScale * event.scale;
                  this.scaleFactor = Math.min(4.0, Math.max(1.0, next));
                  if (this.scaleFactor <= 1.01) {
                    this.panX = 0;
                    this.panY = 0;
                  }
                }),
              TapGesture({ count: 2 })
                .onAction(() => {
                  if (this.scaleFactor > 1.2) {
                    this.scaleFactor = 1.0;
                    this.panX = 0;
                    this.panY = 0;
                  } else {
                    this.scaleFactor = 2.2;
                  }
                })
            )
          )
      }

      if (this.loading && this.pixelMap === undefined) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color('#FFFFFFFF')
      }

      if (this.failed) {
        Text('原图加载失败')
          .fontSize(14)
          .fontColor('#CCFFFFFF')
      }

      if (this.usingFallback && this.loading) {
        Text('正在加载原图…')
          .fontSize(11)
          .fontColor('#FFFFFFFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor('#88000000')
          .position({ x: 16, y: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF000000')
  }
}
