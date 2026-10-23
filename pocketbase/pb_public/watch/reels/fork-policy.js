// C3: validate untrusted channel messages before they reach markup or players.
((root) => {
  'use strict';
  const reactions = new Set(['', '❤️', '😂', '😮', '😢', '🔥', '👍']);
  const reaction = (value) => typeof value === 'string' && reactions.has(value);
  const clip = (value) => typeof value === 'string' && /^(shorts|tiktok|rutube|vk|dzen):[A-Za-z0-9_-]{6,100}$/.test(value);
  const person = (value) => typeof value === 'string' && /^[a-z0-9]{15}$/.test(value);
  const current = (value) => value && clip(value.id) && person(value.owner) && (value.by == null || person(value.by));
  function message(data) {
    if (!data || typeof data !== 'object' || typeof data.t !== 'string') return null;
    if (!data.t.startsWith('reels-')) return data;
    if (!person(data.from)) return null;
    if (data.lead != null && data.lead !== '' && !person(data.lead)) return null;
    switch (data.t) {
      case 'reels-react':
        if (!clip(data.id) || !reaction(data.e)) return null;
        break;
      case 'reels-reel':
        if (!current(data)) return null;
        break;
      case 'reels-state':
        if (!person(data.to) || (data.cur != null && !current(data.cur))) return null;
        // fall through
      case 'reels-queue':
        if (!Array.isArray(data.ids)) return null;
        data = {...data, ids: data.ids.filter(clip).slice(0, 100)};
        break;
      case 'reels-saved':
      case 'reels-pause':
        if (!clip(data.id)) return null;
        break;
    }
    return data;
  }
  const policy = Object.freeze({reaction, clip, person, message});
  if (typeof module !== 'undefined' && module.exports) module.exports = policy;
  else root.ForkReelsPolicy = policy;
})(typeof window === 'undefined' ? globalThis : window);
