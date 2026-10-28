// Firebase'siz tarayici bildirimi (VAPID web push). Anahtarlar .env: WEB_PUSH_VAPID_PUBLIC, WEB_PUSH_VAPID_PRIVATE, WEB_PUSH_SUBJECT (mailto: ya da https:).
// Yoksa ozellik kapali (enabled:false). `web-push` paketi ilk gonderimde tembel yuklenir.
import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { parsePositiveId } from './people_common.js';

const pushUserCodeOf = (authUser) => parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, 2147483647);

export const MAX_SUBSCRIPTIONS_PER_USER = 10;
const rawOf = (name) => String(process.env[name] ?? '').trim();

export function webPushConfig() {
  const publicKey = rawOf('WEB_PUSH_VAPID_PUBLIC');
  const privateKey = rawOf('WEB_PUSH_VAPID_PRIVATE');
  const subject = rawOf('WEB_PUSH_SUBJECT');
  const enabled = Boolean(publicKey && privateKey && /^(mailto:|https:\/\/)/.test(subject));
  return { enabled, publicKey: enabled ? publicKey : null, privateKey, subject };
}

export const webPushHooks = {
  sender: async () => {
    const mod = await import('web-push');
    const lib = mod.default ?? mod;
    const cfg = webPushConfig();
    lib.setVapidDetails(cfg.subject, cfg.publicKey, cfg.privateKey);
    return lib;
  },
};

const unavailable = () => new PlatformError(503, 'WEB_PUSH_UNAVAILABLE', 'Tarayıcı bildirimi şu an kullanılamıyor.');
const invalid = (m) => new PlatformError(400, 'INVALID_BODY', m);

/**
 * Abonelik adresi (endpoint) icin IZINLI tarayici bildirim servisleri - TEK kaynak. Sunucu bu adreslere kendi VAPID basligiyla POST eder;
 * kullanicinin verdigi keyfi bir https adresi (saldirgan sunucusu, ic ag, bulut metadata) bu yuzden KABUL EDILMEZ: kor SSRF ve sonsuz yanitla
 * `web-push` yanit tamponunu sisirip API surecini cokertme yolu kapanir.
 *   'ad.alan.com'  -> yalniz bu ad (tam eslesme)
 *   '*.alan.com'   -> alan.com'un alt alan adlari (alan.com'un kendisi HARIC)
 * Yeni bir servis gerekirse YALNIZ buraya eklenir; *.googleapis.com gibi kullanici icerigi barindirabilen genis jokerler EKLENMEZ.
 */
export const WEB_PUSH_ALLOWED_HOSTS = Object.freeze([
  'fcm.googleapis.com', // Chrome, Edge, Opera, Brave, Samsung Internet (FCM)
  'updates.push.services.mozilla.com', // Firefox
  '*.push.apple.com', // Safari / iOS / macOS (web.push.apple.com)
  '*.notify.windows.com', // Windows Bildirim Hizmeti (WNS)
]);

const MAX_ENDPOINT_LENGTH = 1008; // 'https://' + en cok 1000 karakter (veritabani kisiti 1024)
const DNS_LABEL = '[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?';
// https://<en az iki etiketli alan adi>[:443]/<yol ve sorgu>. Kullanici bilgisi (@), ters bolu, parca (#), bosluk/denetim karakteri, ASCII disi
// harf ve baska kapi YOK; boylece WHATWG URL ile web-push'un kullandigi eski url.parse AYNI ana makineyi gorur (ayristirici farki kapisi yok).
const ENDPOINT_SHAPE = new RegExp(`^https://((?:${DNS_LABEL}\\.)+${DNS_LABEL})(?::443)?/[A-Za-z0-9._~:/?&=+%!$'()*,;-]*$`);

function isAllowedPushHost(host) {
  return WEB_PUSH_ALLOWED_HOSTS.some((entry) => {
    if (!entry.startsWith('*.')) return host === entry;
    const suffix = entry.slice(1); // '.push.apple.com'
    return host.length > suffix.length && host.endsWith(suffix);
  });
}

/** Abonelik adresi izinli bir tarayici bildirim servisine ait mi? (https + izinli alan adi + 443 + kullanici bilgisi/parca yok) */
export function isAllowedPushEndpoint(endpoint) {
  if (typeof endpoint !== 'string' || endpoint.length > MAX_ENDPOINT_LENGTH) return false;
  const shape = ENDPOINT_SHAPE.exec(endpoint);
  if (!shape) return false;
  const host = shape[1].toLowerCase();
  if (!isAllowedPushHost(host)) return false;
  try {
    // Ikinci, bagimsiz denetim: standart URL ayristiricisi da AYNI ana makineyi gormeli.
    const url = new URL(endpoint);
    return url.protocol === 'https:' && url.hostname === host && url.port === '' && url.username === '' && url.password === '' && url.hash === '';
  } catch (_error) {
    return false;
  }
}

