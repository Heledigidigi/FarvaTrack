import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { handle, resetMembershipCache } from '../src/index.js';
import { FakeBucket } from './fake-r2.js';

let bucket, env, deps, rooms;

beforeEach(() => {
  resetMembershipCache();
  bucket = new FakeBucket();
  env = { BUCKET: bucket, FIREBASE_PROJECT_ID: 'proj' };
  rooms = new Map([['a_b', ['a', 'b']]]);
  deps = {
    // Belirteç = uid (gerçek doğrulama auth.test.js'te).
    verify: async (token) => (token && token !== 'kotu' ? token : null),
    now: () => new Date('2026-12-31T00:00:00Z'),
    fetch: async (url, init) => {
      const chatId = decodeURIComponent(url.match(/chats\/([^?]+)/)[1]);
      const uid = init.headers.Authorization.replace('Bearer ', '');
      const members = rooms.get(chatId);
      if (!members || !members.includes(uid)) return new Response('{}', { status: 403 });
      return new Response(JSON.stringify({ fields: { members: { arrayValue: { values: members.map((m) => ({ stringValue: m })) } } } }));
    },
  };
});

const call = (method, path, { uid, body, headers = {} } = {}) => {
  const h = new Headers(headers);
  if (uid) h.set('authorization', `Bearer ${uid}`);
  if (body != null && !h.has('content-length')) h.set('content-length', String(body.length ?? body.byteLength ?? 0));
  return handle(new Request(`https://w.dev${path}`, { method, headers: h, body, duplex: 'half' }), env, deps);
};
const bytes = (n) => new Uint8Array(n).fill(7);

test('oturumsuz istek reddedilir', async () => {
  assert.equal((await call('GET', '/v1/o?p=chats/a_b/media/m/thumb.jpg')).status, 401);
  assert.equal((await call('GET', '/v1/o?p=chats/a_b/media/m/thumb.jpg', { uid: 'kotu' })).status, 401);
});

test('üye yükler ve indirir, yabancı erişemez; Range çalışır', async () => {
  const path = '/v1/o?p=chats/a_b/media/m1/thumb.jpg';
  assert.equal((await call('PUT', path, { uid: 'a', body: bytes(10), headers: { 'content-type': 'image/jpeg' } })).status, 200);
  assert.equal(bucket.objects.get('chats/a_b/media/m1/thumb.jpg').customMetadata.senderId, 'a');

  const got = await call('GET', path, { uid: 'b' });
  assert.equal(got.status, 200);
  assert.equal((await got.arrayBuffer()).byteLength, 10);

  const partial = await call('GET', path, { uid: 'b', headers: { range: 'bytes=2-5' } });
  assert.equal(partial.status, 206);
  assert.equal(partial.headers.get('content-range'), 'bytes 2-5/10');

  rooms.set('a_c', ['a', 'c']);
  assert.equal((await call('GET', path, { uid: 'c' })).status, 403, 'başka odanın üyesi');
  assert.equal((await call('GET', '/v1/o?p=chats/a_b/media/yok/thumb.jpg', { uid: 'a' })).status, 404);
});

test('tür, boyut ve başkasının dosyasının üzerine yazma engellenir', async () => {
  const path = '/v1/o?p=chats/a_b/media/m2/thumb.jpg';
  assert.equal((await call('PUT', path, { uid: 'a', body: bytes(10), headers: { 'content-type': 'image/png' } })).status, 415);
  assert.equal((await call('PUT', '/v1/o?p=users/a/stickers/s.png', { uid: 'a', body: bytes(10), headers: { 'content-type': 'image/png', 'content-length': String(3 * 1024 * 1024) } })).status, 413);
  await call('PUT', path, { uid: 'a', body: bytes(10), headers: { 'content-type': 'image/jpeg' } });
  assert.equal((await call('PUT', path, { uid: 'b', body: bytes(10), headers: { 'content-type': 'image/jpeg' } })).status, 403);
  assert.equal((await call('PUT', '/v1/o?p=users/a/stickers/s.png', { uid: 'b', body: bytes(10), headers: { 'content-type': 'image/png' } })).status, 403);
  assert.equal((await call('PUT', '/v1/o?p=../x', { uid: 'a', body: bytes(1), headers: { 'content-type': 'image/png' } })).status, 400);
});

