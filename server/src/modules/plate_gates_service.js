// Plaka Tanıma A1 (yönetici tarafı): geçiş noktaları (kapı) CRUD + DURUM ekranı, site ayarı (misafir kuralı, kalp atışı eşikleri),
// kenar istemci kayıtları (anahtar bir kez gösterilir, yalnız özeti saklanır), "içeride" listesi ve elle düzeltme.
//
// Hiçbir sayı / yön / eşik koda gömülü değildir (kayıtlar ve plate_site_settings). Durum rozetleri kalp atışı gecikmesinden türetilir:
// çalışıyor (yeşil) < sarı eşik < çalışıyor ama gecikmiş (sarı) < kırmızı eşik < koptu (kırmızı); hiç haber yoksa hiç bağlanmadı (gri).

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { recordAudit, actorFromAuthUser } from './audit_service.js';
import { apartmentLabel } from './people_common.js';
import { formatPlate, iso, maskPlate, notFound } from './plate_recognition_common.js';
import {
  DEFAULT_SITE_SETTINGS,
  DIRECTION_MODES,
  DIRECTION_MODE_LABELS,
  GUEST_RULES,
  GUEST_RULE_LABELS,
  ageSecondsOf,
  assertCameraDirections,
  evaluateGuestAdmission,
  healthOf,
  mergeSettings,
  newEdgeSecret,
  parseEdgeClientInput,
  parseGateInput,
  parseSettingsInput,
  worstBadge,
} from './plate_gates_common.js';

const audit = (db, actor, action, siteCode, targetType, targetId, details) =>
  recordAudit(db, { actor, action, siteCode, targetType, targetId: String(targetId), details }, { inTransaction: db !== pool });

const NEVER = Object.freeze({ state: 'hic_baglanmadi', color: 'gri' });

const parsePositive = (raw, what, code) => {
  const id = Number(raw);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound(what, code);
  return id;
};

// --- Site ayarı -------------------------------------------------------------------------------------------------------------

export async function loadSiteSettings(db, siteCode) {
  const result = await db.query(
    `SELECT guest_rule, heartbeat_warn_seconds, heartbeat_crit_seconds, heartbeat_interval_seconds, sync_interval_seconds,
            inside_report_hours, inside_timeout_hours, alert_interval_minutes, resident_notify_max_age_minutes,
            command_ttl_seconds, snapshot_interval_seconds, snapshot_idle_interval_seconds, snapshot_keep_minutes
       FROM plate_site_settings WHERE site_code = $1`,
    [siteCode],
  );
  return { ...DEFAULT_SITE_SETTINGS, ...(result.rows[0] ?? {}) };
}

const settingsView = (settings) => ({
  settings,
  defaults: DEFAULT_SITE_SETTINGS,
  guest_rules: GUEST_RULES.map((code) => ({ code, label: GUEST_RULE_LABELS[code] ?? code })),
});

export async function getSiteSettings(siteCode) {
  return settingsView(await loadSiteSettings(pool, siteCode));
}

