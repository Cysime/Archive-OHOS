import { ApiConstants } from '../../core/api/ApiConstants';
import {
  AnnouncementDto,
  CreatorProfileDto,
  CreatorTagDto,
  PostCommentDto,
  PostDetailDto,
  PostSummaryDto
} from '../../core/api/Dtos';
import { PawchiveApi } from '../../core/api/PawchiveApi';
import { PostSortHelper } from '../util/PostSort';
import { CreatorRepository } from './CreatorRepository';
import { FavoriteRepository } from './FavoriteRepository';

export interface PostPageResult {
  items: PostSummaryDto[];
  hasMore: boolean;
  nextOffset: number;
}

export interface PostDetailLoadResult {
  detail: PostDetailDto;
  fromOfflineArchive: boolean;
}

/**
 * 帖子与创作者详情数据仓库（对齐上游 app/data/repo/PostRepository.kt）。
 *
 * - Offset 分页（步进 50，短页即结尾）
 * - 搜索词长度 < 3 自动执行客户端本地过滤（对齐站点实测行为）
 * - 帖子详情网络失败时自动回退到本地收藏全文离线归档
 */
export class PostRepository {
  private readonly api: PawchiveApi;
  private readonly favorites: FavoriteRepository;
  private readonly creators: CreatorRepository;

  constructor(
    api: PawchiveApi,
    favorites: FavoriteRepository,
    creators: CreatorRepository
  ) {
    this.api = api;
    this.favorites = favorites;
    this.creators = creators;
  }

  async loadGlobalPosts(
    query: string = '',
    offset: number = 0,
    bypassCache: boolean = false
  ): Promise<PostPageResult> {
    const trimmed = query.trim();
    const serverQuery = trimmed.length >= 3 ? trimmed : undefined;
    const raw = await this.api.getPosts(serverQuery, offset, bypassCache);
    const hasMore = raw.length >= ApiConstants.PAGE_SIZE;
    const items = (trimmed.length > 0 && trimmed.length < 3)
      ? PostSortHelper.filterByShortQuery(raw, trimmed)
      : raw;
    return {
      items: items,
      hasMore: hasMore,
      nextOffset: offset + ApiConstants.PAGE_SIZE
    };
  }

  async loadCreatorPosts(
    service: string,
    creatorId: string,
    query: string = '',
    tag: string = '',
    offset: number = 0,
    bypassCache: boolean = false
  ): Promise<PostPageResult> {
    const trimmed = query.trim();
    const raw = await this.api.getCreatorPosts(
      service,
      creatorId,
      trimmed.length > 0 ? trimmed : undefined,
      tag.trim().length > 0 ? tag.trim() : undefined,
      offset,
      bypassCache
    );
    return {
      items: raw,
      hasMore: raw.length >= ApiConstants.PAGE_SIZE,
      nextOffset: offset + ApiConstants.PAGE_SIZE
    };
  }

  async loadPostDetailWithOfflineFallback(
    service: string,
    creatorId: string,
    postId: string,
    bypassCache: boolean = false
  ): Promise<PostDetailLoadResult> {
    try {
      const detail = await this.api.getPostDetail(service, creatorId, postId, bypassCache);
      const creatorName = await this.creators.resolveCreatorName(service, creatorId);
      await this.favorites.ensureArchived(detail, creatorName);
      return {
        detail: detail,
        fromOfflineArchive: false
      };
    } catch (err) {
      const archived = await this.favorites.getArchivedPost(service, creatorId, postId);
      if (archived !== undefined) {
        return {
          detail: archived,
          fromOfflineArchive: true
        };
      }
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  async loadPostComments(service: string, creatorId: string, postId: string): Promise<PostCommentDto[]> {
    return this.api.getPostComments(service, creatorId, postId);
  }

  async loadCreatorProfile(service: string, creatorId: string): Promise<CreatorProfileDto> {
    const profile = await this.api.getCreatorProfile(service, creatorId);
    this.creators.rememberName(service, creatorId, profile.name);
    return profile;
  }

  async loadCreatorAnnouncements(service: string, creatorId: string): Promise<AnnouncementDto[]> {
    return this.api.getCreatorAnnouncements(service, creatorId);
  }

  async loadCreatorTags(service: string, creatorId: string): Promise<CreatorTagDto[]> {
    return this.api.getCreatorTags(service, creatorId);
  }

  async loadCreatorLinks(service: string, creatorId: string): Promise<CreatorProfileDto[]> {
    return this.api.getCreatorLinks(service, creatorId);
  }
}
