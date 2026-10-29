// Plaka Tanıma A3 (DB katmanı): sakin giriş/çıkış bildirimi (kişi bazında tercih, varsayılan KAPALI), yönetici kopukluk uyarısı (saatte en çok 1, Drive uyarı deseni)
// ve "içeride" zaman aşımı (bakım rutini). Hepsi EN İYİ ÇABA: hata olay kaydını / zamanlayıcı turunu asla bozmaz. Eşikler plate_site_settings'ten gelir.
//
// Sakin bildirimi yalnız KAYITLI aracın "içeride" durumu gerçekten değiştiğinde (giriş / çıkış) ve olay yeterince tazeyse (kopukluk sonrası kuyruk boşalırken
// eski olaylar bildirim yağdırmasın) gönderilir. Metinde plaka YOK (kilit ekranı).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { CARGO_RECIPIENTS_SQL } from './cargo_notify.js';
import { pushDeviceHooks } from './push_devices.js';
import { sendWebPushToUsers } from './web_push.js';
import { loadSiteSettings } from './plate_gates_service.js';
import { invalidField, maskPlate } from './plate_recognition_common.js';
import { residentContext } from './plate_recognition_permits.js';
import {
  ALERT_KIND_EDGE_LOST,
  EDGE_LOST_AUDIT_ACTION,
  INSIDE_TIMEOUT_AUDIT_ACTION,
  MAX_LISTED,
  lostAlertTexts,
  lostComponents,
  movementTexts,
} from './plate_alerts_common.js';
import { DEFAULT_SITE_SETTINGS } from './plate_gates_common.js';

const logFailure = (what, error) => {
  // eslint-disable-next-line no-console
  console.error(`[plate-notify] ${what} basarisiz:`, error?.code || error?.message || 'hata');
};

/** Web (tarayıcı) + telefon (FCM) bildirimi; kanal yoksa sessizce atlanır. @returns {Promise<{ web: number, fcm: number }>} */
export async function pushToUsers(db, userCodes, { title, body, type, siteCode }) {
  const out = { web: 0, fcm: 0 };
  const codes = [...new Set(userCodes.map(Number).filter((n) => Number.isSafeInteger(n) && n > 0))];
  if (!codes.length) return out;
  try {
    out.web = await sendWebPushToUsers(codes, { title, body, url: '/' }, db);
  } catch (error) {
    logFailure('web push', error);
  }
  try {
    const client = pushDeviceHooks.available() ? pushDeviceHooks.client() : null;
    if (client) {
      const devices = (await db.query(`SELECT fcm_token FROM push_devices WHERE user_code = ANY($1::int[]) AND notifications_enabled`, [codes])).rows ?? [];
      for (const device of devices) {
        const result = await client.send({
          token: device.fcm_token,
          notification: { title, body },
          data: { type, site_code: String(Number(siteCode)) },
          android: { priority: 'NORMAL', ttl: '3600s', notification: { channel_id: 'announcements' } },
        });
        if (result?.kind === 'ok') out.fcm += 1;
      }
    }
  } catch (error) {
    logFailure('fcm', error);
  }
  return out;
}

// --- Sakin: giriş / çıkış bildirimi ----------------------------------------------------------------------------------------------

/** Aracın sahibi: bağlı kişinin hesabı; kişi (ya da hesabı) yoksa dairenin güncel sakinleri. Yalnız tercihi AÇIK olanlar döner. */
async function movementRecipients(db, siteCode, vehicle) {
  let codes = [];
  if (vehicle.person_id) {
    const person = await db.query(`SELECT user_code FROM site_people WHERE id = $1 AND site_code = $2 AND is_active AND user_code IS NOT NULL`, [vehicle.person_id, siteCode]);
    codes = person.rows.map((r) => Number(r.user_code));
  }
  if (!codes.length && vehicle.apartment_id) {
    codes = ((await db.query(CARGO_RECIPIENTS_SQL, [vehicle.apartment_id])).rows ?? []).map((r) => Number(r.user_code));
  }
  if (!codes.length) return [];
  const enabled = await db.query(
    `SELECT np.user_code FROM plate_notify_prefs np
       INNER JOIN users u ON u.user_code = np.user_code AND u.is_active = TRUE AND u.deleted_at IS NULL
      WHERE np.site_code = $1 AND np.movement_enabled AND np.user_code = ANY($2::int[])`,
    [siteCode, codes],
  );
  return enabled.rows.map((r) => Number(r.user_code));
}

