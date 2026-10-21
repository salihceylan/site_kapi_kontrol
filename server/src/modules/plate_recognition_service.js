// Plaka Tanıma: karar kaydı (kamera olayından), olay listesi, kara liste ve kapı/kamera ayarları.
//
// Olay alma ucu 6B'nindir (device_integrations_*: belirteçli POST /camera-events/plate); orası olayı plate_events'e yazar ve BU modülün
// `handlePlateEvent` işlevini (modül açıksa) çağırır. Karar plate_decisions'a yazılır. Kapı AÇILMAZ: kapı komutları / MQTT / firmware bu dosyada YOKTUR;
// auto_open açık kapıda ALLOWED + güven eşiği sağlanırsa karar `would_open` olarak kaydedilir (bkz. planAutoOpen).

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { recordAudit, actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import {
  BLACKLIST_LIMIT,
  DEFAULT_COOLDOWN_SECONDS,
  DEFAULT_MIN_CONFIDENCE,
  MAX_OPENS_PER_MINUTE,
  PLATE_RECOGNITION_MODULE,
  REASON_LABELS,
  decidePlate,
  formatPlate,
  iso,
  maskPlate,
  normalizeTrPlate,
  notFound,
  parseBlacklistInput,
  parseConfidence,
  parseGateSettings,
  parseListQuery,
  planAutoOpen,
} from './plate_recognition_common.js';

const SYSTEM_ACTOR = Object.freeze({ name: 'Plaka tanıma (sistem)', role: 'system' });

async function audit(db, actor, action, siteCode, targetType, targetId, details) {
  await recordAudit(db, { actor, action, siteCode, targetType, targetId: String(targetId), details }, { inTransaction: db !== pool });
}

// --- Kamera olayından karar ------------------------------------------------------------------------------------------

const VEHICLE_SQL = `
  SELECT v.id FROM vehicles v
  LEFT JOIN site_people sp ON sp.id = v.person_id
  LEFT JOIN apartments a ON a.id = v.apartment_id
  WHERE v.site_code = $1 AND v.plate = $2 AND v.is_active
    AND (v.person_id IS NULL OR sp.is_active)
    AND (v.apartment_id IS NULL OR a.is_active)
  LIMIT 1`;

const PERMIT_SQL = `
  SELECT p.id FROM plate_guest_permits p
  INNER JOIN apartments a ON a.id = p.apartment_id AND a.is_active
  WHERE p.site_code = $1 AND p.plate = $2 AND p.revoked_at IS NULL AND p.valid_from <= NOW() AND p.valid_until > NOW()
  ORDER BY p.valid_until DESC LIMIT 1`;

/**
 * 6B olay ucundan (plate_events yazıldıktan sonra) çağrılır. Modül kapalıysa hiçbir şey yazmaz. Hata ASLA olayı kaybettirmez
 * (çağıran try/catch ile sarar). Dönüş: kaydedilen karar ya da null.
 * @param {{ siteCode: number, deviceId: number, eventId: number, plate: string, body: object }} input
 */
export async function handlePlateEvent({ siteCode, deviceId, eventId, plate, body }) {
  if (!(await isModuleEnabled(siteCode, PLATE_RECOGNITION_MODULE))) return null;
  const tr = normalizeTrPlate(plate);
  const confidence = parseConfidence(body?.confidence);
  const settingsRow = (
    await pool.query(
      `SELECT door_id, auto_open, min_confidence, cooldown_seconds FROM plate_gate_settings WHERE site_code = $1 AND device_id = $2 LIMIT 1`,
      [siteCode, deviceId],
    )
  ).rows[0];
  const settings = settingsRow
    ? {
        door_id: Number(settingsRow.door_id),
        auto_open: settingsRow.auto_open === true,
        min_confidence: Number(settingsRow.min_confidence),
        cooldown_seconds: Number(settingsRow.cooldown_seconds),
      }
    : null;
  const minConfidence = settings?.min_confidence ?? DEFAULT_MIN_CONFIDENCE;

  let blacklisted = false;
  let vehicle = null;
  let permit = null;
  if (tr) {
    blacklisted = Boolean((await pool.query(`SELECT 1 FROM plate_blacklist WHERE site_code = $1 AND plate = $2 AND removed_at IS NULL LIMIT 1`, [siteCode, tr])).rows[0]);
    vehicle = (await pool.query(VEHICLE_SQL, [siteCode, tr])).rows[0] ?? null;
    permit = (await pool.query(PERMIT_SQL, [siteCode, tr])).rows[0] ?? null;
  }
  const { decision, reason } = decidePlate({ plate: tr, confidence, minConfidence, blacklisted, vehicle, permit });

  const candidate = Boolean(settings?.auto_open) && decision === 'ALLOWED';
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    let autoAction = 'none';
    if (candidate) {
      // Aynı kapıda eşzamanlı kareler (aynı plakanın art arda okunması) cooldown / dakika sınırını atlatmasın.
      await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_gate:${settings.door_id}`]);
      const recent = await client.query(
        `SELECT COUNT(*) FILTER (WHERE plate = $2 AND decided_at > NOW() - make_interval(secs => $3))::INT AS same_plate,
                COUNT(*) FILTER (WHERE decided_at > NOW() - INTERVAL '60 seconds')::INT AS door_minute
           FROM plate_decisions
          WHERE door_id = $1 AND auto_action = 'would_open' AND decided_at > NOW() - INTERVAL '10 minutes'`,
        [settings.door_id, tr, settings.cooldown_seconds || DEFAULT_COOLDOWN_SECONDS],
      );
      autoAction = planAutoOpen({
        decision,
        confidence,
        settings,
        samePlateRecent: recent.rows[0]?.same_plate ?? 0,
        doorOpensLastMinute: recent.rows[0]?.door_minute ?? 0,
      });
    }
    const inserted = await client.query(
      `INSERT INTO plate_decisions (site_code, event_id, device_id, door_id, plate, confidence, decision, reason, vehicle_id, permit_id, auto_action)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (event_id) DO NOTHING
       RETURNING id`,
      [siteCode, eventId, deviceId, settings?.door_id ?? null, tr ?? String(plate), confidence, decision, reason, vehicle?.id ?? null, permit?.id ?? null, autoAction],
    );
    if (inserted.rows[0] && autoAction === 'would_open') {
      await audit(client, SYSTEM_ACTOR, 'plate.auto_open', siteCode, 'door', settings.door_id, {
        note: 'plaka ile otomatik acma',
        executed: false,
        decision_id: Number(inserted.rows[0].id),
        plate: maskPlate(tr),
        confidence,
      });
    }
    await client.query('COMMIT');
    return { decision, reason, auto_action: autoAction };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

// --- Olay listesi ----------------------------------------------------------------------------------------------------

export async function listDecisions(siteCode, query = {}) {
  const { limit, beforeId, decision } = parseListQuery(query);
  const result = await pool.query(
    `SELECT d.id, d.plate, d.decision, d.reason, d.confidence, d.auto_action, d.decided_at, e.seen_at, c.name AS device_name, g.door_name
       FROM plate_decisions d
       LEFT JOIN plate_events e ON e.id = d.event_id
       LEFT JOIN camera_devices c ON c.id = d.device_id
       LEFT JOIN site_doors g ON g.id = d.door_id
      WHERE d.site_code = $1 AND ($2::BIGINT IS NULL OR d.id < $2) AND ($4::TEXT IS NULL OR d.decision = $4)
      ORDER BY d.id DESC LIMIT $3`,
    [siteCode, beforeId, limit + 1, decision],
  );
  const rows = result.rows.slice(0, limit);
  return {
    events: rows.map((row) => ({
      id: Number(row.id),
      plate: formatPlate(row.plate),
      decision: row.decision,
      reason: row.reason,
      reason_label: REASON_LABELS[row.reason] ?? row.reason,
      confidence: row.confidence === null ? null : Number(row.confidence),
      auto_action: row.auto_action,
      seen_at: iso(row.seen_at ?? row.decided_at),
      device_name: row.device_name ?? null,
      door_name: row.door_name ?? null,
    })),
    next_before_id: result.rows.length > limit ? Number(rows[rows.length - 1].id) : null,
  };
}

// --- Kara liste ------------------------------------------------------------------------------------------------------

function mapBlacklist(row) {
  return {
    id: Number(row.id),
    plate: formatPlate(row.plate),
    reason: row.reason ?? null,
    created_at: iso(row.created_at),
    created_by_name: row.created_by_name ?? null,
  };
}

export async function listBlacklist(siteCode) {
  const result = await pool.query(
    `SELECT b.id, b.plate, b.reason, b.created_at, u.full_name AS created_by_name
       FROM plate_blacklist b LEFT JOIN users u ON u.user_code = b.created_by
      WHERE b.site_code = $1 AND b.removed_at IS NULL ORDER BY b.id DESC LIMIT 500`,
    [siteCode],
  );
  return { items: result.rows.map(mapBlacklist) };
}

export async function addBlacklist({ siteCode, body, authUser }) {
  const input = parseBlacklistInput(body);
  const actor = actorFromAuthUser(authUser);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_blacklist:${siteCode}`]);
    const count = await client.query(`SELECT COUNT(*)::INT AS n FROM plate_blacklist WHERE site_code = $1 AND removed_at IS NULL`, [siteCode]);
    if ((count.rows[0]?.n ?? 0) >= BLACKLIST_LIMIT) {
      throw new PlatformError(409, 'BLACKLIST_FULL', `Kara listede en çok ${BLACKLIST_LIMIT} plaka olabilir.`);
    }
    const dup = await client.query(`SELECT 1 FROM plate_blacklist WHERE site_code = $1 AND plate = $2 AND removed_at IS NULL LIMIT 1`, [siteCode, input.plate]);
    if (dup.rows[0]) throw new PlatformError(409, 'BLACKLIST_EXISTS', 'Bu plaka zaten kara listede.');
    const row = await client.query(
      `INSERT INTO plate_blacklist (site_code, plate, reason, created_by) VALUES ($1, $2, $3, $4)
       RETURNING id, plate, reason, created_at`,
      [siteCode, input.plate, input.reason, actor.userCode],
    );
    await audit(client, authUser, 'plate.blacklist_added', siteCode, 'plate_blacklist', row.rows[0].id, { plate: maskPlate(input.plate) });
    await client.query('COMMIT');
    return { item: mapBlacklist({ ...row.rows[0], created_by_name: actor.name }) };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

export async function removeBlacklist({ siteCode, rawId, authUser }) {
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound('Kayıt', 'BLACKLIST_NOT_FOUND');
  const actor = actorFromAuthUser(authUser);
  const result = await pool.query(
    `UPDATE plate_blacklist SET removed_at = NOW(), removed_by = $3 WHERE id = $1 AND site_code = $2 AND removed_at IS NULL RETURNING id, plate`,
    [id, siteCode, actor.userCode],
  );
  if (!result.rows[0]) throw notFound('Kayıt', 'BLACKLIST_NOT_FOUND');
  await audit(pool, authUser, 'plate.blacklist_removed', siteCode, 'plate_blacklist', id, { plate: maskPlate(result.rows[0].plate) });
  return { ok: true };
}

// --- Kapı / kamera ayarları ------------------------------------------------------------------------------------------

export async function getSettings(siteCode) {
  const [doors, cameras] = await Promise.all([
    pool.query(
      `SELECT d.id AS door_id, d.door_name, d.is_active, s.device_id, s.auto_open, s.min_confidence, s.cooldown_seconds, c.name AS camera_name
         FROM site_doors d
         LEFT JOIN plate_gate_settings s ON s.site_code = d.site_code AND s.door_id = d.id
         LEFT JOIN camera_devices c ON c.id = s.device_id
        WHERE d.site_code = $1 ORDER BY d.door_index NULLS LAST, d.id LIMIT 100`,
      [siteCode],
    ),
    pool.query(`SELECT id, name, is_active FROM camera_devices WHERE site_code = $1 ORDER BY id LIMIT 100`, [siteCode]),
  ]);
  return {
    doors: doors.rows.map((row) => ({
      door_id: Number(row.door_id),
      door_name: row.door_name,
      is_active: row.is_active !== false,
      device_id: row.device_id === null || row.device_id === undefined ? null : Number(row.device_id),
      camera_name: row.camera_name ?? null,
      auto_open: row.auto_open === true,
      min_confidence: row.min_confidence === null || row.min_confidence === undefined ? DEFAULT_MIN_CONFIDENCE : Number(row.min_confidence),
      cooldown_seconds: row.cooldown_seconds ?? DEFAULT_COOLDOWN_SECONDS,
    })),
    cameras: cameras.rows.map((row) => ({ id: Number(row.id), name: row.name, is_active: row.is_active !== false })),
    // Kapı açma bu sürümde YOK: auto_open açık kapıda ALLOWED okumalar yalnız `would_open` olarak kaydedilir.
    auto_open_supported: false,
    defaults: { min_confidence: DEFAULT_MIN_CONFIDENCE, cooldown_seconds: DEFAULT_COOLDOWN_SECONDS, max_opens_per_minute: MAX_OPENS_PER_MINUTE },
  };
}

export async function saveGateSettings({ siteCode, rawDoorId, body, authUser }) {
  const doorId = Number(rawDoorId);
  if (!Number.isSafeInteger(doorId) || doorId <= 0) throw notFound('Kapı', 'DOOR_NOT_FOUND');
  const input = parseGateSettings(body);
  const actor = actorFromAuthUser(authUser);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const door = await client.query(`SELECT id FROM site_doors WHERE id = $1 AND site_code = $2 LIMIT 1`, [doorId, siteCode]);
    if (!door.rows[0]) throw notFound('Kapı', 'DOOR_NOT_FOUND');
    if (input.deviceId !== null) {
      const camera = await client.query(`SELECT id FROM camera_devices WHERE id = $1 AND site_code = $2 AND is_active LIMIT 1`, [input.deviceId, siteCode]);
      if (!camera.rows[0]) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
      const taken = await client.query(`SELECT door_id FROM plate_gate_settings WHERE site_code = $1 AND device_id = $2 AND door_id <> $3 LIMIT 1`, [siteCode, input.deviceId, doorId]);
      if (taken.rows[0]) throw new PlatformError(409, 'CAMERA_ALREADY_MAPPED', 'Bu kamera başka bir kapıya eşlenmiş.');
    }
    const before = await client.query(`SELECT auto_open, device_id FROM plate_gate_settings WHERE site_code = $1 AND door_id = $2 LIMIT 1`, [siteCode, doorId]);
    await client.query(
      `INSERT INTO plate_gate_settings (site_code, door_id, device_id, auto_open, min_confidence, cooldown_seconds, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (site_code, door_id) DO UPDATE SET device_id = EXCLUDED.device_id, auto_open = EXCLUDED.auto_open,
         min_confidence = EXCLUDED.min_confidence, cooldown_seconds = EXCLUDED.cooldown_seconds, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
      [siteCode, doorId, input.deviceId, input.autoOpen, input.minConfidence, input.cooldownSeconds, actor.userCode],
    );
    await audit(client, authUser, 'plate.settings_changed', siteCode, 'door', doorId, {
      auto_open: input.autoOpen,
      previous_auto_open: before.rows[0]?.auto_open === true,
      device_id: input.deviceId,
      min_confidence: input.minConfidence,
      cooldown_seconds: input.cooldownSeconds,
    });
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    if (error?.code === '23505') throw new PlatformError(409, 'CAMERA_ALREADY_MAPPED', 'Bu kamera başka bir kapıya eşlenmiş.');
    throw error;
  } finally {
    client.release();
  }
  return getSettings(siteCode);
}
