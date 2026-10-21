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

export function getWebPushConfig() {
  const cfg = webPushConfig();
  return { enabled: cfg.enabled, public_key: cfg.publicKey };
}

export function parseSubscription(body) {
  const endpoint = typeof body?.endpoint === 'string' ? body.endpoint.trim() : '';
  const p256dh = typeof body?.keys?.p256dh === 'string' ? body.keys.p256dh.trim() : '';
  const auth = typeof body?.keys?.auth === 'string' ? body.keys.auth.trim() : '';
  if (!/^https:\/\/[^\s]{10,1000}$/.test(endpoint)) throw invalid('Abonelik adresi geçersiz.');
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
  const lib = await webPushHooks.sender();
  const payload = JSON.stringify({ title, body, url });
  let ok = 0;
  const dead = [];
  await Promise.all(
    subs.map(async (s) => {
      try {
        await lib.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, timeout: 10000 });
        ok += 1;
      } catch (error) {
        if (error?.statusCode === 404 || error?.statusCode === 410) dead.push(s.id);
      }
    }),
  );
  if (dead.length) await db.query(`DELETE FROM web_push_subscriptions WHERE id = ANY($1::bigint[])`, [dead]);
  return ok;
}

/** Hesap silme: kullanicinin abonelikleri (tablo yoksa atlanir). */
export async function deleteWebPushDataForUser(client, userCode) {
  const has = (await client.query(`SELECT to_regclass('public.web_push_subscriptions') IS NOT NULL AS ok`)).rows?.[0]?.ok === true;
  if (!has) return 0;
  return Number((await client.query(`DELETE FROM web_push_subscriptions WHERE user_code = $1`, [userCode])).rowCount ?? 0);
}
