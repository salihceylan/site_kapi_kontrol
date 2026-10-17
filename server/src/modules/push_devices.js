// Telefon bildirimi (Faz 3b-B): cihaz kaydı / silme / listeleme, test bildirimi, hesap silme ve veri dışa aktarma kancaları.
//
// Sözleşme: docs/PLATFORM_BELGELER.md B3.
//  - Kayıt (PUT /app/push/devices): aynı fcm_token BAŞKA kullanıcı / kurulumdaysa o satır SİLİNİR (cihaz devri), sonra (user_code, install_id)
//    üzerinde UPSERT (jeton yenilenir, last_seen_at = NOW(), failure_count = 0); 23505 yarışında TEK yeniden deneme; kullanıcı başına en çok 10 cihaz
//    (en eski last_seen_at düşer). Push kapalı olsa da kaydedilir. Kullanıcı satırı işlemde `deleted_at IS NULL AND is_active ... FOR KEY SHARE` ile
//    kilitlenir: hesap silme (kimliksizleştirme) UPDATE'i bu işlemi bekler; silme commit ettiyse satır dönmez ve tombstone hesaba jeton YAZILMAZ.
//    Kilit sırası: users (KEY SHARE) -> kullanıcı cihaz kilidi (pg_advisory_xact_lock(PUSH_DEVICE_LOCK_CLASS, user_code): aynı kullanıcının eşzamanlı
//    kayıtları sıraya girer, 10 cihaz sınırı aşılamaz) -> push_devices; hesap silme ile aynı yön (users -> push_devices -> push_outbox).
//  - Kilit sırası (40P01): işçinin çok satırlı otomatik onaylı sonuç yazımları (applyDeviceOutcomes, push_worker finalizeBatch), 10 cihaz kırpması ve
//    hesap silme (deletePushDataForUser) satırları id sırasıyla kilitler (… ORDER BY id FOR UPDATE); işçi tarafında 40P01'de ifade bir kez yeniden
//    denenir. SIRASIZ olanlar: kayıt yolundaki devir silmesi (tek jeton = tek satır) ve UPSERT (kayıt işlemi 40P01 / 23505'te bir kez baştan denenir),
//    bakım silmeleri ve süresi geçenlerin expire UPDATE'i (push_worker / push_outbox; otomatik onaylı, 40P01'de bir kez yeniden denenir).
//  - Süreç düzeyi ölü jeton koruması (deadTokenGuard): hizmet hesabı yüklendikten sonra en az bir BAŞARILI gönderim görülmeden "ölü" sonuç (UNREGISTERED,
//    geçersiz jeton, SENDER_ID_MISMATCH) cihaz SİLDİRMEZ (yanlış projenin hizmet hesabı her jetonu ölü gösterir); işçi satırı deneme iadesiyle pending
//    bırakır, test bildirimi silmez. Son başarıdan beri ölü sayısı >= 20 ve başarı yoksa işçi MASS_DEAD + devre kesici açar.
//  - Silme / liste yalnız ÇAĞIRANIN satırlarıdır (başkasının install_id'si 0 satır = idempotent { ok: true }); jeton hiçbir yanıtta yok.
//  - GİZLİLİK: kayıt jetonu günlüğe, hataya, audit'e yazılmaz (yalnız device_id).

import { pool } from '../db.js';
import {
  MAX_DEVICES_PER_USER,
  PUSH_DEVICE_LOCK_CLASS,
  invalidPushField,
  parseDeviceInput,
  parseInstallId,
  pushAccountDeleted,
  pushUnavailable,
  retryOnDeadlock,
  sanitizeErrorCode,
  PUSH_SEND_CONCURRENCY,
} from './push_common.js';
import { isPushAvailable, pushRuntime } from './push_credentials.js';
import { fcmClientFor } from './push_fcm.js';
import { buildTestMessage } from './push_message.js';
import { parsePositiveId, toIso } from './people_common.js';

const INT32_MAX = 2147483647;

export function pushUserCodeOf(authUser) {
  return parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
}

