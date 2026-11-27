/**
 * 统一应用错误模型（对齐上游 core/error/AppError.kt）。
 */
export enum AppErrorKind {
  NETWORK = 'NETWORK',
  TIMEOUT = 'TIMEOUT',
  UNAUTHORIZED = 'UNAUTHORIZED',
  FORBIDDEN = 'FORBIDDEN',
  NOT_FOUND = 'NOT_FOUND',
  RATE_LIMITED = 'RATE_LIMITED',
  SERVER = 'SERVER',
  CLOUDFLARE = 'CLOUDFLARE',
  PARSE = 'PARSE',
  STORAGE = 'STORAGE',
  CANCELLED = 'CANCELLED',
  UNKNOWN = 'UNKNOWN'
}

export class AppError extends Error {
  readonly kind: AppErrorKind;
  readonly statusCode?: number;

  constructor(kind: AppErrorKind, message: string, statusCode?: number) {
    super(message);
    this.name = 'AppError';
    this.kind = kind;
    this.statusCode = statusCode;
  }

  static fromHttpStatus(statusCode: number, detail?: string): AppError {
    if (statusCode === 401) {
      return new AppError(AppErrorKind.UNAUTHORIZED, detail ?? '会话未登录或已失效（401）', 401);
    }
    if (statusCode === 403) {
      return new AppError(AppErrorKind.FORBIDDEN, detail ?? '访问被拒绝或需要通过安全验证（403）', 403);
    }
    if (statusCode === 404) {
      return new AppError(AppErrorKind.NOT_FOUND, detail ?? '目标内容不存在（404）', 404);
    }
    if (statusCode === 429) {
      return new AppError(AppErrorKind.RATE_LIMITED, detail ?? '请求过于频繁，请稍后再试（429）', 429);
    }
    return new AppError(AppErrorKind.SERVER, detail ?? `服务端错误（HTTP ${statusCode}）`, statusCode);
  }

  static friendlyMessage(err: Object | Error | undefined): string {
    if (err instanceof AppError) {
      return err.message;
    }
    if (err instanceof Error) {
      return err.message.length > 0 ? err.message : '发生未知错误';
    }
    return '发生未知错误';
  }
}
