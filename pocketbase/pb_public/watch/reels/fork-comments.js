/* fork (комментарии TikTok, 22.10): лист комментариев в совместной ленте.
 *
 * Комментарии берёт приложение — браузером на tiktok.com, тем же путём, что
 * и саму ленту (`reelsComments`, lib/fork/reels/tiktok_comments.dart):
 * сервер пары их не видит. Страница только рисует: кнопка со счётчиком в
 * столбике, лист снизу — ролик уезжает вверх, как с открытым чатом, —
 * ответы раскрываются под комментарием, «В наш чат» пересылает его партнёру.
 *
 * С reels.js связь через `window.__forkReels` (ручки) и два вызова оттуда:
 * `forkReelShown` (сменился ролик) и `forkCommentsClose`.
 * Стережёт tests/reels-comments.test.js.
 */
(() => {
  'use strict';
  // Лента строит разметку по готовности документа — встаём следом за ней.
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  function init() {
    const H = window.__forkReels;
    if (!H) return;
    const root = H.root();
    if (!root) return;
    const btn = root.querySelector('.rl-cmt');
    if (!btn) return;

    const T = H.ru ? {
      title: 'Комментарии', n: (n) => fmt(n) + ' ' + plural(n, 'комментарий', 'комментария', 'комментариев'),
      close: 'Закрыть', empty: 'Комментариев пока нет', loading: 'Загружаем комментарии…',
      failed: 'Комментарии не загрузились', blocked: 'TikTok не отдаёт комментарии с вашего адреса',
      retry: 'Повторить', replies: (n) => 'Ответы (' + fmt(n) + ')', more: 'Ещё ответы', hide: 'Скрыть',
      quote: 'В наш чат', sent: 'Отправили в чат', liked: 'Нравится автору', pinned: 'Закреплён автором',
      photo: 'фото', now: 'сейчас', m: 'мин', h: 'ч', d: 'дн', w: 'нед', k: ' тыс.', mln: ' млн',
    } : {
      title: 'Comments', n: (n) => fmt(n) + (n === 1 ? ' comment' : ' comments'),
      close: 'Close', empty: 'No comments yet', loading: 'Loading comments…',
      failed: 'Comments didn’t load', blocked: 'TikTok doesn’t serve comments to your address',
      retry: 'Retry', replies: (n) => 'Replies (' + fmt(n) + ')', more: 'More replies', hide: 'Hide',
      quote: 'To our chat', sent: 'Sent to the chat', liked: 'Liked by creator', pinned: 'Pinned by creator',
      photo: 'photo', now: 'now', m: 'm', h: 'h', d: 'd', w: 'w', k: 'K', mln: 'M',
    };

    function plural(n, one, few, many) {
      const a = n % 10, b = n % 100;
      if (a === 1 && b !== 11) return one;
      if (a >= 2 && a <= 4 && (b < 12 || b > 14)) return few;
      return many;
    }

    /** 1 245 → «1,2 тыс.» / «1.2K», как у площадок. */
    function fmt(n) {
      n = Number(n) || 0;
      const one = (x) => (Math.round(x * 10) / 10).toString().replace('.', H.ru ? ',' : '.').replace(/[,.]0$/, '');
      if (n >= 1e6) return one(n / 1e6) + T.mln;
      if (n >= 1e4 || (!H.ru && n >= 1e3)) return one(n / 1e3) + T.k;
      return H.ru ? String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') : String(n);
    }

    /** Сколько прошло: «3 ч», «2 нед», старше года — дата. */
    function ago(sec) {
      const s = Math.max(0, Date.now() / 1000 - (Number(sec) || 0));
      if (s < 60) return T.now;
      if (s < 3600) return Math.floor(s / 60) + ' ' + T.m;
      if (s < 86400) return Math.floor(s / 3600) + ' ' + T.h;
      if (s < 7 * 86400) return Math.floor(s / 86400) + ' ' + T.d;
      if (s < 365 * 86400) return Math.floor(s / (7 * 86400)) + ' ' + T.w;
      const d = new Date(sec * 1000);
      return d.getDate() + '.' + String(d.getMonth() + 1).padStart(2, '0') + '.' + d.getFullYear();
    }

    const SVG_BUBBLE = '<svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true"><path fill="currentColor" d="M12 3C6.9 3 3 6.5 3 10.9c0 2.5 1.3 4.7 3.3 6.2-.1 1.3-.6 2.6-1.6 3.6-.2.2 0 .6.3.6 2.2-.1 4-.9 5.2-1.9.6.1 1.2.2 1.8.2 5.1 0 9-3.5 9-7.9S17.1 3 12 3zm-4.2 9.3a1.3 1.3 0 1 1 0-2.6 1.3 1.3 0 0 1 0 2.6zm4.2 0a1.3 1.3 0 1 1 0-2.6 1.3 1.3 0 0 1 0 2.6zm4.2 0a1.3 1.3 0 1 1 0-2.6 1.3 1.3 0 0 1 0 2.6z"/></svg>';
    const SVG_HEART = '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M12 20.3 10.6 19C5.6 14.5 2.3 11.5 2.3 7.8 2.3 4.8 4.6 2.5 7.6 2.5c1.7 0 3.3.8 4.4 2 1.1-1.2 2.7-2 4.4-2 3 0 5.3 2.3 5.3 5.3 0 3.7-3.3 6.7-8.3 11.2z"/></svg>';
    const SVG_SEND = '<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path fill="currentColor" d="M3 20l18-8L3 4v6l12 2-12 2z"/></svg>';
    const SVG_X = '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" d="M6 6l12 12M18 6 6 18"/></svg>';

    btn.innerHTML = SVG_BUBBLE + '<span class="cm-n"></span>';
    btn.setAttribute('aria-label', T.title);
    const count = btn.querySelector('.cm-n');

    const sheet = document.createElement('section');
    sheet.className = 'cm-sheet';
    sheet.setAttribute('aria-label', T.title);
    sheet.innerHTML =
      '<div class="cm-grab"><span class="cm-handle"></span>' +
      '<div class="cm-head"><b></b><button type="button" class="cm-x">' + SVG_X + '</button></div></div>' +
      '<div class="cm-list"></div>';
    root.appendChild(sheet);
    const head = sheet.querySelector('.cm-head b');
    const list = sheet.querySelector('.cm-list');
    sheet.querySelector('.cm-x').setAttribute('aria-label', T.close);

    /** Первые страницы по роликам: повторное открытие — без ожидания. */
    const cache = new Map();
    const st = { key: '', total: -1, cursor: 0, more: false, busy: false, items: [], why: '' };

    const isTikTok = (key) => !!key && H.src(key) === 'tiktok';
    const isOpen = () => root.classList.contains('cmts-open');

    /** Запрос к приложению. Нет приложения или ответа — `{ok:false}`. */
    async function ask(args) {
      const b = H.bridge();
      if (!b) return { ok: false, why: 'failed' };
      try {
        const r = await Promise.race([
          b.callHandler('reelsComments', args),
          new Promise((res) => setTimeout(() => res(null), 20000)),
        ]);
        return r && typeof r === 'object' ? r : { ok: false, why: 'failed' };
      } catch (_) {
        return { ok: false, why: 'failed' };
      }
    }

    /** На кнопке — коротко, в одну строку: «39,8К». */
    function short(n) {
      const one = (x) => (Math.round(x * 10) / 10).toString().replace('.', H.ru ? ',' : '.').replace(/[,.]0$/, '');
      if (n >= 1e6) return one(n / 1e6) + (H.ru ? 'М' : 'M');
      if (n >= 1e3) return one(n / 1e3) + (H.ru ? 'К' : 'K');
      return String(n);
    }

    function paintCount() {
      count.textContent = st.total > 0 ? short(st.total) : '';
    }

    function paintHead() {
      head.textContent = st.total > 0 ? T.n(st.total) : T.title;
    }

    /** Первая страница ролика: из кэша или у приложения. */
    async function first(key) {
      const hit = cache.get(key);
      if (hit) return hit;
      const r = await ask({ id: H.id(key), cursor: 0 });
      if (r.ok) cache.set(key, r);
      if (cache.size > 40) cache.delete(cache.keys().next().value);
      return r;
    }

    async function loadFirst(key) {
      st.key = key; st.items = []; st.total = -1; st.cursor = 0; st.more = false; st.why = ''; st.busy = true;
      paintCount();
      if (isOpen()) render();
      const r = await first(key);
      if (st.key !== key) return;
      st.busy = false;
      if (!r.ok) { st.why = r.why || 'failed'; if (isOpen()) render(); return; }
      st.total = Number(r.total) || 0;
      st.items = (r.items || []).slice();
      st.cursor = Number(r.cursor) || 0;
      st.more = !!r.more;
      paintCount();
      if (isOpen()) render();
    }

    async function loadMore() {
      if (st.busy || !st.more || !st.key) return;
      const key = st.key;
      st.busy = true;
      paintFoot();
      const r = await ask({ id: H.id(key), cursor: st.cursor });
      if (st.key !== key) return;
      st.busy = false;
      if (r.ok) {
        const seen = new Set(st.items.map((c) => c.cid));
        (r.items || []).forEach((c) => { if (!seen.has(c.cid)) { st.items.push(c); list.insertBefore(item(c), foot()); } });
        st.cursor = Number(r.cursor) || st.cursor;
        st.more = !!r.more && (r.items || []).length > 0;
      } else {
        st.more = false;
      }
      paintFoot();
    }

    // ── отрисовка ────────────────────────────────────────────────────────────

    function foot() {
      let f = list.querySelector('.cm-foot');
      if (!f) { f = document.createElement('div'); f.className = 'cm-foot'; list.appendChild(f); }
      return f;
    }

    function paintFoot() {
      const f = foot();
      f.innerHTML = st.busy ? '<span class="cm-spin"></span>' : '';
    }

    function note(text, retry) {
      const n = document.createElement('div');
      n.className = 'cm-note';
      n.appendChild(document.createElement('span')).textContent = text;
      if (retry) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'cm-retry';
        b.textContent = T.retry;
        b.addEventListener('click', () => { cache.delete(st.key); loadFirst(st.key); });
        n.appendChild(b);
      }
      return n;
    }

    function render() {
      paintHead();
      list.innerHTML = '';
      if (st.why) {
        list.appendChild(note(st.why === 'blocked' ? T.blocked : T.failed, true));
        return;
      }
      if (st.busy && !st.items.length) {
        for (let i = 0; i < 6; i++) list.appendChild(skeleton());
        return;
      }
      if (!st.items.length) { list.appendChild(note(T.empty)); return; }
      st.items.forEach((c) => list.appendChild(item(c)));
      paintFoot();
    }

    function skeleton() {
      const s = document.createElement('div');
      s.className = 'cm-item cm-skel';
      s.innerHTML = '<i class="cm-av"></i><div class="cm-body"><i></i><i></i></div>';
      return s;
    }

    function avatar(url) {
      const img = document.createElement('img');
      img.className = 'cm-av';
      img.alt = '';
      img.loading = 'lazy';
      img.referrerPolicy = 'no-referrer';
      if (/^https:\/\//.test(url || '')) img.src = url; else img.removeAttribute('src');
      img.addEventListener('error', () => img.removeAttribute('src'), { once: true });
      return img;
    }

    /** Один комментарий: аватар, имя, текст, время, ответы; справа сердце. */
    function item(c, reply) {
      const row = document.createElement('div');
      row.className = 'cm-item' + (reply ? ' is-reply' : '');
      row.dataset.cid = c.cid;
      row.appendChild(avatar(c.avatar));

      const body = row.appendChild(document.createElement('div'));
      body.className = 'cm-body';
      const name = body.appendChild(document.createElement('span'));
      name.className = 'cm-name';
      name.textContent = c.name || '—';
      if (c.pinned || c.authorLiked) {
        const tag = name.appendChild(document.createElement('em'));
        tag.textContent = c.pinned ? T.pinned : T.liked;
      }
      const text = body.appendChild(document.createElement('p'));
      text.className = 'cm-text';
      text.textContent = c.text || (c.photo ? '📷 ' + T.photo : '');

      const meta = body.appendChild(document.createElement('div'));
      meta.className = 'cm-meta';
      meta.appendChild(document.createElement('span')).textContent = ago(c.time);
      const quote = meta.appendChild(document.createElement('button'));
      quote.type = 'button';
      quote.className = 'cm-quote';
      quote.innerHTML = SVG_SEND + '<span></span>';
      quote.lastChild.textContent = T.quote;
      quote.addEventListener('click', () => {
        H.say('💬 «' + (c.text || T.photo) + '» — ' + (c.name || 'TikTok'));
        quote.classList.add('is-done');
        quote.lastChild.textContent = T.sent;
      });

      const like = row.appendChild(document.createElement('div'));
      like.className = 'cm-like';
      like.innerHTML = SVG_HEART + '<span></span>';
      like.lastChild.textContent = c.likes > 0 ? fmt(c.likes) : '';

      if (!reply && c.replies > 0) {
        const box = body.appendChild(document.createElement('div'));
        box.className = 'cm-replies';
        const open = body.appendChild(document.createElement('button'));
        open.type = 'button';
        open.className = 'cm-more';
        const rs = { cursor: 0, shown: 0, busy: false, more: true };
        const label = () => { open.textContent = rs.shown ? (rs.more ? T.more : T.hide) : T.replies(c.replies); };
        label();
        open.addEventListener('click', async () => {
          if (rs.busy) return;
          if (rs.shown && !rs.more) { box.innerHTML = ''; rs.shown = 0; rs.cursor = 0; rs.more = true; label(); return; }
          rs.busy = true;
          open.classList.add('is-busy');
          const r = await ask({ id: H.id(st.key), cid: c.cid, cursor: rs.cursor });
          rs.busy = false;
          open.classList.remove('is-busy');
          if (!r.ok) { open.textContent = T.failed; return; }
          (r.items || []).forEach((x) => { box.appendChild(item(x, true)); rs.shown++; });
          rs.cursor = Number(r.cursor) || rs.cursor;
          rs.more = !!r.more && rs.shown < c.replies && (r.items || []).length > 0;
          label();
        });
      }
      return row;
    }

    // ── открыть, закрыть, смена ролика ───────────────────────────────────────

    function open() {
      if (!isTikTok(st.key)) return;
      H.closeChat();
      root.classList.add('cmts-open');
      btn.classList.add('is-on');
      sheet.style.transform = '';
      render();
      list.scrollTop = 0;
      if (st.why || (!st.busy && st.total < 0)) { cache.delete(st.key); loadFirst(st.key); }
    }

    function close() {
      root.classList.remove('cmts-open');
      btn.classList.remove('is-on');
      sheet.style.transition = '';
      sheet.style.transform = '';
    }
    window.forkCommentsClose = close;

    let prefetch = 0;
    window.forkReelShown = (key) => {
      const tt = isTikTok(key) && !!H.bridge();
      btn.hidden = !tt;
      clearTimeout(prefetch);
      if (!tt) { st.key = ''; if (isOpen()) close(); return; }
      st.key = key; st.total = -1; st.items = []; st.why = ''; st.busy = false;
      paintCount();
      if (isOpen()) { loadFirst(key); return; }
      // Счётчик на кнопке — как у площадки; за листанием не гонимся.
      prefetch = setTimeout(() => { if (st.key === key) loadFirst(key); }, 700);
    };

    btn.addEventListener('click', (e) => { e.stopPropagation(); isOpen() ? close() : open(); });
    sheet.querySelector('.cm-x').addEventListener('click', close);
    list.addEventListener('scroll', () => {
      if (list.scrollTop + list.clientHeight > list.scrollHeight - 300) loadMore();
    }, { passive: true });

    // Свайп вниз за шапку листа (или по списку, прокрученному до верха) — закрыть.
    let y0 = 0, dy = 0, drag = false;
    sheet.addEventListener('pointerdown', (e) => {
      if (e.target.closest('button')) return;
      if (!e.target.closest('.cm-grab') && list.scrollTop > 0) return;
      y0 = e.clientY; dy = 0; drag = true;
    });
    sheet.addEventListener('pointermove', (e) => {
      if (!drag) return;
      dy = Math.max(0, e.clientY - y0);
      if (dy > 6) { sheet.style.transition = 'none'; sheet.style.transform = 'translate3d(0,' + dy + 'px,0)'; }
    });
    const end = () => {
      if (!drag) return;
      drag = false;
      sheet.style.transition = '';
      if (dy > sheet.clientHeight * 0.22) close(); else sheet.style.transform = '';
    };
    sheet.addEventListener('pointerup', end);
    sheet.addEventListener('pointercancel', end);

    // Ролик мог встать раньше, чем загрузился этот файл.
    if (H.cur()) window.forkReelShown(H.cur());
  }
})();
