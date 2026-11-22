import { test } from 'node:test';
import assert from 'node:assert/strict';
import { providerToken, resetApnsCache, sendVoIP } from '../src/apns.js';
import { cleanIceServers, iceServers } from '../src/turn.js';
import { handle, resetMembershipCache, resetNotificationCache } from '../src/index.js';
import { FakeBucket } from './fake-r2.js';

async function apnsKey() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  return { pem: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----`, publicKey: pair.publicKey };
}

test('APNs: ES256 sağlayıcı belirteci doğrulanır ve önbelleğe alınır', async () => {
  resetApnsCache();
  const { pem, publicKey } = await apnsKey();
  const config = { key: pem, keyId: 'KEY123', teamId: 'TEAM45', bundleId: 'com.farvatrack.FarvaTrack' };
  const token = await providerToken(config, () => 1_800_000_000_000);
  const [h, c, s] = token.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: 'KEY123' });
  assert.deepEqual(JSON.parse(Buffer.from(c, 'base64url')), { iss: 'TEAM45', iat: 1_800_000_000 });
  const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok);
  assert.equal(await providerToken(config, () => 1_800_000_000_000 + 60_000), token, '40 dk içinde aynı belirteç');
});

test('APNs: VoIP üretimde tanınmazsa geliştirme sunucusu denenir', async () => {
  resetApnsCache();
  const { pem } = await apnsKey();
  const config = { key: pem, keyId: 'K', teamId: 'T', bundleId: 'com.farvatrack.FarvaTrack' };
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, headers: init.headers, body: JSON.parse(init.body) });
    return url.includes('sandbox') ? new Response('', { status: 200 }) : new Response(JSON.stringify({ reason: 'BadDeviceToken' }), { status: 400 });
  };
  const result = await sendVoIP(config, 'abc', { callId: 'c1' }, { fetcher });
  assert.ok(result.ok);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].headers['apns-topic'], 'com.farvatrack.FarvaTrack.voip');
  assert.equal(calls[0].headers['apns-push-type'], 'voip');
  assert.ok(calls[1].url.startsWith('https://api.sandbox.push.apple.com/3/device/abc'));

  const gone = await sendVoIP(config, 'x', {}, { fetcher: async () => new Response(JSON.stringify({ reason: 'Unregistered' }), { status: 410 }) });
  assert.deepEqual(gone, { ok: false, status: 410, reason: 'Unregistered' });
});

test('TURN: Cloudflare anahtarı, sabit yapılandırma ya da yalnızca STUN', async () => {
  let request;
  const fetcher = async (url, init) => {
    request = { url, init };
    return new Response(JSON.stringify({ iceServers: [
      { urls: ['stun:stun.cloudflare.com:3478'] },
      { urls: ['turn:turn.cloudflare.com:3478?transport=udp', 'turn:turn.cloudflare.com:53?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp'], username: 'u', credential: 'p' },
    ] }), { status: 201 });
  };
  const cf = await iceServers({ TURN_KEY_ID: 'kid', TURN_KEY_API_TOKEN: 'secret' }, fetcher);
  assert.equal(cf.source, 'cloudflare');
  assert.ok(request.url.endsWith('/v1/turn/keys/kid/credentials/generate-ice-servers'));
  assert.equal(request.init.headers.Authorization, 'Bearer secret');
  assert.deepEqual(cf.iceServers[1].urls, ['turn:turn.cloudflare.com:3478?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp'], '53 numaralı port ayıklanır');
  assert.equal(cf.iceServers[1].credential, 'p');

  const fixed = await iceServers({ TURN_URLS: 'turn:a.example:3478, turns:a.example:443', TURN_USERNAME: 'x', TURN_CREDENTIAL: 'y' }, fetcher);
  assert.equal(fixed.source, 'static');
  assert.deepEqual(fixed.iceServers[1], { urls: ['turn:a.example:3478', 'turns:a.example:443'], username: 'x', credential: 'y' });

  assert.equal((await iceServers({}, fetcher)).source, 'stun');
  assert.deepEqual(cleanIceServers([{ urls: 'turn:x:53' }]), []);
});

// MARK: Uç noktalar

function doc(name, fields) {
  const encode = (v) => {
    if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
    if (typeof v === 'boolean') return { booleanValue: v };
    if (v && typeof v === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)])) } };
    return { stringValue: String(v) };
  };
  return { name: `projects/p/databases/(default)/documents/${name}`, fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, encode(v)])) };
}

function setup({ status = 'ringing', callerId = 'a', devices }) {
  resetMembershipCache();
  resetNotificationCache();
  const fcm = [];
  const voip = [];
  const fetcher = async (url, init = {}) => {
    if (url.startsWith('https://fcm.googleapis.com')) { fcm.push(JSON.parse(init.body).message); return new Response('{}'); }
    const path = decodeURIComponent(url.split('/documents/')[1].split('?')[0]);
    if (path === 'chats/a_b') return new Response(JSON.stringify(doc(path, { members: ['a', 'b'], names: { a: 'Ali' } })));
    if (path === 'chats/a_b/calls/c1') return new Response(JSON.stringify(doc(path, { callerId, calleeId: callerId === 'a' ? 'b' : 'a', status })));
    if (path === 'users/b/devices') return new Response(JSON.stringify({ documents: devices.map((d, i) => doc(`users/b/devices/d${i}`, d)) }));
    return new Response('{}', { status: 404 });
  };
  const env = { BUCKET: new FakeBucket(), FIREBASE_PROJECT_ID: 'p', APNS_KEY_P8: 'k', APNS_KEY_ID: 'i', APNS_TEAM_ID: 't' };
  const deps = {
    verify: async (t) => t,
    now: () => new Date(),
    fetch: fetcher,
    googleToken: async () => 'g',
    sendVoIP: async (config, token, payload) => { voip.push({ token, payload }); return { ok: token !== 'kotu' }; },
  };
  const call = (uid, body) => handle(new Request('https://w.dev/v1/call', {
    method: 'POST', headers: { authorization: `Bearer ${uid}`, 'content-type': 'application/json' }, body: JSON.stringify(body),
  }), env, deps);
  const turn = (uid) => handle(new Request('https://w.dev/v1/turn', { headers: uid ? { authorization: `Bearer ${uid}` } : {} }), env, deps);
  return { call, turn, fcm, voip };
}

test('çaldırma: VoIP belirteci olana VoIP, olmayana bildirim', async () => {
  const { call, fcm, voip } = setup({ devices: [{ token: 'f1', voipToken: 'v1' }, { token: 'f2' }, { token: 'f3', voipToken: 'kotu' }, { token: 'f4', muted: true }] });
  const result = await (await call('a', { chatId: 'a_b', callId: 'c1' })).json();
  assert.equal(result.voip, 1);
  assert.equal(result.alerts, 2, 'VoIP başarısızsa bildirime düşülür; sessizdeki atlanır');
  assert.deepEqual(voip[0], { token: 'v1', payload: { callId: 'c1', chatId: 'a_b', callerName: 'Ali', aps: {} } });
  assert.equal(fcm[0].notification.body, '📞 Seni arıyor');
  assert.equal(fcm[0].data.kind, 'call');
  assert.equal(fcm[0].data.callId, 'c1');
  assert.equal((await (await call('a', { chatId: 'a_b', callId: 'c1' })).json()).reason, 'duplicate');
});

test('çaldırma: yalnızca arayan, yalnızca çalarken', async () => {
  assert.equal((await setup({ devices: [] }).call('b', { chatId: 'a_b', callId: 'c1' })).status, 403);
  assert.equal((await setup({ devices: [] }).call('z', { chatId: 'a_b', callId: 'c1' })).status, 403);
  assert.equal((await (await setup({ status: 'ended', devices: [{ token: 't' }] }).call('a', { chatId: 'a_b', callId: 'c1' })).json()).reason, 'not_ringing');
});

test('TURN uç noktası oturum ister', async () => {
  const { turn } = setup({ devices: [] });
  assert.equal((await turn('')).status, 401);
  const body = await (await turn('a')).json();
  assert.equal(body.source, 'stun');
  assert.ok(body.iceServers[0].urls[0].startsWith('stun:'));
});
