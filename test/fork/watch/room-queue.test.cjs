const {test} = require('node:test');
const assert = require('node:assert/strict');
const {create} = require('../../../pocketbase/pb_public/watch/room/fork-queue.js');
const alice = 'aliceaaaaaaaaaa', bob = 'bobbbbbbbbbbbbb', carol = 'carolcccccccccc';
const url = n => `https://example.test/video${n}.mp4`;
const validate = value => /^https:\/\/example\.test\/video\d+\.mp4$/.test(value) ? value : null;
function room() {
  const wire = [], clients = [], plays = new Map();
  let next = 0, failing = false;
  const app = who => {
    plays.set(who, []);
    const queue = create({me: () => who, validate,
      nonce: () => (++next).toString(16).padStart(16, '0'),
      publish: async packet => { if (failing) throw Error('offline'); wire.push(packet); },
      play: (source, from) => plays.get(who).push({url: source, from})});
    clients.push(queue); return queue;
  };
  const flush = (reverse = false) => {
    const packets = wire.splice(0); if (reverse) packets.reverse();
    for (const packet of packets) for (const client of clients) client.receive(packet);
  };
  return {app, wire, plays, flush, fail: value => failing = value};
}

test('concurrent additions converge in either delivery order; remove survives a replay', async () => {
  const bus = room(), a = bus.app(alice), b = bus.app(bob);
  await Promise.all([a.add(url(1)), b.add(url(2))]); bus.flush(true);
  assert.deepEqual(a.list(), b.list()); assert.equal(a.list().length, 2);
  const saved = a.snapshot().entries[0];
  await b.remove(saved.id); const deletion = bus.wire[0]; bus.flush();
  const c = bus.app(carol); c.merge(a.snapshot());
  c.receive({...saved, t: 'fork-queue', kind: 'add', from: saved.id.split(':')[0]});
  assert.deepEqual(a.list(), b.list()); assert.deepEqual(a.list(), c.list());
  const d = bus.app('daviddddddddddd');
  d.receive(deletion); d.receive({...saved, t: 'fork-queue', kind: 'add', from: saved.id.split(':')[0]});
  assert.equal(d.list().length, 0);
});

test('playing consumes the selected entry and only the newest play wins after reordering', async () => {
  const bus = room(), a = bus.app(alice), b = bus.app(bob);
  await a.add(url(1)); await b.add(url(2)); bus.flush();
  await Promise.all([a.start(a.list()[0].id), b.start(b.list()[1].id)]);
  bus.flush(true);
  assert.deepEqual(a.list(), []); assert.deepEqual(b.list(), []);
  assert.deepEqual(bus.plays.get(alice).at(-1), bus.plays.get(bob).at(-1));
  const c = bus.app(carol); c.merge(a.snapshot());
  assert.deepEqual(c.list(), []); assert.deepEqual(bus.plays.get(carol), [], 'snapshot must not restart playback');
});

test('failed publication does not claim a local queue change or start a player', async () => {
  const bus = room(), a = bus.app(alice);
  bus.fail(true); assert.equal(await a.add(url(1)), false); assert.equal(a.list().length, 0);
  bus.fail(false); assert.equal(await a.add(url(1)), true);
  bus.fail(true); assert.equal(await a.next(), false);
  assert.equal(a.list().length, 1); assert.deepEqual(bus.plays.get(alice), []);
});

test('bounded snapshots reject executable links, forged identities and malformed revisions', async () => {
  const bus = room(), a = bus.app(alice);
  assert.equal(await a.add('javascript:alert(1)'), false);
  assert.equal(await a.add('https://example.test/' + 'x'.repeat(3000)), false);
  for (let i = 0; i < 20; i++) assert.equal(await a.add(url(i)), true);
  assert.equal(await a.add(url(21)), false);
  const before = a.list();
  a.receive({t: 'fork-queue', kind: 'add', from: bob, id: alice + ':ffffffffffffffff', clock: 50, url: url(99)});
  a.receive({t: 'fork-queue', kind: 'play', from: bob, id: bob + ':ffffffffffffffff', clock: Infinity, target: before[0].id, url: url(99)});
  assert.equal(a.merge({entries: Array(21).fill({}), removed: []}), false);
  assert.deepEqual(a.list(), before);
});

test('queue operations wait for the native channel acknowledgement', async () => {
  let resolve;
  const a = create({me: () => alice, validate, nonce: () => '0000000000000001',
    publish: () => new Promise(done => resolve = done), play() { throw Error('must not play'); }});
  const pending = a.add(url(1)); assert.deepEqual(a.list(), []);
  resolve(); assert.equal(await pending, true); assert.equal(a.list().length, 1);
});
