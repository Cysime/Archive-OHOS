/**
 * 网络层与仓储全局常量单一来源（对齐上游 core/api/ApiConstants.kt）。
 */
export class ApiConstants {
  /** 平台主域根 URL（登录端点、过盾加载页、Referer 使用，含尾斜杠）。 */
  static readonly MAIN_BASE_URL: string = 'https://pawchive.pw/';

  /** 平台默认 Base URL（无尾斜杠，用于设置项与 UrlProvider）。 */
  static readonly DEFAULT_BASE_URL: string = 'https://pawchive.pw';

  /** 平台主域 host（Cookie 注入与 CDN 子域判断使用）。 */
  static readonly MAIN_HOST: string = 'pawchive.pw';

  /** REST API 根路径。 */
  static readonly API_BASE_URL: string = 'https://pawchive.pw/api/v1/';

  /**
   * 应用专属 User-Agent（与 cf_clearance 强绑定）。
   * 站点文件服务器要求非浏览器可识别 UA。
   */
  static readonly APP_USER_AGENT: string = 'Archive-HarmonyOS (third-party client, no tracking)';

  /** 服务端列表接口每页固定条数（仅支持 offset 分页）。 */
  static readonly PAGE_SIZE: number = 50;

  /** GET JSON 内存缓存有效期（5 分钟）。 */
  static readonly MEMORY_CACHE_TTL_MS: number = 5 * 60 * 1000;

  /** GET JSON 内存缓存最大条目数。 */
  static readonly MEMORY_CACHE_MAX_ENTRIES: number = 200;

  /** Cloudflare 挑战单次过盾超时（30 秒）。 */
  static readonly CHALLENGE_TIMEOUT_MS: number = 30000;

  /** Cloudflare 过盾凭据 TTL（25 分钟）。 */
  static readonly CLEARANCE_TTL_MS: number = 25 * 60 * 1000;

  /** 登录宽限期（60 秒内 401 不判会话失效）。 */
  static readonly LOGIN_GRACE_PERIOD_MS: number = 60 * 1000;

  /** 应用内检查更新默认 GitHub 仓库坐标（指向本 Fork 仓库）。 */
  static readonly GITHUB_OWNER: string = 'Cysime';
  static readonly GITHUB_REPO: string = 'Archive-OHOS';
  static readonly GITHUB_RELEASES_URL: string = 'https://github.com/Cysime/Archive-OHOS/releases';
  static readonly GITHUB_RELEASES_ATOM_URL: string = 'https://github.com/Cysime/Archive-OHOS/releases.atom';
}
