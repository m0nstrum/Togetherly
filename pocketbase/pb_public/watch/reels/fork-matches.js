// fork: persist mutual reactions through the native account boundary.
((root) => {
  'use strict';
  function create(call, policy, timeout = 10000) {
    const saved = new Set(), pending = new Map();
    async function save(key, reaction) {
      if (!policy.clip(key) || !reaction || !policy.reaction(reaction)) return {ok: false};
      if (saved.has(key)) return {ok: true};
      if (pending.has(key)) return pending.get(key);
      const task = (async () => {
        let timer;
        try {
          const reply = await Promise.race([
            call({key, reaction}),
            new Promise(resolve => { timer = setTimeout(() => resolve({ok: false}), timeout); }),
          ]);
          if (reply && reply.ok === true) { saved.add(key); return {ok: true}; }
        } catch (_) { /* show failure at the caller; do not suppress retry */ }
        finally { clearTimeout(timer); }
        return {ok: false};
      })();
      pending.set(key, task);
      try { return await task; } finally { pending.delete(key); }
    }
    return Object.freeze({save});
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {create};
  else root.ForkReelsMatches = create(async (value) => {
    const bridge = root.flutter_inappwebview;
    if (!bridge) return {ok: false};
    return bridge.callHandler('forkReelsMatch', value);
  }, root.ForkReelsPolicy);
})(typeof window === 'undefined' ? globalThis : window);
