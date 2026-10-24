const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const policy = require('../../../pocketbase/pb_public/watch/reels/fork-policy.js');
const from = 'gaaaaaaaaaaaaaa', owner = 'gbbbbbbbbbbbbbb', id = 'shorts:abcdefghijk';

test('channel reactions and player identifiers reject executable input', () => {
  assert.ok(policy.message({t: 'reels-react', from, id, e: '❤️'}));
  assert.ok(policy.message({t: 'reels-react', from, id, e: ''}));
  for (const attack of ['" onerror="alert(1)', '<svg/onload=alert(1)>', '__proto__', {}, null]) {
    assert.equal(policy.message({t: 'reels-react', from, id, e: attack}), null);
    assert.equal(policy.message({t: 'reels-reel', from, id: attack, owner}), null);
    assert.equal(policy.message({t: 'reels-reel', from, id, owner: attack}), null);
  }
  assert.ok(policy.message({t: 'reels-reel', from, id, owner}));
  assert.equal(policy.message({t: 'reels-queue', from, ids: {}}), null);
  assert.deepEqual(policy.message({t: 'reels-queue', from, ids: [id, 'shorts:x" onload="x']} ).ids, [id]);
});

test('native page requests only its room ticket and does not send the account token', async () => {
  let calls = [], requests = 0;
  const ticket = {ok: true, userId: from, channel: 'watch:abcdefgh', connectionToken: 'connection', subscriptionToken: 'subscription'};
  const window = {
    __togetherlyChrome: 1,
    flutter_inappwebview: {callHandler: async (...args) => { calls.push(args); return ticket; }},
  };
  class Centrifuge {
    on() {} connect() {} disconnect() {}
    newSubscription() { return {on() {}, subscribe() {}}; }
  }
  vm.runInNewContext(fs.readFileSync('pocketbase/pb_public/watch/pair.js', 'utf8'), {
    window, Centrifuge, localStorage: {getItem: key => key === 'watch-guest' ? from : JSON.stringify({token: 'ACCOUNT_SECRET'})},
    fetch: async () => { requests++; throw new Error('page must not authenticate'); },
    setTimeout() {},
  });
  const opened = await window.TgPair.open('abcdefgh');
  assert.equal(opened.me, from);
  assert.deepEqual(calls, [['forkWatchTicket', from]]);
  assert.equal(requests, 0);
  ticket.channel = 'watch:other';
  await assert.rejects(window.TgPair.open('abcdefgh'), /native ticket/);
});
