const {test} = require('node:test');
const assert = require('node:assert/strict');
const policy = require('../../../pocketbase/pb_public/watch/reels/fork-policy.js');
const from = 'gaaaaaaaaaaaaaa', to = 'gbbbbbbbbbbbbbb';

test('D1: скорость пары — только 1 или 2', () => {
  assert.ok(policy.message({t: 'reels-rate', from, rate: 2}));
  assert.ok(policy.message({t: 'reels-rate', from, rate: 1}));
  for (const rate of [0, 16, '2', null, {}, -1]) {
    assert.equal(policy.message({t: 'reels-rate', from, rate}), null);
  }
  assert.ok(policy.message({t: 'reels-state', from, to, ids: [], rate: 2}));
  assert.equal(policy.message({t: 'reels-state', from, to, ids: [], rate: 4}), null);
});
