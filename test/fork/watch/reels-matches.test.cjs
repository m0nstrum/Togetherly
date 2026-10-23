const {test} = require('node:test');
const assert = require('node:assert/strict');
const {create} = require('../../../pocketbase/pb_public/watch/reels/fork-matches.js');
const policy = require('../../../pocketbase/pb_public/watch/reels/fork-policy.js');
const clip = 'shorts:abcdefghijk';

test('duplicate and simultaneous matches save exactly once after acknowledgement', async () => {
  let calls = 0, resolve;
  const saving = create(async (payload) => { calls++; assert.deepEqual(payload, {key: clip, reaction: '❤️'});
    return new Promise(r => resolve = r); }, policy);
  const a = saving.save(clip, '❤️'), b = saving.save(clip, '❤️');
  assert.equal(calls, 1);
  resolve({ok: true});
  assert.equal((await a).ok, true); assert.equal((await b).ok, true);
  await saving.save(clip, '🔥'); assert.equal(calls, 1);
});

test('failed persistence can retry; malicious input never reaches native bridge', async () => {
  let calls = 0;
  const saving = create(async () => ({ok: ++calls > 1}), policy);
  assert.equal((await saving.save(clip, '❤️')).ok, false);
  assert.equal((await saving.save(clip, '❤️')).ok, true);
  assert.equal((await saving.save('<img onerror=x>', '❤️')).ok, false);
  assert.equal((await saving.save(clip, '<svg>')).ok, false);
  assert.equal(calls, 2);
});

test('a stalled native reply times out and permits another attempt', async () => {
  let calls = 0;
  const saving = create(() => { calls++; return new Promise(() => {}); }, policy, 5);
  assert.equal((await saving.save(clip, '❤️')).ok, false);
  assert.equal((await saving.save(clip, '❤️')).ok, false);
  assert.equal(calls, 2);
});