export async function saveSiteSettings({ siteCode, body, authUser }) {
  const patch = parseSettingsInput(body);
  const merged = mergeSettings(await loadSiteSettings(pool, siteCode), patch);
  const actor = actorFromAuthUser(authUser);
  await pool.query(
    `INSERT INTO plate_site_settings (site_code, guest_rule, heartbeat_warn_seconds, heartbeat_crit_seconds, heartbeat_interval_seconds, sync_interval_seconds,
                                     inside_report_hours, inside_timeout_hours, alert_interval_minutes, resident_notify_max_age_minutes,
                                     command_ttl_seconds, snapshot_interval_seconds, snapshot_idle_interval_seconds, snapshot_keep_minutes, updated_by, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW())
     ON CONFLICT (site_code) DO UPDATE SET guest_rule = EXCLUDED.guest_rule, heartbeat_warn_seconds = EXCLUDED.heartbeat_warn_seconds,
       heartbeat_crit_seconds = EXCLUDED.heartbeat_crit_seconds, heartbeat_interval_seconds = EXCLUDED.heartbeat_interval_seconds,
       sync_interval_seconds = EXCLUDED.sync_interval_seconds, inside_report_hours = EXCLUDED.inside_report_hours, inside_timeout_hours = EXCLUDED.inside_timeout_hours,
       alert_interval_minutes = EXCLUDED.alert_interval_minutes, resident_notify_max_age_minutes = EXCLUDED.resident_notify_max_age_minutes,
       command_ttl_seconds = EXCLUDED.command_ttl_seconds, snapshot_interval_seconds = EXCLUDED.snapshot_interval_seconds,
       snapshot_idle_interval_seconds = EXCLUDED.snapshot_idle_interval_seconds, snapshot_keep_minutes = EXCLUDED.snapshot_keep_minutes,
       updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
    [
      siteCode,
      merged.guest_rule,
      merged.heartbeat_warn_seconds,
      merged.heartbeat_crit_seconds,
      merged.heartbeat_interval_seconds,
      merged.sync_interval_seconds,
      merged.inside_report_hours,
      merged.inside_timeout_hours,
      merged.alert_interval_minutes,
      merged.resident_notify_max_age_minutes,
      merged.command_ttl_seconds,
      merged.snapshot_interval_seconds,
      merged.snapshot_idle_interval_seconds,
      merged.snapshot_keep_minutes,
      actor.userCode,
    ],
  );
  await audit(pool, authUser, 'plate.site_settings_changed', siteCode, 'site', siteCode, { changed: Object.keys(patch) });
  return settingsView(merged);
}

// --- Kapı yapılandırması (yönetici ekranı + kenar senkronu ortak) ------------------------------------------------------------------

/** Kapılar ve kamera bağları (durum alanları dahil). */
export async function syncDoorsFromSmartKeyPass(db, siteCode) {
  try {
    await db.query(
      `INSERT INTO plate_gates (site_code, name, direction_mode, device_uid, door_id, sort_order, is_active)
       SELECT d.site_code, d.door_name, 'cift', dev.device_uid, d.id, d.door_index, d.is_active
       FROM site_doors d
       LEFT JOIN devices dev ON dev.id = d.assigned_device_id
       WHERE d.site_code = $1
       ON CONFLICT (site_code, lower(name)) DO UPDATE
       SET door_id = EXCLUDED.door_id,
           device_uid = EXCLUDED.device_uid,
           is_active = EXCLUDED.is_active,
           sort_order = EXCLUDED.sort_order`,
      [siteCode],
    );
  } catch (_) {}
}

export async function loadGateConfig(db, siteCode) {
  await syncDoorsFromSmartKeyPass(db, siteCode);
  const [gates, bindings] = await Promise.all([
    db.query(
      `SELECT id, name, direction_mode, device_uid, door_id, sort_order, is_active FROM plate_gates WHERE site_code = $1 ORDER BY sort_order, id`,
      [siteCode],
    ),
    db.query(
      `SELECT gc.gate_id, gc.camera_id, gc.direction, c.name, c.is_active, s.last_frame_at, s.last_read_at, s.reported_at
         FROM plate_gate_cameras gc
         INNER JOIN camera_devices c ON c.id = gc.camera_id
         LEFT JOIN plate_camera_status s ON s.camera_id = gc.camera_id
        WHERE gc.site_code = $1 ORDER BY gc.id`,
      [siteCode],
    ),
  ]);
  return { gates: gates.rows, bindings: bindings.rows };
}

function cameraBadge(row, thresholds, now) {
  if (!row.is_active) return { state: 'koptu', color: 'kirmizi' };
  if (!row.reported_at) return NEVER;
  const age = ageSecondsOf(row.last_frame_at, now);
  return age === null ? { state: 'koptu', color: 'kirmizi' } : healthOf(age, thresholds);
}

function deviceBadge(row) {
  if (!row) return NEVER;
  if (row.is_online) return { state: 'calisiyor', color: 'yesil' };
  return row.last_online_at ? { state: 'koptu', color: 'kirmizi' } : NEVER;
}

/** Yönetici DURUM ekranı: tüm kapılar, kameralar, SmartKeyPass cihazları ve kenar PC'ler rozetleriyle. */
export async function getGatesOverview(siteCode) {
  const now = Date.now();
  const [settings, config, devices, edge, unassigned, inside] = await Promise.all([
    loadSiteSettings(pool, siteCode),
    loadGateConfig(pool, siteCode),
    pool.query(`SELECT device_uid, gate_name, is_online, last_online_at FROM devices WHERE site_code = $1 ORDER BY device_uid LIMIT 500`, [siteCode]),
    pool.query(
      `SELECT id, name, is_active, app_version, schema_version, claimed_at, last_seen_at, last_sync_at, queue_depth, created_at
         FROM plate_edge_clients WHERE site_code = $1 AND revoked_at IS NULL ORDER BY id`,
      [siteCode],
    ),
    pool.query(
      `SELECT c.id, c.name FROM camera_devices c
        WHERE c.site_code = $1 AND c.is_active AND NOT EXISTS (SELECT 1 FROM plate_gate_cameras gc WHERE gc.camera_id = c.id) ORDER BY c.id`,
      [siteCode],
    ),
    pool.query(`SELECT COUNT(*)::INT AS n FROM plate_presence WHERE site_code = $1 AND inside`, [siteCode]),
  ]);
  const thresholds = { warn: settings.heartbeat_warn_seconds, crit: settings.heartbeat_crit_seconds };
  const deviceByUid = new Map(devices.rows.map((row) => [row.device_uid, row]));
  const gates = config.gates.map((gate) => {
    const cameras = config.bindings
      .filter((b) => Number(b.gate_id) === Number(gate.id))
      .map((b) => ({
        camera_id: Number(b.camera_id),
        name: b.name,
        direction: b.direction,
        is_active: b.is_active !== false,
        status: cameraBadge(b, thresholds, now),
        last_frame_at: iso(b.last_frame_at),
        last_read_at: iso(b.last_read_at),
      }));
    const device = gate.device_uid ? { device_uid: gate.device_uid, status: deviceBadge(deviceByUid.get(gate.device_uid)) } : null;
    return {
      id: Number(gate.id),
      name: gate.name,
      direction_mode: gate.direction_mode,
      direction_label: DIRECTION_MODE_LABELS[gate.direction_mode] ?? gate.direction_mode,
      device_uid: gate.device_uid ?? null,
      door_id: gate.door_id === null || gate.door_id === undefined ? null : Number(gate.door_id),
      sort_order: gate.sort_order,
      is_active: gate.is_active !== false,
      device,
      cameras,
      status: worstBadge([...(device ? [device.status] : []), ...cameras.map((c) => c.status)]),
    };
  });
  return {
    server_time: new Date(now).toISOString(),
    ...settingsView(settings),
    direction_modes: DIRECTION_MODES.map((code) => ({ code, label: DIRECTION_MODE_LABELS[code] })),
    gates,
    unassigned_cameras: unassigned.rows.map((row) => ({ id: Number(row.id), name: row.name })),
    devices: devices.rows.map((row) => ({ device_uid: row.device_uid, gate_name: row.gate_name ?? null, status: deviceBadge(row) })),
    edge_clients: edge.rows.map((row) => ({
      id: Number(row.id),
      name: row.name,
      is_active: row.is_active !== false,
      status: row.last_seen_at ? healthOf(ageSecondsOf(row.last_seen_at, now), thresholds) : NEVER,
      app_version: row.app_version ?? null,
      schema_version: row.schema_version ?? null,
      claimed_at: iso(row.claimed_at),
      last_seen_at: iso(row.last_seen_at),
      last_sync_at: iso(row.last_sync_at),
      queue_depth: row.queue_depth ?? null,
    })),
    inside_total: inside.rows[0]?.n ?? 0,
  };
}

// --- Kapı CRUD ---------------------------------------------------------------------------------------------------------------

async function assertGateRefs(db, siteCode, input, cameras, gateId) {
  if (input.device_uid) {
    const device = await db.query(`SELECT 1 FROM devices WHERE device_uid = $1 AND site_code = $2 LIMIT 1`, [input.device_uid, siteCode]);
    if (!device.rows[0]) throw notFound('SmartKeyPass cihazı', 'DEVICE_NOT_FOUND');
    const taken = await db.query(`SELECT 1 FROM plate_gates WHERE site_code = $1 AND device_uid = $2 AND id <> $3 LIMIT 1`, [siteCode, input.device_uid, gateId ?? 0]);
    if (taken.rows[0]) throw new PlatformError(409, 'DEVICE_ALREADY_MAPPED', 'Bu cihaz başka bir kapıya bağlı.');
  }
  if (input.door_id) {
    const door = await db.query(`SELECT 1 FROM site_doors WHERE id = $1 AND site_code = $2 LIMIT 1`, [input.door_id, siteCode]);
    if (!door.rows[0]) throw notFound('Kapı', 'DOOR_NOT_FOUND');
  }
  if (cameras.length) {
    const ids = cameras.map((c) => c.camera_id);
    const found = await db.query(`SELECT id FROM camera_devices WHERE site_code = $1 AND is_active AND id = ANY($2::BIGINT[])`, [siteCode, ids]);
    if (found.rows.length !== ids.length) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
    const mapped = await db.query(`SELECT 1 FROM plate_gate_cameras WHERE camera_id = ANY($1::BIGINT[]) AND gate_id <> $2 LIMIT 1`, [ids, gateId ?? 0]);
    if (mapped.rows[0]) throw new PlatformError(409, 'CAMERA_ALREADY_MAPPED', 'Bir kamera yalnız tek bir kapıya bağlanabilir.');
  }
}

async function insertBindings(client, siteCode, gateId, cameras) {
  for (const camera of cameras) {
    await client.query(`INSERT INTO plate_gate_cameras (site_code, gate_id, camera_id, direction) VALUES ($1, $2, $3, $4)`, [siteCode, gateId, camera.camera_id, camera.direction]);
  }
}

function mapGateWriteError(error) {
  if (error?.code === '23505') {
    if (String(error.constraint).includes('gate_cameras')) return new PlatformError(409, 'CAMERA_ALREADY_MAPPED', 'Bir kamera yalnız tek bir kapıya bağlanabilir.');
    return new PlatformError(409, 'GATE_NAME_TAKEN', 'Bu adla bir kapı zaten var.');
  }
  return error;
}

async function inGateTransaction(siteCode, work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_gates:${siteCode}`]);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw mapGateWriteError(error);
  } finally {
    client.release();
  }
}

