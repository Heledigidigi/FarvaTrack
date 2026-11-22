// FarvaTrack medya sunucusu: Cloudflare R2 + Firebase kimliği.
//
// Uç noktalar (hepsi `Authorization: Bearer <Firebase ID token>` ister, profil fotoğrafı okuma hariç):
//   PUT    /v1/o?p=<yol>                     tek parça yükleme (≤ 95 MB)
//   GET    /v1/o?p=<yol>                     indirme (Range destekli)
//   DELETE /v1/o?p=<yol>                     silme
//   POST   /v1/mpu?p=<yol>                   çok parçalı yükleme başlat → {uploadId}
//   PUT    /v1/mpu?p=&uploadId=&part=<n>     parça yükle → {partNumber, etag}
//   POST   /v1/mpu/complete?p=&uploadId=     bitir (gövde: {parts})
//   DELETE /v1/mpu?p=&uploadId=              iptal
//   DELETE /v1/prefix?p=<klasör/>            klasörü sil (hesap silme, stil silme)
//   POST   /v1/ack?p=<orijal yolu>           alıcı orijali cihazına aldı (temizlik buna bakar)
//   GET    /v1/usage                         depolama özeti
//   POST   /v1/cleanup                       temizliği hemen çalıştır
//   GET    /v1/public/profile_images/<uid>/<ad>.jpg   profil fotoğrafı (herkese açık, tahmin edilemez ad)
// Zamanlanmış görev (cron) her gün temizliği çalıştırır.

import { verifyIdToken } from './auth.js';
import {
  ACK_PREFIX, CLEANUP, authorize, chatIdFor, chatIdContains, parsePath, parsePrefix, selectForCleanup, uploadLimit,
} from './rules.js';

const SINGLE_UPLOAD_LIMIT = 95 * 1024 * 1024;
const MEMBERSHIP_TTL = 5 * 60 * 1000;
const membershipCache = new Map();

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json; charset=utf-8' } });
const fail = (status, message) => json({ error: message }, status);