/** Test / QA için değiştirilebilir: FCM istemcisi, hizmet hesabı (ölü jeton izinin anahtarı) ve saat. */
export const pushDeviceHooks = {
  client: () => fcmClientFor(pushRuntime().account),
  account: () => pushRuntime().account,
  available: () => isPushAvailable(),
  now: () => Date.now(),
};

// --- Süreç düzeyi ölü jeton izi (yanlış proje / yanlış uç koruması) ----------------------------------------

const deadGuard = { account: undefined, successSeen: false, deadSinceSuccess: 0 };

function guardFor(account) {
  if (deadGuard.account !== account) {
    // hizmet hesabı (yeniden) yüklendi: iz sıfırlanır
    deadGuard.account = account;
    deadGuard.successSeen = false;
    deadGuard.deadSinceSuccess = 0;
  }
  return deadGuard;
}

/** Bir gönderim grubunun sonucunu ize işler; güncel izi döner ({ successSeen, deadSinceSuccess }). */
export function recordDeliveryOutcome({ ok = 0, dead = 0 }, account = pushDeviceHooks.account()) {
  const guard = guardFor(account ?? null);
  if (ok > 0) {
    guard.successSeen = true;
    guard.deadSinceSuccess = 0;
  } else {
    guard.deadSinceSuccess += dead;
  }
  return { successSeen: guard.successSeen, deadSinceSuccess: guard.deadSinceSuccess };
}

/** Bu hizmet hesabıyla en az bir başarılı gönderim görüldü mü (ölü jeton silmesi yalnız o zaman serbest). */
export function deadDeletionAllowed(account = pushDeviceHooks.account()) {
  return guardFor(account ?? null).successSeen === true;
}

/** Test / QA: izi sıfırlar. */
export function resetDeadTokenGuard() {
  deadGuard.account = undefined;
  deadGuard.successSeen = false;
  deadGuard.deadSinceSuccess = 0;
}

