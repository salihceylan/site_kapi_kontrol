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
import { recordDoorAccessLog } from '../services/door_service.js';
import { PlatformError } from './errors.js';
import { isModuleEnabled } from './module_service.js';
import { PLATE_RECOGNITION_MODULE, formatPlate, iso, moduleDisabled, notFound } from './plate_recognition_common.js';
import { loadGateConfig, loadSiteSettings } from './plate_gates_service.js';
import { notifyResidentMovement } from './plate_notify.js';
import { apartmentText, doorLogEntry, shortPersonName } from './plate_cameras_common.js';
import { claimCommands, completeCommand } from './plate_edge_commands.js';
import { loadEdgeCameras, storeSnapshot } from './plate_cameras_service.js';
import {
  DECISION_TO_LEGACY,
  PLATE_GATES_SCHEMA_VERSION,
  SUPPORTED_SCHEMA_VERSIONS,
  SYNC_OVERLAP_MS,
  V3_MIN_SCHEMA,
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

// Sürüm 3: kimlik etiketleri (daire "A - 5", kişi "Ali Y.") yalnız GÖSTERİM içindir; kenar bunları olayda geri göndermez (yalnız apartment_id).
const PERSON_NAME_SQL = `COALESCE(NULLIF(BTRIM(u.full_name), ''), NULLIF(BTRIM(sp.full_name), ''))`;

const VEHICLES_SQL = `
  SELECT v.plate, v.id AS vehicle_id, v.apartment_id, b.block_name, a.unit_label, ${PERSON_NAME_SQL} AS person_name FROM vehicles v
  LEFT JOIN site_people sp ON sp.id = v.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  LEFT JOIN apartments a ON a.id = v.apartment_id
  LEFT JOIN site_blocks b ON b.id = a.block_id
  WHERE v.site_code = $1 AND v.is_active AND (v.person_id IS NULL OR sp.is_active) AND (v.apartment_id IS NULL OR a.is_active)
  ORDER BY v.plate, v.id`;

const PERMITS_SQL = `
  SELECT p.id, p.plate, p.apartment_id, p.valid_from, p.valid_until, b.block_name, a.unit_label FROM plate_guest_permits p
  INNER JOIN apartments a ON a.id = p.apartment_id AND a.is_active
  LEFT JOIN site_blocks b ON b.id = a.block_id
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
  const [settings, config, cameras, vehicles, permits, blacklist, apartments, presence] = await Promise.all([
    loadSiteSettings(pool, siteCode),
    loadGateConfig(pool, siteCode),
    // Kamera tanımları (parola dahil) yalnız sürüm 3 istemciye iner; eski istemci bunları kullanamaz, gereksiz yere sır taşınmaz.
    parsed.schemaVersion >= V3_MIN_SCHEMA ? loadEdgeCameras(pool, siteCode) : Promise.resolve([]),
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
        snapshot_interval_seconds: settings.snapshot_interval_seconds,
        snapshot_idle_interval_seconds: settings.snapshot_idle_interval_seconds,
      },
      // Sürüm 3: uygulamadan eklenen kameralar (her senkronda TAM liste; parola yalnız burada, TLS + no-store). Kenar yerel ayarlarla birleştirir.
      cameras,
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
    vehicles: section(
      vehicles.rows.map((r) => ({
        plate: r.plate,
        vehicle_id: Number(r.vehicle_id),
        apartment_id: idOrNull(r.apartment_id),
        apartment_label: apartmentText(r.block_name, r.unit_label),
        person_label: shortPersonName(r.person_name),
      })),
      parsed.vehiclesRev,
    ),
    guest_permits: section(
      permits.rows.map((r) => ({
        id: Number(r.id),
        plate: r.plate,
        apartment_id: Number(r.apartment_id),
        apartment_label: apartmentText(r.block_name, r.unit_label),
        valid_from: iso(r.valid_from),
        valid_until: iso(r.valid_until),
      })),
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

async function loadIdentityLabels(db, siteCode, apartmentId, personId) {
  let apartmentLabel = null;
  let personLabel = null;
  if (apartmentId !== null && apartmentId !== undefined) {
    const row = (
      await db.query(`SELECT b.block_name, a.unit_label FROM apartments a LEFT JOIN site_blocks b ON b.id = a.block_id WHERE a.id = $1 AND a.site_code = $2`, [apartmentId, siteCode])
    ).rows[0];
    if (row) apartmentLabel = apartmentText(row.block_name, row.unit_label);
  }
  if (personId !== null && personId !== undefined) {
    const row = (
      await db.query(
        `SELECT ${PERSON_NAME_SQL} AS person_name FROM site_people sp LEFT JOIN users u ON u.user_code = sp.user_code WHERE sp.id = $1 AND sp.site_code = $2`,
        [personId, siteCode],
      )
    ).rows[0];
    if (row) personLabel = shortPersonName(row.person_name);
  }
  return { apartmentLabel, personLabel };
}

/** En iyi çaba: günlük yazılamazsa olay kaydı ve yanıt etkilenmez (recordDoorAccessLog zaten hatayı yutar; etiket sorgusu için ayrıca sarılır). */
async function writePlateDoorLog({ writeDoorLog, siteCode, gate, plate, identityKind, apartmentId, personId, seenAt }) {
  try {
    const labels = await loadIdentityLabels(pool, siteCode, apartmentId, personId);
    const entry = doorLogEntry({ plateText: formatPlate(plate), identityKind, apartmentLabel: labels.apartmentLabel, personLabel: labels.personLabel });
    await writeDoorLog({
      siteCode,
      doorId: gate?.door_id ?? null,
      doorName: gate?.name ?? 'Plaka tanıma kapısı',
      userName: entry.userName,
      userRole: 'plate',
      apartmentLabel: entry.apartmentLabel,
      triggerType: 'plate',
      openedAt: seenAt,
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[plate] kapi gunlugu yazilamadi:', error?.code || error?.message || 'hata');
  }
}

/** Tekil, idempotent olay kaydı. Aynı event_id ikinci kez gelirse hiçbir şey yazılmaz ({ duplicate: true }). 4xx yanıtlar KALICI hatadır: istemci yeniden denememeli. */
export async function recordEdgeEvent(client, body, { writeDoorLog = recordDoorAccessLog } = {}) {
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
      gate = (await db.query(`SELECT id, name, direction_mode, door_id FROM plate_gates WHERE id = $1 AND site_code = $2`, [gateId, siteCode])).rows[0] ?? null;
      if (!gate) throw notFound('Kapı', 'GATE_NOT_FOUND');
    }
    const existing = (await db.query(`SELECT inside FROM plate_presence WHERE site_code = $1 AND plate = $2 FOR UPDATE`, [siteCode, event.plate])).rows[0] ?? null;
    const direction = resolveDirection({
      gateMode: gate?.direction_mode ?? null,
      cameraDirection: camera.camera_direction ?? null,
      declared: event.direction,
      inside: existing?.inside === true,
    });
    const vehicle = (await db.query(`SELECT id, apartment_id, person_id FROM vehicles WHERE site_code = $1 AND plate = $2 AND is_active LIMIT 1`, [siteCode, event.plate])).rows[0] ?? null;
    const permit = vehicle
      ? null
      : (
          await db.query(
            `SELECT id, apartment_id FROM plate_guest_permits WHERE site_code = $1 AND plate = $2 AND revoked_at IS NULL AND valid_until > NOW() ORDER BY valid_until DESC LIMIT 1`,
            [siteCode, event.plate],
          )
        ).rows[0] ?? null;
    // Kimlik bağlama (sürüm 3): kayıt SUNUCUNUN kendi aramasından türetilir (araç > misafir izni); kenarın daire ipucu yalnız ikisi de bulunamazsa
    // (araç bu arada silindi) ve daire bu siteye aitse kullanılır. Kişi adı satıra KOPYALANMAZ (okuma anında birleştirilir).
    let apartmentId = vehicle?.apartment_id ?? permit?.apartment_id ?? null;
    let identityKind = vehicle ? 'resident' : permit ? 'guest' : null;
    if (apartmentId === null && identityKind === null && event.apartmentHint !== null) {
      const hinted = await db.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 LIMIT 1`, [event.apartmentHint, siteCode]);
      if (hinted.rows[0]) {
        apartmentId = Number(hinted.rows[0].id);
        identityKind = event.identityKind;
      }
    }
    const personId = vehicle?.person_id ?? null;
    const inserted = await db.query(
      `INSERT INTO plate_events (site_code, device_id, plate, matched, vehicle_id, seen_at, gate_id, direction, decision_kind, edge_client_id, client_event_id, schema_version, confidence, reason,
                                apartment_id, person_id, identity_kind, gate_command)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
       ON CONFLICT (site_code, client_event_id) WHERE client_event_id IS NOT NULL DO NOTHING RETURNING id`,
      [
        siteCode,
        event.cameraId,
        event.plate,
        vehicle !== null,
        vehicle?.id ?? null,
        event.seenAt,
        gateId,
        direction,
        event.decision,
        client.id,
        event.eventId,
        event.schemaVersion,
        event.confidence,
        event.reason,
        apartmentId,
        personId,
        identityKind,
        event.gateCommand,
      ],
    );
    if (!inserted.rows[0]) {
      await db.query('ROLLBACK');
      return { ...envelope(), ok: true, duplicate: true };
    }
    const eventId = Number(inserted.rows[0].id);
    const reason =
      event.reason ?? (event.decision === 'acildi' ? (vehicle ? 'vehicle' : permit ? 'guest_permit' : 'edge_open') : event.decision === 'red' ? 'denied' : event.decision === 'kara_liste' ? 'blacklist' : 'not_registered');
    // Mevcut "Olaylar" akışı (plate_decisions) kenar olaylarını da gösterir.
    await db.query(
      `INSERT INTO plate_decisions (site_code, event_id, device_id, door_id, plate, confidence, decision, reason, vehicle_id, permit_id, auto_action, decided_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'none', $11) ON CONFLICT (event_id) DO NOTHING`,
      [siteCode, eventId, event.cameraId, gate?.door_id ?? null, event.plate, event.confidence, DECISION_TO_LEGACY[event.decision], reason, vehicle?.id ?? null, permit?.id ?? null, event.seenAt],
    );
    const transition = presenceTransition({ direction, decision: event.decision });
    const wasInside = existing?.inside === true;
    let inside = wasInside;
    let changed = false;
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
      if (applied.rows[0]) {
        inside = true;
        changed = !wasInside;
      }
    } else if (transition === 'leave' && existing) {
      const applied = await db.query(
        `UPDATE plate_presence SET inside = FALSE, since_at = $3, gate_id = $4, last_event_id = $5, updated_at = NOW()
          WHERE site_code = $1 AND plate = $2 AND since_at <= $3 RETURNING id`,
        [siteCode, event.plate, event.seenAt, gateId, eventId],
      );
      if (applied.rows[0]) {
        inside = false;
        changed = wasInside;
      }
    }
    await db.query(`UPDATE camera_devices SET last_event_at = NOW() WHERE id = $1`, [event.cameraId]);
    await db.query('COMMIT');
    // SmartKeyPass kapı günlüğü (sürüm 3): kenarın kapı komutu KABUL EDİLEN açılışları "Plaka ile" olarak düşer (komut reddedildiyse kapı açılmadı: yazılmaz).
    if (event.decision === 'acildi' && event.gateCommand !== 'failed') {
      await writePlateDoorLog({ writeDoorLog, siteCode, gate, plate: event.plate, identityKind, apartmentId, personId, seenAt: event.seenAt });
    }
    // Sakin bildirimi (A3): yalnız KAYITLI aracın içeride durumu gerçekten değiştiyse; en iyi çaba, yanıtı geciktirmez, hata olayı bozmaz.
    if (changed && vehicle && event.decision === 'acildi') void notifyResidentMovement({ siteCode, vehicle, direction, seenAt: event.seenAt });
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
    `UPDATE plate_edge_clients SET last_seen_at = NOW(), app_version = COALESCE($2, app_version), schema_version = $3, queue_depth = $4,
            recognition_ready = COALESCE($5::BOOLEAN, recognition_ready),
            recognition_note = CASE WHEN $5::BOOLEAN IS NULL THEN recognition_note ELSE $6::TEXT END
      WHERE id = $1`,
    [client.id, beat.appVersion, beat.schemaVersion, beat.queueDepth, beat.recognitionReady, beat.recognitionNote],
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
    // Sürüm 3: bekleyen uzaktan komutlar (GET /commands ile AYNI atomik talep; sürüm < 3 istemci komutu anlamaz, bu yüzden talep edilmez).
    commands: beat.schemaVersion >= V3_MIN_SCHEMA ? await claimCommands(client) : [],
  };
}

// --- commands / snapshot (sürüm 3) --------------------------------------------------------------------------------------------------

export async function commandsEdge(client) {
  return { ...envelope(), server_time: new Date().toISOString(), commands: await claimCommands(client) };
}

export async function commandResultEdge(client, rawId, body) {
  return { ...envelope(), ...(await completeCommand(client, rawId, body)) };
}

export async function snapshotEdge(client, rawCameraId, buffer, headers) {
  return { ...envelope(), ...(await storeSnapshot(client, rawCameraId, buffer, headers)) };
}
