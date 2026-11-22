import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { handle, resetMembershipCache, resetNotificationCache } from '../src/index.js';
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

test('not sohbetinde gönderen kendi orijalini işaretleyebilir', async () => {
  rooms.set('a_a', ['a', 'a']);
  const p = 'chats/a_a/media/n1/original.jpg';
  assert.equal((await call('PUT', `/v1/o?p=${p}`, { uid: 'a', body: bytes(5), headers: { 'content-type': 'image/jpeg' } })).status, 200);
  const ack = await (await call('POST', `/v1/ack?p=${p}`, { uid: 'a' })).json();
  assert.equal(ack.ignored, undefined);
  assert.ok(bucket.objects.has(`acks/${p}`));
  assert.equal((await call('GET', `/v1/o?p=${p}`, { uid: 'b' })).status, 403, 'başkası göremez');
});

// MARK: Bildirim (8G)


function firestoreDoc(name, fields) {
  const encode = (v) => {
    if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
    if (v === null) return { nullValue: null };
    if (typeof v === 'boolean') return { booleanValue: v };
    if (typeof v === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)])) } };
    return { stringValue: String(v) };
  };
  return { name: `projects/proj/databases/(default)/documents/${name}`, fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, encode(v)])) };
}

function notifyDeps({ devices, message, fcmStatus = 200 }) {
  const sent = [];
  const removed = [];
  const fetcher = async (url, init = {}) => {
    if (url.startsWith('https://fcm.googleapis.com')) {
      sent.push(JSON.parse(init.body).message);
      return fcmStatus === 200 ? new Response('{}') : new Response(JSON.stringify({ error: { status: 'NOT_FOUND' } }), { status: fcmStatus });
    }
    const docPath = decodeURIComponent(url.split('/documents/')[1].split('?')[0]);
    if (init.method === 'DELETE') { removed.push(docPath); return new Response('{}'); }
    if (docPath.endsWith(':runQuery')) {
      return new Response(JSON.stringify([{ document: firestoreDoc('chats/a_b/messages/m1', message) }]));
    }
    if (docPath === 'chats/a_b') return new Response(JSON.stringify(firestoreDoc('chats/a_b', { members: ['a', 'b'], names: { a: 'Ali', b: 'Elif' } })));
    if (docPath === 'chats/a_a') return new Response(JSON.stringify(firestoreDoc('chats/a_a', { members: ['a', 'a'] })));
    if (docPath === 'chats/a_b/messages/m1') return new Response(JSON.stringify(firestoreDoc(docPath, message)));
    if (docPath === 'users/b/devices') return new Response(JSON.stringify({ documents: devices.map((d) => firestoreDoc(`users/b/devices/${d.id}`, d.fields)) }));
    return new Response('{}', { status: 404 });
  };
  return { deps: { ...deps, fetch: fetcher, googleToken: async () => 'g-token' }, sent, removed };
}

const notifyCall = (uid, body, d) => handle(new Request('https://w.dev/v1/notify', {
  method: 'POST', headers: { authorization: `Bearer ${uid}`, 'content-type': 'application/json' }, body: JSON.stringify(body),
}), env, d);

test('bildirim: gönderenin mesajı karşı tarafın cihazlarına gider', async () => {
  resetNotificationCache();
  const { deps: d, sent, removed } = notifyDeps({
    message: { senderId: 'a', type: 'audio', text: '', deleted: false },
    devices: [{ id: 'd1', fields: { token: 'tok1', muted: false } }, { id: 'd2', fields: { token: 'tok2', muted: true } }],
  });
  const result = await (await notifyCall('a', { chatId: 'a_b', messageId: 'm1' }, d)).json();
  assert.equal(result.sent, 1, 'sessize alınan cihaza gitmez');
  assert.equal(sent[0].token, 'tok1');
  assert.equal(sent[0].notification.title, 'Ali');
  assert.equal(sent[0].notification.body, '🎤 Sesli mesaj');
  assert.equal(sent[0].apns.payload.aps.badge, 1);
  assert.deepEqual(removed, []);

  const again = await (await notifyCall('a', { chatId: 'a_b', messageId: 'm1' }, d)).json();
  assert.equal(again.reason, 'duplicate', 'yeniden deneme çift bildirim üretmez');
});

test('bildirim: başkasının mesajı, yabancı oda ve not sohbeti', async () => {
  resetNotificationCache();
  const { deps: d, sent } = notifyDeps({ message: { senderId: 'b', type: 'text', text: 'selam' }, devices: [{ id: 'd1', fields: { token: 't' } }] });
  assert.equal((await notifyCall('a', { chatId: 'a_b', messageId: 'm1' }, d)).status, 403, 'yalnızca kendi mesajı için');
  assert.equal((await notifyCall('c', { chatId: 'a_b', messageId: 'm1' }, d)).status, 403);
  assert.equal((await notifyCall('a', { chatId: '../x', messageId: 'm1' }, d)).status, 400);
  assert.equal((await (await notifyCall('a', { chatId: 'a_a', messageId: 'm9' }, d)).json()).reason, 'personal');
  assert.equal(sent.length, 0);
});

test('bildirim: geçersiz belirteç silinir; servis hesabı yoksa sessizce atlanır', async () => {
  resetNotificationCache();
  const { deps: d, removed } = notifyDeps({ message: { senderId: 'a', type: 'text', text: 'selam' }, devices: [{ id: 'eski', fields: { token: 't' } }], fcmStatus: 404 });
  const result = await (await notifyCall('a', { chatId: 'a_b', messageId: 'm1' }, d)).json();
  assert.equal(result.removed, 1);
  assert.deepEqual(removed, ['users/b/devices/eski']);

  resetNotificationCache();
  const none = await (await notifyCall('a', { chatId: 'a_b', messageId: 'm1' }, { ...d, googleToken: async () => null })).json();
  assert.equal(none.reason, 'not_configured');
});