async function inTransaction(db, work) {
  const client = await db.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const result = await work(client);
    await client.query('COMMIT');
    began = false;
    return result;
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

/** Kullanıcı satırını işlem sonuna dek KEY SHARE ile kilitler; silinmiş / pasif hesapta 401 ACCOUNT_DELETED. */
export async function lockLiveUser(client, userCode) {
  const user = await client.query(
    'SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL AND is_active = TRUE FOR KEY SHARE',
    [userCode],
  );
  if (!user.rows?.[0]) {
    throw pushAccountDeleted();
  }
}

async function registerOnce(db, userCode, input) {
  return inTransaction(db, async (client) => {
    await lockLiveUser(client, userCode);
    // Kullanıcı başına kayıt kilidi (iki-int sınıf "PUSH"; push_common.js): 9 cihaz + 2 eşzamanlı yeni kurulum 11 satır bırakmasın.
    await client.query('SELECT pg_advisory_xact_lock($1::int, $2::int)', [PUSH_DEVICE_LOCK_CLASS, userCode]);
    // Cihaz devri: aynı jeton başka kullanıcı / kurulumdaysa o satır silinir (A çıkış yapamadan B girerse A'ya B'nin bildirimi gitmez).
    await client.query('DELETE FROM push_devices WHERE fcm_token = $1 AND NOT (user_code = $2 AND install_id = $3)', [
      input.token,
      userCode,
      input.installId,
    ]);
    const saved = await client.query(
      `
        INSERT INTO push_devices (user_code, install_id, platform, fcm_token, app_version, notifications_enabled)
        VALUES ($1, $2, $3, $4, $5::TEXT, COALESCE($6::BOOLEAN, TRUE))
        ON CONFLICT (user_code, install_id) DO UPDATE SET
          platform = EXCLUDED.platform,
          fcm_token = EXCLUDED.fcm_token,
          app_version = COALESCE($5::TEXT, push_devices.app_version),
          notifications_enabled = COALESCE($6::BOOLEAN, push_devices.notifications_enabled),
          last_seen_at = NOW(),
          failure_count = 0,
          last_error_code = NULL
        RETURNING id
      `,
      [userCode, input.installId, input.platform, input.token, input.appVersion, input.notificationsEnabled],
    );
    // Kullanıcı başına en çok 10 cihaz: en eski last_seen_at düşer (yeni kaydedilen asla). Silinecekler id sırasıyla kilitlenir.
    await client.query(
      `
        DELETE FROM push_devices
        WHERE id IN (
          SELECT id FROM push_devices
          WHERE id = ANY(ARRAY(SELECT id FROM push_devices WHERE user_code = $1 ORDER BY last_seen_at DESC, id DESC OFFSET $2))
          ORDER BY id
          FOR UPDATE
        )
      `,
      [userCode, MAX_DEVICES_PER_USER],
    );
    return Number(saved.rows[0].id);
  });
}

/**
 * PUT /app/push/devices -> { ok: true, device_id, push_available }.
 * 23505 (eşzamanlı aynı jeton başka kullanıcıda): TEK yeniden deneme (ikinci denemede devir silmesi diğer satırı görür).
 * 54000 (çok uzun jeton dizin sınırını aştı): 400 INVALID_BODY.
 */
export async function registerPushDevice(authUser, body, db = pool) {
  const userCode = pushUserCodeOf(authUser);
  if (userCode === null) {
    throw pushAccountDeleted();
  }
  const input = parseDeviceInput(body);
  let deviceId;
  for (let attempt = 1; ; attempt += 1) {
    try {
      deviceId = await registerOnce(db, userCode, input);
      break;
    } catch (error) {
      if ((error?.code === '23505' || error?.code === '40P01') && attempt === 1) {
        continue;
      }
      if (error?.code === '54000' || error?.code === '23514') {
        throw invalidPushField('Bildirim jetonu geçersiz.');
      }
      throw error;
    }
  }
  return { ok: true, device_id: deviceId, push_available: pushDeviceHooks.available() };
}

/** DELETE /app/push/devices/:installId -> { ok: true } (idempotent; yalnız çağıranın satırı). */
export async function deletePushDevice(authUser, rawInstallId, db = pool) {
  const userCode = pushUserCodeOf(authUser);
  if (userCode === null) {
    throw pushAccountDeleted();
  }
  const installId = parseInstallId(rawInstallId);
  if (installId === null) {
    throw invalidPushField('Kurulum kimliği geçersiz.');
  }
  await db.query('DELETE FROM push_devices WHERE user_code = $1 AND install_id = $2', [userCode, installId]);
  return { ok: true };
}

/** GET /app/push/devices -> { items: [{ install_id, platform, app_version, last_seen_at }] } (jeton ASLA dönmez). */
export async function listPushDevices(authUser, db = pool) {
  const userCode = pushUserCodeOf(authUser);
  if (userCode === null) {
    return { items: [] };
  }
  const result = await db.query(
    `
      SELECT install_id, platform, app_version, last_seen_at
      FROM push_devices
      WHERE user_code = $1
      ORDER BY last_seen_at DESC, id DESC
    `,
    [userCode],
  );
  return {
    items: (result.rows ?? []).map((row) => ({
      install_id: row.install_id,
      platform: row.platform,
      app_version: row.app_version ?? null,
      last_seen_at: toIso(row.last_seen_at),
    })),
  };
}

export { retryOnDeadlock };

/** id sırasıyla kilitleyen alt sorgu: çok satırlı yazımlar hesap silme ile AYNI sırada kilitler. */
const LOCK_DEVICES_BY_ID = 'SELECT id FROM push_devices WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR UPDATE';

/**
 * Cihaz sonuçlarını yazar (otomatik onaylı kısa ifadeler; satırlar id sırasıyla kilitlenir; 40P01'de bir kez yeniden). Ölü jeton yalnız HÂLÂ aynı
 * jetonsa silinir. `failures` failure_count'u artırır (cihaza özgü geçici hata); `notes` yalnız last_error_code yazar, failure_count'u ARTIRMAZ:
 * yapılandırma hataları (APNs anahtarı yok), çıplak 404 / mesaj hatası (invalid) ve doğrulanmamış ölü sonuç cihazın suçu değildir; aksi halde 30 günden
 * uzun süren bir yapılandırma hatasında bakımın "kalıcı hatalı" kuralı sağlam cihazları silerdi.
 */
export async function applyDeviceOutcomes({ successIds = [], failures = [], notes = [], dead = [] }, db = pool) {
  if (successIds.length > 0) {
    await retryOnDeadlock(() =>
      db.query(
        `UPDATE push_devices SET last_success_at = NOW(), failure_count = 0, last_error_code = NULL WHERE id IN (${LOCK_DEVICES_BY_ID})`,
        [successIds],
      ),
    );
  }
  if (failures.length > 0) {
    await retryOnDeadlock(() =>
      db.query(
        `
          UPDATE push_devices d
          SET failure_count = LEAST(d.failure_count + 1, 32000), last_error_code = v.code
          FROM unnest($1::BIGINT[], $2::TEXT[]) AS v(id, code)
          WHERE d.id = v.id AND d.id IN (${LOCK_DEVICES_BY_ID})
        `,
        [failures.map((entry) => entry.id), failures.map((entry) => sanitizeErrorCode(entry.code))],
      ),
    );
  }
  if (notes.length > 0) {
    await retryOnDeadlock(() =>
      db.query(
        `
          UPDATE push_devices d
          SET last_error_code = v.code
          FROM unnest($1::BIGINT[], $2::TEXT[]) AS v(id, code)
          WHERE d.id = v.id AND d.id IN (${LOCK_DEVICES_BY_ID})
        `,
        [notes.map((entry) => entry.id), notes.map((entry) => sanitizeErrorCode(entry.code))],
      ),
    );
  }
  if (dead.length > 0) {
    // Gönderim sırasında aynı kurulum yeni jetonla kaydolduysa (id aynı, jeton farklı) satır KORUNUR.
    await retryOnDeadlock(() =>
      db.query(
        `
          DELETE FROM push_devices d
          USING unnest($1::BIGINT[], $2::TEXT[]) AS v(id, token)
          WHERE d.id = v.id AND d.fcm_token = v.token AND d.id IN (${LOCK_DEVICES_BY_ID})
        `,
        [dead.map((entry) => entry.id), dead.map((entry) => entry.token)],
      ),
    );
  }
}

/** Sınırlı eşzamanlılıkla işler (sıra korunur). */
export async function mapLimited(items, concurrency, work) {
  const results = new Array(items.length);
  let cursor = 0;
  const worker = async () => {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await work(items[index], index);
    }
  };
  await Promise.all(Array.from({ length: Math.min(Math.max(concurrency, 1), items.length) }, worker));
  return results;
}

