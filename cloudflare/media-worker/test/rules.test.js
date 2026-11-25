import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authorize, chatIdFor, parsePath, parsePrefix, selectForCleanup, uploadLimit, GB, MB } from '../src/rules.js';

const allow = async () => true;
const deny = async () => false;

test('yollar çözülür, tehlikeliler reddedilir', () => {
  assert.deepEqual(parsePath('chats/a_b/media/M1/original.heic'), { kind: 'chat', chatId: 'a_b', messageId: 'M1', file: 'original.heic', media: 'original' });
  assert.equal(parsePath('chats/a_b/media/M1/voice.m4a').media, 'voice');
  assert.equal(parsePath('users/u1/stickers/abc-1.png').kind, 'sticker');
  assert.equal(parsePath('users/u1/bubbles/s1/draw-1.png').kind, 'bubble');
  assert.equal(parsePath('profile_images/u1/x-9.jpg').kind, 'profile');
  for (const bad of ['', '../etc', 'chats/a_b/media/../x/thumb.jpg', 'chats/a_b/media/M1/evil.exe', 'users/u1/stickers/a.jpg', 'acks/chats/a_b/media/M/original.jpg', 'chats//media/M/thumb.jpg']) {
    assert.equal(parsePath(bad), null, bad);
  }
  assert.deepEqual(parsePrefix('chats/a_b/'), { kind: 'chat', chatId: 'a_b' });
  assert.deepEqual(parsePrefix('users/u1/bubbles/s1/'), { kind: 'owner', owner: 'u1' });
  assert.equal(parsePrefix('users/'), null);
  assert.equal(parsePrefix('chats/a_b'), null);
  assert.equal(chatIdFor('b', 'a'), 'a_b');
});

test('izinler eski Storage kurallarıyla aynı', async () => {
  const chat = parsePath('chats/a_b/media/M1/thumb.jpg');
  assert.equal(await authorize({ op: 'read', parsed: chat, uid: 'a', isMember: allow, sharesChat: deny }), true);
  assert.equal(await authorize({ op: 'read', parsed: chat, uid: 'c', isMember: allow, sharesChat: deny }), false, 'oda kimliğinde yok');
  assert.equal(await authorize({ op: 'read', parsed: chat, uid: 'a', isMember: deny, sharesChat: deny }), false, 'oda yok');
  assert.equal(await authorize({ op: 'write', parsed: chat, uid: 'a', existingSender: 'b', isMember: allow, sharesChat: deny }), false, 'başkasının dosyası');
  assert.equal(await authorize({ op: 'write', parsed: chat, uid: 'a', existingSender: 'a', isMember: allow, sharesChat: deny }), true);

  const sticker = parsePath('users/u1/stickers/s.png');
  assert.equal(await authorize({ op: 'read', parsed: sticker, uid: 'u1', isMember: deny, sharesChat: deny }), true);
  assert.equal(await authorize({ op: 'read', parsed: sticker, uid: 'u2', isMember: allow, sharesChat: allow }), false);

  const bubble = parsePath('users/u1/bubbles/s/a.png');
  assert.equal(await authorize({ op: 'read', parsed: bubble, uid: 'u2', isMember: deny, sharesChat: allow }), true, 'sohbet arkadaşı okur');
  assert.equal(await authorize({ op: 'read', parsed: bubble, uid: 'u2', isMember: deny, sharesChat: deny }), false);
  assert.equal(await authorize({ op: 'write', parsed: bubble, uid: 'u2', isMember: allow, sharesChat: allow }), false);

  const profile = parsePath('profile_images/u1/a.jpg');
  assert.equal(await authorize({ op: 'write', parsed: profile, uid: 'u2', isMember: allow, sharesChat: allow }), false);
  assert.equal(await authorize({ op: 'read', parsed: chat, uid: null, isMember: allow, sharesChat: allow }), false);
});

