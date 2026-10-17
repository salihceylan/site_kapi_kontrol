// Telefon bildirimi (Faz 3b-B): bildirim tercihlerinin push bölümü (GET / PUT /app/notification-preferences EKLEMELİ genişleme).
//
// Sözleşme: docs/PLATFORM_BELGELER.md B3 / B7. announcement_inbox.js bu modülü çağırır (e-posta tercihleri orada kalır).
//  - GET yanıtına eklenir: push_available (push GERÇEKTEN hazırsa true), push_show_preview, push_quiet { enabled, start: "HH:MM", end: "HH:MM" },
//    push_devices (kayıtlı cihaz sayısı). push_announcements mevcut alandır (varsayılan TRUE, "normal duyuru push'u").
//  - PUT KISMİ: push_announcements, push_show_preview, push_quiet_enabled (boolean), push_quiet_start / push_quiet_end ("HH:MM"). Gönderilmeyen
//    alan değişmez; bilinmeyen anahtarlar yok sayılır. Başlangıç = bitiş 400 (saklı değerle birleştirilmiş hâli denetlenir).
//  - Yazma işlemi kullanıcı satırını `deleted_at IS NULL ... FOR KEY SHARE` ile kilitler (silinmiş / pasif hesaba tercih yazılmaz); kilit sırası
//    users -> notification_preferences (hesap silme ile aynı yön).

import { pool } from '../db.js';
import { DEFAULT_QUIET_END, DEFAULT_QUIET_START, formatHhmm, invalidPushField, parseHhmm } from './push_common.js';
import { isPushAvailable } from './push_credentials.js';
import { lockLiveUser } from './push_devices.js';

const BOOLEAN_KEYS = ['push_announcements', 'push_show_preview', 'push_quiet_enabled'];
const TIME_KEYS = ['push_quiet_start', 'push_quiet_end'];
export const PUSH_PREFERENCE_KEYS = Object.freeze([...BOOLEAN_KEYS, ...TIME_KEYS]);

const BOOLEAN_MESSAGES = {
  push_announcements: 'Telefon bildirimi tercihi geçersiz (açık veya kapalı olmalıdır).',
  push_show_preview: 'Bildirimde başlık gösterme tercihi geçersiz (açık veya kapalı olmalıdır).',
  push_quiet_enabled: 'Sessiz saat tercihi geçersiz (açık veya kapalı olmalıdır).',
};
const TIME_MESSAGES = {
  push_quiet_start: 'Sessiz saat başlangıcı geçersiz (SS:DD biçiminde olmalıdır).',
  push_quiet_end: 'Sessiz saat bitişi geçersiz (SS:DD biçiminde olmalıdır).',
};

/** Test / QA için değiştirilebilir. */
export const pushPreferenceHooks = {
  available: () => isPushAvailable(),
};

/**
 * Gövdeden push anahtarlarını doğrular (YAZMADAN önce). `present`: en az bir push anahtarı gönderildi.
 * @returns {{ present: boolean, values: Record<string, boolean | number> }}
 */
export function parsePushPreferenceInput(body) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const values = {};
  for (const key of BOOLEAN_KEYS) {
    if (input[key] === undefined) continue;
    if (typeof input[key] !== 'boolean') {
      throw invalidPushField(BOOLEAN_MESSAGES[key]);
    }
    values[key] = input[key];
  }
  for (const key of TIME_KEYS) {
    if (input[key] === undefined) continue;
    const minutes = parseHhmm(input[key]);
    if (minutes === null) {
      throw invalidPushField(TIME_MESSAGES[key]);
    }
    values[key] = minutes;
  }
  if (values.push_quiet_start !== undefined && values.push_quiet_start === values.push_quiet_end) {
    throw invalidPushField('Sessiz saatlerin başlangıcı ve bitişi aynı olamaz.');
  }
  return { present: Object.keys(values).length > 0, values };
}

const QUIET_SAME = () => invalidPushField('Sessiz saatlerin başlangıcı ve bitişi aynı olamaz.');

/**
 * Push tercihlerini ÇAĞIRANIN açık işleminde (kullanıcı satırı KEY SHARE kilitli olmalı: lockLiveUser) kısmi yazar. Gönderilmeyen alan değişmez;
 * satır yoksa varsayılanlarla oluşur. Kuralı ihlal eden saklı değerle birleşim (başlangıç = bitiş) 400 INVALID_BODY. announcement_inbox.setNotificationPreferences
 * (e-posta + push tek işlem) ve savePushPreferences bu işlevi paylaşır.
 */