/**
 * POST /app/push/test -> { ok, sent, failed }: çağıranın (izinli) cihazlarına GENEL "Test bildirimi" (outbox dışı, doğrudan). `ok` = en az bir cihaza
 * iletildi. Push hazır değilse 503 PUSH_UNAVAILABLE. Ölü jetonlu cihaz satırı YALNIZ bu hizmet hesabıyla daha önce (ya da bu çağrıda) başarılı bir
 * gönderim görüldüyse silinir (canlıya almadaki ilk test yanlış projenin hesabıyla yapılırsa cihazlar silinmez).
 */
export async function sendTestPush(authUser, db = pool) {
  const userCode = pushUserCodeOf(authUser);
  if (userCode === null) {
    throw pushAccountDeleted();
  }
  const client = pushDeviceHooks.available() ? pushDeviceHooks.client() : null;
  if (!client) {
    throw pushUnavailable();
  }
  const devices = (
    await db.query(
      'SELECT id, fcm_token FROM push_devices WHERE user_code = $1 AND notifications_enabled ORDER BY last_seen_at DESC, id DESC',
      [userCode],
    )
  ).rows ?? [];
  const nowMs = pushDeviceHooks.now();
  const results = await mapLimited(devices, PUSH_SEND_CONCURRENCY, (device) =>
    client.send(buildTestMessage({ token: device.fcm_token, nowMs })),
  );
  const okCount = results.filter((result) => result.kind === 'ok').length;
  const deadCount = results.filter((result) => result.kind === 'dead').length;
  const guard = recordDeliveryOutcome({ ok: okCount, dead: deadCount }, pushDeviceHooks.account());
  const outcome = { successIds: [], failures: [], notes: [], dead: [] };
  results.forEach((result, index) => {
    const device = devices[index];
    if (result.kind === 'ok') {
      outcome.successIds.push(Number(device.id));
    } else if (result.kind === 'dead' && guard.successSeen) {
      outcome.dead.push({ id: Number(device.id), token: device.fcm_token });
    } else if (result.kind === 'transient') {
      outcome.failures.push({ id: Number(device.id), code: result.code });
    } else {
      // doğrulanmamış ölü, APNs yapılandırması, kimlik, mesaj / çıplak 404: cihazın suçu değil (failure_count artmaz)
      outcome.notes.push({ id: Number(device.id), code: result.code });
    }
  });
  await applyDeviceOutcomes(outcome, db);
  const sent = outcome.successIds.length;
  const failed = devices.length - sent;
  if (failed > 0) {
    const codes = [...new Set(results.filter((result) => result.kind !== 'ok').map((result) => sanitizeErrorCode(result.code)))];
    // eslint-disable-next-line no-console
    console.error(`[push] test bildirimi hatasi: kodlar=${codes.join(',')}`);
  }
  return { ok: sent > 0, sent, failed };
}

