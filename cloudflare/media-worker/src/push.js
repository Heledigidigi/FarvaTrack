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
  const placeholder = PLACEHOLDERS[message.type] || 'Yeni mesaj';
  const caption = String(message.text || '').trim();
  return caption ? `${placeholder}: ${caption.slice(0, 80)}` : placeholder;
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
