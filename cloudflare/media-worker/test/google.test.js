import { test } from 'node:test';
import assert from 'node:assert/strict';
import { accessToken, decodeFields, parseServiceAccount, resetTokenCache } from '../src/google.js';

async function serviceAccount() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return { sa: { client_email: 'sa@proj.iam.gserviceaccount.com', private_key: pem }, publicKey: pair.publicKey };
}

test('servis hesabı: imzalı JWT ile belirteç alınır ve önbelleğe konur', async () => {
  resetTokenCache();
  const { sa, publicKey } = await serviceAccount();
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, body: init.body });
    return new Response(JSON.stringify({ access_token: 'g-token', expires_in: 3600 }));
  };
  const now = () => 1_800_000_000_000;
  assert.equal(await accessToken(sa, { fetcher, now }), 'g-token');
  assert.equal(await accessToken(sa, { fetcher, now }), 'g-token');
  assert.equal(calls.length, 1, 'önbellekten');

  const assertion = new URLSearchParams(calls[0].body).get('assertion');
  const [h, c, sig] = assertion.split('.');
  const claims = JSON.parse(Buffer.from(c, 'base64url').toString());
  assert.equal(claims.iss, sa.client_email);
  assert.equal(claims.aud, 'https://oauth2.googleapis.com/token');
  assert.ok(claims.scope.includes('firebase.messaging'));
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, Buffer.from(sig, 'base64url'), new TextEncoder().encode(`${h}.${c}`));
  assert.ok(valid, 'imza doğru');
});

test('servis hesabı secret biçimleri ve Firestore değerleri', () => {
  const json = JSON.stringify({ client_email: 'x', private_key: 'y' });
  assert.equal(parseServiceAccount(json).client_email, 'x');
  assert.equal(parseServiceAccount(Buffer.from(json).toString('base64')).client_email, 'x');
  assert.equal(parseServiceAccount(''), null);
  assert.equal(parseServiceAccount('{"a":1}'), null);
  assert.deepEqual(decodeFields({
    members: { arrayValue: { values: [{ stringValue: 'a' }, { stringValue: 'b' }] } },
    names: { mapValue: { fields: { a: { stringValue: 'Ali' } } } },
    deleted: { booleanValue: false },
    readAt: { nullValue: null },
    n: { integerValue: '3' },
  }), { members: ['a', 'b'], names: { a: 'Ali' }, deleted: false, readAt: null, n: 3 });
});