/**
 * Kayıtlı aracın giriş / çıkışı (içeride durumu değişti). En iyi çaba; çağıran beklemez.
 * @param {{ siteCode: number, vehicle: { id: number, person_id?: number|null, apartment_id?: number|null }, direction: 'giris'|'cikis', seenAt: Date }} input
 */
export async function notifyResidentMovement({ siteCode, vehicle, direction, seenAt }, db = pool) {
  try {
    const settings = await loadSiteSettings(db, siteCode);
    if (Date.now() - seenAt.getTime() > settings.resident_notify_max_age_minutes * 60_000) return { skipped: 'stale' };
    const recipients = await movementRecipients(db, siteCode, vehicle);
    if (!recipients.length) return { skipped: 'no_opt_in' };
    const texts = movementTexts({ direction, seenAt });
    return { recipients: recipients.length, ...(await pushToUsers(db, recipients, { ...texts, type: 'plate_movement', siteCode })) };
  } catch (error) {
    logFailure('sakin bildirimi', error);
    return { error: true };
  }
}

/** Sakin tercihi (varsayılan KAPALI: satır yoksa kapalı). */
export async function readMovementPref(db, siteCode, userCode) {
  const row = (await db.query(`SELECT movement_enabled FROM plate_notify_prefs WHERE site_code = $1 AND user_code = $2`, [siteCode, userCode])).rows[0];
  return row?.movement_enabled === true;
}

export async function setMovementPref(authUser, body) {
  const ctx = await residentContext(authUser, body.site_code);
  if (typeof body.movement_enabled !== 'boolean') {
    throw invalidField('Bildirim tercihi doğru/yanlış olmalı.', 'movement_enabled');
  }
  await pool.query(
    `INSERT INTO plate_notify_prefs (site_code, user_code, movement_enabled, updated_at) VALUES ($1, $2, $3, NOW())
     ON CONFLICT (site_code, user_code) DO UPDATE SET movement_enabled = EXCLUDED.movement_enabled, updated_at = NOW()`,
    [ctx.siteCode, actorFromAuthUser(authUser).userCode, body.movement_enabled],
  );
  return { movement_enabled: body.movement_enabled };
}

// --- Yönetici: kopukluk uyarısı --------------------------------------------------------------------------------------------------

/** Aynı site + tür için uyarı en sık `intervalMinutes`'te bir (kalıcı sınırlayıcı: yeniden başlatma / çift süreç yağdırmaz). @returns {Promise<boolean>} bu çağrı uyarı hakkını aldı mı */
export async function claimAlert(db, siteCode, kind, intervalMinutes) {
  const result = await db.query(
    `INSERT INTO plate_alert_state (site_code, kind, last_sent_at) VALUES ($1, $2, NOW())
     ON CONFLICT (site_code, kind) DO UPDATE SET last_sent_at = NOW() WHERE plate_alert_state.last_sent_at <= NOW() - make_interval(mins => $3::INT)
     RETURNING 1 AS ok`,
    [siteCode, kind, intervalMinutes],
  );
  return result.rows.length === 1;
}

export async function managerUserCodes(db, siteCode) {
  const result = await db.query(
    `SELECT DISTINCT u.user_code FROM users u
      WHERE u.is_active = TRUE AND u.deleted_at IS NULL AND u.user_code IN (
        SELECT manager_user_code FROM site_manager_sites WHERE site_code = $1
        UNION
        SELECT user_code FROM site_memberships WHERE site_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
      )`,
    [siteCode],
  );
  return result.rows.map((r) => Number(r.user_code));
}