export function getWebPushConfig() {
  const cfg = webPushConfig();
  return { enabled: cfg.enabled, public_key: cfg.publicKey };
}

export function parseSubscription(body) {
  const endpoint = typeof body?.endpoint === 'string' ? body.endpoint.trim() : '';
  const p256dh = typeof body?.keys?.p256dh === 'string' ? body.keys.p256dh.trim() : '';
  const auth = typeof body?.keys?.auth === 'string' ? body.keys.auth.trim() : '';
  if (!isAllowedPushEndpoint(endpoint)) throw invalid('Abonelik adresi geçersiz ya da bu bildirim servisi desteklenmiyor.');
  if (!/^[A-Za-z0-9_-]{20,200}$/.test(p256dh) || !/^[A-Za-z0-9_-]{8,100}$/.test(auth)) throw invalid('Abonelik anahtarları geçersiz.');
  return { endpoint, p256dh, auth };
}

export async function saveSubscription(authUser, body, db = pool) {
  if (!webPushConfig().enabled) throw unavailable();
  const userCode = pushUserCodeOf(authUser);
  if (userCode === null) throw new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
  const sub = parseSubscription(body);
  const count = await db.query(`SELECT COUNT(*)::int AS n FROM web_push_subscriptions WHERE user_code = $1 AND endpoint <> $2`, [userCode, sub.endpoint]);
  if (Number(count.rows[0].n) >= MAX_SUBSCRIPTIONS_PER_USER) {
    await db.query(
      `DELETE FROM web_push_subscriptions WHERE id IN (SELECT id FROM web_push_subscriptions WHERE user_code = $1 ORDER BY created_at LIMIT 1)`,
      [userCode],
    );
  }
  await db.query(
    `INSERT INTO web_push_subscriptions (user_code, endpoint, p256dh, auth) VALUES ($1, $2, $3, $4)
     ON CONFLICT (endpoint) DO UPDATE SET user_code = EXCLUDED.user_code, p256dh = EXCLUDED.p256dh, auth = EXCLUDED.auth`,
    [userCode, sub.endpoint, sub.p256dh, sub.auth],
  );
  return { ok: true };
}

export async function deleteSubscription(authUser, body, db = pool) {
  const userCode = pushUserCodeOf(authUser);
  const endpoint = typeof body?.endpoint === 'string' ? body.endpoint.trim() : '';
  if (userCode !== null && endpoint) {
    await db.query(`DELETE FROM web_push_subscriptions WHERE user_code = $1 AND endpoint = $2`, [userCode, endpoint]);
  }
  return { ok: true };
}

/** Kullanicilara tarayici bildirimi (en iyi caba). 404/410 abonelikler silinir. @returns {Promise<number>} basarili sayisi */
export async function sendWebPushToUsers(userCodes, { title, body, url = '/' }, db = pool) {
  if (!webPushConfig().enabled || !userCodes?.length) return 0;
  const subs = (await db.query(`SELECT id, endpoint, p256dh, auth FROM web_push_subscriptions WHERE user_code = ANY($1::int[])`, [userCodes])).rows ?? [];
  if (!subs.length) return 0;
  // Gonderimden hemen once yeniden denetim: izin listesinden ONCE kaydedilmis ya da elle eklenmis uygunsuz adreslere ASLA istek atilmaz; satir silinir.
  const dead = [];
  const sendable = [];
  for (const s of subs) {
    if (isAllowedPushEndpoint(s.endpoint)) sendable.push(s);
    else dead.push(s.id);
  }
  let ok = 0;
  if (sendable.length) {
    const lib = await webPushHooks.sender();
    const payload = JSON.stringify({ title, body, url });
    await Promise.all(
      sendable.map(async (s) => {
        try {
          await lib.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, timeout: 10000 });
          ok += 1;
        } catch (error) {
          if (error?.statusCode === 404 || error?.statusCode === 410) dead.push(s.id);
        }
      }),
    );
  }
  if (dead.length) await db.query(`DELETE FROM web_push_subscriptions WHERE id = ANY($1::bigint[])`, [dead]);
  return ok;
}

/** Hesap silme: kullanicinin abonelikleri (tablo yoksa atlanir). */
export async function deleteWebPushDataForUser(client, userCode) {
  const has = (await client.query(`SELECT to_regclass('public.web_push_subscriptions') IS NOT NULL AS ok`)).rows?.[0]?.ok === true;
  if (!has) return 0;
  return Number((await client.query(`DELETE FROM web_push_subscriptions WHERE user_code = $1`, [userCode])).rowCount ?? 0);
}