export async function writePushPreferences(client, userCode, values) {
  const current = (
    await client.query('SELECT push_quiet_start, push_quiet_end FROM notification_preferences WHERE user_code = $1 FOR UPDATE', [userCode])
  ).rows?.[0];
  const start = values.push_quiet_start ?? Number(current?.push_quiet_start ?? DEFAULT_QUIET_START);
  const end = values.push_quiet_end ?? Number(current?.push_quiet_end ?? DEFAULT_QUIET_END);
  if (start === end) {
    throw QUIET_SAME();
  }
  try {
    await client.query(
      `
        INSERT INTO notification_preferences (user_code, push_announcements, push_show_preview, push_quiet_enabled, push_quiet_start, push_quiet_end)
        VALUES ($1, COALESCE($2::BOOLEAN, TRUE), COALESCE($3::BOOLEAN, FALSE), COALESCE($4::BOOLEAN, FALSE), $5::SMALLINT, $6::SMALLINT)
        ON CONFLICT (user_code) DO UPDATE SET
          push_announcements = COALESCE($2::BOOLEAN, notification_preferences.push_announcements),
          push_show_preview = COALESCE($3::BOOLEAN, notification_preferences.push_show_preview),
          push_quiet_enabled = COALESCE($4::BOOLEAN, notification_preferences.push_quiet_enabled),
          push_quiet_start = $5::SMALLINT,
          push_quiet_end = $6::SMALLINT,
          updated_at = NOW()
      `,
      [
        userCode,
        values.push_announcements ?? null,
        values.push_show_preview ?? null,
        values.push_quiet_enabled ?? null,
        start,
        end,
      ],
    );
  } catch (error) {
    if (error?.code === '23514') {
      throw QUIET_SAME();
    }
    throw error;
  }
}

/**
 * Push tercihlerini kısmi yazar (kendi işlemi). Gönderilmeyen alan değişmez; satır yoksa varsayılanlarla oluşur.
 */
export async function savePushPreferences(userCode, values, db = pool) {
  const client = await db.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await lockLiveUser(client, userCode);
    await writePushPreferences(client, userCode, values);
    await client.query('COMMIT');
    began = false;
  } catch (error) {
    if (error?.code === '23514') {
      throw QUIET_SAME();
    }
    throw error;
  } finally {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    client.release();
  }
}

/** Kayıt yokken / kullanıcı yokken push alanları (varsayılanlar). */
export function pushPreferenceFields(row, deviceCount) {
  return {
    push_available: pushPreferenceHooks.available(),
    push_show_preview: row ? row.push_show_preview === true : false,
    push_quiet: {
      enabled: row ? row.push_quiet_enabled === true : false,
      start: formatHhmm(row?.push_quiet_start ?? DEFAULT_QUIET_START, DEFAULT_QUIET_START),
      end: formatHhmm(row?.push_quiet_end ?? DEFAULT_QUIET_END, DEFAULT_QUIET_END),
    },
    push_devices: Number(deviceCount ?? 0),
  };
}

export const PUSH_PREFERENCES_SQL = `
  SELECT np.push_show_preview, np.push_quiet_enabled, np.push_quiet_start, np.push_quiet_end,
         (SELECT COUNT(*)::INTEGER FROM push_devices d WHERE d.user_code = $1) AS device_count
  FROM (SELECT $1::INTEGER AS user_code) me
  LEFT JOIN notification_preferences np ON np.user_code = me.user_code
`;

/**
 * Tercih yanıtına push alanlarını ekler (GET ve PUT yanıtı). push_available her zaman güncel çalışma durumudur.
 * `userCode` null ise DB sorgusu yok (varsayılanlar).
 */
export async function withPushPreferences(body, userCode, db = pool) {
  if (userCode === null || userCode === undefined) {
    return { ...body, ...pushPreferenceFields(null, 0) };
  }
  const row = (await db.query(PUSH_PREFERENCES_SQL, [userCode])).rows?.[0] ?? null;
  const stored = row && row.push_quiet_start !== null && row.push_quiet_start !== undefined ? row : null;
  return { ...body, ...pushPreferenceFields(stored, row?.device_count ?? 0) };
}
