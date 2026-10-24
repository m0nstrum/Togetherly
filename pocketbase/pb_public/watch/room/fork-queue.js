// fork: convergent session queue. URLs follow the room's existing visibility rules.
((root) => {
  'use strict';
  const actor = value => typeof value === 'string' && /^[a-z0-9]{15}$/.test(value);
  const identifier = value => typeof value === 'string' && /^[a-z0-9]{15}:[a-f0-9]{16}$/.test(value);
  const revision = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
  const compare = (a, b) => a.clock - b.clock || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  function create({me, publish, validate, play, changed = () => {}, nonce = () =>
    Array.from(root.crypto.getRandomValues(new Uint8Array(8)), b => b.toString(16).padStart(2, '0')).join('')}) {
    const entries = new Map(), removed = new Set();
    let clock = 0, latestPlay = null;
    const list = () => [...entries.values()].sort(compare);
    function prune() { while (removed.size > 1000) removed.delete(removed.values().next().value); }
    const urlOf = value => typeof value === 'string' && value.length <= 2048 ? validate(value) : null;
    function validEntry(value) {
      return value && identifier(value.id) && revision(value.clock) && urlOf(value.url);
    }
    function trim() {
      for (const item of list().slice(20)) { entries.delete(item.id); removed.add(item.id); }
    }
    function receive(packet) {
      if (!packet || packet.t !== 'fork-queue' || !actor(packet.from) || !identifier(packet.id) ||
          !packet.id.startsWith(packet.from + ':') || !revision(packet.clock)) return false;
      const kind = packet.kind;
      if (!['add', 'remove', 'play'].includes(kind)) return false;
      if (kind === 'add' && !urlOf(packet.url)) return false;
      if (kind !== 'add' && (!identifier(packet.target) || (kind === 'play' && !urlOf(packet.url)))) return false;
      clock = Math.max(clock, packet.clock);
      if (kind === 'add') {
        if (!removed.has(packet.id) && !entries.has(packet.id)) {
          entries.set(packet.id, {id: packet.id, clock: packet.clock, url: urlOf(packet.url)});
          trim();
        }
      } else {
        removed.add(packet.target); entries.delete(packet.target);
        if (kind === 'play' && (!latestPlay || compare(packet, latestPlay) > 0)) {
          latestPlay = {id: packet.id, clock: packet.clock, from: packet.from, url: urlOf(packet.url)};
          play(latestPlay.url, packet.from);
        }
      }
      prune(); changed(list());
      return true;
    }
    async function commit(kind, fields) {
      if (!actor(me())) return false;
      const packet = {t: 'fork-queue', kind, from: me(), id: me() + ':' + nonce(), clock: ++clock, ...fields};
      try { await publish(packet); } catch (_) { return false; }
      return receive(packet);
    }
    async function add(raw) {
      const url = urlOf(raw);
      if (!url || list().length >= 20) return false;
      return commit('add', {url});
    }
    async function remove(id) {
      if (!entries.has(id)) return false;
      return commit('remove', {target: id});
    }
    async function start(id) {
      const entry = entries.get(id);
      if (!entry) return false;
      return commit('play', {target: id, url: entry.url});
    }
    function snapshot() {
      return {entries: list(), removed: [...removed].slice(-200), clock, latestPlay};
    }
    function merge(value) {
      if (!value || !Array.isArray(value.entries) || !Array.isArray(value.removed) ||
          value.entries.length > 20 || value.removed.length > 200) return false;
      if (revision(value.clock)) clock = Math.max(clock, value.clock);
      for (const id of value.removed) if (identifier(id)) { removed.add(id); entries.delete(id); }
      for (const item of value.entries) {
        if (validEntry(item) && !removed.has(item.id) && !entries.has(item.id)) {
          entries.set(item.id, {id: item.id, clock: item.clock, url: urlOf(item.url)});
          clock = Math.max(clock, item.clock);
        }
      }
      const current = value.latestPlay;
      if (validEntry(current) && actor(current.from) && current.id.startsWith(current.from + ':') &&
          (!latestPlay || compare(current, latestPlay) > 0)) {
        latestPlay = {id: current.id, clock: current.clock, from: current.from, url: urlOf(current.url)};
        clock = Math.max(clock, current.clock);
      }
      trim(); prune(); changed(list()); return true;
    }
    return Object.freeze({list, add, remove, start, receive, snapshot, merge,
      next: () => list().length ? start(list()[0].id) : Promise.resolve(false)});
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {create};
  else root.ForkWatchQueue = {create};
})(typeof window === 'undefined' ? globalThis : window);