export async function createGate({ siteCode, body, authUser }) {
  throw new PlatformError(
    400,
    'DOORS_MANAGED_BY_SMARTKEYPASS',
    'Kapılar SmartKeyPass modülünden yönetilir. Plaka modülünde yeni kapı eklenemez; kapı ekleme SmartKeyPass modülünden yapılır.',
  );
}

const UPDATABLE = Object.freeze(['name', 'direction_mode', 'device_uid', 'door_id', 'sort_order', 'is_active']);

export async function updateGate({ siteCode, rawId, body, authUser }) {
  const gateId = parsePositive(rawId, 'Kapı', 'GATE_NOT_FOUND');
  const patch = parseGateInput(body, { partial: true });
  if (!Object.keys(patch).length) throw new PlatformError(400, 'INVALID_BODY', 'Değişiklik yok.');
  await inGateTransaction(siteCode, async (client) => {
    const found = await client.query(`SELECT id, direction_mode FROM plate_gates WHERE id = $1 AND site_code = $2 FOR UPDATE`, [gateId, siteCode]);
    if (!found.rows[0]) throw notFound('Kapı', 'GATE_NOT_FOUND');
    const mode = patch.direction_mode ?? found.rows[0].direction_mode;
    const cameras =
      patch.cameras ??
      (patch.direction_mode
        ? (await client.query(`SELECT camera_id, direction FROM plate_gate_cameras WHERE gate_id = $1`, [gateId])).rows.map((r) => ({ camera_id: Number(r.camera_id), direction: r.direction }))
        : []);
    assertCameraDirections(mode, cameras);
    await assertGateRefs(client, siteCode, patch, patch.cameras ?? [], gateId);
    const keys = UPDATABLE.filter((key) => patch[key] !== undefined);
    if (keys.length) {
      const sets = keys.map((key, index) => `${key} = $${index + 3}`);
      await client.query(`UPDATE plate_gates SET ${sets.join(', ')}, updated_at = NOW() WHERE id = $1 AND site_code = $2`, [gateId, siteCode, ...keys.map((key) => patch[key])]);
    }
    if (patch.cameras) {
      await client.query(`DELETE FROM plate_gate_cameras WHERE gate_id = $1`, [gateId]);
      await insertBindings(client, siteCode, gateId, patch.cameras);
    }
    await audit(client, authUser, 'plate.gate_updated', siteCode, 'plate_gate', gateId, { changed: Object.keys(patch) });
  });
  return getGatesOverview(siteCode);
}

