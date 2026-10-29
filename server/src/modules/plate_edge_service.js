// Plaka Tanıma A1: KENAR İSTEMCİ uçlarının servisi (güvenlik kulübesindeki Windows PC). Kimlik: kenar istemci anahtarı (`<id>.<gizli>`, DB'de yalnız SHA-256),
// kapsam: anahtarın bağlı olduğu SİTE (başka siteye erişemez). Sözleşme sürümlüdür (`schema_version`, bkz. plate_gates_common.js).
//
//   claim      anahtarı doğrular, sürüm bilgisini kaydeder, aralık ipuçlarını (kalp atışı / senkron) döner
//   sync       izin listesi: araçlar + misafir izinleri + kara liste (bölüm özetiyle "değişmedi") + daire kapasite / içerideki sayılar + "içeride" farkı (updated_since)
//   events     TEK olay (event_id ile idempotent): kayıt + karar kaydı + "içeride" geçişi; kapı AÇMAZ (karar ve açma kenardadır)
//   heartbeat  kenar PC + kamera başına son kare / son okuma zamanı (yönetici DURUM ekranı bunu okur)
//
// Karar KENARDA verilir (offline-first); sunucu yalnız kaydeder ve "içeride" durumunu tutar.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { isModuleEnabled } from './module_service.js';
import { PLATE_RECOGNITION_MODULE, iso, moduleDisabled, notFound } from './plate_recognition_common.js';
import { loadGateConfig, loadSiteSettings } from './plate_gates_service.js';
import {
  DECISION_TO_LEGACY,
  PLATE_GATES_SCHEMA_VERSION,
  SUPPORTED_SCHEMA_VERSIONS,
  SYNC_OVERLAP_MS,
  edgeKeyMatches,
  invalidEdgeKey,
  parseClaim,
  parseEdgeEvent,
  parseEdgeKey,
  parseHeartbeat,
  parseSyncQuery,
  presenceTransition,
  resolveDirection,
  revisionOf,
} from './plate_gates_common.js';

/** Anahtarı doğrular ve modülün açık olduğunu denetler. @returns {{ id: number, siteCode: number, name: string, siteName: string|null }} */
export async function authenticateEdge(rawKey) {
  const key = parseEdgeKey(rawKey);
  if (!key) throw invalidEdgeKey();
  const result = await pool.query(
    `SELECT c.id, c.site_code, c.key_hash, c.is_active, c.name, s.name AS site_name
       FROM plate_edge_clients c LEFT JOIN sites s ON s.site_code = c.site_code WHERE c.id = $1`,
    [key.id],
  );
  const row = result.rows[0];
  if (!row || !row.is_active || !edgeKeyMatches(key.secret, row.key_hash)) throw invalidEdgeKey();
  const siteCode = Number(row.site_code);
  if (!(await isModuleEnabled(siteCode, PLATE_RECOGNITION_MODULE))) throw moduleDisabled();
  return { id: Number(row.id), siteCode, name: row.name, siteName: row.site_name ?? null };
}

const envelope = () => ({ schema_version: PLATE_GATES_SCHEMA_VERSION });

// --- claim ---------------------------------------------------------------------------------------------------------------------

export async function claimEdge(client, body) {
  const { schemaVersion, appVersion } = parseClaim(body);
  await pool.query(
    `UPDATE plate_edge_clients SET claimed_at = COALESCE(claimed_at, NOW()), last_seen_at = NOW(), app_version = COALESCE($2, app_version), schema_version = $3 WHERE id = $1`,
    [client.id, appVersion, schemaVersion],
  );
  const settings = await loadSiteSettings(pool, client.siteCode);
  return {
    ...envelope(),
    supported_schema_versions: [...SUPPORTED_SCHEMA_VERSIONS],
    server_time: new Date().toISOString(),
    client: { id: client.id, name: client.name },
    site: { site_code: client.siteCode, name: client.siteName },
    intervals: { heartbeat_seconds: settings.heartbeat_interval_seconds, sync_seconds: settings.sync_interval_seconds },
  };
}

// --- sync -----------------------------------------------------------------------------------------------------------------------

