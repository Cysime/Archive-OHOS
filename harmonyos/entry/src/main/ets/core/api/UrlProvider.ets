import { ApiConstants } from './ApiConstants';

/**
 * 文件 / 缩略图 / 头像 / 临时流 URL 推导规则（对齐上游 app/data/remote/UrlProvider.kt）。
 *
 * - 缩略图：https://img.<host>/thumbnail/data{path}
 * - 原始文件：https://file.<host>/data{path}
 * - 作者头像：https://<host>/icons/{service}/{id}
 * - 作者横幅：https://<host>/banners/{service}/{id}
 * - deferred 附件优先走 temp_url / temp_download_url
 */
export class UrlProvider {
  static readonly DEFAULT_BASE_URL: string = ApiConstants.DEFAULT_BASE_URL;

  private static trimTrailingSlash(value: string): string {
    let end = value.length;
    while (end > 0 && value.charAt(end - 1) === '/') {
      end--;
    }
    return value.substring(0, end);
  }

  static apiV1(baseUrl: string): string {
    const cleaned = UrlProvider.trimTrailingSlash(baseUrl.trim());
    const root = cleaned.length > 0 ? cleaned : UrlProvider.DEFAULT_BASE_URL;
    return `${root}/api/v1`;
  }

  static extractHost(baseUrl: string): string {
    const cleaned = UrlProvider.trimTrailingSlash(baseUrl.trim());
    const effective = cleaned.length > 0 ? cleaned : UrlProvider.DEFAULT_BASE_URL;
    const schemeEnd = effective.indexOf('://');
    const rest = schemeEnd >= 0 ? effective.substring(schemeEnd + 3) : effective;
    const slashIdx = rest.indexOf('/');
    const hostPort = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    const colonIdx = hostPort.indexOf(':');
    return (colonIdx >= 0 ? hostPort.substring(0, colonIdx) : hostPort).toLowerCase();
  }

  static isTargetSiteUrl(url: string, configuredBaseUrl: string = UrlProvider.DEFAULT_BASE_URL): boolean {
    const targetHost = UrlProvider.extractHost(url);
    if (targetHost.length === 0) {
      return false;
    }
    const baseHost = UrlProvider.extractHost(configuredBaseUrl);
    if (targetHost === baseHost || targetHost.endsWith(`.${baseHost}`)) {
      return true;
    }
    return targetHost === ApiConstants.MAIN_HOST || targetHost.endsWith(`.${ApiConstants.MAIN_HOST}`);
  }

  /**
   * 内嵌 ArkWeb（登录/注册/Cloudflare 过盾）允许导航的域名白名单：
   * 仅放行目标站点本身与 Cloudflare / 人机验证相关域，拦截所有第三方广告与恶意跳转（如 awhilepowershakily.com）。
   */
  static isAllowedWebViewUrl(url: string, configuredBaseUrl: string = UrlProvider.DEFAULT_BASE_URL): boolean {
    const trimmed = url.trim().toLowerCase();
    if (trimmed.length === 0 || trimmed === 'about:blank' || trimmed.startsWith('data:') || trimmed.startsWith('blob:')) {
      return true;
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    if (UrlProvider.isTargetSiteUrl(trimmed, configuredBaseUrl)) {
      return true;
    }
    const host = UrlProvider.extractHost(trimmed);
    const allowedSuffixes: string[] = [
      'cloudflare.com',
      'hcaptcha.com',
      'recaptcha.net',
      'gstatic.com',
      'arkoselabs.com',
      'funcaptcha.com'
    ];
    for (let i = 0; i < allowedSuffixes.length; i++) {
      const suffix = allowedSuffixes[i];
      if (host === suffix || host.endsWith(`.${suffix}`)) {
        return true;
      }
    }
    if ((host === 'www.google.com' || host === 'google.com') && trimmed.includes('/recaptcha')) {
      return true;
    }
    return false;
  }

  private static subdomainBase(baseUrl: string, prefix: string): string {
    const cleaned = UrlProvider.trimTrailingSlash(baseUrl.trim());
    if (cleaned.length === 0) {
      return UrlProvider.subdomainBase(UrlProvider.DEFAULT_BASE_URL, prefix);
    }
    const schemeEnd = cleaned.indexOf('://');
    if (schemeEnd <= 0) {
      return cleaned;
    }
    const scheme = cleaned.substring(0, schemeEnd);
    const rest = cleaned.substring(schemeEnd + 3);
    const slashIdx = rest.indexOf('/');
    const host = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    const path = slashIdx >= 0 ? rest.substring(slashIdx + 1) : '';
    const prefixDot = `${prefix}.`;
    const targetHost = host.startsWith(prefixDot) ? host : `${prefixDot}${host}`;
    return path.length === 0 ? `${scheme}://${targetHost}` : `${scheme}://${targetHost}/${path}`;
  }

  static imgBase(baseUrl: string): string {
    return UrlProvider.subdomainBase(baseUrl, 'img');
  }

  static fileBase(baseUrl: string): string {
    return UrlProvider.subdomainBase(baseUrl, 'file');
  }

  static thumbnailUrl(baseUrl: string, path: string): string {
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    return `${UrlProvider.trimTrailingSlash(UrlProvider.imgBase(baseUrl))}/thumbnail/data${normalizedPath}`;
  }

  static fileUrl(baseUrl: string, path: string): string {
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    return `${UrlProvider.trimTrailingSlash(UrlProvider.fileBase(baseUrl))}/data${normalizedPath}`;
  }

  static playbackUrl(baseUrl: string, path?: string, tempUrl?: string): string | undefined {
    if (tempUrl !== undefined && tempUrl.trim().length > 0) {
      return tempUrl;
    }
    if (path !== undefined && path.trim().length > 0) {
      return UrlProvider.fileUrl(baseUrl, path);
    }
    return undefined;
  }

  static downloadUrl(baseUrl: string, path?: string, tempDownloadUrl?: string): string | undefined {
    if (tempDownloadUrl !== undefined && tempDownloadUrl.trim().length > 0) {
      return tempDownloadUrl;
    }
    if (path !== undefined && path.trim().length > 0) {
      return UrlProvider.fileUrl(baseUrl, path);
    }
    return undefined;
  }

  static isTemporaryUrl(url: string): boolean {
    return url.includes('?e=') || url.includes('&e=');
  }

  static iconUrl(baseUrl: string, service: string, creatorId: string): string {
    const root = UrlProvider.trimTrailingSlash(baseUrl.trim()) || UrlProvider.DEFAULT_BASE_URL;
    return `${root}/icons/${service}/${creatorId}`;
  }

  static bannerUrl(baseUrl: string, service: string, creatorId: string): string {
    const root = UrlProvider.trimTrailingSlash(baseUrl.trim()) || UrlProvider.DEFAULT_BASE_URL;
    return `${root}/banners/${service}/${creatorId}`;
  }

  static contentImageUrl(baseUrl: string, src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src;
    }
    const root = UrlProvider.trimTrailingSlash(baseUrl.trim()) || UrlProvider.DEFAULT_BASE_URL;
    if (src.startsWith('/')) {
      return `${root}${src}`;
    }
    return `${root}/${src}`;
  }
}
