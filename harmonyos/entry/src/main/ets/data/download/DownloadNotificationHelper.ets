import { notificationManager } from '@kit.NotificationKit';
import { FlexParsers } from '../../core/api/FlexParsers';
import { Fmt } from '../../core/util/Fmt';
import { Logger } from '../../core/util/Logger';
import { DownloadRecord, DownloadStatus } from './DownloadModels';

const TAG: string = 'DownloadNotif';

/**
 * 独立任务进度通知管理器（对齐上游 DownloadNotificationController）。
 * 每条下载任务对应独立通知 ID，无通知权限时静默跳过，不影响下载流程。
 */
export class DownloadNotificationHelper {
  private static notificationId(recordId: string): number {
    const hex = FlexParsers.simpleHash(`dl:${recordId}`);
    const parsed = parseInt(hex.substring(0, 6), 16);
    return Number.isNaN(parsed) ? 1001 : (1000 + (parsed % 50000));
  }

  static publishProgress(record: DownloadRecord): void {
    const id = DownloadNotificationHelper.notificationId(record.id);
    const pct = record.totalBytes > 0
      ? Math.min(100, Math.floor((record.downloadedBytes * 100) / record.totalBytes))
      : 0;

    let title = record.fileName;
    let text = '';
    if (record.status === DownloadStatus.COMPLETED) {
      title = `下载完成：${record.fileName}`;
      text = record.totalBytes > 0 ? Fmt.bytes(record.totalBytes) : '已保存到本地';
    } else if (record.status === DownloadStatus.FAILED) {
      title = `下载失败：${record.fileName}`;
      text = record.errorMessage ?? '网络错误，可点击重试';
    } else if (record.status === DownloadStatus.PAUSED) {
      title = `已暂停：${record.fileName}`;
      text = `已下载 ${Fmt.bytes(record.downloadedBytes)}（支持断点续传）`;
    } else if (record.status === DownloadStatus.WAITING_WIFI) {
      title = `等待 Wi-Fi：${record.fileName}`;
      text = '已开启仅 Wi-Fi 下载';
    } else {
      const speed = record.speedBytesPerSec > 0 ? ` · ${Fmt.bytes(record.speedBytesPerSec)}/s` : '';
      text = record.totalBytes > 0
        ? `${pct}% · ${Fmt.bytes(record.downloadedBytes)} / ${Fmt.bytes(record.totalBytes)}${speed}`
        : `已下载 ${Fmt.bytes(record.downloadedBytes)}${speed}`;
    }

    const request: notificationManager.NotificationRequest = {
      id: id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text
        }
      }
    };

    notificationManager.publish(request).catch((e: Object) => {
      Logger.d(TAG, `publish notification skipped: ${String(e)}`);
    });
  }

  static cancel(recordId: string): void {
    const id = DownloadNotificationHelper.notificationId(recordId);
    notificationManager.cancel(id).catch(() => {});
  }
}