/**
 * Bir sitenin kenar PC / kamera durumunu değerlendirir; kırmızı eşik aşıldıysa (ve sıklık sınırı izin veriyorsa) yöneticilere uyarı düşer:
 * site denetim kaydı (uygulama içinde görünür; Drive uyarı deseni) + anlık bildirim. @returns {Promise<{ lost: boolean, alerted: boolean }>}
 */
export async function checkEdgeHealth(db, siteCode, nowMs = Date.now()) {
  const settings = await loadSiteSettings(db, siteCode);
  const [edge, cameras] = await Promise.all([
    db.query(`SELECT name, last_seen_at FROM plate_edge_clients WHERE site_code = $1 AND is_active AND revoked_at IS NULL ORDER BY id`, [siteCode]),
    db.query(
      `SELECT c.name, s.reported_at, s.last_frame_at FROM plate_gate_cameras gc
         INNER JOIN camera_devices c ON c.id = gc.camera_id AND c.is_active
         LEFT JOIN plate_camera_status s ON s.camera_id = gc.camera_id
        WHERE gc.site_code = $1 ORDER BY gc.id`,
      [siteCode],
    ),
  ]);
  const lost = lostComponents({ edgeClients: edge.rows, cameras: cameras.rows, critSeconds: settings.heartbeat_crit_seconds, nowMs });
  if (!lost.any) return { lost: false, alerted: false };
  if (!(await claimAlert(db, siteCode, ALERT_KIND_EDGE_LOST, settings.alert_interval_minutes))) return { lost: true, alerted: false };
  await recordAudit(db, {
    actor: null,
    action: EDGE_LOST_AUDIT_ACTION,
    siteCode,
    targetType: 'plate_edge',
    details: { edge: lost.edge.slice(0, MAX_LISTED).map((x) => x.name), edge_total: lost.edge.length, cameras: lost.cameras.slice(0, MAX_LISTED).map((x) => x.name), camera_total: lost.cameras.length },
  });
  const texts = lostAlertTexts(lost);
  try {
    await pushToUsers(db, await managerUserCodes(db, siteCode), { ...texts, type: 'plate_edge_lost', siteCode });
  } catch (error) {
    logFailure('yonetici bildirimi', error);
  }
  return { lost: true, alerted: true };
}

// --- "İçeride" zaman aşımı (bakım rutini) ----------------------------------------------------------------------------------------

/**
 * `inside_timeout_hours` (site ayarı; satır yoksa varsayılan) saatten uzun "içeride" kalan araçları otomatik düşürür ve sitenin denetim kaydına iz bırakır.
 * Kenarın bir sonraki senkronunda `updated_at` ile düşüş gider. since_at'e dokunulmaz (sonradan gelen gerçek olaylar sıralamayı bozmaz).
 * @returns {Promise<number>} düşürülen araç sayısı
 */
export async function expireStalePresence(db = pool) {
  const result = await db.query(
    `UPDATE plate_presence p SET inside = FALSE, updated_at = NOW()
      FROM (
        SELECT q.id, COALESCE(s.inside_timeout_hours, $1::INT) AS hours
          FROM plate_presence q LEFT JOIN plate_site_settings s ON s.site_code = q.site_code
         WHERE q.inside AND q.since_at < NOW() - make_interval(hours => COALESCE(s.inside_timeout_hours, $1::INT))
      ) x
     WHERE p.id = x.id AND p.inside
     RETURNING p.site_code, p.plate, x.hours`,
    [DEFAULT_SITE_SETTINGS.inside_timeout_hours],
  );
  const bySite = new Map();
  for (const row of result.rows) {
    const key = Number(row.site_code);
    const entry = bySite.get(key) ?? { hours: row.hours, plates: [] };
    entry.plates.push(maskPlate(row.plate));
    bySite.set(key, entry);
  }
  for (const [siteCode, entry] of bySite) {
    await recordAudit(db, {
      actor: null,
      action: INSIDE_TIMEOUT_AUDIT_ACTION,
      siteCode,
      targetType: 'plate_presence',
      details: { count: entry.plates.length, timeout_hours: entry.hours, plates: entry.plates.slice(0, 20) },
    });
  }
  return result.rows.length;
}
