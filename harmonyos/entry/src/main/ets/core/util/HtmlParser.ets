/**
 * 极简 HTML → 节点解析器（对齐上游 app/util/HtmlParser.kt）。
 * 支持 p/br/b/strong/i/em/u/a/img，无 WebView 依赖，支持单遍实体解码防止二次解码篡改。
 */
export interface HtmlSpan {
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  link?: string;
}

export enum HtmlNodeType {
  PARAGRAPH = 'PARAGRAPH',
  IMAGE = 'IMAGE'
}

export interface HtmlNode {
  type: HtmlNodeType;
  spans?: HtmlSpan[];
  src?: string;
}

const ENTITY_REGEX: RegExp = /&nbsp;|&lt;|&gt;|&quot;|&apos;|&amp;|&#\d+;|&#[xX][0-9a-fA-F]+;/g;

export class HtmlParser {
  static parse(html: string): HtmlNode[] {
    if (html.trim().length === 0) {
      return [];
    }
    const cleaned = html
      .replace(/<(script|style)[^>]*>[\s\S]*?<\/\s*\1\s*>/gi, '')
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/\r/g, '')
      .replace(/\n/g, ' ');

    const nodes: HtmlNode[] = [];
    let spans: HtmlSpan[] = [];
    let bold = false;
    let italic = false;
    let underline = false;
    let link: string | undefined = undefined;
    let buffer = '';

    const flushText = (): void => {
      if (buffer.length > 0) {
        spans.push({
          text: buffer,
          bold: bold,
          italic: italic,
          underline: underline,
          link: link
        });
        buffer = '';
      }
    };

    const flushParagraph = (): void => {
      flushText();
      if (spans.length > 0) {
        nodes.push({
          type: HtmlNodeType.PARAGRAPH,
          spans: spans
        });
        spans = [];
      }
    };

    let i = 0;
    while (i < cleaned.length) {
      const lt = cleaned.indexOf('<', i);
      if (lt < 0) {
        buffer += HtmlParser.decodeEntities(cleaned.substring(i));
        break;
      }
      if (lt > i) {
        buffer += HtmlParser.decodeEntities(cleaned.substring(i, lt));
      }
      const gt = cleaned.indexOf('>', lt);
      if (gt < 0) {
        buffer += cleaned.substring(lt);
        break;
      }
      const tag = cleaned.substring(lt + 1, gt).trim();
      i = gt + 1;
      const lower = tag.toLowerCase();

      if (lower === 'img' || lower.startsWith('img ') || lower.startsWith('img/')) {
        flushText();
        const src = HtmlParser.attrOf(tag, 'src');
        if (src !== undefined) {
          nodes.push({ type: HtmlNodeType.IMAGE, src: src });
        }
      } else if (lower === 'br' || lower.startsWith('br ') || lower === 'br/' ||
        lower === 'p' || lower.startsWith('p ') || lower === '/p') {
        flushParagraph();
      } else if (lower === 'b' || lower === 'strong') {
        flushText();
        bold = true;
      } else if (lower === '/b' || lower === '/strong') {
        flushText();
        bold = false;
      } else if (lower === 'i' || lower === 'em') {
        flushText();
        italic = true;
      } else if (lower === '/i' || lower === '/em') {
        flushText();
        italic = false;
      } else if (lower === 'u') {
        flushText();
        underline = true;
      } else if (lower === '/u') {
        flushText();
        underline = false;
      } else if (lower === 'a' || lower.startsWith('a ')) {
        flushText();
        link = HtmlParser.attrOf(tag, 'href');
      } else if (lower === '/a') {
        flushText();
        link = undefined;
      }
    }
    flushParagraph();
    return nodes;
  }

  private static attrOf(tag: string, name: string): string | undefined {
    const doubleQuote = new RegExp(`${name}\\s*=\\s*"([^"]*)"`, 'i');
    const dm = doubleQuote.exec(tag);
    if (dm !== null && dm[1].trim().length > 0) {
      return dm[1];
    }
    const singleQuote = new RegExp(`${name}\\s*=\\s*'([^']*)'`, 'i');
    const sm = singleQuote.exec(tag);
    if (sm !== null && sm[1].trim().length > 0) {
      return sm[1];
    }
    return undefined;
  }

  /**
   * 实体单遍解码：避免 `&amp;lt;` 被二次解码为 `<`。
   */
  static decodeEntities(text: string): string {
    return text.replace(ENTITY_REGEX, (entity: string): string => {
      if (entity === '&nbsp;') {
        return ' ';
      }
      if (entity === '&lt;') {
        return '<';
      }
      if (entity === '&gt;') {
        return '>';
      }
      if (entity === '&quot;') {
        return '"';
      }
      if (entity === '&apos;') {
        return "'";
      }
      if (entity === '&amp;') {
        return '&';
      }
      const body = entity.substring(2, entity.length - 1);
      const isHex = body.startsWith('x') || body.startsWith('X');
      const codePoint = isHex ? parseInt(body.substring(1), 16) : parseInt(body, 10);
      if (!Number.isNaN(codePoint) && codePoint >= 1 && codePoint <= 0x10FFFF) {
        return String.fromCodePoint(codePoint);
      }
      return entity;
    });
  }

  static htmlToPlainText(html?: string): string {
    if (html === undefined || html.trim().length === 0) {
      return '';
    }
    const withoutBlocks = html
      .replace(/<(script|style)[^>]*>[\s\S]*?<\/\s*\1\s*>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<br\s*\/?>/gi, ' ')
      .replace(/<\/(p|div|blockquote|li|h[1-6])\s*>/gi, ' ')
      .replace(/<[^>]*>/g, ' ');
    return HtmlParser.decodeEntities(withoutBlocks).replace(/\s+/g, ' ').trim();
  }
}
