// Google servis hesabı: OAuth erişim belirteci (RS256 JWT) ve Firestore REST yardımcıları.
// Firestore'a servis hesabıyla erişilir (kurallar atlanır); izin denetimini Worker kendisi yapar.

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
export const SCOPES = 'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore';

const b64url = (bytes) => {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const encodeJSON = (obj) => b64url(new TextEncoder().encode(JSON.stringify(obj)));

function pemToBytes(pem) {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** `FIREBASE_SERVICE_ACCOUNT` secret'ını çözer (JSON ya da base64 JSON). */
export function parseServiceAccount(raw) {
  if (!raw) return null;
  let text = String(raw).trim();
  if (!text.startsWith('{')) {
    try { text = atob(text); } catch { return null; }
  }
  try {
    const sa = JSON.parse(text);
    if (!sa.client_email || !sa.private_key) return null;
    return sa;
  } catch {
    return null;
  }
}

let cached = { key: '', token: '', expires: 0 };

/** Servis hesabıyla erişim belirteci (süresi dolana kadar önbellekte). */
export async function accessToken(sa, { fetcher = fetch, now = () => Date.now() } = {}) {
  const seconds = Math.floor(now() / 1000);
  if (cached.key === sa.client_email && cached.expires - 60 > seconds) return cached.token;

  const header = encodeJSON({ alg: 'RS256', typ: 'JWT' });
  const claims = encodeJSON({ iss: sa.client_email, scope: SCOPES, aud: TOKEN_URL, iat: seconds, exp: seconds + 3600 });
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToBytes(sa.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`)));
  const assertion = `${header}.${claims}.${b64url(signature)}`;

  const response = await fetcher(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
  });
  if (!response.ok) throw new Error(`Google erişim belirteci alınamadı (${response.status})`);
  const body = await response.json();
  cached = { key: sa.client_email, token: body.access_token, expires: seconds + (body.expires_in || 3600) };
  return cached.token;
}

export function resetTokenCache() {
  cached = { key: '', token: '', expires: 0 };
}

// MARK: Firestore değerleri

/** Firestore REST değerini düz JavaScript değerine çevirir. */
export function decodeValue(value) {
  if (!value || typeof value !== 'object') return null;
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in value) return decodeFields(value.mapValue.fields || {});
  return null;
}

export function decodeFields(fields = {}) {
  const out = {};
  for (const [name, value] of Object.entries(fields)) out[name] = decodeValue(value);
  return out;
}

/** Servis hesabıyla Firestore istemcisi. */
export function firestore(projectId, token, fetcher = fetch) {
  const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  const headers = { Authorization: `Bearer ${token}`, 'content-type': 'application/json' };
  const path = (p) => p.split('/').map(encodeURIComponent).join('/');
  return {
    async get(docPath) {
      const response = await fetcher(`${base}/${path(docPath)}`, { headers });
      if (response.status === 404) return null;
      if (!response.ok) throw new Error(`Firestore okunamadı (${response.status})`);
      const body = await response.json();
      return { id: body.name.split('/').pop(), ...decodeFields(body.fields) };
    },
    async list(collectionPath) {
      const response = await fetcher(`${base}/${path(collectionPath)}?pageSize=50`, { headers });
      if (!response.ok) return [];
      const body = await response.json();
      return (body.documents || []).map((d) => ({ id: d.name.split('/').pop(), ...decodeFields(d.fields) }));
    },
    async remove(docPath) {
      await fetcher(`${base}/${path(docPath)}`, { method: 'DELETE', headers });
    },
    /** Bir alt koleksiyondaki en yeni `limit` belge (createdAt'e göre). */
    async latest(parentPath, collectionId, limit) {
      const response = await fetcher(`${base}/${path(parentPath)}:runQuery`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          structuredQuery: {
            from: [{ collectionId }],
            orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
            limit,
          },
        }),
      });
      if (!response.ok) return [];
      const rows = await response.json();
      return rows.filter((r) => r.document).map((r) => ({ id: r.document.name.split('/').pop(), ...decodeFields(r.document.fields) }));
    },
  };
}
