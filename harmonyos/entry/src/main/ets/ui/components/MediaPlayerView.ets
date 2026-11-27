import { media } from '@kit.MediaKit';
import { AppContainer } from '../../core/AppContainer';
import { Logger } from '../../core/util/Logger';
import { AppIcon } from '../design/AppComponents';
import { ArchiveThemeController } from '../theme/PurrColors';

const TAG: string = 'MediaPlayerView';

/**
 * 原生音视频播放器（基于 `@kit.MediaKit` AVPlayer + XComponent）。
 *
 * 通过 `media.createMediaSourceWithUrl(url, headers)` 注入应用专属 UA 与 Cookie，
 * 支持播放 `t1.pawchive.pw` 签名 HLS（master.m3u8）以及 `file.pawchive.pw` MP4 / 音频附件。
 */
@ComponentV2
export struct MediaPlayerView {
  @Param @Require url: string;
  @Param isAudioOnly: boolean = false;
  @Param title: string = '';

  private readonly theme: ArchiveThemeController = ArchiveThemeController.getInstance();
  private readonly xComponentController: XComponentController = new XComponentController();

  @Local isPlaying: boolean = false;
  @Local isBuffering: boolean = true;
  @Local durationMs: number = 0;
  @Local currentMs: number = 0;
  @Local errorMsg: string = '';

  private avPlayer?: media.AVPlayer;
  private surfaceId: string = '';
  private released: boolean = false;

  aboutToAppear(): void {
    if (this.isAudioOnly) {
      this.initPlayer();
    }
  }

  aboutToDisappear(): void {
    this.released = true;
    this.releasePlayer();
  }

  private async initPlayer(): Promise<void> {
    if (this.released || this.url.trim().length === 0) {
      return;
    }
    await this.releasePlayer();
    this.isBuffering = true;
    this.errorMsg = '';
    try {
      const player = await media.createAVPlayer();
      if (this.released) {
        await player.release();
        return;
      }
      this.avPlayer = player;
      this.bindCallbacks(player);

      const headers = AppContainer.getInstance().apiClient.buildSiteHeaders(this.url);
      const source = media.createMediaSourceWithUrl(this.url, headers);
      await player.setMediaSource(source);
    } catch (e) {
      this.isBuffering = false;
      this.errorMsg = `播放器初始化失败：${String(e)}`;
      Logger.w(TAG, `initPlayer failed: ${String(e)}`);
    }
  }

  private bindCallbacks(player: media.AVPlayer): void {
    player.on('stateChange', (state: string) => {
      if (this.released) {
        return;
      }
      if (state === 'initialized') {
        if (!this.isAudioOnly && this.surfaceId.length > 0) {
          player.surfaceId = this.surfaceId;
        }
        player.prepare().catch((e: Object) => {
          this.errorMsg = `准备播放失败：${String(e)}`;
        });
      } else if (state === 'prepared') {
        this.isBuffering = false;
        this.durationMs = Math.max(0, player.duration);
        player.play().catch((e: Object) => {
          Logger.w(TAG, `play failed: ${String(e)}`);
        });
      } else if (state === 'playing') {
        this.isPlaying = true;
        this.isBuffering = false;
      } else if (state === 'paused' || state === 'completed') {
        this.isPlaying = false;
      }
    });

    player.on('durationUpdate', (duration: number) => {
      this.durationMs = Math.max(0, duration);
    });

    player.on('timeUpdate', (time: number) => {
      this.currentMs = Math.max(0, time);
    });

    player.on('error', (err) => {
      this.isBuffering = false;
      this.isPlaying = false;
      this.errorMsg = `播放错误 (${err.code}): ${err.message}`;
      Logger.w(TAG, `AVPlayer error: ${err.code} ${err.message}`);
    });
  }

  private async releasePlayer(): Promise<void> {
    if (this.avPlayer !== undefined) {
      const p = this.avPlayer;
      this.avPlayer = undefined;
      try {
        await p.reset();
      } catch (_e) {
        // ignore
      }
      try {
        await p.release();
      } catch (_e) {
        // ignore
      }
    }
  }

  private togglePlayPause(): void {
    if (this.avPlayer === undefined) {
      this.initPlayer();
      return;
    }
    if (this.isPlaying) {
      this.avPlayer.pause().catch(() => {});
    } else {
      this.avPlayer.play().catch(() => {});
    }
  }

  private seekTo(ms: number): void {
    if (this.avPlayer !== undefined) {
      this.avPlayer.seek(ms);
    }
  }

  private formatClock(ms: number): string {
    const totalSec = Math.max(0, Math.floor(ms / 1000));
    const min = Math.floor(totalSec / 60);
    const sec = totalSec % 60;
    return `${min}:${`${sec}`.padStart(2, '0')}`;
  }

  build() {
    Column({ space: 10 }) {
      if (!this.isAudioOnly) {
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: `av_surface_${this.url.length}`,
            type: XComponentType.SURFACE,
            controller: this.xComponentController
          })
            .onLoad(() => {
              this.surfaceId = this.xComponentController.getXComponentSurfaceId();
              this.initPlayer();
            })
            .width('100%')
            .height('100%')

          if (this.isBuffering) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color('#FFFFFFFF')
          }

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor('#FFFFB4AB')
              .padding(12)
              .borderRadius(10)
              .backgroundColor('#AA000000')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FF000000')
      } else {
        Column({ space: 8 }) {
          AppIcon({ icon: $r('app.media.ic_play'), iconSize: 36, tint: this.theme.colors.primary })
          Text(this.title.length > 0 ? this.title : '音频附件')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFFFF')
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(12)
              .fontColor('#FFFFB4AB')
          }
        }
        .width('100%')
        .padding(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          AppIcon({
            icon: this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'),
            iconSize: 18,
            tint: '#FFFFFFFF'
          })
        }
        .width(38)
        .height(38)
        .backgroundColor('#33FFFFFF')
        .onClick(() => {
          this.togglePlayPause();
        })

        Text(this.formatClock(this.currentMs))
          .fontSize(11)
          .fontColor('#CCFFFFFF')

        Slider({
          value: this.currentMs,
          min: 0,
          max: Math.max(1000, this.durationMs),
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor(this.theme.colors.primary)
          .trackColor('#44FFFFFF')
          .onChange((val: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End) {
              this.seekTo(val);
            }
          })

        Text(this.formatClock(this.durationMs))
          .fontSize(11)
          .fontColor('#CCFFFFFF')
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 10 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