export async function deleteGate({ siteCode, rawId, authUser }) {
  throw new PlatformError(
    400,
    'DOORS_MANAGED_BY_SMARTKEYPASS',
    'Kapılar SmartKeyPass modülünden yönetilir. Plaka modülünde kapı silinemez; kapı kaldırma SmartKeyPass modülünden yapılır.',
  );
}

// --- Kenar istemci kayıtları -------------------------------------------------------------------------------------------------------

/** Anahtar `<id>.<gizli>` yalnız burada (oluşturma / yenileme yanıtında) görünür; DB'de yalnız SHA-256 özeti. */
export async function createEdgeClient({ siteCode, body, authUser }) {
  const { name } = parseEdgeClientInput(body);
  const actor = actorFromAuthUser(authUser);
  const { secret, hash } = newEdgeSecret();
  const row = await pool.query(`INSERT INTO plate_edge_clients (site_code, name, key_hash, created_by) VALUES ($1, $2, $3, $4) RETURNING id`, [siteCode, name, hash, actor.userCode]);
  const id = Number(row.rows[0].id);
  await audit(pool, authUser, 'plate.edge_client_created', siteCode, 'plate_edge_client', id, { name });
  return { client: { id, name }, edge_key: `${id}.${secret}` };
}

export async function rotateEdgeKey({ siteCode, rawId, authUser }) {
  const id = parsePositive(rawId, 'Kenar istemci', 'EDGE_CLIENT_NOT_FOUND');
  const { secret, hash } = newEdgeSecret();
  const result = await pool.query(
    `UPDATE plate_edge_clients SET key_hash = $3, claimed_at = NULL WHERE id = $1 AND site_code = $2 AND is_active AND revoked_at IS NULL RETURNING id`,
    [id, siteCode, hash],
  );
  if (!result.rows[0]) throw notFound('Kenar istemci', 'EDGE_CLIENT_NOT_FOUND');
  await audit(pool, authUser, 'plate.edge_client_rotated', siteCode, 'plate_edge_client', id, {});
  return { edge_key: `${id}.${secret}` };
}

