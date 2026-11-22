// TURN/STUN sunucuları: kimlik bilgileri yapılandırmadan (secret) gelir, uygulamaya gömülmez.

export const FALLBACK_ICE = [{ urls: ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'] }];
export const TURN_TTL = 6 * 60 * 60;

/** Cloudflare Realtime TURN yanıtı: 53 numaralı port (DNS) adresleri ayıklanır. */
export function cleanIceServers(servers) {
  return (servers || [])
    .map((s) => {
      const urls = (Array.isArray(s.urls) ? s.urls : [s.urls]).filter((u) => typeof u === 'string' && !/:53(\?|$)/.test(u));
      return { ...s, urls };
    })
    .filter((s) => s.urls.length > 0);
}

/**
 * Sıra: Cloudflare TURN anahtarı (TURN_KEY_ID + TURN_KEY_API_TOKEN) → sabit TURN (TURN_URLS + TURN_USERNAME +
 * TURN_CREDENTIAL; ör. başka bir sağlayıcı) → yalnızca STUN.
 */
export async function iceServers(env, fetcher = fetch) {
  if (env.TURN_KEY_ID && env.TURN_KEY_API_TOKEN) {
    const response = await fetcher(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ ttl: TURN_TTL }),
    });
    if (response.ok) {
      const body = await response.json();
      const servers = cleanIceServers(body.iceServers);
      if (servers.length) return { iceServers: servers, source: 'cloudflare' };
    }
  }
  if (env.TURN_URLS && env.TURN_USERNAME && env.TURN_CREDENTIAL) {
    const urls = String(env.TURN_URLS).split(',').map((u) => u.trim()).filter(Boolean);
    return { iceServers: [...FALLBACK_ICE, { urls, username: env.TURN_USERNAME, credential: env.TURN_CREDENTIAL }], source: 'static' };
  }
  return { iceServers: FALLBACK_ICE, source: 'stun' };
}
