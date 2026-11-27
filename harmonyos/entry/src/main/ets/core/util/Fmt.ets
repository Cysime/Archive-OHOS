/**
 * 常用格式化工具（字节体积、日期、计数）。
 */
export class Fmt {
  static bytes(size: number): string {
    if (size < 1024) {
      return `${Math.max(0, Math.trunc(size))} B`;
    }
    const kb = size / 1024;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }
    const mb = kb / 1024;
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`;
    }
    const gb = mb / 1024;
    return `${gb.toFixed(2)} GB`;
  }

  static shortDate(iso?: string): string {
    if (iso === undefined || iso.trim().length === 0) {
      return '';
    }
    const tIdx = iso.indexOf('T');
    if (tIdx > 0) {
      return iso.substring(0, tIdx);
    }
    const spaceIdx = iso.indexOf(' ');
    if (spaceIdx > 0) {
      return iso.substring(0, spaceIdx);
    }
    return iso.substring(0, Math.min(10, iso.length));
  }

  static compactCount(count: number): string {
    if (count < 1000) {
      return `${count}`;
    }
    if (count < 10000) {
      return `${(count / 1000).toFixed(1)}k`;
    }
    return `${(count / 10000).toFixed(1)}万`;
  }
}