const VEHICLES_SQL = `
  SELECT v.plate, v.id AS vehicle_id, v.apartment_id FROM vehicles v
  LEFT JOIN site_people sp ON sp.id = v.person_id
  LEFT JOIN apartments a ON a.id = v.apartment_id
  WHERE v.site_code = $1 AND v.is_active AND (v.person_id IS NULL OR sp.is_active) AND (v.apartment_id IS NULL OR a.is_active)
  ORDER BY v.plate, v.id`;

const PERMITS_SQL = `
  SELECT p.id, p.plate, p.apartment_id, p.valid_from, p.valid_until FROM plate_guest_permits p
  INNER JOIN apartments a ON a.id = p.apartment_id AND a.is_active
  WHERE p.site_code = $1 AND p.revoked_at IS NULL AND p.valid_until > NOW() ORDER BY p.id`;

const APARTMENTS_SQL = `
  SELECT a.id, a.parking_slots, COALESCE(p.n, 0)::INT AS inside_count FROM apartments a
  LEFT JOIN (SELECT apartment_id, COUNT(*) AS n FROM plate_presence WHERE site_code = $1 AND inside GROUP BY apartment_id) p ON p.apartment_id = a.id
  WHERE a.site_code = $1 AND a.is_active AND (a.parking_slots > 0 OR COALESCE(p.n, 0) > 0) ORDER BY a.id`;

function section(items, clientRev) {
  const rev = revisionOf(items);
  return rev === clientRev ? { rev, unchanged: true } : { rev, items };
}

export async function syncEdge(client, query) {
  const parsed = parseSyncQuery(query);
  const siteCode = client.siteCode;
  const serverTime = new Date((await pool.query(`SELECT NOW() AS now`)).rows[0].now);
  const since = parsed.since ? new Date(parsed.since.getTime() - SYNC_OVERLAP_MS) : null;
  const [settings, config, vehicles, permits, blacklist, apartments, presence] = await Promise.all([
    loadSiteSettings(pool, siteCode),
    loadGateConfig(pool, siteCode),
    pool.query(VEHICLES_SQL, [siteCode]),
    pool.query(PERMITS_SQL, [siteCode]),
    pool.query(`SELECT plate FROM plate_blacklist WHERE site_code = $1 AND removed_at IS NULL ORDER BY plate`, [siteCode]),
    pool.query(APARTMENTS_SQL, [siteCode]),
    since
      ? pool.query(`SELECT plate, apartment_id, kind, inside, since_at FROM plate_presence WHERE site_code = $1 AND updated_at > $2 ORDER BY id`, [siteCode, since])
      : pool.query(`SELECT plate, apartment_id, kind, inside, since_at FROM plate_presence WHERE site_code = $1 AND inside ORDER BY id`, [siteCode]),
  ]);
  await pool.query(`UPDATE plate_edge_clients SET last_sync_at = NOW(), last_seen_at = NOW() WHERE id = $1`, [client.id]);
  const idOrNull = (value) => (value === null || value === undefined ? null : Number(value));
  return {
    ...envelope(),
    server_time: serverTime.toISOString(),
    full: since === null,
    config: {
      settings: {
        guest_rule: settings.guest_rule,
        heartbeat_interval_seconds: settings.heartbeat_interval_seconds,
        sync_interval_seconds: settings.sync_interval_seconds,
      },
      gates: config.gates.map((gate) => ({
        id: Number(gate.id),
        name: gate.name,
        direction_mode: gate.direction_mode,
        device_uid: gate.device_uid ?? null,
        is_active: gate.is_active !== false,
        cameras: config.bindings
          .filter((b) => Number(b.gate_id) === Number(gate.id))
          .map((b) => ({ camera_id: Number(b.camera_id), name: b.name, direction: b.direction, is_active: b.is_active !== false })),
      })),
    },
    vehicles: section(vehicles.rows.map((r) => ({ plate: r.plate, vehicle_id: Number(r.vehicle_id), apartment_id: idOrNull(r.apartment_id) })), parsed.vehiclesRev),
    guest_permits: section(
      permits.rows.map((r) => ({ id: Number(r.id), plate: r.plate, apartment_id: Number(r.apartment_id), valid_from: iso(r.valid_from), valid_until: iso(r.valid_until) })),
      parsed.permitsRev,
    ),
    blacklist: section(blacklist.rows.map((r) => ({ plate: r.plate })), parsed.blacklistRev),
    apartments: apartments.rows.map((r) => ({ id: Number(r.id), parking_slots: r.parking_slots, inside_count: r.inside_count })),
    presence: {
      full: since === null,
      items: presence.rows.map((r) => ({ plate: r.plate, apartment_id: idOrNull(r.apartment_id), kind: r.kind, inside: r.inside === true, since_at: iso(r.since_at) })),
    },
  };
}

