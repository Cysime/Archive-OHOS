import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { FlexParsers, JsonObject } from '../../core/api/FlexParsers';
import { Logger } from '../../core/util/Logger';

const TAG: string = 'BlockedContentRepo';
const PREFS_NAME: string = 'archive_blocked_content';
const KEY_CREATORS: string = 'blocked_creators_json';
const KEY_POSTS: string = 'blocked_posts_json';

export interface BlockedCreatorItem {
  service: string;
  creatorId: string;
  name: string;
  blockedAt: number;
}

export interface BlockedPostItem {
  service: string;
  creatorId: string;
  postId: string;
  title: string;
  blockedAt: number;
}

export type BlockedChangeListener = () => void;

/**
 * 内容屏蔽仓库（对齐上游 BlockedContentFilter + BlockedCreatorManager + BlockedPostManager）。
 *
 * - 启动期预热内存快照，支持列表展示层同步判定
 * - 屏蔽过滤在展示层执行而非分页源，取消屏蔽后无需重新拉取列表
 */
export class BlockedContentRepository {
  private prefs?: preferences.Preferences;
  private creatorsMap: Map<string, BlockedCreatorItem> = new Map<string, BlockedCreatorItem>();
  private postsMap: Map<string, BlockedPostItem> = new Map<string, BlockedPostItem>();
  private readonly listeners: Set<BlockedChangeListener> = new Set<BlockedChangeListener>();

  static creatorKey(service: string, creatorId: string): string {
    return `${service.toLowerCase()}:${creatorId}`;
  }

  static postKey(service: string, creatorId: string, postId: string): string {
    return `${service.toLowerCase()}:${creatorId}:${postId}`;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
      await this.loadFromPrefs();
    } catch (e) {
      Logger.e(TAG, `init blocked prefs failed: ${String(e)}`);
    }
  }

  private async loadFromPrefs(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    try {
      const rawCreators = String(await this.prefs.get(KEY_CREATORS, '[]'));
      const creatorsArr = FlexParsers.asArray(JSON.parse(rawCreators) as Object);
      this.creatorsMap.clear();
      for (let i = 0; i < creatorsArr.length; i++) {
        const obj = FlexParsers.asObject(creatorsArr[i]);
        if (obj === undefined) {
          continue;
        }
        const service = FlexParsers.readString(obj, 'service') ?? '';
        const creatorId = FlexParsers.readString(obj, 'creatorId') ?? '';
        if (service.length > 0 && creatorId.length > 0) {
          this.creatorsMap.set(BlockedContentRepository.creatorKey(service, creatorId), {
            service: service,
            creatorId: creatorId,
            name: FlexParsers.readString(obj, 'name') ?? creatorId,
            blockedAt: FlexParsers.readNumber(obj, 'blockedAt') ?? 0
          });
        }
      }

      const rawPosts = String(await this.prefs.get(KEY_POSTS, '[]'));
      const postsArr = FlexParsers.asArray(JSON.parse(rawPosts) as Object);
      this.postsMap.clear();
      for (let i = 0; i < postsArr.length; i++) {
        const obj = FlexParsers.asObject(postsArr[i]);
        if (obj === undefined) {
          continue;
        }
        const service = FlexParsers.readString(obj, 'service') ?? '';
        const creatorId = FlexParsers.readString(obj, 'creatorId') ?? '';
        const postId = FlexParsers.readString(obj, 'postId') ?? '';
        if (service.length > 0 && creatorId.length > 0 && postId.length > 0) {
          this.postsMap.set(BlockedContentRepository.postKey(service, creatorId, postId), {
            service: service,
            creatorId: creatorId,
            postId: postId,
            title: FlexParsers.readString(obj, 'title') ?? postId,
            blockedAt: FlexParsers.readNumber(obj, 'blockedAt') ?? 0
          });
        }
      }
    } catch (e) {
      Logger.w(TAG, `load blocked content failed: ${String(e)}`);
    }
  }

  private async persist(): Promise<void> {
    if (this.prefs !== undefined) {
      try {
        await this.prefs.put(KEY_CREATORS, JSON.stringify(this.listBlockedCreators()));
        await this.prefs.put(KEY_POSTS, JSON.stringify(this.listBlockedPosts()));
        await this.prefs.flush();
      } catch (e) {
        Logger.e(TAG, `persist blocked content failed: ${String(e)}`);
      }
    }
    this.listeners.forEach((fn: BlockedChangeListener) => {
      fn();
    });
  }

  subscribe(listener: BlockedChangeListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: BlockedChangeListener): void {
    this.listeners.delete(listener);
  }

  isCreatorBlocked(service: string, creatorId: string): boolean {
    return this.creatorsMap.has(BlockedContentRepository.creatorKey(service, creatorId));
  }

  isPostBlocked(service: string, creatorId: string, postId: string): boolean {
    if (this.isCreatorBlocked(service, creatorId)) {
      return true;
    }
    return this.postsMap.has(BlockedContentRepository.postKey(service, creatorId, postId));
  }

  listBlockedCreators(): BlockedCreatorItem[] {
    const out: BlockedCreatorItem[] = [];
    this.creatorsMap.forEach((item: BlockedCreatorItem) => {
      out.push(item);
    });
    out.sort((a: BlockedCreatorItem, b: BlockedCreatorItem) => b.blockedAt - a.blockedAt);
    return out;
  }

  listBlockedPosts(): BlockedPostItem[] {
    const out: BlockedPostItem[] = [];
    this.postsMap.forEach((item: BlockedPostItem) => {
      out.push(item);
    });
    out.sort((a: BlockedPostItem, b: BlockedPostItem) => b.blockedAt - a.blockedAt);
    return out;
  }

  async blockCreator(service: string, creatorId: string, name: string): Promise<void> {
    const key = BlockedContentRepository.creatorKey(service, creatorId);
    this.creatorsMap.set(key, {
      service: service,
      creatorId: creatorId,
      name: name.trim().length > 0 ? name : creatorId,
      blockedAt: Date.now()
    });
    await this.persist();
  }

  async unblockCreator(service: string, creatorId: string): Promise<void> {
    this.creatorsMap.delete(BlockedContentRepository.creatorKey(service, creatorId));
    await this.persist();
  }

  async blockPost(service: string, creatorId: string, postId: string, title: string): Promise<void> {
    const key = BlockedContentRepository.postKey(service, creatorId, postId);
    this.postsMap.set(key, {
      service: service,
      creatorId: creatorId,
      postId: postId,
      title: title.trim().length > 0 ? title : postId,
      blockedAt: Date.now()
    });
    await this.persist();
  }

  async unblockPost(service: string, creatorId: string, postId: string): Promise<void> {
    this.postsMap.delete(BlockedContentRepository.postKey(service, creatorId, postId));
    await this.persist();
  }

  async clearAll(): Promise<void> {
    this.creatorsMap.clear();
    this.postsMap.clear();
    await this.persist();
  }
}
