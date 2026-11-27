/**
 * 全应用导航路由表（对齐上游 ui/navigation/AppNavHost.kt 全部 15 条路由）。
 */
export class AppRoutes {
  static readonly MAIN: string = 'main';
  static readonly SETTINGS: string = 'settings';
  static readonly ABOUT: string = 'about';
  static readonly STORAGE: string = 'storage';
  static readonly SEARCH: string = 'search';
  static readonly HISTORY: string = 'history';
  static readonly DOWNLOADS: string = 'downloads';
  static readonly LOGIN: string = 'login';
  static readonly NOTIFICATIONS: string = 'notifications';
  static readonly BLOCKED: string = 'blocked';
  static readonly TRANSLATION: string = 'translation';
  static readonly CREATOR: string = 'creator';
  static readonly POST: string = 'post';
  static readonly VIEWER: string = 'viewer';
}

export interface CreatorRouteParam {
  service: string;
  creatorId: string;
}

export interface PostRouteParam {
  service: string;
  creatorId: string;
  postId: string;
}

export interface ViewerRouteParam {
  service: string;
  creatorId: string;
  postId: string;
  initialIndex: number;
}
