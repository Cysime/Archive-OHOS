import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x2026;

export class Logger {
  static d(tag: string, msg: string): void {
    hilog.debug(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  static i(tag: string, msg: string): void {
    hilog.info(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  static w(tag: string, msg: string): void {
    hilog.warn(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  static e(tag: string, msg: string): void {
    hilog.error(LOG_DOMAIN, tag, '%{public}s', msg);
  }
}
