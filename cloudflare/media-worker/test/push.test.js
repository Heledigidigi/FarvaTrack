import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildFcmMessage, isDeadToken, notificationBody, unreadCount, MAX_BODY } from '../src/push.js';

test('bildirim metni türe göre', () => {
  assert.equal(notificationBody({ type: 'text', text: '  Akşam\n spora? ' }), 'Akşam spora?');
  assert.equal(notificationBody({ type: 'image', text: '' }), '📷 Fotoğraf');
  assert.equal(notificationBody({ type: 'video' }), '🎬 Video');
  assert.equal(notificationBody({ type: 'audio' }), '🎤 Sesli mesaj');
  assert.equal(notificationBody({ type: 'sticker' }), '🌟 Sticker');
  assert.equal(notificationBody({ type: 'image', text: 'manzara' }), '📷 Fotoğraf: manzara');
  assert.equal(notificationBody({ type: 'yeni-tur' }), 'Yeni mesaj');
  assert.equal(notificationBody({ type: 'text', text: '   ' }), null);
  assert.equal(notificationBody({ type: 'text', text: 'x', deleted: true }), null);
  const long = notificationBody({ type: 'text', text: 'a'.repeat(500) });
  assert.equal(long.length, MAX_BODY);
  assert.ok(long.endsWith('…'));
});

test('okunmamış sayısı: karşı tarafın son okunmuş mesajına kadar', () => {
  const recent = [
    { senderId: 'a' }, { senderId: 'b' }, { senderId: 'a', deleted: true }, { senderId: 'a' },
    { senderId: 'a', readAt: '2026-01-01T00:00:00Z' }, { senderId: 'a' },
  ];
  assert.equal(unreadCount(recent, 'a'), 2);
  assert.equal(unreadCount([], 'a'), 0);
});

test('FCM yükü', () => {
  const m = buildFcmMessage({ token: 't', title: 'Elif', body: 'selam', chatId: 'a_b', messageId: 'm1', type: 'text', badge: 3 }).message;
  assert.equal(m.token, 't');
  assert.deepEqual(m.notification, { title: 'Elif', body: 'selam' });
  assert.deepEqual(m.data, { chatId: 'a_b', messageId: 'm1', type: 'text', kind: 'chat' });
  assert.equal(m.apns.payload.aps.badge, 3);
  assert.equal(m.apns.payload.aps.category, 'CHAT_MESSAGE');
  assert.equal(m.apns.payload.aps['thread-id'], 'a_b');
  assert.ok(isDeadToken(404, null));
  assert.ok(isDeadToken(400, { error: { status: 'INVALID_ARGUMENT' } }));
  assert.ok(isDeadToken(400, { error: { details: [{ errorCode: 'UNREGISTERED' }] } }));
  assert.ok(!isDeadToken(500, { error: { status: 'INTERNAL' } }));
});
