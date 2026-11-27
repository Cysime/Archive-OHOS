import { ApiClient } from './ApiClient';
import {
  AnnouncementDto,
  CreatorDto,
  CreatorProfileDto,
  CreatorTagDto,
  DtoParsers,
  HashSearchResultDto,
  PostCommentDto,
  PostDetailDto,
  PostSummaryDto,
  SessionFavoriteDto
} from './Dtos';
import { FlexParsers, JsonValue } from './FlexParsers';
import { AppError, AppErrorKind } from '../error/AppError';

/**
 * Pawchive API v1 完整接口封装（对齐上游 app/remote/PawchiveApi.kt & core/api/PawchiveApi.kt）。
 */
export class PawchiveApi {
  private readonly client: ApiClient;

  constructor(client: ApiClient) {
    this.client = client;
  }

  private parseJson(raw: string): JsonValue {
    try {
      return JSON.parse(raw) as JsonValue;
    } catch (e) {
      throw new AppError(AppErrorKind.PARSE, `响应 JSON 解析失败：${String(e)}`);
    }
  }

  private buildQuery(params: Map<string, string>): string {
    const parts: string[] = [];
    params.forEach((value: string, key: string) => {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    });
    return parts.length > 0 ? `?${parts.join('&')}` : '';
  }

  async getCreators(): Promise<CreatorDto[]> {
    const raw = await this.client.requestApiJson('/creators', { bypassCache: true, timeoutMs: 90000 });
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: CreatorDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parseCreator(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async getPosts(query?: string, offset: number = 0, bypassCache: boolean = false): Promise<PostSummaryDto[]> {
    const params: Map<string, string> = new Map<string, string>();
    if (query !== undefined && query.trim().length >= 3) {
      params.set('q', query.trim());
    }
    if (offset > 0) {
      params.set('o', `${offset}`);
    }
    const raw = await this.client.requestApiJson(`/posts${this.buildQuery(params)}`, { bypassCache: bypassCache });
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parsePostSummary(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async getCreatorPosts(
    service: string,
    creatorId: string,
    query?: string,
    tag?: string,
    offset: number = 0,
    bypassCache: boolean = false
  ): Promise<PostSummaryDto[]> {
    const params: Map<string, string> = new Map<string, string>();
    if (query !== undefined && query.trim().length > 0) {
      params.set('q', query.trim());
    }
    if (tag !== undefined && tag.trim().length > 0) {
      params.set('tag', tag.trim());
    }
    if (offset > 0) {
      params.set('o', `${offset}`);
    }
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}${this.buildQuery(params)}`;
    const raw = await this.client.requestApiJson(path, { bypassCache: bypassCache });
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parsePostSummary(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async getPostDetail(
    service: string,
    creatorId: string,
    postId: string,
    bypassCache: boolean = false
  ): Promise<PostDetailDto> {
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}/post/${encodeURIComponent(postId)}`;
    const raw = await this.client.requestApiJson(path, { bypassCache: bypassCache });
    const parsed = DtoParsers.parsePostDetail(this.parseJson(raw));
    if (parsed === undefined) {
      throw new AppError(AppErrorKind.PARSE, '帖子详情数据为空或格式异常');
    }
    return parsed;
  }

  async getCreatorProfile(service: string, creatorId: string): Promise<CreatorProfileDto> {
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}/profile`;
    const raw = await this.client.requestApiJson(path);
    const parsed = DtoParsers.parseCreatorProfile(this.parseJson(raw));
    if (parsed === undefined) {
      throw new AppError(AppErrorKind.PARSE, '创作者资料解析失败');
    }
    return parsed;
  }

  async getCreatorAnnouncements(service: string, creatorId: string): Promise<AnnouncementDto[]> {
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}/announcements`;
    const raw = await this.client.requestApiJson(path);
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: AnnouncementDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parseAnnouncement(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async getCreatorTags(service: string, creatorId: string): Promise<CreatorTagDto[]> {
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}/tags`;
    const raw = await this.client.requestApiJson(path);
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: CreatorTagDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parseCreatorTag(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async getCreatorLinks(service: string, creatorId: string): Promise<CreatorProfileDto[]> {
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}/links`;
    const raw = await this.client.requestApiJson(path);
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: CreatorProfileDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parseCreatorProfile(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async getPostComments(service: string, creatorId: string, postId: string): Promise<PostCommentDto[]> {
    const path = `/${encodeURIComponent(service)}/user/${encodeURIComponent(creatorId)}/post/${encodeURIComponent(postId)}/comments`;
    const raw = await this.client.requestApiJson(path);
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: PostCommentDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parseComment(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async searchByHash(fileHash: string): Promise<HashSearchResultDto> {
    const path = `/search_hash/${encodeURIComponent(fileHash.trim())}`;
    const raw = await this.client.requestApiJson(path, { bypassCache: true });
    return DtoParsers.parseHashSearchResult(this.parseJson(raw));
  }

  async getAccountFavorites(
    type: 'post' | 'artist',
    offset: number = 0,
    bypassCache: boolean = true
  ): Promise<SessionFavoriteDto[]> {
    const params: Map<string, string> = new Map<string, string>();
    params.set('type', type);
    if (offset > 0) {
      params.set('o', `${offset}`);
    }
    const raw = await this.client.requestApiJson(`/account/favorites${this.buildQuery(params)}`, {
      bypassCache: bypassCache
    });
    const arr = FlexParsers.asArray(this.parseJson(raw));
    const out: SessionFavoriteDto[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = DtoParsers.parseSessionFavorite(arr[i]);
      if (parsed !== undefined) {
        out.push(parsed);
      }
    }
    return out;
  }

  async addFavoritePost(service: string, creatorId: string, postId: string): Promise<void> {
    const path = `/favorites/post/${encodeURIComponent(service)}/${encodeURIComponent(creatorId)}/${encodeURIComponent(postId)}`;
    await this.client.requestApiJson(path, { method: 'POST', bypassCache: true });
    this.client.invalidateCachePrefix('/api/v1/account/favorites');
  }

  async removeFavoritePost(service: string, creatorId: string, postId: string): Promise<void> {
    const path = `/favorites/post/${encodeURIComponent(service)}/${encodeURIComponent(creatorId)}/${encodeURIComponent(postId)}`;
    await this.client.requestApiJson(path, { method: 'DELETE', bypassCache: true });
    this.client.invalidateCachePrefix('/api/v1/account/favorites');
  }

  async addFavoriteCreator(service: string, creatorId: string): Promise<void> {
    const path = `/favorites/creator/${encodeURIComponent(service)}/${encodeURIComponent(creatorId)}`;
    await this.client.requestApiJson(path, { method: 'POST', bypassCache: true });
    this.client.invalidateCachePrefix('/api/v1/account/favorites');
  }

  async removeFavoriteCreator(service: string, creatorId: string): Promise<void> {
    const path = `/favorites/creator/${encodeURIComponent(service)}/${encodeURIComponent(creatorId)}`;
    await this.client.requestApiJson(path, { method: 'DELETE', bypassCache: true });
    this.client.invalidateCachePrefix('/api/v1/account/favorites');
  }
}
