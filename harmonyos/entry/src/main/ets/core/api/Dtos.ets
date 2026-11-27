import { FlexParsers, JsonObject, JsonValue } from './FlexParsers';

/**
 * Pawchive API v1 领域模型与 DTO 解析器（对齐上游 app/domain/Models.kt & remote/Dtos.kt）。
 */
export enum MediaKind {
  IMAGE = 'IMAGE',
  VIDEO = 'VIDEO',
  AUDIO = 'AUDIO',
  FILE = 'FILE'
}

const IMAGE_EXTS: Set<string> = new Set<string>(['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif']);
const VIDEO_EXTS: Set<string> = new Set<string>(['mp4', 'webm', 'mov', 'mkv', 'm4v']);
const AUDIO_EXTS: Set<string> = new Set<string>(['mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac', 'opus']);

export interface AttachmentDto {
  name?: string;
  path?: string;
  previewOnly: boolean;
  deferred: boolean;
  tempUrl?: string;
  tempDownloadUrl?: string;
  tempExpires?: string;
}

export interface CreatorDto {
  service: string;
  id: string;
  name: string;
  publicId?: string;
  indexed?: number;
  updated?: number;
  favorited: number;
  everImported: boolean;
}

export interface CreatorProfileDto {
  service: string;
  id: string;
  name: string;
  publicId?: string;
  indexed?: string;
  updated?: string;
  everImported?: boolean;
}

export interface PostSummaryDto {
  service: string;
  creatorId: string;
  postId: string;
  title: string;
  excerpt?: string;
  published?: string;
  cover?: AttachmentDto;
  previewOnly: boolean;
}

export interface PostDetailDto {
  service: string;
  creatorId: string;
  postId: string;
  title: string;
  contentHtml: string;
  added?: string;
  published?: string;
  edited?: string;
  file?: AttachmentDto;
  attachments: AttachmentDto[];
  tags: string[];
  prev?: string;
  next?: string;
  previewOnly: boolean;
}

export interface AnnouncementDto {
  service: string;
  userId: string;
  content: string;
  added?: string;
}

export interface CreatorTagDto {
  tag: string;
  postCount: number;
}

export interface PostCommentDto {
  id: string;
  parentId?: string;
  commenter: string;
  content: string;
  published?: string;
}

export interface SessionFavoriteDto {
  id: string;
  service: string;
  name?: string;
  updated?: string;
  favedSeq?: number;
  user?: string;
  title?: string;
}

export interface DiscordHitDto {
  id: string;
  server: string;
  channel: string;
  excerpt?: string;
  published?: string;
}

export interface HashSearchResultDto {
  sitePosts: PostSummaryDto[];
  discordHits: DiscordHitDto[];
}

export class AttachmentHelper {
  static displayName(att: AttachmentDto, fallback: string = 'file'): string {
    if (att.name !== undefined && att.name.trim().length > 0) {
      return att.name;
    }
    if (att.path !== undefined) {
      const idx = att.path.lastIndexOf('/');
      const tail = idx >= 0 ? att.path.substring(idx + 1) : att.path;
      if (tail.trim().length > 0) {
        return tail;
      }
    }
    return fallback;
  }

  static kind(att: AttachmentDto): MediaKind {
    const raw = (att.name ?? att.path ?? '').toLowerCase();
    const dot = raw.lastIndexOf('.');
    const ext = dot >= 0 ? raw.substring(dot + 1) : '';
    if (IMAGE_EXTS.has(ext)) {
      return MediaKind.IMAGE;
    }
    if (VIDEO_EXTS.has(ext)) {
      return MediaKind.VIDEO;
    }
    if (AUDIO_EXTS.has(ext)) {
      return MediaKind.AUDIO;
    }
    return MediaKind.FILE;
  }

  static tempLinkExpired(att: AttachmentDto, nowMs: number = Date.now()): boolean {
    if (att.tempExpires === undefined || att.tempExpires.trim().length === 0) {
      return false;
    }
    const parsed = Date.parse(att.tempExpires);
    if (Number.isNaN(parsed)) {
      return false;
    }
    return parsed < nowMs;
  }

  static hasPlayableSource(att: AttachmentDto, nowMs: number = Date.now()): boolean {
    if (AttachmentHelper.tempLinkExpired(att, nowMs)) {
      return false;
    }
    const hasTemp = att.tempUrl !== undefined && att.tempUrl.trim().length > 0;
    const hasPath = att.path !== undefined && att.path.trim().length > 0;
    return hasTemp || hasPath;
  }
}