/** Kullanıcı bu sohbetin üyesi mi: Firestore'a kullanıcının kendi belirteciyle sorulur (kurallar karar verir). */
async function chatMember(env, deps, token, uid, chatId) {
  if (!chatIdContains(chatId, uid)) return false;
  const key = `${uid}|${chatId}`;
  const cached = membershipCache.get(key);
  if (cached && cached.expires > Date.now()) return cached.value;
  const url = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/chats/${encodeURIComponent(chatId)}?mask.fieldPaths=members`;
  const response = await deps.fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  let value = false;
  if (response.ok) {
    const body = await response.json();
    const members = body?.fields?.members?.arrayValue?.values?.map((v) => v.stringValue) || [];
    value = members.includes(uid);
  }
  // Yalnızca olumlu sonuç önbelleğe alınır: yeni açılan oda hemen çalışsın.
  if (value) membershipCache.set(key, { value, expires: Date.now() + MEMBERSHIP_TTL });
  return value;
}

function contextFor(env, deps, token, uid) {
  return {
    isMember: (chatId) => chatMember(env, deps, token, uid, chatId),
    sharesChat: (other) => chatMember(env, deps, token, uid, chatIdFor(uid, other)),
  };
}

const defaultDeps = {
  fetch: (...args) => fetch(...args),
  verify: (token, projectId) => verifyIdToken(token, projectId),
  now: () => new Date(),
};

/** Testler için önbelleği temizler. */
export function resetMembershipCache() {
  membershipCache.clear();
}

async function deleteKeys(env, keys) {
  for (let i = 0; i < keys.length; i += 1000) {
    await env.BUCKET.delete(keys.slice(i, i + 1000));
  }
}

async function listAll(env, prefix) {
  const objects = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000 });
    objects.push(...page.objects);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return objects;
}

/** 60 gün / 10 GB kuralı. Yalnızca alıcının aldığı orijaller silinir; önizleme, ses ve sticker'lar kalır. */
export async function runCleanup(env, now = new Date()) {
  const all = await listAll(env, undefined);
  const objects = [];
  const acked = new Set();
  for (const o of all) {
    if (o.key.startsWith(ACK_PREFIX)) acked.add(o.key.slice(ACK_PREFIX.length));
    else objects.push({ key: o.key, size: o.size, uploaded: o.uploaded });
  }
  const result = selectForCleanup(objects, acked, now);
  await deleteKeys(env, result.keys.flatMap((key) => [key, ACK_PREFIX + key]));
  // Orijali çoktan silinmiş sahipsiz işaretler.
  const existing = new Set(objects.map((o) => o.key));
  const orphans = [...acked].filter((key) => !existing.has(key)).map((key) => ACK_PREFIX + key);
  await deleteKeys(env, orphans);
  return { deleted: result.keys.length, totalBytes: result.totalBytes, afterBytes: result.afterBytes, waitingBytes: result.waitingBytes };
}

async function usage(env) {
  const all = await listAll(env, undefined);
  let used = 0;
  let originals = 0;
  for (const o of all) {
    if (o.key.startsWith(ACK_PREFIX)) continue;
    used += o.size;
    if (/\/original\.[a-z0-9]{2,5}$/.test(o.key)) originals += o.size;
  }
  return {
    usedBytes: used,
    originalBytes: originals,
    limitBytes: 10 * 1000 * 1000 * 1000,
    highWaterBytes: CLEANUP.highWaterBytes,
    retentionDays: CLEANUP.retentionDays,
  };
}

function objectHeaders(object) {
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('accept-ranges', 'bytes');
  return headers;
}

async function serveObject(env, request, key, cacheControl) {
  const object = await env.BUCKET.get(key, { range: request.headers, onlyIf: request.headers });
  if (!object) return fail(404, 'Dosya bulunamadı');
  const headers = objectHeaders(object);
  if (cacheControl) headers.set('cache-control', cacheControl);
  if (!('body' in object) || !object.body) return new Response(null, { status: 304, headers });
  if (object.range && request.headers.has('range')) {
    const offset = object.range.offset ?? 0;
    const length = object.range.length ?? object.size - offset;
    headers.set('content-range', `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set('content-length', String(length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set('content-length', String(object.size));
  return new Response(object.body, { headers });
}

export async function handle(request, env, deps = defaultDeps) {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;

  if (method === 'GET' && path === '/') return json({ ok: true, service: 'farvatrack-media' });

  // Profil fotoğrafı: avatarlar kimliksiz yüklenir; ad rastgele olduğu için tahmin edilemez.
  if (method === 'GET' && path.startsWith('/v1/public/')) {
    const key = decodeURIComponent(path.slice('/v1/public/'.length));
    const parsed = parsePath(key);
    if (!parsed || parsed.kind !== 'profile') return fail(404, 'Bulunamadı');
    return serveObject(env, request, key, 'public, max-age=86400');
  }

  const token = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  const uid = await deps.verify(token, env.FIREBASE_PROJECT_ID);
  if (!uid) return fail(401, 'Oturum geçersiz');
  const ctx = contextFor(env, deps, token, uid);
  const key = url.searchParams.get('p') || '';

  if (path === '/v1/usage' && method === 'GET') return json(await usage(env));
  if (path === '/v1/cleanup' && method === 'POST') return json(await runCleanup(env, deps.now()));

  if (path === '/v1/prefix' && method === 'DELETE') {
    const prefix = parsePrefix(key);
    if (!prefix) return fail(400, 'Geçersiz klasör');
    const allowed = prefix.kind === 'owner' ? prefix.owner === uid : await ctx.isMember(prefix.chatId);
    if (!allowed) return fail(403, 'İzin yok');
    const objects = await listAll(env, key);
    const keys = objects.map((o) => o.key);
    if (prefix.kind === 'chat') keys.push(...(await listAll(env, ACK_PREFIX + key)).map((o) => o.key));
    await deleteKeys(env, keys);
    return json({ deleted: keys.length });
  }

  const parsed = parsePath(key);
  if (!parsed) return fail(400, 'Geçersiz yol');

  if (path === '/v1/ack' && method === 'POST') {
    if (parsed.kind !== 'chat' || parsed.media !== 'original') return fail(400, 'Yalnızca orijaller');
    if (!(await authorize({ op: 'read', parsed, uid, ...ctx }))) return fail(403, 'İzin yok');
    const head = await env.BUCKET.head(key);
    if (!head) return fail(404, 'Dosya bulunamadı');
    // Gönderen kendi dosyasını "aldım" diye işaretleyemez.
    if (head.customMetadata?.senderId === uid) return json({ ok: true, ignored: true });
    await env.BUCKET.put(ACK_PREFIX + key, new Uint8Array(0), { customMetadata: { by: uid } });
    return json({ ok: true });
  }

  if (path === '/v1/o') {
    if (method === 'GET') {
      if (!(await authorize({ op: 'read', parsed, uid, ...ctx }))) return fail(403, 'İzin yok');
      return serveObject(env, request, key, 'private, max-age=3600');
    }
    if (method === 'DELETE') {
      if (!(await authorize({ op: 'delete', parsed, uid, ...ctx }))) return fail(403, 'İzin yok');
      await env.BUCKET.delete([key, ACK_PREFIX + key]);
      return json({ ok: true });
    }
    if (method === 'PUT') {
      const limit = uploadLimit(parsed);
      const type = request.headers.get('content-type') || '';
      const size = Number(request.headers.get('content-length') || '-1');
      if (!limit.type.test(type)) return fail(415, 'Dosya türüne izin yok');
      if (!(size >= 0) || size > Math.min(limit.maxBytes, SINGLE_UPLOAD_LIMIT)) return fail(413, 'Dosya çok büyük');
      const existing = await env.BUCKET.head(key);
      const existingSender = existing?.customMetadata?.senderId || null;
      if (!(await authorize({ op: 'write', parsed, uid, existingSender, ...ctx }))) return fail(403, 'İzin yok');
      if (parsed.kind === 'profile') {
        // Tek profil fotoğrafı tutulur: eskiler silinir.
        const old = (await listAll(env, `profile_images/${uid}/`)).map((o) => o.key).filter((k) => k !== key);
        await deleteKeys(env, old);
      }
      await env.BUCKET.put(key, request.body, {
        httpMetadata: { contentType: type },
        customMetadata: { senderId: uid },
      });
      return json({ ok: true });
    }
  }

  if (path === '/v1/mpu' && method === 'POST') {
    const limit = uploadLimit(parsed);
    const type = request.headers.get('content-type') || '';
    const total = Number(request.headers.get('x-total-size') || '-1');
    if (!limit.type.test(type)) return fail(415, 'Dosya türüne izin yok');
    if (!(total >= 0) || total > limit.maxBytes) return fail(413, 'Dosya çok büyük');
    const existing = await env.BUCKET.head(key);
    const existingSender = existing?.customMetadata?.senderId || null;
    if (!(await authorize({ op: 'write', parsed, uid, existingSender, ...ctx }))) return fail(403, 'İzin yok');
    const upload = await env.BUCKET.createMultipartUpload(key, {
      httpMetadata: { contentType: type },
      customMetadata: { senderId: uid },
    });
    return json({ uploadId: upload.uploadId });
  }

  if (path.startsWith('/v1/mpu')) {
    const uploadId = url.searchParams.get('uploadId') || '';
    if (!uploadId) return fail(400, 'uploadId eksik');
    if (!(await authorize({ op: 'write', parsed, uid, ...ctx }))) return fail(403, 'İzin yok');
    const upload = env.BUCKET.resumeMultipartUpload(key, uploadId);

    if (path === '/v1/mpu' && method === 'PUT') {
      const part = Number(url.searchParams.get('part'));
      const size = Number(request.headers.get('content-length') || '-1');
      if (!Number.isInteger(part) || part < 1 || part > 10000) return fail(400, 'Geçersiz parça');
      if (!(size > 0) || size > SINGLE_UPLOAD_LIMIT) return fail(413, 'Parça çok büyük');
      const uploaded = await upload.uploadPart(part, request.body);
      return json({ partNumber: uploaded.partNumber, etag: uploaded.etag });
    }
    if (path === '/v1/mpu/complete' && method === 'POST') {
      const body = await request.json();
      const object = await upload.complete(body.parts || []);
      // Çok parçalı yüklemede toplam boyut ancak sonunda kesinleşir.
      if (object.size > uploadLimit(parsed).maxBytes || object.customMetadata?.senderId !== uid) {
        await env.BUCKET.delete(key);
        return fail(413, 'Dosya çok büyük');
      }
      return json({ ok: true, size: object.size });
    }
    if (path === '/v1/mpu' && method === 'DELETE') {
      await upload.abort();
      return json({ ok: true });
    }
  }

  return fail(404, 'Bilinmeyen istek');
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      return fail(500, String(error?.message || error));
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runCleanup(env));
  },
};
