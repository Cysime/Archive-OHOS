import { FlexParsers, JsonValue } from '../../core/api/FlexParsers';
import { HtmlParser } from '../../core/util/HtmlParser';

export interface PostTranslation {
  title: string;
  html: string;
  sourceLanguage: string;
}

export const TITLE_OPEN: string = '<<<TITLE';
export const TITLE_CLOSE: string = 'TITLE>>>';
export const HTML_OPEN: string = '<<<HTML';
export const HTML_CLOSE: string = 'HTML>>>';
export const PLACEHOLDER_TITLE: string = '<译文标题>';
export const PLACEHOLDER_HTML: string = '<译文正文 HTML>';

/**
 * 哨兵分段帖子翻译解析器（100% 纯逻辑，对齐上游 TranslationClient.kt）。
 */
export class TranslationParser {
  static detectSourceLanguage(sample: string): string {
    const plain = HtmlParser.htmlToPlainText(sample);
    if (/[\u3040-\u30ff]/.test(plain)) {
      return '日语';
    }
    if (/[\uac00-\ud7af]/.test(plain)) {
      return '韩语';
    }
    if (/[\u0400-\u04ff]/.test(plain)) {
      return '俄语';
    }
    if (/[\u0600-\u06ff]/.test(plain)) {
      return '阿拉伯语';
    }
    if (/[\u4e00-\u9fff]/.test(plain)) {
      return '中文';
    }
    if (/[a-zA-Z]{3,}/.test(plain)) {
      return '英语';
    }
    return '外语';
  }

  private static unescapeJsonString(value: string): string {
    return value
      .replace(/\\\\/g, '\u0000')
      .replace(/\\n/g, '\n')
      .replace(/\\r/g, '\r')
      .replace(/\\t/g, '\t')
      .replace(/\\"/g, '"')
      .replace(/\u0000/g, '\\');
  }

  private static normalizeForCompare(text: string): string {
    return HtmlParser.htmlToPlainText(text).replace(/\s+/g, '').trim();
  }

  static parsePostTranslation(
    raw: string,
    sourceTitle: string,
    sourceHtml: string
  ): PostTranslation {
    let cleaned = raw.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    if (cleaned.includes(PLACEHOLDER_TITLE) || cleaned.includes(PLACEHOLDER_HTML)) {
      throw new Error('模型把输出格式的占位说明当成了译文，请换用更强的模型或重试');
    }

    let parsedTitle = sourceTitle;
    let parsedHtml = '';

    const titleStart = cleaned.indexOf(TITLE_OPEN);
    const titleEnd = cleaned.indexOf(TITLE_CLOSE);
    const htmlStart = cleaned.indexOf(HTML_OPEN);
    if (titleStart >= 0 && titleEnd > titleStart && htmlStart >= 0) {
      const t = cleaned.substring(titleStart + TITLE_OPEN.length, titleEnd).trim();
      let h = cleaned.substring(htmlStart + HTML_OPEN.length);
      const htmlEnd = h.indexOf(HTML_CLOSE);
      if (htmlEnd >= 0) {
        h = h.substring(0, htmlEnd);
      }
      if (t.length > 0) {
        parsedTitle = t;
      }
      parsedHtml = h.trim();
    }

    if (parsedHtml.length === 0) {
      const start = cleaned.indexOf('{');
      const end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        const slice = cleaned.substring(start, end + 1);
        try {
          const obj = FlexParsers.asObject(JSON.parse(slice) as JsonValue);
          const jHtml = FlexParsers.readString(obj, 'html');
          const jTitle = FlexParsers.readString(obj, 'title');
          if (jHtml !== undefined && jHtml.trim().length > 0) {
            parsedHtml = jHtml.trim();
            if (jTitle !== undefined && jTitle.trim().length > 0) {
              parsedTitle = jTitle.trim();
            }
          }
        } catch (_jsonErr) {
          const htmlMatch = /"html"\s*:\s*"((?:[^"\\]|\\.)*)"/s.exec(slice);
          if (htmlMatch !== null && htmlMatch[1].trim().length > 0) {
            parsedHtml = TranslationParser.unescapeJsonString(htmlMatch[1]).trim();
            const titleMatch = /"title"\s*:\s*"((?:[^"\\]|\\.)*)"/s.exec(slice);
            if (titleMatch !== null && titleMatch[1].trim().length > 0) {
              parsedTitle = TranslationParser.unescapeJsonString(titleMatch[1]).trim();
            }
          }
        }
      }
    }

    if (parsedHtml.length === 0) {
      parsedHtml = cleaned;
    }

    const srcNorm = TranslationParser.normalizeForCompare(`${sourceTitle}${sourceHtml}`);
    const outNorm = TranslationParser.normalizeForCompare(`${parsedTitle}${parsedHtml}`);
    if (srcNorm.length > 0 && srcNorm === outNorm) {
      throw new Error('译文与原文完全一致，模型可能未执行翻译，请检查提示词或更换模型');
    }

    return {
      title: parsedTitle,
      html: parsedHtml,
      sourceLanguage: TranslationParser.detectSourceLanguage(`${sourceTitle} ${sourceHtml}`)
    };
  }
}
