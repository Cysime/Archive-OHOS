#!/usr/bin/env node
/**
 * Pure-logic unit test runner for HarmonyOS ArkTS (.ets) core modules.
 * Transpiles real .ets sources using TypeScript bundled with HarmonyOS Command Line Tools
 * into .hvigor/outputs/unit-tests-stage and executes assertions against the compiled ESM modules.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const TOOL_HOME = process.env.TOOL_HOME || path.join(os.homedir(), 'Library/Huawei/command-line-tools');
const tsPath = path.join(TOOL_HOME, 'hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const ts = require(tsPath);

const HARMONY_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const ETS_ROOT = path.join(HARMONY_ROOT, 'entry', 'src', 'main', 'ets');
const STAGE_ROOT = path.join(HARMONY_ROOT, '.hvigor', 'outputs', 'unit-tests-stage');

const PURE_MODULES = [
  'core/api/ApiConstants.ets',
  'core/api/UrlProvider.ets',
  'core/api/ApiMemoryCache.ets',
  'core/api/FlexParsers.ets',
  'core/api/Dtos.ets',
  'core/error/AppError.ets',
  'core/util/HtmlParser.ets',
  'core/util/Fmt.ets',
  'data/util/PostSort.ets',
  'data/download/DownloadModels.ets',
  'data/ai/ModelProfile.ets',
  'data/ai/AiProtocol.ets',
  'data/ai/TranslationParser.ets',
  'data/ops/UpdateParser.ets'
];

fs.rmSync(STAGE_ROOT, { recursive: true, force: true });
for (const rel of PURE_MODULES) {
  const srcPath = path.join(ETS_ROOT, rel);
  const dstPath = path.join(STAGE_ROOT, rel.replace(/\.ets$/, '.mjs'));
  fs.mkdirSync(path.dirname(dstPath), { recursive: true });
  const source = fs.readFileSync(srcPath, 'utf8');
  const transpiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
      strict: false
    },
    fileName: srcPath
  });
  let js = transpiled.outputText;
  js = js.replace(/(from\s+['"])(\.\.?\/[^'"]+)(['"])/g, (_, p1, p2, p3) => {
    return p2.endsWith('.mjs') ? `${p1}${p2}${p3}` : `${p1}${p2}.mjs${p3}`;
  });
  fs.writeFileSync(dstPath, js, 'utf8');
}

const load = (relMjs) => import(pathToFileURL(path.join(STAGE_ROOT, relMjs)).href);

const { UrlProvider } = await load('core/api/UrlProvider.mjs');
const { ApiMemoryCache } = await load('core/api/ApiMemoryCache.mjs');
const { FlexParsers } = await load('core/api/FlexParsers.mjs');
const { DtoParsers, AttachmentHelper, MediaKind } = await load('core/api/Dtos.mjs');
const { HtmlParser, HtmlNodeType } = await load('core/util/HtmlParser.mjs');
const { Fmt } = await load('core/util/Fmt.mjs');
const { PostSortHelper, PostSortMode } = await load('data/util/PostSort.mjs');
const { DownloadNamingHelper } = await load('data/download/DownloadModels.mjs');
const { ApiType } = await load('data/ai/ModelProfile.mjs');
const { AiProtocol } = await load('data/ai/AiProtocol.mjs');
const { TranslationParser } = await load('data/ai/TranslationParser.mjs');
const { UpdateParser } = await load('data/ops/UpdateParser.mjs');

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`PASS: ${name}`);
}

test('UrlProvider derives img/file/icon/banner/apiV1 subdomains', () => {
  assert.equal(UrlProvider.apiV1('https://pawchive.pw/'), 'https://pawchive.pw/api/v1');
  assert.equal(
    UrlProvider.thumbnailUrl('https://pawchive.pw', '/a9/d7/abc.jpg'),
    'https://img.pawchive.pw/thumbnail/data/a9/d7/abc.jpg'
  );
  assert.equal(
    UrlProvider.fileUrl('https://pawchive.pw', '/a9/d7/abc.jpg'),
    'https://file.pawchive.pw/data/a9/d7/abc.jpg'
  );
  assert.equal(
    UrlProvider.iconUrl('https://pawchive.pw/', 'patreon', '12345'),
    'https://pawchive.pw/icons/patreon/12345'
  );
  assert.equal(
    UrlProvider.bannerUrl('https://pawchive.pw', 'fanbox', '999'),
    'https://pawchive.pw/banners/fanbox/999'
  );
  assert.equal(
    UrlProvider.contentImageUrl('https://pawchive.pw', '/uploads/a.png'),
    'https://pawchive.pw/uploads/a.png'
  );
});

test('UrlProvider prefers temp_url / temp_download_url for deferred videos', () => {
  const hls = 'https://t1.pawchive.pw/v/id/master.m3u8?e=1791392960&s=abc';
  const dl = 'https://t1.pawchive.pw/d/id/vid.mp4?e=1791392960&s=abc';
  assert.equal(UrlProvider.playbackUrl('https://pawchive.pw', '/x.mp4', hls), hls);
  assert.equal(UrlProvider.downloadUrl('https://pawchive.pw', '/x.mp4', dl), dl);
  assert.equal(UrlProvider.isTemporaryUrl(hls), true);
  assert.equal(UrlProvider.isTargetSiteUrl(hls, 'https://pawchive.pw'), true);
  assert.equal(UrlProvider.isTargetSiteUrl('https://example.com/a.jpg', 'https://pawchive.pw'), false);
  assert.equal(UrlProvider.isAllowedWebViewUrl('https://pawchive.pw/account/register', 'https://pawchive.pw'), true);
  assert.equal(UrlProvider.isAllowedWebViewUrl('https://challenges.cloudflare.com/turnstile', 'https://pawchive.pw'), true);
  assert.equal(UrlProvider.isAllowedWebViewUrl('https://awhilepowershakily.com/', 'https://pawchive.pw'), false);
});

test('FlexParsers parses Postgres array literal tags and JSON arrays', () => {
  assert.deepEqual(
    FlexParsers.parseFlexStringList('{"Atelier Ryza",Benefits,NSFW,NULL,"a,b","x\\"y"}'),
    ['Atelier Ryza', 'Benefits', 'NSFW', 'a,b', 'x"y']
  );
  assert.deepEqual(FlexParsers.parseFlexStringList(['NSFW', null, 'Art']), ['NSFW', 'Art']);
  assert.deepEqual(FlexParsers.parseFlexStringList('{}'), []);
  assert.equal(FlexParsers.parseFlexUnixSeconds(1700000000), 1700000000);
  assert.equal(FlexParsers.parseFlexUnixSeconds('2026-10-07T00:00:00Z'), 1791331200);
});

test('DtoParsers handles commenter_name fallback & deferred attachments', () => {
  const c1 = DtoParsers.parseComment({ id: '1', commenter: '105541049', commenter_name: 'Captain Keyes', content: 'hi' });
  assert.equal(c1?.commenter, 'Captain Keyes');
  const c2 = DtoParsers.parseComment({ id: '2', commenter: '105541049', content: 'hi' });
  assert.equal(c2?.commenter, '105541049');

  const att = DtoParsers.parseAttachment({
    name: '755699804.mp4',
    deferred: true,
    temp_url: 'https://t1.pawchive.pw/v/1/master.m3u8?e=2000000000&s=x',
    temp_expires: '2099-01-01T00:00:00Z'
  });
  assert.ok(att);
  assert.equal(AttachmentHelper.kind(att), MediaKind.VIDEO);
  assert.equal(AttachmentHelper.hasPlayableSource(att), true);
});

test('HtmlParser single-pass entity decode does not double-decode &amp;lt; or &amp;#39;', () => {
  assert.equal(HtmlParser.decodeEntities('&amp;lt; &amp;#39; &#39; &#x27; &nbsp;'), "&lt; &#39; ' '  ");
  const nodes = HtmlParser.parse('<p>Hello <b>world</b> <a href="https://pawchive.pw">link</a></p><img src="/a.png"/>');
  assert.equal(nodes.length, 2);
  assert.equal(nodes[0].type, HtmlNodeType.PARAGRAPH);
  assert.equal(nodes[1].type, HtmlNodeType.IMAGE);
  assert.equal(nodes[1].src, '/a.png');
  assert.equal(HtmlParser.htmlToPlainText('<p>Line 1</p><script>bad()</script><p>Line 2 &amp; 3</p>'), 'Line 1 Line 2 & 3');
});

test('ApiMemoryCache supports TTL, LRU eviction, and invalidateByPathPrefix', () => {
  const cache = new ApiMemoryCache(2, 1000);
  cache.put('u1|/api/v1/posts', '/api/v1/posts', '[]', 100);
  cache.put('u1|/api/v1/account/favorites?type=post', '/api/v1/account/favorites?type=post', '[1]', 100);
  assert.equal(cache.get('u1|/api/v1/posts', 500), '[]');
  assert.equal(cache.get('u1|/api/v1/posts', 1200), undefined);
  cache.put('u1|/api/v1/account/favorites?type=artist', '/api/v1/account/favorites?type=artist', '[2]', 1300);
  cache.invalidateByPathPrefix('/api/v1/account/favorites');
  assert.equal(cache.size(), 0);
});

test('Fmt formats bytes, dates, and compact counts', () => {
  assert.equal(Fmt.bytes(1536), '1.5 KB');
  assert.equal(Fmt.shortDate('2026-10-07T12:30:00Z'), '2026-10-07');
  assert.equal(Fmt.compactCount(12500), '1.3万');
});

test('PostSortHelper sorts, dedupes by creator, filters fav creators & short queries', () => {
  const sample = [
    { service: 'patreon', creatorId: 'c1', postId: '1', title: 'Beta', published: '2026-10-01', previewOnly: false },
    { service: 'patreon', creatorId: 'c1', postId: '2', title: 'Alpha', published: '2026-10-03', previewOnly: false },
    { service: 'fanbox', creatorId: 'c2', postId: '3', title: 'Gamma', published: '2026-10-02', previewOnly: false }
  ];
  const byNewest = PostSortHelper.sortPosts(sample, PostSortMode.PUBLISHED_DESC);
  assert.deepEqual(byNewest.map((p) => p.postId), ['2', '3', '1']);
  const byTitle = PostSortHelper.sortPosts(sample, PostSortMode.TITLE_ASC);
  assert.deepEqual(byTitle.map((p) => p.postId), ['2', '1', '3']);
  const dedupedCreator = PostSortHelper.deduplicateByCreator(byNewest);
  assert.deepEqual(dedupedCreator.map((p) => p.postId), ['2', '3']);
  const filteredFav = PostSortHelper.filterOutCreators(byNewest, new Set(['patreon:c1']));
  assert.deepEqual(filteredFav.map((p) => p.postId), ['3']);
  const shortFiltered = PostSortHelper.filterByShortQuery(sample, 'ga');
  assert.deepEqual(shortFiltered.map((p) => p.postId), ['3']);
});

test('DownloadNamingHelper formats names, strips signed query for fingerprint, and matches rules', () => {
  const formatted = DownloadNamingHelper.formatFileName(
    '{creator}_{post_id}_{index}_{name}',
    'patreon',
    'Alice/Bob',
    '999',
    0,
    'cover:01.png'
  );
  assert.equal(formatted, 'Alice_Bob_999_1_cover_01.png');

  const fp1 = DownloadNamingHelper.fingerprint('https://t1.pawchive.pw/d/1/a.mp4?e=100&s=aaa', 'patreon', 'c1', 'p1');
  const fp2 = DownloadNamingHelper.fingerprint('https://t1.pawchive.pw/d/1/a.mp4?e=200&s=bbb', 'patreon', 'c1', 'p1');
  assert.equal(fp1, fp2);

  const rule = { id: 1, name: 'Patreon Videos', service: 'patreon', mediaKinds: [MediaKind.VIDEO], enabled: true, createdAt: 0 };
  assert.equal(DownloadNamingHelper.matchesRule(rule, 'patreon', 'c1', { name: 'clip.mp4', previewOnly: false, deferred: true }), true);
  assert.equal(DownloadNamingHelper.matchesRule(rule, 'fanbox', 'c1', { name: 'clip.mp4', previewOnly: false, deferred: true }), false);
});

test('AiProtocol builds provider-specific bodies, enforces Anthropic temp/top_p exclusivity & omits disabled params', () => {
  const anthProfile = {
    id: 'p1', name: 'Claude', apiType: ApiType.ANTHROPIC,
    url: 'https://api.anthropic.com/v1/messages', model: 'claude-3-7-sonnet',
    temperature: 0.7, topP: 0.9, enableThinking: false, enableWebSearch: false
  };
  const anthReq = AiProtocol.buildRequest(anthProfile, 'sk-ant', 'sys', [], 'hello');
  assert.equal(anthReq.headers['x-api-key'], 'sk-ant');
  const anthBody = JSON.parse(anthReq.body);
  assert.equal(anthBody.temperature, 0.7);
  assert.equal(anthBody.top_p, undefined);
  assert.equal(anthBody.thinking, undefined);
  assert.equal(anthBody.tools, undefined);

  const gemProfile = {
    id: 'p2', name: 'Gemini', apiType: ApiType.GEMINI,
    url: 'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent',
    model: 'gemini-2.5-flash', enableThinking: true, enableWebSearch: true
  };
  const gemReq = AiProtocol.buildRequest(gemProfile, 'gk-123', 'sys', [], 'hi');
  assert.equal(gemReq.url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent');
  assert.equal(gemReq.headers['x-goog-api-key'], 'gk-123');
  const gemReply = AiProtocol.parseReply(ApiType.GEMINI, JSON.stringify({
    candidates: [{
      content: { parts: [{ thought: true, text: 'thinking...' }, { text: 'Final answer' }] },
      groundingMetadata: {}
    }]
  }));
  assert.equal(gemReply.text, 'Final answer');
  assert.equal(gemReply.reasoningChars, 11);
  assert.equal(gemReply.searchSignal, true);
});

test('TranslationParser parses sentinels, repairs broken JSON newlines, and catches placeholders/fake translations', () => {
  const sentinel = '<<<TITLE\n新标题\nTITLE>>>\n<<<HTML\n<p>已翻译正文</p>\nHTML>>>';
  const r1 = TranslationParser.parsePostTranslation(sentinel, 'New Title', '<p>Original body</p>');
  assert.equal(r1.title, '新标题');
  assert.equal(r1.html, '<p>已翻译正文</p>');
  assert.equal(r1.sourceLanguage, '英语');

  const brokenJson = '{"title": "标题", "html": "<p>第一行\n第二行</p>"}';
  const r2 = TranslationParser.parsePostTranslation(brokenJson, 'Title', '<p>Line 1\nLine 2</p>');
  assert.equal(r2.title, '标题');
  assert.equal(r2.html, '<p>第一行\n第二行</p>');

  assert.throws(
    () => TranslationParser.parsePostTranslation('<<<TITLE\n<译文标题>\nTITLE>>>\n<<<HTML\n<译文正文 HTML>\nHTML>>>', 'A', '<p>B</p>'),
    /占位说明/
  );
  assert.throws(
    () => TranslationParser.parsePostTranslation('<<<TITLE\nSame\nTITLE>>>\n<<<HTML\n<p>Text</p>\nHTML>>>', 'Same', '<p>Text</p>'),
    /完全一致/
  );
});

test('UpdateParser compares semver and parses GitHub releases.atom fallback with STABLE/BETA channel rules', () => {
  assert.equal(UpdateParser.compareSemver('1.0.5', '1.0.4'), 1);
  assert.equal(UpdateParser.compareSemver('1.0.5', '1.0.5-beta.1'), 1);
  assert.equal(UpdateParser.compareSemver('v1.0.4', '1.0.4'), 0);

  const atomXml = `<?xml version="1.0" encoding="UTF-8"?>
  <feed>
    <entry>
      <title>v1.1.0-beta.1</title>
      <link href="https://github.com/Cysime/Archive-OHOS/releases/tag/v1.1.0-beta.1"/>
      <updated>2026-11-28T00:00:00Z</updated>
    </entry>
    <entry>
      <title>v1.0.5</title>
      <link href="https://github.com/Cysime/Archive-OHOS/releases/tag/v1.0.5"/>
      <updated>2026-11-27T00:00:00Z</updated>
    </entry>
  </feed>`;

  const stable = UpdateParser.parseReleasesAtom(atomXml, 'STABLE', 'https://github.com/Cysime/Archive-OHOS/releases');
  assert.equal(stable?.tagName, 'v1.0.5');
  assert.equal(stable?.fromAtomFallback, true);

  const beta = UpdateParser.parseReleasesAtom(atomXml, 'BETA', 'https://github.com/Cysime/Archive-OHOS/releases');
  assert.equal(beta?.tagName, 'v1.1.0-beta.1');
});

console.log(`\nALL ${passed} UNIT TESTS PASSED.`);
