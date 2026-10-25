/* fork (docs/E2E.md §10.1): страница комнаты в приложении — только
 * плеер. С флагом `__forkNativeChat` переписки на странице нет; без флага
 * (браузер) всё как было.
 *
 * Запуск: NODE_PATH=$(npm root -g) node test/fork/web/room_native_chat.test.js
 */
const { chromium } = require('playwright');
const path = require('path');

const base = 'file://' + path.resolve(__dirname, '../../../pocketbase/pb_public/watch/room/index.html');
const PHONE = { width: 390, height: 844 };

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM || undefined,
  });
  let ok = true;
  const check = (name, cond) => {
    console.log((cond ? '  ✓ ' : '  ✗ ') + name);
    if (!cond) ok = false;
  };

  async function open(native) {
    const context = await browser.newContext({ viewport: PHONE, isMobile: true });
    // Сети в тесте нет: внешнее (Centrifugo, шрифты) обрываем сразу.
    await context.route('**/*', (r) =>
      r.request().url().startsWith('file:') ? r.continue() : r.abort());
    if (native) await context.addInitScript(() => { window.__forkNativeChat = true; });
    const page = await context.newPage();
    await page.goto(base + '#native1test', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(800);
    return page;
  }
  const visible = (page, sel) => page.locator(sel).isVisible().catch(() => false);

  console.log('1. в приложении чата на странице нет');
  const app = await open(true);
  check('переписка скрыта', !(await visible(app, '.side')));
  check('поле ввода скрыто', !(await visible(app, '.composer')));
  check('кнопки чата нет', !(await visible(app, '#chatToggle')));

  console.log('2. в браузере чат на месте');
  const web = await open(false);
  check('переписка видна', await visible(web, '.side'));
  check('кнопка чата есть', await visible(web, '#chatToggle'));

  await browser.close();
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