export class DtoParsers {
  static parseAttachment(raw: JsonValue): AttachmentDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const name = FlexParsers.readString(obj, 'name');
    const path = FlexParsers.readString(obj, 'path');
    const tempUrl = FlexParsers.readString(obj, 'temp_url');
    const tempDownloadUrl = FlexParsers.readString(obj, 'temp_download_url');
    const tempExpires = FlexParsers.readString(obj, 'temp_expires');
    const deferred = FlexParsers.readBoolean(obj, 'deferred', false);
    const previewOnly = FlexParsers.readBoolean(obj, 'preview_only', false);
    if (
      (path === undefined || path.trim().length === 0) &&
      !deferred &&
      (tempUrl === undefined || tempUrl.trim().length === 0) &&
      (tempDownloadUrl === undefined || tempDownloadUrl.trim().length === 0)
    ) {
      return undefined;
    }
    return {
      name: name,
      path: path,
      previewOnly: previewOnly,
      deferred: deferred,
      tempUrl: tempUrl,
      tempDownloadUrl: tempDownloadUrl,
      tempExpires: tempExpires
    };
  }

  static parseCreator(raw: JsonValue): CreatorDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const id = FlexParsers.readString(obj, 'id') ?? '';
    const service = FlexParsers.readString(obj, 'service') ?? '';
    if (id.length === 0 || service.length === 0) {
      return undefined;
    }
    return {
      service: service,
      id: id,
      name: FlexParsers.readString(obj, 'name') ?? id,
      publicId: FlexParsers.readString(obj, 'public_id'),
      indexed: FlexParsers.parseFlexUnixSeconds(obj['indexed']),
      updated: FlexParsers.parseFlexUnixSeconds(obj['updated']),
      favorited: Math.trunc(FlexParsers.readNumber(obj, 'favorited') ?? 0),
      everImported: FlexParsers.readBoolean(obj, 'ever_imported', false)
    };
  }

  static parseCreatorProfile(raw: JsonValue): CreatorProfileDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const id = FlexParsers.readString(obj, 'id') ?? '';
    const service = FlexParsers.readString(obj, 'service') ?? '';
    if (id.length === 0 || service.length === 0) {
      return undefined;
    }
    return {
      service: service,
      id: id,
      name: FlexParsers.readString(obj, 'name') ?? id,
      publicId: FlexParsers.readString(obj, 'public_id'),
      indexed: FlexParsers.readString(obj, 'indexed'),
      updated: FlexParsers.readString(obj, 'updated'),
      everImported: obj['ever_imported'] !== undefined ? FlexParsers.readBoolean(obj, 'ever_imported', false) : undefined
    };
  }

  static parsePostSummary(raw: JsonValue): PostSummaryDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const postId = FlexParsers.readString(obj, 'id') ?? '';
    const creatorId = FlexParsers.readString(obj, 'user') ?? '';
    const service = FlexParsers.readString(obj, 'service') ?? '';
    if (postId.length === 0 || creatorId.length === 0 || service.length === 0) {
      return undefined;
    }
    let cover = DtoParsers.parseAttachment(obj['file']);
    if (cover === undefined) {
      const attachments = FlexParsers.asArray(obj['attachments']);
      for (let i = 0; i < attachments.length; i++) {
        const candidate = DtoParsers.parseAttachment(attachments[i]);
        if (candidate !== undefined) {
          cover = candidate;
          break;
        }
      }
    }
    return {
      service: service,
      creatorId: creatorId,
      postId: postId,
      title: FlexParsers.readString(obj, 'title') ?? '',
      excerpt: FlexParsers.readString(obj, 'substring') ?? FlexParsers.readString(obj, 'content'),
      published: FlexParsers.readString(obj, 'published') ?? FlexParsers.readString(obj, 'added'),
      cover: cover,
      previewOnly: FlexParsers.readBoolean(obj, 'preview_only', false)
    };
  }

  static parsePostDetail(raw: JsonValue): PostDetailDto | undefined {
    const rootObj = FlexParsers.asObject(raw);
    if (rootObj === undefined) {
      return undefined;
    }
    // 兼容部分接口返回 `{ post: {...} }` 或直接返回 Post 对象
    const obj = FlexParsers.asObject(rootObj['post']) ?? rootObj;
    const postId = FlexParsers.readString(obj, 'id') ?? '';
    const creatorId = FlexParsers.readString(obj, 'user') ?? '';
    const service = FlexParsers.readString(obj, 'service') ?? '';
    if (postId.length === 0 || creatorId.length === 0 || service.length === 0) {
      return undefined;
    }
    const rawAttachments = FlexParsers.asArray(obj['attachments']);
    const attachments: AttachmentDto[] = [];
    for (let i = 0; i < rawAttachments.length; i++) {
      const parsed = DtoParsers.parseAttachment(rawAttachments[i]);
      if (parsed !== undefined) {
        attachments.push(parsed);
      }
    }
    return {
      service: service,
      creatorId: creatorId,
      postId: postId,
      title: FlexParsers.readString(obj, 'title') ?? '',
      contentHtml: FlexParsers.readString(obj, 'content') ?? '',
      added: FlexParsers.readString(obj, 'added'),
      published: FlexParsers.readString(obj, 'published'),
      edited: FlexParsers.readString(obj, 'edited'),
      file: DtoParsers.parseAttachment(obj['file']),
      attachments: attachments,
      tags: FlexParsers.parseFlexStringList(obj['tags']),
      prev: FlexParsers.readString(obj, 'prev') ?? FlexParsers.readString(rootObj, 'prev'),
      next: FlexParsers.readString(obj, 'next') ?? FlexParsers.readString(rootObj, 'next'),
      previewOnly: FlexParsers.readBoolean(obj, 'preview_only', false)
    };
  }

  static parseComment(raw: JsonValue): PostCommentDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const id = FlexParsers.readString(obj, 'id') ?? '';
    // 优先使用 commenter_name，缺失时回退到 commenter（对齐 API_NOTES 第 5 节实测结论）
    const commenterName = FlexParsers.readString(obj, 'commenter_name');
    const commenterId = FlexParsers.readString(obj, 'commenter');
    const commenter = (commenterName !== undefined && commenterName.trim().length > 0)
      ? commenterName
      : (commenterId ?? '');
    return {
      id: id,
      parentId: FlexParsers.readString(obj, 'parent_id'),
      commenter: commenter,
      content: FlexParsers.readString(obj, 'content') ?? '',
      published: FlexParsers.readString(obj, 'published')
    };
  }

  static parseAnnouncement(raw: JsonValue): AnnouncementDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    return {
      service: FlexParsers.readString(obj, 'service') ?? '',
      userId: FlexParsers.readString(obj, 'user_id') ?? '',
      content: FlexParsers.readString(obj, 'content') ?? '',
      added: FlexParsers.readString(obj, 'added')
    };
  }

  static parseCreatorTag(raw: JsonValue): CreatorTagDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const tag = FlexParsers.readString(obj, 'tag') ?? '';
    if (tag.length === 0) {
      return undefined;
    }
    return {
      tag: tag,
      postCount: Math.trunc(FlexParsers.readNumber(obj, 'post_count') ?? 0)
    };
  }

  static parseSessionFavorite(raw: JsonValue): SessionFavoriteDto | undefined {
    const obj = FlexParsers.asObject(raw);
    if (obj === undefined) {
      return undefined;
    }
    const id = FlexParsers.readString(obj, 'id') ?? '';
    const service = FlexParsers.readString(obj, 'service') ?? '';
    if (id.length === 0 || service.length === 0) {
      return undefined;
    }
    return {
      id: id,
      service: service,
      name: FlexParsers.readString(obj, 'name'),
      updated: FlexParsers.readString(obj, 'updated'),
      favedSeq: FlexParsers.readNumber(obj, 'faved_seq'),
      user: FlexParsers.readString(obj, 'user'),
      title: FlexParsers.readString(obj, 'title')
    };
  }

  static parseHashSearchResult(raw: JsonValue): HashSearchResultDto {
    const obj = FlexParsers.asObject(raw);
    const sitePosts: PostSummaryDto[] = [];
    const discordHits: DiscordHitDto[] = [];
    if (obj === undefined) {
      return { sitePosts: sitePosts, discordHits: discordHits };
    }
    const postsArr = FlexParsers.asArray(obj['posts']);
    for (let i = 0; i < postsArr.length; i++) {
      const pObj = FlexParsers.asObject(postsArr[i]);
      if (pObj === undefined) {
        continue;
      }
      const service = (FlexParsers.readString(pObj, 'service') ?? '').toLowerCase();
      if (service === 'discord') {
        discordHits.push({
          id: FlexParsers.readString(pObj, 'id') ?? '',
          server: FlexParsers.readString(pObj, 'server') ?? FlexParsers.readString(pObj, 'user') ?? '',
          channel: FlexParsers.readString(pObj, 'channel') ?? '',
          excerpt: FlexParsers.readString(pObj, 'content') ?? FlexParsers.readString(pObj, 'substring'),
          published: FlexParsers.readString(pObj, 'published')
        });
      } else {
        const post = DtoParsers.parsePostSummary(pObj);
        if (post !== undefined) {
          sitePosts.push(post);
        }
      }
    }
    return { sitePosts: sitePosts, discordHits: discordHits };
  }
}
