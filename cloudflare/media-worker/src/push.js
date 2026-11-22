// Bildirim içeriği: saf fonksiyonlar (node --test ile denenir).

const PLACEHOLDERS = {
  image: '📷 Fotoğraf',
  video: '🎬 Video',
  audio: '🎤 Sesli mesaj',
  sticker: '🌟 Sticker',
  call: '📞 Arama',
};

export const MAX_BODY = 180;

/** Mesaj türüne göre bildirim metni (uygulamadaki `ChatMessageType.placeholder` ile aynı). */
export function notificationBody(message) {
  if (!message || message.deleted) return null;
  if (message.type === 'text' || !message.type) {
    const text = String(message.text || '').replace(/\s+/g, ' ').trim();
    if (!text) return null;
    return text.length > MAX_BODY ? `${text.slice(0, MAX_BODY - 1)}…` : text;
  }
  if (message.type === 'call') return callSummary(message.call);
  const placeholder = PLACEHOLDERS[message.type] || 'Yeni mesaj';
  const caption = String(message.text || '').trim();
  return caption ? `${placeholder}: ${caption.slice(0, 80)}` : placeholder;
}

/** Arama satırı bildirimi (alıcının gözünden; uygulamadaki `CallFormat.summary` ile aynı). */
export function callSummary(call) {
  switch (call?.outcome) {
    case 'answered': {
      const total = Math.max(0, Math.round(Number(call.duration) || 0));
      const h = Math.floor(total / 3600);
      const m = Math.floor((total % 3600) / 60);
      const s = String(total % 60).padStart(2, '0');
      return `📞 Sesli arama · ${h > 0 ? `${h}:${String(m).padStart(2, '0')}` : m}:${s}`;
    }
    case 'declined': return '📞 Reddedilen arama';
    case 'busy': return '📞 Hat meşguldü';
    case 'failed': return '📞 Arama bağlanamadı';
    default: return '📞 Cevapsız arama';
  }
}

/**
 * Alıcının bu sohbette okumadığı mesaj sayısı (uygulama simgesindeki rozet).
 * `recent`: en yeniden eskiye mesajlar. Karşı tarafın mesajları, ilk okunmuş olanına kadar sayılır.
 */
export function unreadCount(recent, senderId) {
  let count = 0;
  for (const message of recent) {
    if (message.senderId !== senderId) continue;
    if (message.readAt) break;
    if (!message.deleted) count += 1;
  }
  return count;
}

/** FCM HTTP v1 mesajı (APNs yükü dahil). */
export function buildFcmMessage({ token, title, body, chatId, messageId, type, badge }) {
  return {
    message: {
      token,
      notification: { title, body },
      data: { chatId, messageId, type: type || 'text', kind: 'chat' },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
        payload: {
          aps: {
            badge,
            sound: 'default',
            'thread-id': chatId,
            category: 'CHAT_MESSAGE',
            'mutable-content': 1,
          },
        },
      },
    },
  };
}

/** FCM yanıtı belirtecin artık geçersiz olduğunu mu söylüyor (cihaz kaydı silinir). */
export function isDeadToken(status, body) {
  if (status === 404) return true;
  const code = body?.error?.details?.find?.((d) => d.errorCode)?.errorCode || body?.error?.status;
  return code === 'UNREGISTERED' || (status === 400 && code === 'INVALID_ARGUMENT');
}
