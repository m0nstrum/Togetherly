/* fork (комментарии TikTok, 22.10): лист комментариев в совместной ленте.
 *
 * Приложение отвечает на `reelsComments` (здесь — подставной мост с
 * готовыми ответами), страница рисует: кнопка со счётчиком только у роликов
 * TikTok, лист с комментариями, ответы под комментарием, подгрузка при
 * прокрутке, «В наш чат», закрытие крестиком и касанием по ролику.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/reels-comments.test.js
 *   SHOTS=<папка> — снимки листа.
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.webp': 'image/webp', '.png': 'image/png' };

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
      let file = path.join(ROOT, url);
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      if (!file.startsWith(ROOT) || !fs.existsSync(file)) return res.writeHead(404).end('нет');
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

const FAKE_CENTRIFUGE = `
window.Centrifuge = class {
  constructor() { this._on = {}; }
  on(ev, cb) { (this._on[ev] = this._on[ev] || []).push(cb); return this; }
  connect() { (this._on.connected || []).forEach((cb) => cb({})); }
  disconnect() {}
  newSubscription() {
    const handlers = {};
    return {
      on(ev, cb) { (handlers[ev] = handlers[ev] || []).push(cb); return this; },
      subscribe() { setTimeout(() => (handlers.subscribed || []).forEach((cb) => cb({})), 0); },
      unsubscribe() {},
      publish(d) { (window.__pub = window.__pub || []).push(d); return Promise.resolve(); },
      presence() { return Promise.resolve({ clients: { a: { user: 'me' } } }); },
    };
  }
};`;

/** Мост приложения: лента из двух роликов TikTok, комментарии — страницами. */
const APP = `
  window.__asked = [];
  window.__chat = [];
  window.__togetherlyChrome = 1;
  window.__forkNativeChat = true;
  const now = Math.floor(Date.now() / 1000);
  const mk = (i, extra) => Object.assign({ cid: String(9000000 + i), name: 'Зритель ' + i, avatar: '', text: 'Комментарий номер ' + i,
    likes: 1500 - i * 10, replies: 0, time: now - i * 3600, authorLiked: false, pinned: false, photo: false }, extra || {});
  window.flutter_inappwebview = { callHandler: async (h, a) => {
    if (h === 'reelsFeed') return ['7600000000000000001', '7600000000000000002'];
    if (h === 'forkChat') { window.__chat.push(a.text); return null; }
    if (h !== 'reelsComments') return null;
    window.__asked.push(a);
    if (a.cid) return { ok: true, total: 3, cursor: 10, more: false, items: [mk(101, { text: 'ответ' }), mk(102, { text: 'ещё ответ' })] };
    if (a.cursor === 0) return { ok: true, total: 39758, cursor: 20, more: true,
      items: [mk(1, { replies: 2, pinned: true, text: 'Это лучшее, что я видел сегодня 😂' })].concat(Array.from({ length: 19 }, (_, i) => mk(i + 2))) };
    return { ok: true, total: 39758, cursor: a.cursor + 20, more: false, items: Array.from({ length: 5 }, (_, i) => mk(a.cursor + i + 1)) };
  } };
`;

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const srv = await serve();
  const base = `http://127.0.0.1:${srv.address().port}`;
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 2, locale: 'ru-RU', isMobile: true, hasTouch: true });
  await ctx.route(/^https?:\/\/(?!127\.0\.0\.1)/, (r) => r.abort());
  await ctx.route('**/vendor/centrifuge.js', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: FAKE_CENTRIFUGE }));
  await ctx.route('**/api/watch/token', (r) => r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, userId: 'me', channel: 'watch:cm1', connectionToken: 'т', subscriptionToken: 'т' }) }));
  const p = await ctx.newPage();
  p.on('pageerror', (e) => { ok = false; console.log('  !! ошибка страницы:', '' + e); });
  await p.addInitScript(APP);
  await p.goto(base + '/watch/reels/?feed=tiktok&name=%D0%90%D0%BD%D1%8F#cm1', { waitUntil: 'domcontentloaded' });
  await p.waitForFunction(() => { const b = document.querySelector('.rl-cmt'); return b && !b.hidden; }, null, { timeout: 15000 });
  await p.waitForFunction(() => (document.querySelector('.rl-cmt .cm-n') || {}).textContent, null, { timeout: 5000 }).catch(() => {});

  console.log('1. кнопка');
  check('у ролика TikTok есть кнопка комментариев', await p.isVisible('.rl-cmt'));
  const n = await p.textContent('.rl-cmt .cm-n');
  check('со счётчиком в одну строку, как у площадки', n === '39,8К', JSON.stringify(n));
  if (process.env.SHOTS) await p.screenshot({ path: path.join(process.env.SHOTS, 'cm-0-rail.png') });

  console.log('2. лист');
  await p.click('.rl-cmt');
  await p.waitForTimeout(450);
  check('лист открылся', await p.evaluate(() => document.querySelector('.rl').classList.contains('cmts-open')));
  check('в шапке число', /39,8 тыс. комментариев/.test(await p.textContent('.cm-head b')), await p.textContent('.cm-head b'));
  check('первая страница — 20 комментариев', (await p.$$('.cm-sheet .cm-item:not(.is-reply)')).length === 20);
  check('закреплённый подписан', /Закреплён/.test(await p.textContent('.cm-item .cm-name em')));
  check('первая страница из кэша — второй раз не спрашиваем', (await p.evaluate(() => window.__asked.length)) === 1);
  if (process.env.SHOTS) await p.screenshot({ path: path.join(process.env.SHOTS, 'cm-1-sheet.png') });

  console.log('3. ответы и подгрузка');
  await p.click('.cm-more');
  await p.waitForTimeout(200);
  check('ответы раскрылись под комментарием', (await p.$$('.cm-replies .cm-item.is-reply')).length === 2);
  check('кнопка стала «Скрыть»', (await p.textContent('.cm-more')) === 'Скрыть');
  if (process.env.SHOTS) await p.screenshot({ path: path.join(process.env.SHOTS, 'cm-2-replies.png') });
  await p.evaluate(() => { const l = document.querySelector('.cm-list'); l.scrollTop = l.scrollHeight; l.dispatchEvent(new Event('scroll')); });
  await p.waitForTimeout(300);
  check('прокрутка вниз подгрузила ещё', (await p.$$('.cm-sheet .cm-item:not(.is-reply)')).length === 25);

  console.log('4. в наш чат');
  await p.click('.cm-quote');
  await p.waitForTimeout(100);
  const sent = await p.evaluate(() => window.__chat);
  check('комментарий ушёл в чат пары', sent.length === 1 && /лучшее/.test(sent[0]) && /Зритель 1/.test(sent[0]), JSON.stringify(sent));
  check('и кнопка сказала об этом', /Отправили/.test(await p.textContent('.cm-quote')));

  console.log('5. закрыть');
  await p.click('.cm-x');
  await p.waitForTimeout(200);
  check('крестик закрывает', !(await p.evaluate(() => document.querySelector('.rl').classList.contains('cmts-open'))));
  await p.click('.rl-cmt');
  await p.waitForTimeout(200);
  await p.mouse.click(196, 120);
  await p.waitForTimeout(250);
  check('касание по ролику закрывает', !(await p.evaluate(() => document.querySelector('.rl').classList.contains('cmts-open'))));
  await p.click('.rl-cmt');
  await p.click('.rl-chatbtn').catch(() => {});
  await p.evaluate(() => document.querySelector('.rl-chatbtn').click());
  await p.waitForTimeout(150);
  check('чат и комментарии не открыты разом', await p.evaluate(() => {
    const r = document.querySelector('.rl'); return !(r.classList.contains('cmts-open') && r.classList.contains('chat-open'));
  }));

  console.log('6. другие площадки');
  await p.evaluate(() => window.forkReelShown('shorts:abcdefghijk'));
  check('у Shorts кнопки нет', !(await p.isVisible('.rl-cmt')));

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
