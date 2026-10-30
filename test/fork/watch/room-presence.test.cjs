// fork (B10): «партнёр не в комнате, хотя пишет и жмёт кнопки».
//
// Зрители страницы — люди из присутствия Centrifugo (без служебных подключений
// приложения) плюс те, от кого недавно пришло сообщение комнаты: нативный
// плеер сидит в канале подключением приложения и в присутствии не виден.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function load() {
  const window = {};
  vm.runInNewContext(fs.readFileSync('pocketbase/pb_public/watch/pair.js', 'utf8'), {
    window, localStorage: {getItem: () => null}, setTimeout() {},
  });
  return window.TgPair;
}

const me = 'gaaaaaaaaaaaaaa';
const page = {client: 'c1', user: me};
const app = {client: 'c2', user: 'uMine', chan_info: {app: 1}};
const partnerApp = {client: 'c3', user: 'uPartner', chan_info: {app: 1}};

test('нативный плеер партнёра: присутствие его не видит, а команды — видят', () => {
  const P = load();
  const presence = {clients: {c1: page, c2: app, c3: partnerApp}};
  assert.equal(P.countViewers(presence, {}, 1000, me), 1);
  assert.equal(P.countViewers(presence, {uPartner: 1000}, 1000, me), 2);
});

test('«слышали» живёт HEARD_MS, потом партнёр снова не в счёт', () => {
  const P = load();
  const heard = {uPartner: 0};
  assert.equal(P.countViewers(null, heard, P.HEARD_MS - 1, me), 2);
  assert.equal(P.countViewers(null, heard, P.HEARD_MS, me), 1);
});

test('без ответа присутствия себя всё равно считаем, один человек — один зритель', () => {
  const P = load();
  assert.equal(P.countViewers(null, {}, 0, me), 1);
  const presence = {clients: {c1: page, c9: {client: 'c9', user: 'gbbbbbbbbbbbbbb'}}};
  assert.equal(P.countViewers(presence, {gbbbbbbbbbbbbbb: 0}, 1, me), 2);
});

test('голос, шифр и нативный чат служебного подключения — не признак зрителя', () => {
  const P = load();
  assert.equal(P.hears({t: 'pause', from: 'uPartner', at: 3}, 'uPartner'), true);
  assert.equal(P.hears({t: 'here', from: 'uPartner'}, 'uPartner'), true);
  // Нативный чат комнаты — служебное подключение того, кто уже в счёте.
  for (const t of ['chat', 'rk?', 'rk', 'log']) assert.equal(P.hears({t, from: 'uMine'}), false);
  assert.equal(P.hears({t: 'e2e', from: 'uPartner'}), false);
  assert.equal(P.hears({t: 'voice-hello', from: 'uPartner'}), false);
  assert.equal(P.hears({t: 'bye', from: 'uPartner'}), false);
  assert.equal(P.hears({t: 'pause'}), false);
});

test('отправитель — по серверу, а не по полю from', () => {
  const P = load();
  assert.equal(P.hears({t: 'hello', from: 'uFake'}, 'uPartner'), false);
  assert.equal(P.hears({t: 'hello', from: 'uPartner'}), false);
});
