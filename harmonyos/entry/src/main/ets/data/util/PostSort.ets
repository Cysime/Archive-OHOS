import { PostSummaryDto } from '../../core/api/Dtos';

export enum PostSortMode {
  PUBLISHED_DESC = 'PUBLISHED_DESC',
  PUBLISHED_ASC = 'PUBLISHED_ASC',
  TITLE_ASC = 'TITLE_ASC',
  TITLE_DESC = 'TITLE_DESC'
}

export class PostSortHelper {
  static label(mode: PostSortMode): string {
    if (mode === PostSortMode.PUBLISHED_ASC) {
      return '发布时间（从旧到新）';
    }
    if (mode === PostSortMode.TITLE_ASC) {
      return '标题（A → Z）';
    }
    if (mode === PostSortMode.TITLE_DESC) {
      return '标题（Z → A）';
    }
    return '发布时间（从新到旧）';
  }

  static sortPosts(posts: PostSummaryDto[], mode: PostSortMode): PostSummaryDto[] {
    const copy = posts.slice();
    copy.sort((a: PostSummaryDto, b: PostSummaryDto): number => {
      if (mode === PostSortMode.TITLE_ASC) {
        return a.title.localeCompare(b.title);
      }
      if (mode === PostSortMode.TITLE_DESC) {
        return b.title.localeCompare(a.title);
      }
      const pa = a.published ?? '';
      const pb = b.published ?? '';
      if (mode === PostSortMode.PUBLISHED_ASC) {
        return pa.localeCompare(pb);
      }
      return pb.localeCompare(pa);
    });
    return copy;
  }

  /**
   * 仅保留每位创作者在当前列表中出现的第一条帖子（「同作者仅显示一条」开关）。
   */
  static deduplicateByCreator(posts: PostSummaryDto[]): PostSummaryDto[] {
    const seen: Set<string> = new Set<string>();
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < posts.length; i++) {
      const p = posts[i];
      const key = `${p.service}:${p.creatorId}`;
      if (!seen.has(key)) {
        seen.add(key);
        out.push(p);
      }
    }
    return out;
  }

  /**
   * 过滤掉已收藏的创作者的帖子（「隐藏已收藏创作者」开关）。
   */
  static filterOutCreators(posts: PostSummaryDto[], excludedCreatorKeys: Set<string>): PostSummaryDto[] {
    if (excludedCreatorKeys.size === 0) {
      return posts;
    }
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < posts.length; i++) {
      const p = posts[i];
      const key = `${p.service}:${p.creatorId}`;
      if (!excludedCreatorKeys.has(key)) {
        out.push(p);
      }
    }
    return out;
  }

  /**
   * 当搜索词长度 < 3 时，站点会忽略 `q` 参数，需要客户端本地过滤。
   */
  static filterByShortQuery(posts: PostSummaryDto[], query: string): PostSummaryDto[] {
    const q = query.trim().toLowerCase();
    if (q.length === 0) {
      return posts;
    }
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < posts.length; i++) {
      const p = posts[i];
      const inTitle = p.title.toLowerCase().includes(q);
      const inExcerpt = (p.excerpt ?? '').toLowerCase().includes(q);
      const inCreator = p.creatorId.toLowerCase().includes(q);
      if (inTitle || inExcerpt || inCreator) {
        out.push(p);
      }
    }
    return out;
  }

  /**
   * 单页内去重（按 service:creatorId:postId），用于分页追加或整页重置。
   */
  static deduplicatePosts(posts: PostSummaryDto[]): PostSummaryDto[] {
    const seen: Set<string> = new Set<string>();
    const out: PostSummaryDto[] = [];
    for (let i = 0; i < posts.length; i++) {
      const p = posts[i];
      const key = `${p.service}:${p.creatorId}:${p.postId}`;
      if (!seen.has(key)) {
        seen.add(key);
        out.push(p);
      }
    }
    return out;
  }
}
