// fork (B4): снимок комнаты для новичка.
//
// Сервер комнату не хранит: ролик, очередь и переписку новичку присылает тот,
// кто уже внутри, в ответ на его `hello`. Раньше ответ терялся, если вкладка
// с роликом в этот момент спала (приложение в фоне) или ролик был только в
// очереди, — и новичок видел «ничего не выбрано», хотя партнёр уже выбрал.
//
// Теперь: пустая вкладка отвечает на чужой `hello` встречным `hello` с
// пометкой `echo` — проснувшийся партнёр с роликом пришлёт снимок; а сам
// новичок повторяет `hello`, пока в комнате кто-то есть и снимка нет.
((root) => {
  'use strict';
  /** Есть ли что передать новичку: ролик, файл, переписка или очередь. */
  function hasSnapshot(state, queue) {
    if (!state) return false;
    if (state.url || state.file || (state.log && state.log.length)) return true;
    return !!(queue && ((queue.entries && queue.entries.length) || queue.latestPlay));
  }
  /** Ответ на `hello`: 'state' — прислать снимок, 'echo' — встречный hello,
   *  null — молчать (встречный hello пустому не отвечаем: без пинг-понга). */
  function helloReply(state, queue, data) {
    if (hasSnapshot(state, queue)) return 'state';
    if (data && data.echo) return null;
    return 'echo';
  }
  /** Повторить свой `hello`: снимка ещё нет, а в комнате кроме нас кто-то есть. */
  function shouldRetry(state, tries, max) {
    return !!state && !state.synced && !state.kind && (state.viewers || 1) > 1 && tries < max;
  }
  const api = Object.freeze({hasSnapshot, helloReply, shouldRetry, RETRY_MS: 4000, RETRIES: 3});
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ForkRoomSync = api;
})(typeof window === 'undefined' ? globalThis : window);
