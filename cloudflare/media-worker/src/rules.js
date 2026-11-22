// Dosya yolu kuralları: eski firebase/storage.rules ile aynı izinler.
// Saf fonksiyonlar; Worker dışında `node --test` ile denenir.

export const MB = 1024 * 1024;
export const GB = 1000 * 1000 * 1000;

const SEGMENT = /^[A-Za-z0-9_.-]{1,128}$/;
const PNG_NAME = /^[A-Za-z0-9-]+\.png$/;
const ORIGINAL_NAME = /^original\.[a-z0-9]{2,5}$/;

/** Yolun türünü çözer; tanınmayan ya da tehlikeli yollar `null`. */
export function parsePath(path) {
  if (typeof path !== 'string' || path.length === 0 || path.length > 512) return null;
  const parts = path.split('/');
  if (parts.some((p) => !SEGMENT.test(p) || p === '.' || p === '..')) return null;

  // profile_images/{uid}/{ad}.jpg
  if (parts.length === 3 && parts[0] === 'profile_images' && /^[A-Za-z0-9-]+\.jpg$/.test(parts[2])) {
    return { kind: 'profile', owner: parts[1], file: parts[2] };
  }
  // users/{uid}/stickers/{id}.png
  if (parts.length === 4 && parts[0] === 'users' && parts[2] === 'stickers' && PNG_NAME.test(parts[3])) {
    return { kind: 'sticker', owner: parts[1], file: parts[3] };
  }
  // users/{uid}/bubbles/{stilId}/{dosyaId}.png
  if (parts.length === 5 && parts[0] === 'users' && parts[2] === 'bubbles' && PNG_NAME.test(parts[4])) {
    return { kind: 'bubble', owner: parts[1], styleId: parts[3], file: parts[4] };
  }
  // chats/{chatId}/media/{mesajId}/{dosya}
  if (parts.length === 5 && parts[0] === 'chats' && parts[2] === 'media') {
    const file = parts[4];
    let media = null;
    if (file === 'thumb.jpg') media = 'thumb';
    else if (ORIGINAL_NAME.test(file)) media = 'original';
    else if (file === 'sticker.png') media = 'sticker';
    else if (file === 'voice.m4a') media = 'voice';
    if (!media) return null;
    return { kind: 'chat', chatId: parts[1], messageId: parts[3], file, media };
  }
  return null;
}

/** Toplu silinebilecek klasörler. */
export function parsePrefix(prefix) {
  if (typeof prefix !== 'string' || !prefix.endsWith('/')) return null;
  const parts = prefix.slice(0, -1).split('/');
  if (parts.some((p) => !SEGMENT.test(p) || p === '.' || p === '..')) return null;
  if (parts.length === 2 && parts[0] === 'profile_images') return { kind: 'owner', owner: parts[1] };
  if (parts.length === 3 && parts[0] === 'users' && (parts[2] === 'stickers' || parts[2] === 'bubbles')) {
    return { kind: 'owner', owner: parts[1] };
  }
  if (parts.length === 4 && parts[0] === 'users' && parts[2] === 'bubbles') return { kind: 'owner', owner: parts[1] };
  if (parts.length === 2 && parts[0] === 'chats') return { kind: 'chat', chatId: parts[1] };
  return null;
}

