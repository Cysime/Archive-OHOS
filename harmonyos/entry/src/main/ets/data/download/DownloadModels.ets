import { AttachmentDto, AttachmentHelper, MediaKind } from '../../core/api/Dtos';
import { FlexParsers } from '../../core/api/FlexParsers';

export enum DownloadStatus {
  QUEUED = 'QUEUED',
  WAITING_WIFI = 'WAITING_WIFI',
  RUNNING = 'RUNNING',
  PAUSED = 'PAUSED',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

export interface DownloadRecord {
  id: string;
  url: string;
  fingerprint: string;
  fileName: string;
  tempPath: string;
  targetUri?: string;
  service: string;
  creatorId: string;
  postId: string;
  status: DownloadStatus;
  downloadedBytes: number;
  totalBytes: number;
  speedBytesPerSec: number;
  errorMessage?: string;
  createdAt: number;
  updatedAt: number;
}

export interface DownloadRule {
  id: number;
  name: string;
  service?: string;
  creatorId?: string;
  mediaKinds: MediaKind[];
  enabled: boolean;
  createdAt: number;
}

export interface DownloadEnqueueRequest {
  url: string;
  fileName: string;
  service: string;
  creatorId: string;
  postId: string;
  previewOnly?: boolean;
}

export class DownloadNamingHelper {
  static sanitizeFileName(raw: string): string {
    const cleaned = raw
      .replace(/[\\/:*?"<>|\r\n\t]+/g, '_')
      .replace(/\s+/g, ' ')
      .trim();
    if (cleaned.length === 0) {
      return 'file';
    }
    return cleaned.length > 140 ? cleaned.substring(0, 140) : cleaned;
  }

  static formatFileName(
    template: string,
    service: string,
    creator: string,
    postId: string,
    index: number,
    originalName: string
  ): string {
    const safeOriginal = DownloadNamingHelper.sanitizeFileName(originalName);
    const dotIdx = safeOriginal.lastIndexOf('.');
    const base = dotIdx > 0 ? safeOriginal.substring(0, dotIdx) : safeOriginal;
    const ext = dotIdx > 0 ? safeOriginal.substring(dotIdx) : '';

    const filled = (template.trim().length > 0 ? template : '{creator}_{post_id}_{index}_{name}')
      .replace(/\{service\}/g, service)
      .replace(/\{creator\}/g, creator)
      .replace(/\{post_id\}/g, postId)
      .replace(/\{index\}/g, `${index + 1}`)
      .replace(/\{name\}/g, base);

    const sanitized = DownloadNamingHelper.sanitizeFileName(filled);
    if (ext.length > 0 && !sanitized.toLowerCase().endsWith(ext.toLowerCase())) {
      return `${sanitized}${ext}`;
    }
    return sanitized;
  }

  static fingerprint(url: string, service: string, creatorId: string, postId: string): string {
    // 对带临时签名的链接去除 query 参数，避免刷新链接后重复下载同一附件
    const qIdx = url.indexOf('?');
    const stableUrl = qIdx >= 0 ? url.substring(0, qIdx) : url;
    const raw = `${service.toLowerCase()}|${creatorId}|${postId}|${stableUrl}`;
    const h1 = FlexParsers.simpleHash(raw);
    const h2 = FlexParsers.simpleHash(`fp:${raw}:${raw.length}`);
    return `${h1}_${h2}`;
  }

  static matchesRule(rule: DownloadRule, service: string, creatorId: string, attachment: AttachmentDto): boolean {
    if (!rule.enabled) {
      return false;
    }
    if (rule.service !== undefined && rule.service.trim().length > 0) {
      if (rule.service.trim().toLowerCase() !== service.trim().toLowerCase()) {
        return false;
      }
    }
    if (rule.creatorId !== undefined && rule.creatorId.trim().length > 0) {
      if (rule.creatorId.trim() !== creatorId.trim()) {
        return false;
      }
    }
    const kind = AttachmentHelper.kind(attachment);
    return rule.mediaKinds.includes(kind);
  }
}