// --- Hesap silme ve kişisel veri dışa aktarma kancaları -------------------------------------------------

/**
 * Hesap silme işleminin İÇİNDE (aynı client) çağrılır: kullanıcının cihaz jetonlarını ve bildirim kuyruğu satırlarını siler (kullanıcı satırı silinmeyip
 * kimliksizleştirildiği için CASCADE ÇALIŞMAZ; outbox'ta FK yok). Tablo yoksa (041 öncesi şema) atlanır. Kilit sırası: users -> push_devices -> push_outbox.
 * @returns {Promise<{ devices: number, outbox: number }>}
 */
export async function deletePushDataForUser(client, userCode) {
  const tables = (
    await client.query(
      `SELECT to_regclass('public.push_devices') IS NOT NULL AS has_devices, to_regclass('public.push_outbox') IS NOT NULL AS has_outbox`,
    )
  ).rows?.[0];
  const summary = { devices: 0, outbox: 0 };
  // Satırlar id sırasıyla kilitlenir (işçinin çok satırlı otomatik onaylı yazımlarıyla aynı sıra -> 40P01 yok); (user_code) indeksleri tablo taramasını önler.
  if (tables?.has_devices === true) {
    summary.devices = Number(
      (await client.query('DELETE FROM push_devices WHERE id IN (SELECT id FROM push_devices WHERE user_code = $1 ORDER BY id FOR UPDATE)', [userCode])).rowCount ?? 0,
    );
  }
  if (tables?.has_outbox === true) {
    summary.outbox = Number(
      (await client.query('DELETE FROM push_outbox WHERE id IN (SELECT id FROM push_outbox WHERE user_code = $1 ORDER BY id FOR UPDATE)', [userCode])).rowCount ?? 0,
    );
  }
  return summary;
}

/**
 * Veri dışa aktarma (aynı salt okunur işlem): kayıtlı cihazlar (platform, app_version, tarihler). Jeton ve kurulum kimliği HARİÇ (excluded notu).
 * Tablo yoksa boş liste.
 */
export async function exportPushDevices(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.push_devices') AS t`)).rows?.[0]?.t;
  if (!present) {
    return [];
  }
  const rows =
    (
      await client.query(
        `
          SELECT platform, app_version, notifications_enabled, created_at, last_seen_at, last_success_at
          FROM push_devices WHERE user_code = $1 ORDER BY created_at, id
        `,
        [userCode],
      )
    ).rows ?? [];
  return rows.map((row) => ({
    platform: row.platform,
    app_version: row.app_version ?? null,
    notifications_enabled: row.notifications_enabled === true,
    created_at: toIso(row.created_at),
    last_seen_at: toIso(row.last_seen_at),
    last_success_at: toIso(row.last_success_at),
  }));
}

export const PUSH_EXPORT_EXCLUDED_NOTE =
  'Telefon bildirimi cihaz kayıtlarının bildirim jetonu (FCM) ve kurulum kimliği: güvenlik nedeniyle dışarıda bırakılmıştır (yalnız platform, uygulama sürümü ve tarihler yer alır).';
