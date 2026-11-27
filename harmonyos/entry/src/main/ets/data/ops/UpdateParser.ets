import { FlexParsers, JsonValue } from '../../core/api/FlexParsers';
import { HtmlParser } from '../../core/util/HtmlParser';

export type UpdateChannelName = 'STABLE' | 'BETA';

export interface ReleaseInfo {
  tagName: string;
  version: string;
  title: string;
  notes: string;
  htmlUrl: string;
  publishedAt: string;
  prerelease: boolean;
  fromAtomFallback: boolean;
}

/**
 * GitHub Release 语义化版本比较与 API / Atom Feed 解析器（100% 纯逻辑，对齐上游 UpdateChecker & GithubReleaseFeed）。
 */
export class UpdateParser {
  static normalizeVersion(raw: string): string {
    const trimmed = raw.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1).trim();
    }
    return trimmed;
  }

  static isPrereleaseTag(tag: string): boolean {
    return UpdateParser.normalizeVersion(tag).includes('-');
  }

  /**
   * 比较语义化版本：a > b 返回 1，a < b 返回 -1，相等返回 0。
   * 同主版本时，正式版 > 预发布版（1.0.5 > 1.0.5-beta.1）。
   */
  static compareSemver(aRaw: string, bRaw: string): number {
    const aNorm = UpdateParser.normalizeVersion(aRaw);
    const bNorm = UpdateParser.normalizeVersion(bRaw);

    const aDash = aNorm.indexOf('-');
    const bDash = bNorm.indexOf('-');
    const aCore = aDash >= 0 ? aNorm.substring(0, aDash) : aNorm;
    const bCore = bDash >= 0 ? bNorm.substring(0, bDash) : bNorm;
    const aPre = aDash >= 0 ? aNorm.substring(aDash + 1) : '';
    const bPre = bDash >= 0 ? bNorm.substring(bDash + 1) : '';

    const aNums = aCore.split('.');
    const bNums = bCore.split('.');
    const len = Math.max(aNums.length, bNums.length);
    for (let i = 0; i < len; i++) {
      const av = parseInt(aNums[i] ?? '0', 10) || 0;
      const bv = parseInt(bNums[i] ?? '0', 10) || 0;
      if (av !== bv) {
        return av > bv ? 1 : -1;
      }
    }

    if (aPre.length === 0 && bPre.length === 0) {
      return 0;
    }
    if (aPre.length === 0) {
      return 1;
    }
    if (bPre.length === 0) {
      return -1;
    }
    if (aPre === bPre) {
      return 0;
    }
    return aPre > bPre ? 1 : -1;
  }

  static parseApiReleases(rawJson: string, channel: UpdateChannelName): ReleaseInfo | undefined {
    const parsed = JSON.parse(rawJson) as JsonValue;
    const list: JsonValue[] = Array.isArray(parsed) ? (parsed as JsonValue[]) : [parsed];
    const candidates: ReleaseInfo[] = [];

    for (let i = 0; i < list.length; i++) {
      const obj = FlexParsers.asObject(list[i]);
      if (obj === undefined) {
        continue;
      }
      const draft = FlexParsers.readBoolean(obj, 'draft', false);
      if (draft) {
        continue;
      }
      const tagName = FlexParsers.readString(obj, 'tag_name') ?? '';
      if (tagName.length === 0) {
        continue;
      }
      const prerelease = FlexParsers.readBoolean(obj, 'prerelease', UpdateParser.isPrereleaseTag(tagName));
      if (channel === 'STABLE' && prerelease) {
        continue;
      }
      candidates.push({
        tagName: tagName,
        version: UpdateParser.normalizeVersion(tagName),
        title: FlexParsers.readString(obj, 'name') ?? tagName,
        notes: FlexParsers.readString(obj, 'body') ?? '',
        htmlUrl: FlexParsers.readString(obj, 'html_url') ?? '',
        publishedAt: FlexParsers.readString(obj, 'published_at') ?? '',
        prerelease: prerelease,
        fromAtomFallback: false
      });
    }
    return UpdateParser.pickLatest(candidates);
  }

  /**
   * 解析 GitHub `releases.atom` XML（当 GitHub REST API 触发 403/429 限流时自动降级使用）。
   */
  static parseReleasesAtom(xml: string, channel: UpdateChannelName, fallbackReleasesUrl: string): ReleaseInfo | undefined {
    const entryRegex = /<entry>([\s\S]*?)<\/entry>/gi;
    const candidates: ReleaseInfo[] = [];
    let match: RegExpExecArray | null = entryRegex.exec(xml);
    while (match !== null) {
      const block = match[1];
      const linkMatch = /<link[^>]+href="([^"]+)"/i.exec(block);
      const titleMatch = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(block);
      const updatedMatch = /<updated[^>]*>([\s\S]*?)<\/updated>/i.exec(block);
      const href = linkMatch !== null ? linkMatch[1] : fallbackReleasesUrl;
      const slashIdx = href.lastIndexOf('/');
      const tagFromHref = slashIdx >= 0 ? decodeURIComponent(href.substring(slashIdx + 1)) : '';
      const rawTitle = titleMatch !== null ? HtmlParser.decodeEntities(titleMatch[1].trim()) : tagFromHref;
      const tagName = tagFromHref.length > 0 ? tagFromHref : rawTitle;
      if (tagName.length > 0) {
        const prerelease = UpdateParser.isPrereleaseTag(tagName);
        if (channel === 'BETA' || !prerelease) {
          candidates.push({
            tagName: tagName,
            version: UpdateParser.normalizeVersion(tagName),
            title: rawTitle.length > 0 ? rawTitle : tagName,
            notes: '',
            htmlUrl: href,
            publishedAt: updatedMatch !== null ? updatedMatch[1].trim() : '',
            prerelease: prerelease,
            fromAtomFallback: true
          });
        }
      }
      match = entryRegex.exec(xml);
    }
    return UpdateParser.pickLatest(candidates);
  }

  private static pickLatest(items: ReleaseInfo[]): ReleaseInfo | undefined {
    if (items.length === 0) {
      return undefined;
    }
    let best = items[0];
    for (let i = 1; i < items.length; i++) {
      if (UpdateParser.compareSemver(items[i].version, best.version) > 0) {
        best = items[i];
      }
    }
    return best;
  }
}
