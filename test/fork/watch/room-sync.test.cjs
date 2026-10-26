const {test} = require('node:test');
const assert = require('node:assert/strict');
const sync = require('../../../pocketbase/pb_public/watch/room/fork-sync.js');

const empty = {url: '', file: null, log: [], synced: false, kind: '', viewers: 1};
const noQueue = {entries: [], removed: [], clock: 0, latestPlay: null};

test('B4: a tab with a video, chat or queue answers hello with a snapshot', () => {
  assert.equal(sync.helloReply({...empty, url: 'https://youtu.be/x'}, noQueue, {}), 'state');
  assert.equal(sync.helloReply({...empty, log: [{text: 'hi'}]}, noQueue, {}), 'state');
  assert.equal(sync.helloReply(empty, {...noQueue, entries: [{id: 'a'}]}, {}), 'state');
  assert.equal(sync.helloReply(empty, {...noQueue, latestPlay: {id: 'a'}}, {echo: true}), 'state');
});

test('B4: an empty tab echoes hello once, never answers an echo', () => {
  assert.equal(sync.helloReply(empty, noQueue, {}), 'echo');
  assert.equal(sync.helloReply(empty, noQueue, {echo: true}), null);
});

test('B4: hello is retried only while someone else is here and nothing arrived', () => {
  assert.equal(sync.shouldRetry({...empty, viewers: 2}, 0, sync.RETRIES), true);
  assert.equal(sync.shouldRetry({...empty, viewers: 1}, 0, sync.RETRIES), false);
  assert.equal(sync.shouldRetry({...empty, viewers: 2, synced: true}, 0, sync.RETRIES), false);
  assert.equal(sync.shouldRetry({...empty, viewers: 2, kind: 'yt'}, 0, sync.RETRIES), false);
  assert.equal(sync.shouldRetry({...empty, viewers: 2}, sync.RETRIES, sync.RETRIES), false);
});
