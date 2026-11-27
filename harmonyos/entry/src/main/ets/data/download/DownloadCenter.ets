import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { ApiClient } from '../../core/api/ApiClient';
import { AttachmentDto, AttachmentHelper, PostDetailDto } from '../../core/api/Dtos';
import { UrlProvider } from '../../core/api/UrlProvider';
import { ArchiveDatabase } from '../../core/db/ArchiveDatabase';
import { SessionManager } from '../../core/store/SessionManager';
import { SettingsManager } from '../../core/store/SettingsManager';
import { Logger } from '../../core/util/Logger';
import {
  DownloadEnqueueRequest,
  DownloadNamingHelper,
  DownloadRecord,
  DownloadStatus
} from './DownloadModels';
import { DownloadNotificationHelper } from './DownloadNotificationHelper';
import { NetworkStateHelper } from './NetworkStateHelper';

const TAG: string = 'DownloadCenter';

export type DownloadListListener = (records: DownloadRecord[]) => void;

interface ActiveTransfer {
  session: rcp.Session;
  request: rcp.Request;
  intent: 'RUNNING' | 'PAUSED' | 'CANCELLED';
}

class FileWriterHolder {
  file?: fileIo.File = undefined;
}

/**
 * 流式下载中心（对齐上游 DownloadCenter + HttpDownloadManager）。
 *
 * - 并发上限 1–5（遵循 SettingsManager 钳制与服务器合规限制）
 * - 指纹去重、自动跳过 `preview_only` 附件
 * - HTTP Range 断点续传（校验 206/Content-Length；若服务端如 `temp_download_url` 返回 416 则自动清临时文件从头全量下载）
 * - 失败自动重试 1–3 次（指数退避 >= 1s）
 * - 仅 Wi-Fi 下载开关检查
 * - 5% 进度节流写 RDB 检查点与通知栏更新
 */
export class DownloadCenter {
  private readonly apiClient: ApiClient;
  private readonly database: ArchiveDatabase;
  private readonly settings: SettingsManager;
  private readonly sessionManager: SessionManager;

  private downloadsDir: string = '';
  private records: Map<string, DownloadRecord> = new Map<string, DownloadRecord>();
  private activeTransfers: Map<string, ActiveTransfer> = new Map<string, ActiveTransfer>();
  private queueIds: string[] = [];
  private readonly listeners: Set<DownloadListListener> = new Set<DownloadListListener>();

  constructor(
    apiClient: ApiClient,
    database: ArchiveDatabase,
    settings: SettingsManager,
    sessionManager: SessionManager
  ) {
    this.apiClient = apiClient;
    this.database = database;
    this.settings = settings;
    this.sessionManager = sessionManager;
  }

  private ns(): string {
    return this.sessionManager.getSessionNamespace();
  }

  async init(context: common.Context): Promise<void> {
    this.downloadsDir = `${context.filesDir}/downloads`;
    try {
      if (!fileIo.accessSync(this.downloadsDir)) {
        fileIo.mkdirSync(this.downloadsDir, true);
      }
    } catch (e) {
      Logger.w(TAG, `mkdir downloadsDir failed: ${String(e)}`);
    }
    await this.loadRecordsFromDb();
  }

  subscribe(listener: DownloadListListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: DownloadListListener): void {
    this.listeners.delete(listener);
  }

  listRecords(): DownloadRecord[] {
    const out: DownloadRecord[] = [];
    this.records.forEach((rec: DownloadRecord) => {
      out.push(rec);
    });
    out.sort((a: DownloadRecord, b: DownloadRecord) => b.createdAt - a.createdAt);
    return out;
  }

  private emit(): void {
    const list = this.listRecords();
    this.listeners.forEach((fn: DownloadListListener) => {
      fn(list);
    });
  }

  private parseStatus(raw: string): DownloadStatus {
    if (raw === DownloadStatus.COMPLETED) {
      return DownloadStatus.COMPLETED;
    }
    if (raw === DownloadStatus.PAUSED) {
      return DownloadStatus.PAUSED;
    }
    if (raw === DownloadStatus.FAILED) {
      return DownloadStatus.FAILED;
    }
    if (raw === DownloadStatus.CANCELLED) {
      return DownloadStatus.CANCELLED;
    }
    if (raw === DownloadStatus.WAITING_WIFI) {
      return DownloadStatus.WAITING_WIFI;
    }
    if (raw === DownloadStatus.RUNNING) {
      return DownloadStatus.PAUSED; // 应用重启后上次运行中的任务保持暂停态等待续传
    }
    return DownloadStatus.QUEUED;
  }

