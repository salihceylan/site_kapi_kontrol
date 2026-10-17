// Telefon bildirimi (Faz 3b-B): FCM mesajı ve bildirim metni. Saf: DB / ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_BELGELER.md B5 (mesaj biçimi) ve B7 (metin, K14).
//  - Metin gönderim ANINDA kurulur (outbox'ta metin saklanmaz). Varsayılan AYRINTISIZ: normal -> başlık site adı (<= 40), gövde "Yönetimden yeni bir
//    duyuru var."; acil -> başlık "Acil duyuru", gövde "{Site adı}: acil bir duyuru var. Ayrıntı için uygulamayı açın.". Kullanıcı
//    `push_show_preview` açtıysa gövde duyuru başlığıdır (<= 80 karakter, tek satır, duyuru başlığı temizliği). Finansal / kişisel ayrıntı YOK.
//  - `data` yalnız sabit anahtarlar + sayısal kimlikler (type, announcement_id, site_code, importance); başlık / gövde / ad ASLA. iOS `badge` YOK.
//  - acil: Android HIGH + `urgent` kanalı, iOS `time-sensitive`, ttl 172800 sn; normal: NORMAL + `announcements`, `active`, ttl 86400 sn.
//    Çift teslim collapse_key / apns-collapse-id = ann-<id> ile cihazda tek bildirime iner.

import { TTL_SECONDS } from './push_common.js';

export const SITE_NAME_MAX = 40;
export const PREVIEW_TITLE_MAX = 80;
export const DEFAULT_SITE_LABEL = 'Site Yönetimi';
export const NORMAL_BODY = 'Yönetimden yeni bir duyuru var.';
export const URGENT_TITLE = 'Acil duyuru';
export const urgentBody = (siteLabel) => `${siteLabel}: acil bir duyuru var. Ayrıntı için uygulamayı açın.`;
export const TEST_TITLE = 'Test bildirimi';
export const TEST_BODY = 'Telefon bildirimleri bu cihazda çalışıyor.';
const TEST_TTL_SECONDS = 600;

// Duyuru başlığı temizliğiyle aynı kurallar (announcement_common.normalizeTitle): görünmez / yön denetim karakterleri atılır, satır sonu ve kontrol
// karakterleri boşluğa döner, boşluklar tekleşir. U+200D (emoji birleştirici) korunur.
const STRIPPED_CODE_POINTS = new Set([
  0x061c, 0x200b, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xfeff,
]);
const LINE_SEPARATORS = new RegExp(`\\r\\n?|\\n|${String.fromCodePoint(0x2028)}|${String.fromCodePoint(0x2029)}`, 'g');
// eslint-disable-next-line no-control-regex
const CONTROL_ALL = /[\x00-\x1f\x7f-\x9f]/g;

/** Tek satır, temiz, en çok `max` karakter (kod noktası); uzunsa "…" ile kısaltılır. Metin değilse ''. */
export function singleLine(value, max) {
  if (typeof value !== 'string') {
    return '';
  }
  let text = '';
  for (const ch of value.normalize('NFC').replace(LINE_SEPARATORS, ' ')) {
    if (!STRIPPED_CODE_POINTS.has(ch.codePointAt(0))) {
      text += ch;
    }
  }
  text = text.replace(CONTROL_ALL, ' ').replace(/\s+/g, ' ').trim();
  const chars = Array.from(text);
  if (chars.length <= max) {
    return text;
  }
  return `${chars.slice(0, Math.max(1, max - 1)).join('').trimEnd()}…`;
}

/** Bildirim metni (B7). */
export function announcementTexts({ siteName, title, importance, showPreview }) {
  const siteLabel = singleLine(siteName, SITE_NAME_MAX) || DEFAULT_SITE_LABEL;
  const preview = showPreview === true ? singleLine(title, PREVIEW_TITLE_MAX) : '';
  if (importance === 'urgent') {
    return { title: URGENT_TITLE, body: preview || urgentBody(siteLabel) };
  }
  return { title: siteLabel, body: preview || NORMAL_BODY };
}

/**
 * Duyuru bildirimi (FCM HTTP v1 `message`). `token` yalnız istek gövdesine girer; çağıran mesajı günlüğe YAZMAZ.
 */
export function buildAnnouncementMessage({ token, announcementId, siteCode, siteName, title, importance, showPreview, nowMs = Date.now(), ttlSeconds = null }) {
  const urgent = importance === 'urgent';
  const id = String(Number(announcementId));
  const site = String(Number(siteCode));
  // ttl = min(varsayılan, outbox geçerliliğinden kalan): geç gönderilen bildirim FCM / APNs'te expires_at'ten sonra beklemez.
  const defaultTtl = urgent ? TTL_SECONDS.urgent : TTL_SECONDS.normal;
  const remaining = Number(ttlSeconds);
  const ttl = Number.isFinite(remaining) && ttlSeconds !== null ? Math.max(1, Math.min(defaultTtl, Math.floor(remaining))) : defaultTtl;
  const collapse = `ann-${id}`;
  return {
    token,
    notification: announcementTexts({ siteName, title, importance: urgent ? 'urgent' : 'normal', showPreview }),
    data: { type: 'announcement', announcement_id: id, site_code: site, importance: urgent ? 'urgent' : 'normal' },
    android: {
      priority: urgent ? 'HIGH' : 'NORMAL',
      ttl: `${ttl}s`,
      collapse_key: collapse,
      notification: { channel_id: urgent ? 'urgent' : 'announcements', tag: collapse },
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
        'apns-collapse-id': collapse,
        'apns-expiration': String(Math.floor(nowMs / 1000) + ttl),
      },
      payload: { aps: { sound: 'default', 'thread-id': `site-${site}`, 'interruption-level': urgent ? 'time-sensitive' : 'active' } },
    },
  };
}

/** POST /app/push/test: genel "Test bildirimi" (duyuruya bağlı değil; data yalnız type). */
export function buildTestMessage({ token, nowMs = Date.now() }) {
  return {
    token,
    notification: { title: TEST_TITLE, body: TEST_BODY },
    data: { type: 'test' },
    android: { priority: 'NORMAL', ttl: `${TEST_TTL_SECONDS}s`, notification: { channel_id: 'announcements' } },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
        'apns-expiration': String(Math.floor(nowMs / 1000) + TEST_TTL_SECONDS),
      },
      payload: { aps: { sound: 'default', 'interruption-level': 'active' } },
    },
  };
}
