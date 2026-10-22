/* fork (комната как в Rave, 22.10): во встроенном окне приложения страница —
 * только окно видео, а о каждом действии рассказывает приложению.
 *
 * Проверяет: шапка, поле ссылки и чат скрыты, кадр во всё окно; в пустом окне
 * кнопка «Выбрать видео» зовёт приложение; команды `window.forkRoom`
 * доходят; действие партнёра уходит приложению и вспыхивает на кадре; в
 * обычном браузере всё по-старому.
 *
 * Запуск: node pocketbase/pb_public/watch/tests/room-shell.test.js
 */
const { chromium } = require('/home/alelx/.hermes/hermes-agent/node_modules/playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.woff2': 'font/woff2',
  '.png': 'image/png',
};

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

/** Centrifuge без сети: подписка сразу, публикации копятся, входящие — руками. */
const FAKE_CENTRIFUGE = `
window.Centrifuge = class {
  constructor() { this._on = {}; }
  on(ev, cb) { (this._on[ev] = this._on[ev] || []).push(cb); return this; }
  connect() { (this._on.connected || []).forEach((cb) => cb({})); }
  disconnect() {}
  newSubscription() {
    const handlers = {};
    window.__deliver = (data) => (handlers.publication || []).forEach((cb) => cb({ data }));
    return {
      on(ev, cb) { (handlers[ev] = handlers[ev] || []).push(cb); return this; },
      subscribe() { setTimeout(() => (handlers.subscribed || []).forEach((cb) => cb({})), 0); },
      unsubscribe() {},
      publish(d) { (window.__pub = window.__pub || []).push(d); return Promise.resolve(); },
      presence() { return Promise.resolve({ clients: { a: { user: 'me' }, b: { user: 'her' } } }); },
    };
  }
};`;

const APP = (shell) => `
  window.__events = [];
  window.flutter_inappwebview = { callHandler: (n, d) => { window.__events.push([n, d]); return Promise.resolve(null); } };
  window.__togetherlyChrome = 1;
  window.__forkNativeChat = true;
  ${shell ? "window.__forkShell = true; window.__forkPartner = 'Аня';" : ''}
`;

let ok = true;
const check = (n, c, x = '') => { console.log((c ? '  ✓ ' : '  ✗ ') + n, x); if (!c) ok = false; };

(async () => {
  const srv = await serve();
  const base = `http://127.0.0.1:${srv.address().port}`;
  const browser = await chromium.launch();

  async function open(shell) {
    const ctx = await browser.newContext({ viewport: { width: 393, height: 221 }, locale: 'ru-RU' });
    await ctx.route(/^https?:\/\/(?!127\.0\.0\.1)/, (r) => r.abort());
    await ctx.route('**/vendor/centrifuge.js', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: FAKE_CENTRIFUGE }));
    await ctx.route('**/api/watch/token', (r) => r.fulfill({
      status: 200, contentType: 'application/json',
      body: JSON.stringify({ ok: true, userId: 'me', channel: 'watch:shell1', connectionToken: 'т', subscriptionToken: 'т' }),
    }));
    const p = await ctx.newPage();
    p.on('pageerror', (e) => { ok = false; console.log('  !! ошибка страницы:', '' + e); });
    await p.addInitScript(APP(shell));
    await p.goto(base + '/watch/room/#shell1', { waitUntil: 'domcontentloaded' });
    await p.waitForTimeout(700);
    return p;
  }
  const events = (p, t) => p.evaluate((t) => window.__events.filter((e) => e[0] === 'forkRoom' && e[1].t === t).map((e) => e[1]), t);

  console.log('1. окно видео в приложении');
  const p = await open(true);
  const hidden = await p.evaluate(() => ['.top--room', '.source', '.composer', '.side']
    .map((s) => getComputedStyle(document.querySelector(s)).display));
  check('шапка, поле ссылки и чат скрыты', hidden.every((d) => d === 'none'), JSON.stringify(hidden));
  const box = await p.evaluate(() => { const r = document.querySelector('#player').getBoundingClientRect(); return [r.width, r.height]; });
  check('кадр во всё окно', box[0] === 393 && box[1] === 221, JSON.stringify(box));
  check('сказали приложению, сколько в комнате', (await events(p, 'viewers')).some((e) => e.n === 2));

  await p.click('.fork-empty button');
  check('«Выбрать видео» зовёт приложение', (await events(p, 'pick')).length === 1);

  console.log('2. команды приложения');
  const good = await p.evaluate(() => window.forkRoom.play('https://youtu.be/abcdefghijk'));
  check('forkRoom.play включает ссылку', good === true);
  const src = await events(p, 'source');
  check('приложение узнало, что включили вы', src.length === 1 && src[0].by === 'me' && src[0].kind === 'youtube', JSON.stringify(src));
  check('партнёру ушла ссылка', await p.evaluate(() => (window.__pub || []).some((m) => m.t === 'source')));
  const bad = await p.evaluate(() => window.forkRoom.play('просто текст'));
  check('плохая ссылка — отказ', bad === false);
  check('и отказ объяснён вслух', (await events(p, 'status')).some((e) => e.loud && /ссылк/i.test(e.text)));

  console.log('3. действие партнёра');
  await p.evaluate(() => window.__deliver({ t: 'pause', at: 754, from: 'her' }));
  await p.waitForTimeout(200);
  const acts = await events(p, 'act');
  check('пауза партнёра — приложению', acts.some((e) => e.by === 'partner' && e.at === 754), JSON.stringify(acts));
  const flash = await p.evaluate(() => { const el = document.querySelector('.fork-act'); return el && el.classList.contains('is-on') ? el.textContent : ''; });
  check('и вспышка на кадре с именем и временем', /Аня/.test(flash) && /12:34/.test(flash), JSON.stringify(flash));
  await p.evaluate(() => window.__deliver({ t: 'sync', at: 760, playing: true, from: 'her' }));
  await p.waitForTimeout(100);
  check('такт ведущего — не действие', (await events(p, 'act')).length === acts.length);

  console.log('4. обычный браузер — по-старому');
  const w = await open(false);
  const shown = await w.evaluate(() => getComputedStyle(document.querySelector('.source')).display);
  check('поле ссылки на месте', shown !== 'none', shown);
  check('команд приложения нет', await w.evaluate(() => typeof window.forkRoom === 'undefined'));
  check('событий приложению нет', (await w.evaluate(() => window.__events.filter((e) => e[0] === 'forkRoom').length)) === 0);

  await browser.close();
  srv.close();
  console.log(ok ? '\nВСЁ СОШЛОСЬ' : '\nЕСТЬ РАСХОЖДЕНИЯ');
  process.exit(ok ? 0 : 1);
})();