/** İki kullanıcının oda kimliği: `<küçük uid>_<büyük uid>` (uygulamadaki ChatID ile aynı). */
export function chatIdFor(a, b) {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

/** Oda kimliğinde istekte bulunan var mı (Firestore sorgusundan önce ucuz eleme). */
export function chatIdContains(chatId, uid) {
  const index = chatId.indexOf('_');
  if (index <= 0) return false;
  return chatId.slice(0, index) === uid || chatId.slice(index + 1) === uid;
}

/** Yazma sınırları: boyut ve içerik türü. */
export function uploadLimit(parsed) {
  switch (parsed.kind) {
    case 'profile': return { maxBytes: 5 * MB, type: /^image\/.+$/ };
    case 'sticker': return { maxBytes: 2 * MB, type: /^image\/png$/ };
    case 'bubble': return { maxBytes: 1 * MB, type: /^image\/png$/ };
    case 'chat':
      switch (parsed.media) {
        case 'thumb': return { maxBytes: 2 * MB, type: /^image\/jpeg$/ };
        case 'original': return { maxBytes: 2 * 1024 * MB, type: /^(image|video)\/.+$/ };
        case 'sticker': return { maxBytes: 2 * MB, type: /^image\/png$/ };
        case 'voice': return { maxBytes: 50 * MB, type: /^audio\/(mp4|aac|x-m4a|m4a)$/ };
      }
  }
  return null;
}

/**
 * İzin kararı. `isMember(chatId)` ve `sharesChat(otherUid)` Firestore'a soran (önbellekli) async yardımcılar.
 * op: 'read' | 'write' | 'delete'. `existingSender`: üzerine yazılan dosyanın göndereni (yoksa null).
 */
export async function authorize({ op, parsed, uid, isMember, sharesChat, existingSender = null }) {
  if (!uid || !parsed) return false;
  switch (parsed.kind) {
    case 'profile':
      if (op === 'read') return true;
      return parsed.owner === uid;
    case 'sticker':
      return parsed.owner === uid;
    case 'bubble':
      if (op === 'read') return parsed.owner === uid || (await sharesChat(parsed.owner));
      return parsed.owner === uid;
    case 'chat': {
      if (!chatIdContains(parsed.chatId, uid)) return false;
      if (!(await isMember(parsed.chatId))) return false;
      if (op === 'write' && existingSender && existingSender !== uid) return false;
      return true;
    }
  }
  return false;
}

// MARK: Temizlik

export const CLEANUP = {
  retentionDays: 60,
  // R2 ücretsiz kotası 10 GB: aşmadan önce en eski orijallerden yer açılır.
  highWaterBytes: 9 * GB,
  lowWaterBytes: 8.5 * GB,
};

export const ACK_PREFIX = 'acks/';
const ORIGINAL_KEY = /^chats\/[^/]+\/media\/[^/]+\/original\.[a-z0-9]{2,5}$/;

export function isOriginalKey(key) {
  return ORIGINAL_KEY.test(key);
}

/**
 * Hangi orijaller silinecek. Yalnızca alıcının "aldım" dediği (ack) orijaller silinir:
 *  1) 60 günden eskiler,
 *  2) toplam hâlâ üst sınırın üstündeyse, kalan alınmış orijaller en eskiden başlayarak alt sınıra inene kadar.
 * objects: [{key, size, uploaded: Date}] (acks/ hariç), acked: Set(orijal anahtarları)
 */
export function selectForCleanup(objects, acked, now, options = CLEANUP) {
  const total = objects.reduce((sum, o) => sum + o.size, 0);
  const cutoff = now.getTime() - options.retentionDays * 24 * 60 * 60 * 1000;
  const originals = objects
    .filter((o) => isOriginalKey(o.key))
    .sort((a, b) => a.uploaded.getTime() - b.uploaded.getTime());

  const selected = new Set();
  let remaining = total;
  for (const o of originals) {
    if (acked.has(o.key) && o.uploaded.getTime() < cutoff) {
      selected.add(o.key);
      remaining -= o.size;
    }
  }
  if (remaining > options.highWaterBytes) {
    for (const o of originals) {
      if (remaining <= options.lowWaterBytes) break;
      if (selected.has(o.key) || !acked.has(o.key)) continue;
      selected.add(o.key);
      remaining -= o.size;
    }
  }
  const waiting = originals.filter((o) => !acked.has(o.key)).reduce((sum, o) => sum + o.size, 0);
  return {
    keys: [...selected],
    totalBytes: total,
    afterBytes: remaining,
    // Alıcının henüz indirmediği orijaller silinmez; sınır bu yüzden aşılabilir.
    waitingBytes: waiting,
  };
}