  async loadRecordsFromDb(): Promise<void> {
    this.records.clear();
    try {
      const store = this.database.getStore();
      const rs = await store.querySql(
        'SELECT id, url, fingerprint, file_name, temp_path, target_uri, service, creator_id, post_id, status, downloaded_bytes, total_bytes, error_message, created_at, updated_at FROM download_records WHERE account_ns = ? ORDER BY created_at DESC',
        [this.ns()]
      );
      try {
        while (rs.goToNextRow()) {
          const rec: DownloadRecord = {
            id: rs.getString(0),
            url: rs.getString(1),
            fingerprint: rs.getString(2),
            fileName: rs.getString(3),
            tempPath: rs.getString(4),
            targetUri: rs.isColumnNull(5) ? undefined : rs.getString(5),
            service: rs.getString(6),
            creatorId: rs.getString(7),
            postId: rs.getString(8),
            status: this.parseStatus(rs.getString(9)),
            downloadedBytes: rs.getLong(10),
            totalBytes: rs.getLong(11),
            speedBytesPerSec: 0,
            errorMessage: rs.isColumnNull(12) ? undefined : rs.getString(12),
            createdAt: rs.getLong(13),
            updatedAt: rs.getLong(14)
          };
          this.records.set(rec.id, rec);
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.w(TAG, `loadRecordsFromDb failed: ${String(e)}`);
    }
    this.emit();
  }

  private async persistRecord(rec: DownloadRecord): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql(
        'INSERT OR REPLACE INTO download_records (id, account_ns, url, fingerprint, file_name, temp_path, target_uri, service, creator_id, post_id, status, downloaded_bytes, total_bytes, error_message, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          rec.id,
          this.ns(),
          rec.url,
          rec.fingerprint,
          rec.fileName,
          rec.tempPath,
          rec.targetUri ?? null,
          rec.service,
          rec.creatorId,
          rec.postId,
          rec.status,
          rec.downloadedBytes,
          rec.totalBytes,
          rec.errorMessage ?? null,
          rec.createdAt,
          rec.updatedAt
        ]
      );
    } catch (e) {
      Logger.w(TAG, `persistRecord(${rec.id}) failed: ${String(e)}`);
    }
  }

  async enqueue(req: DownloadEnqueueRequest): Promise<DownloadRecord | undefined> {
    if (req.previewOnly === true || req.url.trim().length === 0) {
      return undefined;
    }
    const fp = DownloadNamingHelper.fingerprint(req.url, req.service, req.creatorId, req.postId);

    // 去重：若同指纹任务已完成或在队列/下载中，直接复用
    let existing: DownloadRecord | undefined = undefined;
    this.records.forEach((rec: DownloadRecord) => {
      if (rec.fingerprint === fp && rec.status !== DownloadStatus.CANCELLED && rec.status !== DownloadStatus.FAILED) {
        existing = rec;
      }
    });
    if (existing !== undefined) {
      return existing;
    }

    const now = Date.now();
    const id = `dl_${now}_${Math.floor(Math.random() * 100000)}`;
    const safeName = DownloadNamingHelper.sanitizeFileName(req.fileName);
    const tempPath = `${this.downloadsDir}/${id}_${safeName}.part`;

    const record: DownloadRecord = {
      id: id,
      url: req.url,
      fingerprint: fp,
      fileName: safeName,
      tempPath: tempPath,
      service: req.service,
      creatorId: req.creatorId,
      postId: req.postId,
      status: DownloadStatus.QUEUED,
      downloadedBytes: 0,
      totalBytes: -1,
      speedBytesPerSec: 0,
      createdAt: now,
      updatedAt: now
    };
    this.records.set(id, record);
    await this.persistRecord(record);
    this.queueIds.push(id);
    this.emit();
    this.pumpQueue();
    return record;
  }

  async enqueuePostAttachments(
    detail: PostDetailDto,
    creatorName: string,
    selectedIndices?: number[]
  ): Promise<number> {
    const all: AttachmentDto[] = [];
    if (detail.file !== undefined) {
      all.push(detail.file);
    }
    for (let i = 0; i < detail.attachments.length; i++) {
      all.push(detail.attachments[i]);
    }
    const baseUrl = this.apiClient.getBaseUrl();
    const namingTemplate = this.settings.getSnapshot().fileNamingFormat;
    let added = 0;

    for (let i = 0; i < all.length; i++) {
      if (selectedIndices !== undefined && !selectedIndices.includes(i)) {
        continue;
      }
      const att = all[i];
      if (att.previewOnly) {
        continue;
      }
      const url = UrlProvider.downloadUrl(baseUrl, att.path, att.tempDownloadUrl);
      if (url === undefined) {
        continue;
      }
      const origName = AttachmentHelper.displayName(att, `attachment_${i + 1}`);
      const formattedName = DownloadNamingHelper.formatFileName(
        namingTemplate,
        detail.service,
        creatorName.length > 0 ? creatorName : detail.creatorId,
        detail.postId,
        i,
        origName
      );
      const rec = await this.enqueue({
        url: url,
        fileName: formattedName,
        service: detail.service,
        creatorId: detail.creatorId,
        postId: detail.postId,
        previewOnly: att.previewOnly
      });
      if (rec !== undefined) {
        added++;
      }
    }
    return added;
  }

  pause(id: string): void {
    const rec = this.records.get(id);
    if (rec === undefined) {
      return;
    }
    this.queueIds = this.queueIds.filter((qid: string) => qid !== id);
    const active = this.activeTransfers.get(id);
    if (active !== undefined) {
      active.intent = 'PAUSED';
      try {
        active.session.cancel(active.request);
      } catch (_e) {
        // ignore cancel error
      }
    } else if (rec.status === DownloadStatus.QUEUED || rec.status === DownloadStatus.WAITING_WIFI) {
      rec.status = DownloadStatus.PAUSED;
      rec.speedBytesPerSec = 0;
      rec.updatedAt = Date.now();
      this.persistRecord(rec);
      DownloadNotificationHelper.publishProgress(rec);
      this.emit();
    }
  }

  resume(id: string): void {
    const rec = this.records.get(id);
    if (rec === undefined) {
      return;
    }
    if (rec.status === DownloadStatus.RUNNING || rec.status === DownloadStatus.COMPLETED) {
      return;
    }
    rec.status = DownloadStatus.QUEUED;
    rec.errorMessage = undefined;
    rec.updatedAt = Date.now();
    this.persistRecord(rec);
    if (!this.queueIds.includes(id)) {
      this.queueIds.push(id);
    }
    this.emit();
    this.pumpQueue();
  }

  cancel(id: string): void {
    const rec = this.records.get(id);
    if (rec === undefined) {
      return;
    }
    this.queueIds = this.queueIds.filter((qid: string) => qid !== id);
    const active = this.activeTransfers.get(id);
    if (active !== undefined) {
      active.intent = 'CANCELLED';
      try {
        active.session.cancel(active.request);
      } catch (_e) {
        // ignore
      }
    } else {
      rec.status = DownloadStatus.CANCELLED;
      rec.speedBytesPerSec = 0;
      rec.updatedAt = Date.now();
      this.safeDeleteFile(rec.tempPath);
      this.persistRecord(rec);
      DownloadNotificationHelper.cancel(id);
      this.emit();
    }
  }

  async removeRecord(id: string): Promise<void> {
    this.cancel(id);
    const rec = this.records.get(id);
    if (rec !== undefined) {
      this.safeDeleteFile(rec.tempPath);
      if (rec.targetUri !== undefined && rec.targetUri.startsWith(this.downloadsDir)) {
        this.safeDeleteFile(rec.targetUri);
      }
      this.records.delete(id);
    }
    try {
      const store = this.database.getStore();
      await store.executeSql('DELETE FROM download_records WHERE id = ?', [id]);
    } catch (e) {
      Logger.w(TAG, `removeRecord(${id}) failed: ${String(e)}`);
    }
    DownloadNotificationHelper.cancel(id);
    this.emit();
  }

  private pumpQueue(): void {
    const maxConcurrent = SettingsManager.clampConcurrency(this.settings.getSnapshot().downloadConcurrency);
    while (this.activeTransfers.size < maxConcurrent && this.queueIds.length > 0) {
      const nextId = this.queueIds.shift();
      if (nextId === undefined) {
        break;
      }
      const rec = this.records.get(nextId);
      if (rec === undefined || rec.status === DownloadStatus.COMPLETED || rec.status === DownloadStatus.CANCELLED) {
        continue;
      }
      this.runTask(rec);
    }
  }

  private async runTask(rec: DownloadRecord): Promise<void> {
    if (this.settings.getSnapshot().downloadWifiOnly) {
      const wifi = await NetworkStateHelper.isWifiConnected();
      if (!wifi) {
        rec.status = DownloadStatus.WAITING_WIFI;
        rec.speedBytesPerSec = 0;
        rec.updatedAt = Date.now();
        await this.persistRecord(rec);
        DownloadNotificationHelper.publishProgress(rec);
        this.emit();
        return;
      }
    }

    const maxRetries = SettingsManager.clampRetries(this.settings.getSnapshot().downloadMaxRetries);
    let attempt = 0;
    let forceFullDownload = false;

    while (attempt < maxRetries) {
      attempt++;
      const outcome = await this.executeSingleAttempt(rec, forceFullDownload);
      if (outcome === 'COMPLETED' || outcome === 'PAUSED' || outcome === 'CANCELLED') {
        this.pumpQueue();
        return;
      }
      if (outcome === 'RETRY_FULL') {
        forceFullDownload = true;
        this.safeDeleteFile(rec.tempPath);
        rec.downloadedBytes = 0;
        continue;
      }
      if (attempt < maxRetries) {
        await this.delay(1000 * attempt);
      }
    }

    rec.status = DownloadStatus.FAILED;
    rec.speedBytesPerSec = 0;
    rec.updatedAt = Date.now();
    await this.persistRecord(rec);
    DownloadNotificationHelper.publishProgress(rec);
    this.emit();
    this.pumpQueue();
  }

  private async executeSingleAttempt(
    rec: DownloadRecord,
    forceFullDownload: boolean
  ): Promise<'COMPLETED' | 'PAUSED' | 'CANCELLED' | 'RETRY_FULL' | 'FAILED'> {
    let existingSize = 0;
    if (!forceFullDownload) {
      existingSize = this.getFileSize(rec.tempPath);
    }
    rec.downloadedBytes = existingSize;
    rec.status = DownloadStatus.RUNNING;
    rec.errorMessage = undefined;
    rec.updatedAt = Date.now();
    await this.persistRecord(rec);
    this.emit();

    const writer = new FileWriterHolder();
    let lastNotifiedPercent = -10;
    let lastSampleTime = Date.now();
    let lastSampleBytes = existingSize;
    let expectedTotal = rec.totalBytes;
    let responseStatus = 0;

    const mergedHeaders = this.apiClient.buildSiteHeaders(rec.url);
    const rcpHeaders: rcp.RequestHeaders = {};
    const keys = Object.keys(mergedHeaders);
    for (let i = 0; i < keys.length; i++) {
      rcpHeaders[keys[i].toLowerCase()] = mergedHeaders[keys[i]];
    }

    const openForWrite = (append: boolean): void => {
      if (writer.file !== undefined) {
        return;
      }
      const mode = append
        ? (fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND)
        : (fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      writer.file = fileIo.openSync(rec.tempPath, mode);
    };

    const closeWriter = (): void => {
      if (writer.file !== undefined) {
        try {
          fileIo.closeSync(writer.file.fd);
        } catch (_ce) {
          // ignore close error
        }
        writer.file = undefined;
      }
    };

    const eventsHandler: rcp.HttpEventsHandler = {
      onHeaderReceive: (headers: rcp.ResponseHeaders): void => {
        const lenVal = headers['content-length'];
        const lenStr = Array.isArray(lenVal) ? (lenVal[0] ?? '') : (lenVal ?? '');
        const parsedLen = parseInt(lenStr, 10);
        if (!Number.isNaN(parsedLen) && parsedLen > 0) {
          expectedTotal = existingSize > 0 && responseStatus === 206 ? existingSize + parsedLen : parsedLen;
          rec.totalBytes = expectedTotal;
        }
      },
      onDataReceive: (incomingData: ArrayBuffer): number => {
        if (responseStatus >= 400) {
          return incomingData.byteLength;
        }
        const useAppend = existingSize > 0 && responseStatus === 206;
        if (writer.file === undefined) {
          if (!useAppend) {
            rec.downloadedBytes = 0;
          }
          openForWrite(useAppend);
        }
        if (writer.file !== undefined) {
          fileIo.writeSync(writer.file.fd, incomingData);
        }
        rec.downloadedBytes += incomingData.byteLength;

        const now = Date.now();
        const elapsed = now - lastSampleTime;
        if (elapsed >= 500) {
          const delta = rec.downloadedBytes - lastSampleBytes;
          rec.speedBytesPerSec = Math.max(0, Math.floor((delta * 1000) / elapsed));
          lastSampleTime = now;
          lastSampleBytes = rec.downloadedBytes;
          this.emit();
        }

        if (rec.totalBytes > 0) {
          const pct = Math.floor((rec.downloadedBytes * 100) / rec.totalBytes);
          if (pct - lastNotifiedPercent >= 5) {
            lastNotifiedPercent = pct;
            rec.updatedAt = now;
            this.persistRecord(rec);
            DownloadNotificationHelper.publishProgress(rec);
          }
        }
        return incomingData.byteLength;
      }
    };

    let session: rcp.Session | undefined = undefined;
    try {
      const cfg: rcp.SessionConfiguration = {
        requestConfiguration: {
          transfer: {
            autoRedirect: true,
            timeout: {
              connectMs: 30000,
              transferMs: 0
            }
          },
          tracing: {
            httpEventsHandler: eventsHandler
          }
        }
      };
      session = rcp.createSession(cfg);
      const transferRange: rcp.TransferRange | undefined = existingSize > 0 ? { from: existingSize } : undefined;
      const request = new rcp.Request(rec.url, 'GET', rcpHeaders, undefined, undefined, transferRange);
      const transfer: ActiveTransfer = {
        session: session,
        request: request,
        intent: 'RUNNING'
      };
      this.activeTransfers.set(rec.id, transfer);

      const response = await session.fetch(request);
      responseStatus = response.statusCode;
      closeWriter();

      if (transfer.intent === 'PAUSED') {
        rec.status = DownloadStatus.PAUSED;
        rec.speedBytesPerSec = 0;
        rec.updatedAt = Date.now();
        await this.persistRecord(rec);
        DownloadNotificationHelper.publishProgress(rec);
        this.emit();
        return 'PAUSED';
      }

      if (transfer.intent === 'CANCELLED') {
        rec.status = DownloadStatus.CANCELLED;
        rec.speedBytesPerSec = 0;
        this.safeDeleteFile(rec.tempPath);
        await this.persistRecord(rec);
        DownloadNotificationHelper.cancel(rec.id);
        this.emit();
        return 'CANCELLED';
      }

      if (responseStatus === 416 && existingSize > 0) {
        Logger.w(TAG, `HTTP 416 on Range request for ${rec.fileName}; falling back to full download.`);
        return 'RETRY_FULL';
      }

      if (responseStatus >= 200 && responseStatus < 300) {
        const finalPath = `${this.downloadsDir}/${rec.id}_${rec.fileName}`;
        try {
          if (fileIo.accessSync(rec.tempPath)) {
            fileIo.renameSync(rec.tempPath, finalPath);
          }
        } catch (renErr) {
          Logger.w(TAG, `rename completed file failed: ${String(renErr)}`);
        }
        rec.targetUri = finalPath;
        rec.status = DownloadStatus.COMPLETED;
        rec.speedBytesPerSec = 0;
        if (rec.totalBytes <= 0) {
          rec.totalBytes = rec.downloadedBytes;
        }
        rec.updatedAt = Date.now();
        await this.persistRecord(rec);
        DownloadNotificationHelper.publishProgress(rec);
        this.emit();
        return 'COMPLETED';
      }

      rec.errorMessage = `HTTP ${responseStatus}`;
      return 'FAILED';
    } catch (e) {
      closeWriter();
      const active = this.activeTransfers.get(rec.id);
      if (active !== undefined && active.intent === 'PAUSED') {
        rec.status = DownloadStatus.PAUSED;
        rec.speedBytesPerSec = 0;
        rec.updatedAt = Date.now();
        await this.persistRecord(rec);
        DownloadNotificationHelper.publishProgress(rec);
        this.emit();
        return 'PAUSED';
      }
      if (active !== undefined && active.intent === 'CANCELLED') {
        rec.status = DownloadStatus.CANCELLED;
        rec.speedBytesPerSec = 0;
        this.safeDeleteFile(rec.tempPath);
        await this.persistRecord(rec);
        DownloadNotificationHelper.cancel(rec.id);
        this.emit();
        return 'CANCELLED';
      }
      rec.errorMessage = String(e);
      Logger.w(TAG, `download attempt failed (${rec.fileName}): ${String(e)}`);
      return 'FAILED';
    } finally {
      this.activeTransfers.delete(rec.id);
      if (session !== undefined) {
        try {
          session.close();
        } catch (_closeErr) {
          // ignore
        }
      }
    }
  }

  private getFileSize(path: string): number {
    try {
      if (!fileIo.accessSync(path)) {
        return 0;
      }
      const stat = fileIo.statSync(path);
      return stat.size;
    } catch (_e) {
      return 0;
    }
  }

  private safeDeleteFile(path: string): void {
    try {
      if (path.length > 0 && fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_e) {
      // ignore
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