test('çok parçalı yükleme', async () => {
  const p = 'chats/a_b/media/m3/original.mov';
  const created = await call('POST', `/v1/mpu?p=${p}`, { uid: 'a', headers: { 'content-type': 'video/quicktime', 'x-total-size': '30' } });
  const { uploadId } = await created.json();
  const parts = [];
  for (const n of [1, 2]) {
    const r = await call('PUT', `/v1/mpu?p=${p}&uploadId=${uploadId}&part=${n}`, { uid: 'a', body: bytes(15) });
    parts.push(await r.json());
  }
  const done = await call('POST', `/v1/mpu/complete?p=${p}&uploadId=${uploadId}`, {
    uid: 'a', body: new TextEncoder().encode(JSON.stringify({ parts })), headers: { 'content-type': 'application/json' },
  });
  assert.equal(done.status, 200);
  assert.equal(bucket.objects.get(p).bytes.length, 30);
  assert.equal(bucket.objects.get(p).customMetadata.senderId, 'a');
  assert.equal((await call('POST', `/v1/mpu?p=${p}`, { uid: 'a', headers: { 'content-type': 'video/quicktime', 'x-total-size': String(3 * 1024 ** 3) } })).status, 413);
});

test('baloncuk dosyasını sohbet arkadaşı okur, yabancı okuyamaz', async () => {
  const path = '/v1/o?p=users/a/bubbles/s1/d-1.png';
  await call('PUT', path, { uid: 'a', body: bytes(5), headers: { 'content-type': 'image/png' } });
  assert.equal((await call('GET', path, { uid: 'b' })).status, 200);
  assert.equal((await call('GET', path, { uid: 'z' })).status, 403);
});

test('alındı işareti yalnızca alıcıdan; temizlik 60 günü ve alındıyı gözetir', async () => {
  const p = 'chats/a_b/media/m4/original.jpg';
  bucket.clock = () => new Date('2026-10-01T00:00:00Z');  // 91 gün önce
  await call('PUT', `/v1/o?p=${p}`, { uid: 'a', body: bytes(20), headers: { 'content-type': 'image/jpeg' } });
  await call('PUT', '/v1/o?p=chats/a_b/media/m4/thumb.jpg', { uid: 'a', body: bytes(2), headers: { 'content-type': 'image/jpeg' } });
  bucket.clock = () => new Date('2026-12-30T00:00:00Z');

  assert.equal((await (await call('POST', '/v1/cleanup', { uid: 'a' })).json()).deleted, 0, 'alınmadan silinmez');
  assert.equal((await (await call('POST', `/v1/ack?p=${p}`, { uid: 'a' })).json()).ignored, true, 'gönderen işaretleyemez');
  assert.equal((await call('POST', `/v1/ack?p=${p}`, { uid: 'b' })).status, 200);
  assert.ok(bucket.objects.has(`acks/${p}`));

  const usage = await (await call('GET', '/v1/usage', { uid: 'b' })).json();
  assert.equal(usage.usedBytes, 22);
  assert.equal(usage.originalBytes, 20);

  const result = await (await call('POST', '/v1/cleanup', { uid: 'b' })).json();
  assert.equal(result.deleted, 1);
  assert.ok(!bucket.objects.has(p));
  assert.ok(!bucket.objects.has(`acks/${p}`));
  assert.ok(bucket.objects.has('chats/a_b/media/m4/thumb.jpg'), 'önizleme kalır');
  assert.equal((await call('GET', `/v1/o?p=${p}`, { uid: 'b' })).status, 404);
});

test('klasör silme: sahibi ya da sohbet üyesi', async () => {
  await call('PUT', '/v1/o?p=users/a/stickers/s1.png', { uid: 'a', body: bytes(3), headers: { 'content-type': 'image/png' } });
  await call('PUT', '/v1/o?p=chats/a_b/media/m5/original.jpg', { uid: 'a', body: bytes(3), headers: { 'content-type': 'image/jpeg' } });
  await call('POST', '/v1/ack?p=chats/a_b/media/m5/original.jpg', { uid: 'b' });
  assert.equal((await call('DELETE', '/v1/prefix?p=users/a/stickers/', { uid: 'b' })).status, 403);
  assert.equal((await call('DELETE', '/v1/prefix?p=users/a/stickers/', { uid: 'a' })).status, 200);
  assert.equal((await call('DELETE', '/v1/prefix?p=chats/a_b/', { uid: 'b' })).status, 200);
  assert.equal(bucket.objects.size, 0);
});

test('profil fotoğrafı: tek dosya, herkese açık okuma', async () => {
  await call('PUT', '/v1/o?p=profile_images/a/x1.jpg', { uid: 'a', body: bytes(4), headers: { 'content-type': 'image/jpeg' } });
  await call('PUT', '/v1/o?p=profile_images/a/x2.jpg', { uid: 'a', body: bytes(4), headers: { 'content-type': 'image/jpeg' } });
  assert.deepEqual([...bucket.objects.keys()], ['profile_images/a/x2.jpg'], 'eskisi silinir');
  assert.equal((await call('GET', '/v1/public/profile_images/a/x2.jpg')).status, 200);
  assert.equal((await call('GET', '/v1/public/chats/a_b/media/m/thumb.jpg')).status, 404, 'yalnızca profil fotoğrafları açık');
});
