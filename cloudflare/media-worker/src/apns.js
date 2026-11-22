// APNs (Apple) doğrudan gönderim: VoIP push (kilit ekranında arama). ES256 JWT, .p8 anahtarı.

const b64url = (bytes) => {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const encodeJSON = (obj) => b64url(new TextEncoder().encode(JSON.stringify(obj)));

function pemToBytes(pem) {
  const body = String(pem).replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** APNs ayarları secret'lardan; eksikse `null` (VoIP push gönderilmez, FCM bildirimine düşülür). */
export function apnsConfig(env) {
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
  return {
    key: env.APNS_KEY_P8,
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    bundleId: env.APNS_BUNDLE_ID || 'com.farvatrack.FarvaTrack',
  };
}

let cached = { keyId: '', token: '', issued: 0 };

/** APNs sağlayıcı belirteci (Apple: 20–60 dk arası yenilenmeli; 40 dk önbellek). */
export async function providerToken(config, now = () => Date.now()) {
  const seconds = Math.floor(now() / 1000);
  if (cached.keyId === config.keyId && seconds - cached.issued < 40 * 60) return cached.token;
  const header = encodeJSON({ alg: 'ES256', kid: config.keyId });
  const claims = encodeJSON({ iss: config.teamId, iat: seconds });
  const key = await crypto.subtle.importKey('pkcs8', pemToBytes(config.key), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  // WebCrypto ECDSA imzası r||s (IEEE P1363) biçimindedir; JWT ES256 de bunu bekler.
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${claims}`)));
  const token = `${header}.${claims}.${b64url(signature)}`;
  cached = { keyId: config.keyId, token, issued: seconds };
  return token;
}

export function resetApnsCache() {
  cached = { keyId: '', token: '', issued: 0 };
}

export const APNS_HOSTS = ['https://api.push.apple.com', 'https://api.sandbox.push.apple.com'];

/**
 * VoIP push gönderir. Önce üretim, `BadDeviceToken` ise geliştirme (Xcode'dan kurulum) sunucusu denenir.
 * Döner: { ok, status, reason }.
 */
export async function sendVoIP(config, deviceToken, payload, { fetcher = fetch, now = () => Date.now() } = {}) {
  const jwt = await providerToken(config, now);
  let last = { ok: false, status: 0, reason: '' };
  for (const host of APNS_HOSTS) {
    const response = await fetcher(`${host}/3/device/${deviceToken}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': `${config.bundleId}.voip`,
        'apns-push-type': 'voip',
        'apns-priority': '10',
        'apns-expiration': '0',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    if (response.ok) return { ok: true, status: response.status, reason: '' };
    const body = await response.json().catch(() => ({}));
    last = { ok: false, status: response.status, reason: body.reason || '' };
    if (last.reason !== 'BadDeviceToken') break;
  }
  return last;
}