test('yükleme sınırları', () => {
  assert.equal(uploadLimit(parsePath('chats/a_b/media/M/original.mov')).maxBytes, 2 * 1024 * MB);
  assert.ok(uploadLimit(parsePath('chats/a_b/media/M/original.mov')).type.test('video/quicktime'));
  assert.ok(!uploadLimit(parsePath('chats/a_b/media/M/thumb.jpg')).type.test('image/png'));
  assert.ok(uploadLimit(parsePath('chats/a_b/media/M/voice.m4a')).type.test('audio/mp4'));
});

test('temizlik: 60 günden eski alınmış orijaller, sonra sınır', () => {
  const now = new Date('2026-12-31T00:00:00Z');
  const day = 86400000;
  const o = (key, size, ageDays) => ({ key, size, uploaded: new Date(now.getTime() - ageDays * day) });
  const objects = [
    o('chats/a_b/media/1/original.jpg', 1 * GB, 90),
    o('chats/a_b/media/1/thumb.jpg', 100, 90),
    o('chats/a_b/media/2/original.mov', 1 * GB, 70),   // alınmadı: silinmez
    o('chats/a_b/media/3/original.mov', 1 * GB, 30),
    o('chats/a_b/media/4/voice.m4a', 10, 100),         // ses kalır
  ];
  const acked = new Set(['chats/a_b/media/1/original.jpg', 'chats/a_b/media/3/original.mov']);
  const result = selectForCleanup(objects, acked, now);
  assert.deepEqual(result.keys, ['chats/a_b/media/1/original.jpg']);
  assert.equal(result.waitingBytes, 1 * GB);

  // Sınır aşılırsa 60 gün dolmamış ama alınmış olanlar en eskiden başlayarak silinir.
  const big = [
    o('chats/a_b/media/5/original.mov', 4 * GB, 20),
    o('chats/a_b/media/6/original.mov', 3 * GB, 10),
    o('chats/a_b/media/7/original.mov', 3 * GB, 5),
  ];
  const acks = new Set(big.map((x) => x.key));
  const limited = selectForCleanup(big, acks, now);
  assert.deepEqual(limited.keys, ['chats/a_b/media/5/original.mov']);
  assert.equal(limited.afterBytes, 6 * GB);

  // Hiçbiri alınmadıysa hiçbir şey silinmez.
  assert.deepEqual(selectForCleanup(big, new Set(), now).keys, []);
  // Sınırın altında ve yeni: dokunulmaz.
  assert.deepEqual(selectForCleanup([o('chats/a_b/media/8/original.jpg', 5, 1)], new Set(['chats/a_b/media/8/original.jpg']), now).keys, []);
});

test('diyet fotoğrafı yolu ve izinleri', async () => {
  assert.deepEqual(parsePath('diet/P1/1b2c3d4e-aa.jpg'), { kind: 'diet', programId: 'P1', file: '1b2c3d4e-aa.jpg' });
  assert.equal(parsePath('diet/P1/x.png'), null);
  assert.equal(parsePath('diet/P1/kisa.jpg'), null);
  assert.deepEqual(parsePrefix('diet/P1/'), { kind: 'diet', programId: 'P1' });
  assert.equal(uploadLimit({ kind: 'diet' }).maxBytes, 5 * MB);
  const parsed = parsePath('diet/P1/1b2c3d4e-aa.jpg');
  const owner = async () => ({ read: true, owner: true });
  const viewer = async () => ({ read: true, owner: false });
  const stranger = async () => ({ read: false, owner: false });
  assert.equal(await authorize({ op: 'write', parsed, uid: 'a', dietAccess: owner }), true);
  assert.equal(await authorize({ op: 'read', parsed, uid: 'b', dietAccess: viewer }), true);
  assert.equal(await authorize({ op: 'write', parsed, uid: 'b', dietAccess: viewer }), false);
  assert.equal(await authorize({ op: 'delete', parsed, uid: 'b', dietAccess: viewer }), false);
  assert.equal(await authorize({ op: 'read', parsed, uid: 'c', dietAccess: stranger }), false);
  assert.equal(await authorize({ op: 'read', parsed, uid: 'c' }), false);
});
