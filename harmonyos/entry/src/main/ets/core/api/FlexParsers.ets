/**
 * 站点非规范 JSON 字段兼容解析器（对齐上游 FlexStringListSerializer & FlexLongSerializer）。
 *
 * 1. `tags` 可能是 JSON 数组 `["NSFW","Benefits"]` 或 Postgres 数组字面量字符串 `{"Atelier Ryza",Benefits,NSFW}`
 * 2. `indexed` / `updated` 在 `/creators` 为 Unix 秒数字，在 `/profile` 为 ISO-8601 字符串
 * 3. 安全提取动态 JSON 对象字段（严格遵循 ArkTS 类型约束，不使用 any）
 */
export type JsonValue = Object | string | number | boolean | null | undefined;
export type JsonObject = Record<string, JsonValue>;

export class FlexParsers {
  static asObject(value: JsonValue): JsonObject | undefined {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      return undefined;
    }
    return value as JsonObject;
  }

  static asArray(value: JsonValue): JsonValue[] {
    if (Array.isArray(value)) {
      return value as JsonValue[];
    }
    return [];
  }

  static readString(obj: JsonObject | undefined, key: string): string | undefined {
    if (obj === undefined) {
      return undefined;
    }
    const raw = obj[key];
    if (raw === null || raw === undefined) {
      return undefined;
    }
    if (typeof raw === 'string') {
      return raw;
    }
    if (typeof raw === 'number' || typeof raw === 'boolean') {
      return `${raw}`;
    }
    return undefined;
  }

  static readNumber(obj: JsonObject | undefined, key: string): number | undefined {
    if (obj === undefined) {
      return undefined;
    }
    const raw = obj[key];
    if (typeof raw === 'number' && !Number.isNaN(raw)) {
      return raw;
    }
    if (typeof raw === 'string' && raw.trim().length > 0) {
      const parsed = Number(raw.trim());
      if (!Number.isNaN(parsed)) {
        return parsed;
      }
    }
    return undefined;
  }

  static readBoolean(obj: JsonObject | undefined, key: string, defaultValue: boolean = false): boolean {
    if (obj === undefined) {
      return defaultValue;
    }
    const raw = obj[key];
    if (typeof raw === 'boolean') {
      return raw;
    }
    if (typeof raw === 'number') {
      return raw !== 0;
    }
    if (typeof raw === 'string') {
      const lower = raw.trim().toLowerCase();
      if (lower === 'true' || lower === '1') {
        return true;
      }
      if (lower === 'false' || lower === '0') {
        return false;
      }
    }
    return defaultValue;
  }

  /**
   * 兼容解析 Unix 秒、毫秒或 ISO-8601 字符串，返回 Unix 秒（缺失或非法返回 undefined）。
   */
  static parseFlexUnixSeconds(value: JsonValue): number | undefined {
    if (value === null || value === undefined) {
      return undefined;
    }
    if (typeof value === 'number' && !Number.isNaN(value)) {
      return Math.trunc(value);
    }
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (trimmed.length === 0) {
        return undefined;
      }
      const asNum = Number(trimmed);
      if (!Number.isNaN(asNum)) {
        return Math.trunc(asNum);
      }
      const ms = Date.parse(trimmed);
      if (!Number.isNaN(ms)) {
        return Math.trunc(ms / 1000);
      }
    }
    return undefined;
  }

  /**
   * 兼容解析 JSON 字符串数组或 Postgres 数组字面量字符串。
   */
  static parseFlexStringList(value: JsonValue): string[] {
    if (value === null || value === undefined) {
      return [];
    }
    if (Array.isArray(value)) {
      const out: string[] = [];
      const arr = value as JsonValue[];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i];
        if (item !== null && item !== undefined) {
          if (typeof item === 'string') {
            out.push(item);
          } else if (typeof item === 'number' || typeof item === 'boolean') {
            out.push(`${item}`);
          }
        }
      }
      return out;
    }
    if (typeof value === 'string') {
      return FlexParsers.parsePostgresArray(value);
    }
    return [];
  }

  /**
   * 解析 Postgres 数组字面量：`{a,"b,c",d}` -> ['a', 'b,c', 'd']。
   * 支持双引号元素、引号内逗号、`\"` 与 `\\` 转义；未加引号的 `NULL` 视为空。
   */
  static parsePostgresArray(raw: string): string[] {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }
    let inner = trimmed;
    if (trimmed.length >= 2 && trimmed.startsWith('{') && trimmed.endsWith('}')) {
      inner = trimmed.substring(1, trimmed.length - 1);
    }
    if (inner.trim().length === 0) {
      return [];
    }

    const out: string[] = [];
    let current = '';
    let inQuotes = false;
    let escaped = false;
    let elementQuoted = false;

    const flush = (quoted: boolean): void => {
      const value = current;
      current = '';
      if (quoted) {
        out.push(value);
      } else {
        const bare = value.trim();
        if (bare.length > 0 && bare.toUpperCase() !== 'NULL') {
          out.push(bare);
        }
      }
    };

    for (let i = 0; i < inner.length; i++) {
      const c = inner.charAt(i);
      if (escaped) {
        current += c;
        escaped = false;
      } else if (c === '\\') {
        escaped = true;
      } else if (c === '"') {
        if (inQuotes) {
          flush(true);
          inQuotes = false;
          elementQuoted = false;
        } else {
          inQuotes = true;
          elementQuoted = true;
        }
      } else if (c === ',' && !inQuotes) {
        flush(elementQuoted);
        elementQuoted = false;
      } else {
        current += c;
      }
    }
    if (current.length > 0 || elementQuoted) {
      flush(elementQuoted);
    }
    return out;
  }

  /**
   * 计算字符串简易稳定哈希（用于 ApiMemoryCache 会话命名空间隔离）。
   */
  static simpleHash(input: string): string {
    if (input.length === 0) {
      return 'anon';
    }
    let hash = 2166136261;
    for (let i = 0; i < input.length; i++) {
      hash ^= input.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }
}
