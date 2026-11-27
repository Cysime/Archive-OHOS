import { rcp } from '@kit.RemoteCommunicationKit';
import { ApiConstants } from '../../core/api/ApiConstants';
import { SettingsManager, UpdateChannel } from '../../core/store/SettingsManager';
import { ReleaseInfo, UpdateChannelName, UpdateParser } from './UpdateParser';

export enum UpdateCheckStatus {
  UP_TO_DATE = 'UP_TO_DATE',
  UPDATE_AVAILABLE = 'UPDATE_AVAILABLE',
  RATE_LIMITED = 'RATE_LIMITED',
  ERROR = 'ERROR'
}

export interface UpdateCheckResult {
  status: UpdateCheckStatus;
  currentVersion: string;
  latest?: ReleaseInfo;
  message: string;
}

export const CURRENT_APP_VERSION: string = '1.0.4';

/**
 * GitHub Release 更新检查器（指向本 Fork 仓库 `Cysime/Archive-OHOS`）。
 *
 * - STABLE 读 `/releases/latest`，BETA 读 `/releases`
 * - API 返回 403/429 或异常时自动降级读取 `releases.atom`（不计 API 配额）
 * - 两条路都失败时区分 `RATE_LIMITED` 与普通错误
 */
export class UpdateChecker {
  private readonly settings: SettingsManager;

  constructor(settings: SettingsManager) {
    this.settings = settings;
  }

  private async fetchText(url: string, accept: string): Promise<[number, string]> {
    let session: rcp.Session | undefined = undefined;
    try {
      session = rcp.createSession({
        requestConfiguration: {
          transfer: {
            autoRedirect: true,
            timeout: { connectMs: 15000, transferMs: 25000 }
          }
        }
      });
      const headers: rcp.RequestHeaders = {
        'user-agent': ApiConstants.APP_USER_AGENT,
        'accept': accept
      };
      const req = new rcp.Request(url, 'GET', headers);
      const resp = await session.fetch(req);
      return [resp.statusCode, resp.toString() ?? ''];
    } catch (e) {
      throw new Error(`fetch update failed: ${String(e)}`);
    } finally {
      if (session !== undefined) {
        try {
          session.close();
        } catch (_e) {
          // ignore
        }
      }
    }
  }

  async check(channelOverride?: UpdateChannel): Promise<UpdateCheckResult> {
    const channel = channelOverride ?? this.settings.getSnapshot().updateChannel;
    const channelName: UpdateChannelName = channel === UpdateChannel.BETA ? 'BETA' : 'STABLE';
    const owner = ApiConstants.GITHUB_OWNER;
    const repo = ApiConstants.GITHUB_REPO;
    const apiUrl = channel === UpdateChannel.BETA
      ? `https://api.github.com/repos/${owner}/${repo}/releases?per_page=10`
      : `https://api.github.com/repos/${owner}/${repo}/releases/latest`;

    let rateLimited = false;
    let release: ReleaseInfo | undefined = undefined;

    try {
      const apiRes = await this.fetchText(apiUrl, 'application/vnd.github+json');
      if (apiRes[0] >= 200 && apiRes[0] < 300) {
        release = UpdateParser.parseApiReleases(apiRes[1], channelName);
      } else if (apiRes[0] === 403 || apiRes[0] === 429) {
        rateLimited = true;
      }
    } catch (_apiErr) {
      // 降级到 releases.atom
    }

    if (release === undefined) {
      try {
        const atomRes = await this.fetchText(ApiConstants.GITHUB_RELEASES_ATOM_URL, 'application/atom+xml,text/xml');
        if (atomRes[0] >= 200 && atomRes[0] < 300) {
          release = UpdateParser.parseReleasesAtom(atomRes[1], channelName, ApiConstants.GITHUB_RELEASES_URL);
        }
      } catch (_atomErr) {
        // 两条路线均不可达
      }
    }

    if (release === undefined) {
      if (rateLimited) {
        return {
          status: UpdateCheckStatus.RATE_LIMITED,
          currentVersion: CURRENT_APP_VERSION,
          message: 'GitHub 限流了，稍后再试'
        };
      }
      return {
        status: UpdateCheckStatus.ERROR,
        currentVersion: CURRENT_APP_VERSION,
        message: '检查更新失败，请检查网络或仓库是否已发布 Release'
      };
    }

    if (UpdateParser.compareSemver(release.version, CURRENT_APP_VERSION) > 0) {
      return {
        status: UpdateCheckStatus.UPDATE_AVAILABLE,
        currentVersion: CURRENT_APP_VERSION,
        latest: release,
        message: `发现新版本 ${release.tagName}`
      };
    }

    return {
      status: UpdateCheckStatus.UP_TO_DATE,
      currentVersion: CURRENT_APP_VERSION,
      latest: release,
      message: `当前已是最新版本（v${CURRENT_APP_VERSION}）`
    };
  }
}