// --- events ---------------------------------------------------------------------------------------------------------------------

/** Tekil, idempotent olay kaydı. Aynı event_id ikinci kez gelirse hiçbir şey yazılmaz ({ duplicate: true }). 4xx yanıtlar KALICI hatadır: istemci yeniden denememeli. */
export async function recordEdgeEvent(client, body) {
  const event = parseEdgeEvent(body);
  const siteCode = client.siteCode;
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    await db.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_presence:${siteCode}:${event.plate}`]);
    const camera = (
      await db.query(
        `SELECT c.id, gc.gate_id, gc.direction AS camera_direction FROM camera_devices c
         LEFT JOIN plate_gate_cameras gc ON gc.camera_id = c.id WHERE c.id = $1 AND c.site_code = $2`,
        [event.cameraId, siteCode],
      )
    ).rows[0];
    if (!camera) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
    const gateId = event.gateId ?? (camera.gate_id === null || camera.gate_id === undefined ? null : Number(camera.gate_id));
    let gate = null;
    if (gateId !== null) {
      gate = (await db.query(`SELECT id, direction_mode, door_id FROM plate_gates WHERE id = $1 AND site_code = $2`, [gateId, siteCode])).rows[0] ?? null;
      if (!gate) throw notFound('Kapı', 'GATE_NOT_FOUND');
    }
    const existing = (await db.query(`SELECT inside FROM plate_presence WHERE site_code = $1 AND plate = $2 FOR UPDATE`, [siteCode, event.plate])).rows[0] ?? null;
    const direction = resolveDirection({
      gateMode: gate?.direction_mode ?? null,
      cameraDirection: camera.camera_direction ?? null,
      declared: event.direction,
      inside: existing?.inside === true,
    });
    const vehicle = (await db.query(`SELECT id, apartment_id FROM vehicles WHERE site_code = $1 AND plate = $2 AND is_active LIMIT 1`, [siteCode, event.plate])).rows[0] ?? null;
    const permit = vehicle
      ? null
      : (
          await db.query(
            `SELECT id, apartment_id FROM plate_guest_permits WHERE site_code = $1 AND plate = $2 AND revoked_at IS NULL AND valid_until > NOW() ORDER BY valid_until DESC LIMIT 1`,
            [siteCode, event.plate],
          )
        ).rows[0] ?? null;
    const inserted = await db.query(
      `INSERT INTO plate_events (site_code, device_id, plate, matched, vehicle_id, seen_at, gate_id, direction, decision_kind, edge_client_id, client_event_id, schema_version, confidence, reason)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       ON CONFLICT (site_code, client_event_id) WHERE client_event_id IS NOT NULL DO NOTHING RETURNING id`,
      [siteCode, event.cameraId, event.plate, vehicle !== null, vehicle?.id ?? null, event.seenAt, gateId, direction, event.decision, client.id, event.eventId, event.schemaVersion, event.confidence, event.reason],
    );
    if (!inserted.rows[0]) {
      await db.query('ROLLBACK');
      return { ...envelope(), ok: true, duplicate: true };
    }
    const eventId = Number(inserted.rows[0].id);
    const reason =
      event.reason ?? (event.decision === 'acildi' ? (vehicle ? 'vehicle' : permit ? 'guest_permit' : 'edge_open') : event.decision === 'red' ? 'denied' : 'not_registered');
    // Mevcut "Olaylar" akışı (plate_decisions) kenar olaylarını da gösterir.
    await db.query(
      `INSERT INTO plate_decisions (site_code, event_id, device_id, door_id, plate, confidence, decision, reason, vehicle_id, permit_id, auto_action, decided_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'none', $11) ON CONFLICT (event_id) DO NOTHING`,
      [siteCode, eventId, event.cameraId, gate?.door_id ?? null, event.plate, event.confidence, DECISION_TO_LEGACY[event.decision], reason, vehicle?.id ?? null, permit?.id ?? null, event.seenAt],
    );
    const transition = presenceTransition({ direction, decision: event.decision });
    let inside = existing?.inside === true;
    if (transition === 'enter') {
      const kind = vehicle ? 'resident' : permit ? 'guest' : 'other';
      const applied = await db.query(
        `INSERT INTO plate_presence (site_code, plate, apartment_id, kind, gate_id, inside, since_at, last_event_id)
         VALUES ($1, $2, $3, $4, $5, TRUE, $6, $7)
         ON CONFLICT (site_code, plate) DO UPDATE SET apartment_id = EXCLUDED.apartment_id, kind = EXCLUDED.kind, gate_id = EXCLUDED.gate_id,
           inside = TRUE, since_at = EXCLUDED.since_at, last_event_id = EXCLUDED.last_event_id, updated_at = NOW()
         WHERE plate_presence.since_at <= EXCLUDED.since_at RETURNING id`,
        [siteCode, event.plate, vehicle?.apartment_id ?? permit?.apartment_id ?? null, kind, gateId, event.seenAt, eventId],
      );
      if (applied.rows[0]) inside = true;
    } else if (transition === 'leave' && existing) {
      const applied = await db.query(
        `UPDATE plate_presence SET inside = FALSE, since_at = $3, gate_id = $4, last_event_id = $5, updated_at = NOW()
          WHERE site_code = $1 AND plate = $2 AND since_at <= $3 RETURNING id`,
        [siteCode, event.plate, event.seenAt, gateId, eventId],
      );
      if (applied.rows[0]) inside = false;
    }
    await db.query(`UPDATE camera_devices SET last_event_at = NOW() WHERE id = $1`, [event.cameraId]);
    await db.query('COMMIT');
    return { ...envelope(), ok: true, duplicate: false, event_id: eventId, direction, inside };
  } catch (error) {
    await db.query('ROLLBACK').catch(() => {});
    if (error?.code === '23505') throw new PlatformError(409, 'DUPLICATE_EVENT', 'Olay zaten kayıtlı.');
    throw error;
  } finally {
    db.release();
  }
}

// --- heartbeat -------------------------------------------------------------------------------------------------------------------

export async function heartbeatEdge(client, body) {
  const beat = parseHeartbeat(body);
  await pool.query(
    `UPDATE plate_edge_clients SET last_seen_at = NOW(), app_version = COALESCE($2, app_version), schema_version = $3, queue_depth = $4 WHERE id = $1`,
    [client.id, beat.appVersion, beat.schemaVersion, beat.queueDepth],
  );
  if (beat.cameras.length) {
    // Yalnız bu sitenin kameraları yazılır (başka sitenin kamera kimliği sessizce atlanır).
    await pool.query(
      `INSERT INTO plate_camera_status (camera_id, site_code, edge_client_id, last_frame_at, last_read_at, reported_at)
       SELECT c.id, $1, $2, t.frame_at, t.read_at, NOW()
         FROM unnest($3::BIGINT[], $4::TIMESTAMPTZ[], $5::TIMESTAMPTZ[]) AS t(camera_id, frame_at, read_at)
         INNER JOIN camera_devices c ON c.id = t.camera_id AND c.site_code = $1
       ON CONFLICT (camera_id) DO UPDATE SET edge_client_id = EXCLUDED.edge_client_id, last_frame_at = EXCLUDED.last_frame_at,
         last_read_at = COALESCE(EXCLUDED.last_read_at, plate_camera_status.last_read_at), reported_at = NOW()`,
      [
        client.siteCode,
        client.id,
        beat.cameras.map((c) => c.cameraId),
        beat.cameras.map((c) => c.lastFrameAt?.toISOString() ?? null),
        beat.cameras.map((c) => c.lastReadAt?.toISOString() ?? null),
      ],
    );
  }
  const settings = await loadSiteSettings(pool, client.siteCode);
  return {
    ...envelope(),
    ok: true,
    server_time: new Date().toISOString(),
    intervals: { heartbeat_seconds: settings.heartbeat_interval_seconds, sync_seconds: settings.sync_interval_seconds },
  };
}
