import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyIdToken, resetKeyCache } from '../src/auth.js';

const enc = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');

async function setup() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  const fetcher = async () => new Response(JSON.stringify({ keys: [{ ...jwk, kid: 'k1' }] }), { headers: { 'cache-control': 'max-age=100' } });
  const sign = async (payload, kid = 'k1') => {
    const head = enc({ alg: 'RS256', kid });
    const body = enc(payload);
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(`${head}.${body}`));
    return `${head}.${body}.${Buffer.from(sig).toString('base64url')}`;
  };
  return { fetcher, sign };
}

test('geçerli belirteç uid döndürür, bozuklar reddedilir', async () => {
  resetKeyCache();
  const { fetcher, sign } = await setup();
  const now = 1_800_000_000_000;
  const base = { aud: 'proj', iss: 'https://securetoken.google.com/proj', sub: 'u1', iat: now / 1000 - 10, exp: now / 1000 + 600 };
  const opts = { fetcher, now: () => now };
  assert.equal(await verifyIdToken(await sign(base), 'proj', opts), 'u1');
  assert.equal(await verifyIdToken(await sign({ ...base, aud: 'baska' }), 'proj', opts), null);
  assert.equal(await verifyIdToken(await sign({ ...base, exp: now / 1000 - 1 }), 'proj', opts), null, 'süresi dolmuş');
  assert.equal(await verifyIdToken(await sign(base, 'yok'), 'proj', opts), null, 'bilinmeyen anahtar');
  const token = await sign(base);
  const tampered = token.split('.');
  tampered[1] = enc({ ...base, sub: 'saldirgan' });
  assert.equal(await verifyIdToken(tampered.join('.'), 'proj', opts), null, 'imza tutmaz');
  assert.equal(await verifyIdToken('a.b', 'proj', opts), null);
  assert.equal(await verifyIdToken('', 'proj', opts), null);
});
