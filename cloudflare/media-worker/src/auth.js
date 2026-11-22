// Firebase kimlik belirteci (ID token) doğrulaması: RS256 imza + iss/aud/süre.

const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let keyCache = { keys: null, expires: 0 };

function base64UrlToBytes(value) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeJSON(part) {
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(part)));
}

async function publicKeys(fetcher) {
  const now = Date.now();
  if (keyCache.keys && keyCache.expires > now) return keyCache.keys;
  const response = await fetcher(JWKS_URL);
  if (!response.ok) throw new Error('Anahtarlar alınamadı');
  const body = await response.json();
  const maxAge = Number((response.headers.get('cache-control') || '').match(/max-age=(\d+)/)?.[1] || 3600);
  keyCache = { keys: body.keys || [], expires: now + Math.min(maxAge, 6 * 3600) * 1000 };
  return keyCache.keys;
}

/**
 * Geçerliyse kullanıcı kimliğini (uid) döndürür, değilse `null`.
 * `fetcher` ve `now` testlerde değiştirilir.
 */
export async function verifyIdToken(token, projectId, { fetcher = fetch, now = () => Date.now() } = {}) {
  if (!token || !projectId) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  let header, payload;
  try {
    header = decodeJSON(parts[0]);
    payload = decodeJSON(parts[1]);
  } catch {
    return null;
  }
  if (header.alg !== 'RS256' || !header.kid) return null;

  const seconds = Math.floor(now() / 1000);
  if (payload.aud !== projectId) return null;
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;
  if (typeof payload.sub !== 'string' || payload.sub.length === 0 || payload.sub.length > 128) return null;
  if (typeof payload.exp !== 'number' || payload.exp <= seconds) return null;
  if (typeof payload.iat !== 'number' || payload.iat > seconds + 300) return null;

  const jwk = (await publicKeys(fetcher)).find((k) => k.kid === header.kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey(
    'jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5', key, base64UrlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  return valid ? payload.sub : null;
}

/** Testler için anahtar önbelleğini sıfırlar. */
export function resetKeyCache() {
  keyCache = { keys: null, expires: 0 };
}