export async function revokeEdgeClient({ siteCode, rawId, authUser }) {
  const id = parsePositive(rawId, 'Kenar istemci', 'EDGE_CLIENT_NOT_FOUND');
  const result = await pool.query(
    `UPDATE plate_edge_clients SET is_active = FALSE, revoked_at = NOW() WHERE id = $1 AND site_code = $2 AND revoked_at IS NULL RETURNING id, name`,
    [id, siteCode],
  );
  if (!result.rows[0]) throw notFound('Kenar istemci', 'EDGE_CLIENT_NOT_FOUND');
  await audit(pool, authUser, 'plate.edge_client_revoked', siteCode, 'plate_edge_client', id, { name: result.rows[0].name });
  return { ok: true };
}

// --- "İçeride" ---------------------------------------------------------------------------------------------------------------------

const INSIDE_ROWS_SQL = `
  SELECT p.id, p.plate, p.kind, p.apartment_id, p.since_at, g.name AS gate_name, b.block_name, a.unit_label
    FROM plate_presence p
    LEFT JOIN apartments a ON a.id = p.apartment_id
    LEFT JOIN site_blocks b ON b.id = a.block_id
    LEFT JOIN plate_gates g ON g.id = p.gate_id`;

/** İçerideki araçlar + park yeri olan / içeride aracı olan dairelerin doluluğu ve misafir kabul durumu + "çıkışı olmayan girişler" raporu (eşik site ayarı). */
export async function listInside(siteCode) {
  const settings = await loadSiteSettings(pool, siteCode);
  const now = Date.now();
  const mapItem = (row) => {
    const since = iso(row.since_at);
    const age = ageSecondsOf(row.since_at, now);
    return {
      id: Number(row.id),
      plate: formatPlate(row.plate),
      kind: row.kind,
      apartment_id: row.apartment_id === null ? null : Number(row.apartment_id),
      apartment_label: row.apartment_id === null ? null : apartmentLabel(row.block_name, row.unit_label),
      since_at: since,
      inside_hours: age === null ? null : Math.floor(age / 3600),
      gate_name: row.gate_name ?? null,
    };
  };
  const [items, apartments, total, overdue] = await Promise.all([
    pool.query(`${INSIDE_ROWS_SQL} WHERE p.site_code = $1 AND p.inside ORDER BY p.since_at DESC LIMIT 200`, [siteCode]),
    pool.query(
      `SELECT a.id, b.block_name, a.unit_label, a.parking_slots, COUNT(p.id)::INT AS inside_count
         FROM apartments a
         INNER JOIN site_blocks b ON b.id = a.block_id
         LEFT JOIN plate_presence p ON p.apartment_id = a.id AND p.inside
        WHERE a.site_code = $1 AND a.is_active
        GROUP BY a.id, b.block_name
       HAVING a.parking_slots > 0 OR COUNT(p.id) > 0
        ORDER BY b.block_name, a.unit_label LIMIT 500`,
      [siteCode],
    ),
    pool.query(`SELECT COUNT(*)::INT AS n FROM plate_presence WHERE site_code = $1 AND inside`, [siteCode]),
    pool.query(
      `${INSIDE_ROWS_SQL} WHERE p.site_code = $1 AND p.inside AND p.since_at < NOW() - make_interval(hours => $2::INT) ORDER BY p.since_at ASC LIMIT 200`,
      [siteCode, settings.inside_report_hours],
    ),
  ]);
  return {
    total: total.rows[0]?.n ?? 0,
    guest_rule: settings.guest_rule,
    items: items.rows.map(mapItem),
    // Çıkışı görülmeyen girişler: içeride `inside_report_hours` saatten uzun; `inside_timeout_hours` dolunca bakım rutini otomatik düşürür.
    overdue: { after_hours: settings.inside_report_hours, timeout_hours: settings.inside_timeout_hours, items: overdue.rows.map(mapItem) },
    apartments: apartments.rows.map((row) => ({
      id: Number(row.id),
      label: apartmentLabel(row.block_name, row.unit_label),
      parking_slots: row.parking_slots,
      inside_count: row.inside_count,
      guest_admit: evaluateGuestAdmission({ parkingSlots: row.parking_slots, insideCount: row.inside_count, rule: settings.guest_rule }),
    })),
  };
}

/** Elle düzeltme (çıkış kaçırıldıysa): aracı "içeride" listesinden düşürür. */
export async function clearInside({ siteCode, rawId, authUser }) {
  const id = parsePositive(rawId, 'Kayıt', 'PRESENCE_NOT_FOUND');
  const result = await pool.query(
    `UPDATE plate_presence SET inside = FALSE, updated_at = NOW() WHERE id = $1 AND site_code = $2 AND inside RETURNING plate`,
    [id, siteCode],
  );
  if (!result.rows[0]) throw notFound('Kayıt', 'PRESENCE_NOT_FOUND');
  await audit(pool, authUser, 'plate.inside_cleared', siteCode, 'plate_presence', id, { plate: maskPlate(result.rows[0].plate) });
  return { ok: true };
}
