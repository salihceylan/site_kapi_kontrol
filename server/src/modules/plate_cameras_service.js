// Plaka Tanıma sözleşme sürüm 3 (yönetici tarafı): kamera yönetimi (uygulamadan ekle / değiştir / sına), "ağda kamera ara" komutu, görüntü karoları,
// plakayla otomatik kapı açma DURUMU ve kenarın sync'te aldığı kamera tanımları.
//
// Sunucu yerel ağı taramaz ve RTSP izlemez: komutlar plate_edge_commands kuyruğuna yazılır, kenar (köprü) yerelde çalıştırıp sonucu bildirir
// (bkz. plate_edge_commands.js). Kamera parolası AES-256-GCM ile şifreli saklanır (device_integrations_service.encryptSecret); HİÇBİR yönetici yanıtında
// dönmez, yalnız kenarın sync yanıtında (TLS) açık iner. Görüntü: her kameranın yalnız SON karesi tutulur (tarihçe YOK, KVKK).

import { createHash, randomBytes } from 'node:crypto';
import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { decryptSecret, encryptSecret } from './device_integrations_service.js';
import { loadSiteSettings } from './plate_gates_service.js';
import { DEFAULT_SITE_SETTINGS, ageSecondsOf, assertCameraDirections, healthOf, parseSnapshotUpload } from './plate_gates_common.js';
import { iso, notFound } from './plate_recognition_common.js';
import {
  BRANDS,
  CAMERA_LIST_LIMIT,
  computeAutoOpen,
  parseCameraBody,
  resolveNewRtspUrl,
  retargetRtspUrl,
} from './plate_cameras_common.js';
import {
  SEEN_WRITE_THROTTLE_SECONDS,
  expireStaleCommands,
  findOpenCommand,
  housekeepCommands,
  insertCommand,
  latestCommand,
  loadEdgeClients,
  mapCommand,
  pickTargetEdge,
} from './plate_edge_commands.js';

const audit = (db, actor, action, siteCode, targetType, targetId, details) =>
  recordAudit(db, { actor, action, siteCode, targetType, targetId: String(targetId), details }, { inTransaction: db !== pool });

/** İzleyen işareti yazma sıklığı sınırı (saniye): her görüntü isteği satır yazmasın. İç performans ayarı, ürün eşiği değil. */
export const WATCH_WRITE_THROTTLE_SECONDS = 3;
/** İzleyen yok sayılana kadar geçecek süre = bu çarpan x boştaki görüntü aralığı (en az WATCH_MIN_WINDOW_SECONDS). */
export const WATCH_WINDOW_FACTOR = 2;
export const WATCH_MIN_WINDOW_SECONDS = 20;

const NEVER = Object.freeze({ state: 'hic_baglanmadi', color: 'gri' });
const brandLabel = (code) => BRANDS.find((b) => b.code === code)?.label ?? code;
const parsePositive = (raw, what, code) => {
  const id = Number(raw);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound(what, code);
  return id;
};
const idOrNull = (value) => (value === null || value === undefined ? null : Number(value));

// --- Kamera satırı --------------------------------------------------------------------------------------------------------------------

const CAMERA_SELECT = `
  SELECT c.id, c.name, c.brand, c.host, c.port, c.rtsp_url, c.username, (c.password_enc IS NOT NULL) AS has_password, c.is_active, c.last_event_at,
         c.probe_status, c.probe_message, c.probe_width, c.probe_height, c.probe_at,
         gc.gate_id, gc.direction AS gate_direction, g.name AS gate_name, g.direction_mode AS gate_mode,
         s.last_frame_at, s.last_read_at, s.reported_at, s.edge_client_id AS status_edge_id, sn.captured_at AS snapshot_at
    FROM camera_devices c
    LEFT JOIN plate_gate_cameras gc ON gc.camera_id = c.id
    LEFT JOIN plate_gates g ON g.id = gc.gate_id
    LEFT JOIN plate_camera_status s ON s.camera_id = c.id
    LEFT JOIN plate_camera_snapshots sn ON sn.camera_id = c.id AND sn.received_at > NOW() - make_interval(mins => $2)
   WHERE c.site_code = $1`;

function cameraStatus(row, thresholds, now) {
  if (!row.is_active) return { state: 'pasif', color: 'gri' };
  if (!row.reported_at) return NEVER;
  const age = ageSecondsOf(row.last_frame_at, now);
  return age === null ? { state: 'koptu', color: 'kirmizi' } : healthOf(age, thresholds);
}

export function mapCameraRow(row, thresholds, now = Date.now()) {
  const gateId = idOrNull(row.gate_id);
  return {
    id: Number(row.id),
    name: row.name,
    brand: row.brand,
    brand_label: brandLabel(row.brand),
    host: row.host,
    port: row.port ?? null,
    rtsp_url: row.rtsp_url ?? null,
    username: row.username ?? null,
    has_password: row.has_password === true,
    is_active: row.is_active !== false,
    managed: Boolean(row.rtsp_url) || (row.probe_status ?? 'none') !== 'none',
    gate: gateId === null ? null : { id: gateId, name: row.gate_name, direction_mode: row.gate_mode },
    direction: gateId === null ? null : row.gate_direction,
    status: cameraStatus(row, thresholds, now),
    last_frame_at: iso(row.last_frame_at),
    last_read_at: iso(row.last_read_at),
    last_event_at: iso(row.last_event_at),
    probe: {
      status: row.probe_status ?? 'none',
      message: row.probe_message ?? null,
      width: row.probe_width ?? null,
      height: row.probe_height ?? null,
      at: iso(row.probe_at),
    },
    snapshot: { available: Boolean(row.snapshot_at), captured_at: iso(row.snapshot_at) },
  };
}

const thresholdsOf = (settings) => ({ warn: settings.heartbeat_warn_seconds, crit: settings.heartbeat_crit_seconds });

async function loadCamera(db, siteCode, cameraId, settings) {
  const result = await db.query(`${CAMERA_SELECT} AND c.id = $3 LIMIT 1`, [siteCode, settings.snapshot_keep_minutes, cameraId]);
  const row = result.rows[0];
  if (!row) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
  return mapCameraRow(row, thresholdsOf(settings));
}

// --- İzleyen işareti ---------------------------------------------------------------------------------------------------------------

/** Bir yönetici görüntüleri istedi: kenar bir sonraki yüklemede `watched:true` alır ve sık gönderir. Yazma sıklığı sınırlıdır. */
export async function markWatched(db, siteCode) {
  await db.query(
    `INSERT INTO plate_snapshot_watch (site_code, watched_at) VALUES ($1, NOW())
     ON CONFLICT (site_code) DO UPDATE SET watched_at = NOW() WHERE plate_snapshot_watch.watched_at < NOW() - make_interval(secs => $2)`,
    [siteCode, WATCH_WRITE_THROTTLE_SECONDS],
  );
}

export const watchWindowSeconds = (settings) => Math.max(WATCH_MIN_WINDOW_SECONDS, settings.snapshot_idle_interval_seconds * WATCH_WINDOW_FACTOR);

// --- Genel bakış (ızgara) ------------------------------------------------------------------------------------------------------------

export async function getCamerasOverview({ siteCode, canWrite }) {
  const now = Date.now();
  const settings = await loadSiteSettings(pool, siteCode);
  const [cameras, gates, edges] = await Promise.all([
    pool.query(`${CAMERA_SELECT} ORDER BY c.id LIMIT ${CAMERA_LIST_LIMIT}`, [siteCode, settings.snapshot_keep_minutes]),
    pool.query(`SELECT id, name, direction_mode, is_active FROM plate_gates WHERE site_code = $1 ORDER BY sort_order, id`, [siteCode]),
    loadEdgeClients(pool, siteCode, settings, now),
  ]);
  if (canWrite) await markWatched(pool, siteCode);
  const thresholds = thresholdsOf(settings);
  const rows = cameras.rows.map((row) => mapCameraRow(row, thresholds, now));
  const boundActive = rows.filter((c) => c.is_active && c.gate !== null).length;
  return {
    server_time: new Date(now).toISOString(),
    cameras: rows,
    gates: gates.rows.map((g) => ({ id: Number(g.id), name: g.name, direction_mode: g.direction_mode, is_active: g.is_active !== false })),
    edge: { clients: edges, online: edges.some((e) => e.online), count: edges.length },
    auto_open: computeAutoOpen({ edges, boundActiveCameras: boundActive }),
    snapshot: {
      interval_seconds: settings.snapshot_interval_seconds,
      idle_interval_seconds: settings.snapshot_idle_interval_seconds,
      keep_minutes: settings.snapshot_keep_minutes,
    },
    brands: BRANDS.map((b) => ({ code: b.code, label: b.label, default_rtsp_path: b.default_rtsp_path })),
  };
}

// --- Kapı bağı ---------------------------------------------------------------------------------------------------------------------------

async function inCameraTransaction(siteCode, work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Kapı CRUD'u ile AYNI kilit: kapı-kamera bağı eşzamanlı değişmesin.
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`plate_gates:${siteCode}`]);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

async function applyGateAssignment(db, siteCode, cameraId, input) {
  const hasGate = input.gateId !== undefined;
  const hasDirection = input.direction !== undefined;
  if (!hasGate && !hasDirection) return;
  if (hasGate && input.gateId === null) {
    await db.query(`DELETE FROM plate_gate_cameras WHERE camera_id = $1 AND site_code = $2`, [cameraId, siteCode]);
    return;
  }
  const existing = (await db.query(`SELECT gate_id, direction FROM plate_gate_cameras WHERE camera_id = $1 AND site_code = $2`, [cameraId, siteCode])).rows[0] ?? null;
  const gateId = hasGate ? input.gateId : idOrNull(existing?.gate_id);
  if (gateId === null) throw new PlatformError(400, 'INVALID_BODY', 'Yön seçmek için önce bir kapı seçin.', { field: 'gate_id' });
  const gate = (await db.query(`SELECT id, direction_mode FROM plate_gates WHERE id = $1 AND site_code = $2`, [gateId, siteCode])).rows[0];
  if (!gate) throw notFound('Kapı', 'GATE_NOT_FOUND');
  const direction = input.direction ?? existing?.direction ?? 'auto';
  assertCameraDirections(gate.direction_mode, [{ direction }]);
  await db.query(
    `INSERT INTO plate_gate_cameras (site_code, gate_id, camera_id, direction) VALUES ($1, $2, $3, $4)
     ON CONFLICT (camera_id) DO UPDATE SET gate_id = EXCLUDED.gate_id, direction = EXCLUDED.direction`,
    [siteCode, gateId, cameraId, direction],
  );
}

// --- Sınama komutu ---------------------------------------------------------------------------------------------------------------------

/**
 * Kamera için `probe` komutu kuyruğa alır (kenar tanımlıysa). Birden çok kenar varsa: açıkça seçilen, yoksa kameranın son bildirildiği kenar; bulunamazsa
 * komut AÇILMAZ (null döner; uygulama "kenar seçip yeniden sına" der). Kamera `probe_status = 'pending'` olur. @returns {Promise<{ commandId: number, edge: object }|null>}
 */
async function queueProbe(db, { siteCode, cameraId, userCode, requestedEdgeId = null, strict = false }) {
  const settings = await loadSiteSettings(db, siteCode);
  const clients = await loadEdgeClients(db, siteCode, settings);
  // Tercih: açıkça seçilen kenar; yoksa kameranın en son durum bildirdiği kenar (hâlâ etkinse).
  const known = idOrNull((await db.query(`SELECT edge_client_id FROM plate_camera_status WHERE camera_id = $1`, [cameraId])).rows[0]?.edge_client_id);
  const preferred = clients.find((c) => c.id === known) ?? null;
  let edge = null;
  if (requestedEdgeId !== null) edge = strict ? pickTargetEdge(clients, requestedEdgeId) : clients.find((c) => c.id === requestedEdgeId) ?? null;
  else if (preferred) edge = preferred;
  else if (strict) edge = pickTargetEdge(clients, null);
  else if (clients.length === 1) [edge] = clients;
  if (!edge) return null;
  await expireStaleCommands(db, siteCode, settings.command_ttl_seconds);
  const open = await findOpenCommand(db, { edgeClientId: edge.id, kind: 'probe', cameraId });
  const command = open ?? (await insertCommand(db, { siteCode, edgeClientId: edge.id, kind: 'probe', payload: {}, cameraId, userCode }));
  await db.query(
    `UPDATE camera_devices SET probe_status = 'pending', probe_message = NULL, probe_width = NULL, probe_height = NULL, probe_at = NULL WHERE id = $1 AND site_code = $2`,
    [cameraId, siteCode],
  );
  return { commandId: Number(command.id), edge, command, settings, edges: clients };
}

const edgeBrief = (edge) => (edge ? { id: edge.id, name: edge.name, online: edge.online, last_seen_at: edge.last_seen_at } : null);

// --- Kamera ekle / değiştir / sına -----------------------------------------------------------------------------------------------

export async function createCamera({ siteCode, body, authUser }) {
  const input = parseCameraBody(body);
  const requestedEdgeId = Number.isSafeInteger(Number(body.edge_client_id)) && Number(body.edge_client_id) > 0 ? Number(body.edge_client_id) : null;
  const rtspUrl = resolveNewRtspUrl({ brand: input.brand, host: input.host, port: input.port ?? null, rtspUrl: input.rtspUrl, rtspPath: input.rtspPath });
  const actor = actorFromAuthUser(authUser);
  // Olay belirteci bu akışta KULLANILMAZ (olayları kenar anahtarıyla gelir); NOT NULL sütun için rastgele özet yazılır, düz hâli hiçbir yerde tutulmaz.
  const tokenHash = createHash('sha256').update(randomBytes(24).toString('hex')).digest('hex');
  const cameraId = await inCameraTransaction(siteCode, async (client) => {
    const row = await client.query(
      `INSERT INTO camera_devices (site_code, brand, name, host, port, username, password_enc, token_hash, rtsp_url, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id`,
      [siteCode, input.brand, input.name, input.host, input.port ?? null, input.username ?? null, input.password ? encryptSecret(input.password) : null, tokenHash, rtspUrl, actor.userCode],
    );
    const id = Number(row.rows[0].id);
    await applyGateAssignment(client, siteCode, id, input);
    await audit(client, authUser, 'plate.camera_created', siteCode, 'camera_device', id, { brand: input.brand, gate_id: input.gateId ?? null, rtsp: Boolean(rtspUrl) });
    return id;
  });
  const queued = await queueProbe(pool, { siteCode, cameraId, userCode: actor.userCode, requestedEdgeId });
  const settings = queued?.settings ?? (await loadSiteSettings(pool, siteCode));
  return { camera: await loadCamera(pool, siteCode, cameraId, settings), probe_command_id: queued?.commandId ?? null, edge: edgeBrief(queued?.edge) };
}

export async function updateCamera({ siteCode, rawId, body, authUser }) {
  const cameraId = parsePositive(rawId, 'Kamera', 'CAMERA_NOT_FOUND');
  const input = parseCameraBody(body, { partial: true });
  const requestedEdgeId = Number.isSafeInteger(Number(body.edge_client_id)) && Number(body.edge_client_id) > 0 ? Number(body.edge_client_id) : null;
  const actor = actorFromAuthUser(authUser);
  const needsProbe = await inCameraTransaction(siteCode, async (client) => {
    const found = (await client.query(`SELECT id, brand, host, port, rtsp_url, is_active FROM camera_devices WHERE id = $1 AND site_code = $2 FOR UPDATE`, [cameraId, siteCode])).rows[0];
    if (!found) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
    const sets = [];
    const params = [cameraId, siteCode];
    const set = (column, value) => {
      params.push(value);
      sets.push(`${column} = $${params.length}`);
    };
    const host = input.host ?? found.host;
    const port = input.port !== undefined ? input.port : found.port;
    let rtspUrl;
    if (input.rtspUrl !== undefined) rtspUrl = input.rtspUrl;
    else if (input.rtspPath) rtspUrl = resolveNewRtspUrl({ brand: input.brand ?? found.brand, host, port, rtspUrl: null, rtspPath: input.rtspPath });
    else if ((input.host !== undefined || input.port !== undefined) && found.rtsp_url) rtspUrl = retargetRtspUrl(found.rtsp_url, host, port);
    if (input.name !== undefined) set('name', input.name);
    if (input.brand !== undefined) set('brand', input.brand);
    if (input.host !== undefined) set('host', input.host);
    if (input.port !== undefined) set('port', input.port);
    if (rtspUrl !== undefined) set('rtsp_url', rtspUrl);
    if (input.username !== undefined) set('username', input.username);
    if (input.password !== undefined) set('password_enc', input.password === null ? null : encryptSecret(input.password));
    if (input.isActive !== undefined) set('is_active', input.isActive);
    if (sets.length) await client.query(`UPDATE camera_devices SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);
    if (input.isActive === false) await client.query(`DELETE FROM plate_camera_snapshots WHERE camera_id = $1`, [cameraId]); // KVKK: pasif kameranın son karesi kalmaz
    await applyGateAssignment(client, siteCode, cameraId, input);
    await audit(client, authUser, 'plate.camera_updated', siteCode, 'camera_device', cameraId, {
      changed: Object.keys(input).filter((k) => k !== 'hasAddressInput' && k !== 'password'),
      password_changed: input.password !== undefined,
    });
    const connectionChanged =
      input.host !== undefined || input.port !== undefined || input.rtspUrl !== undefined || input.rtspPath !== undefined || input.username !== undefined || input.password !== undefined;
    return connectionChanged && (input.isActive ?? found.is_active) !== false;
  });
  const queued = needsProbe ? await queueProbe(pool, { siteCode, cameraId, userCode: actor.userCode, requestedEdgeId }) : null;
  const settings = queued?.settings ?? (await loadSiteSettings(pool, siteCode));
  return { camera: await loadCamera(pool, siteCode, cameraId, settings), probe_command_id: queued?.commandId ?? null, edge: edgeBrief(queued?.edge) };
}

export async function probeCamera({ siteCode, rawId, body = {}, authUser }) {
  const cameraId = parsePositive(rawId, 'Kamera', 'CAMERA_NOT_FOUND');
  const requestedEdgeId = Number.isSafeInteger(Number(body.edge_client_id)) && Number(body.edge_client_id) > 0 ? Number(body.edge_client_id) : null;
  const found = (await pool.query(`SELECT id, is_active FROM camera_devices WHERE id = $1 AND site_code = $2`, [cameraId, siteCode])).rows[0];
  if (!found) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
  if (found.is_active === false) throw new PlatformError(409, 'CAMERA_INACTIVE', 'Kamera pasif.');
  const actor = actorFromAuthUser(authUser);
  const queued = await queueProbe(pool, { siteCode, cameraId, userCode: actor.userCode, requestedEdgeId, strict: true });
  await audit(pool, authUser, 'plate.camera_probe_requested', siteCode, 'camera_device', cameraId, { command_id: queued.commandId });
  const edgeById = new Map(queued.edges.map((e) => [e.id, e]));
  return { command: mapCommand(queued.command, { edgeById, ttlSeconds: queued.settings.command_ttl_seconds }) };
}

// --- Ağda kamera ara --------------------------------------------------------------------------------------------------------------------

export async function startDiscovery({ siteCode, body = {}, authUser }) {
  const requested = Number(body.edge_client_id);
  const requestedEdgeId = Number.isSafeInteger(requested) && requested > 0 ? requested : null;
  const actor = actorFromAuthUser(authUser);
  const settings = await loadSiteSettings(pool, siteCode);
  const clients = await loadEdgeClients(pool, siteCode, settings);
  const edge = pickTargetEdge(clients, requestedEdgeId);
  await expireStaleCommands(pool, siteCode, settings.command_ttl_seconds);
  const open = await findOpenCommand(pool, { edgeClientId: edge.id, kind: 'discover' });
  const row = open ?? (await insertCommand(pool, { siteCode, edgeClientId: edge.id, kind: 'discover', payload: {}, userCode: actor.userCode }));
  if (!open) await audit(pool, authUser, 'plate.discovery_requested', siteCode, 'plate_edge_client', edge.id, { command_id: Number(row.id) });
  const edgeById = new Map(clients.map((c) => [c.id, c]));
  return { command: mapCommand(row, { edgeById, ttlSeconds: settings.command_ttl_seconds }), reused: Boolean(open) };
}

export async function getLatestDiscovery({ siteCode }) {
  const settings = await loadSiteSettings(pool, siteCode);
  const clients = await loadEdgeClients(pool, siteCode, settings);
  await expireStaleCommands(pool, siteCode, settings.command_ttl_seconds);
  const row = await latestCommand(pool, siteCode, 'discover');
  const edgeById = new Map(clients.map((c) => [c.id, c]));
  const command = row ? mapCommand(row, { edgeById, ttlSeconds: settings.command_ttl_seconds }) : null;
  const edge = command?.edge ?? (clients.length === 1 ? edgeBrief(clients[0]) : null);
  return { command, edge };
}

// --- Görüntü karoları --------------------------------------------------------------------------------------------------------------------

/** Kenardan gelen son kare (üzerine yazılır). Yanıt: izleyen var mı + bir sonraki gönderim aralığı (saniye). Eski kare yeni kareyi ezmez. */
export async function storeSnapshot(client, rawCameraId, buffer, headers, db = pool) {
  const cameraId = parsePositive(rawCameraId, 'Kamera', 'CAMERA_NOT_FOUND');
  const upload = parseSnapshotUpload(buffer, headers);
  const camera = (await db.query(`SELECT id, is_active FROM camera_devices WHERE id = $1 AND site_code = $2`, [cameraId, client.siteCode])).rows[0];
  if (!camera) throw notFound('Kamera', 'CAMERA_NOT_FOUND');
  if (camera.is_active === false) throw new PlatformError(409, 'CAMERA_INACTIVE', 'Kamera pasif; görüntü kabul edilmez.');
  const settings = await loadSiteSettings(db, client.siteCode);
  await db.query(
    `INSERT INTO plate_camera_snapshots (camera_id, site_code, edge_client_id, jpeg, byte_size, width, height, captured_at, received_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
     ON CONFLICT (camera_id) DO UPDATE SET jpeg = EXCLUDED.jpeg, byte_size = EXCLUDED.byte_size, width = EXCLUDED.width, height = EXCLUDED.height,
       captured_at = EXCLUDED.captured_at, edge_client_id = EXCLUDED.edge_client_id, received_at = NOW()
     WHERE plate_camera_snapshots.captured_at <= EXCLUDED.captured_at`,
    [cameraId, client.siteCode, client.id, buffer, upload.byteSize, upload.width, upload.height, upload.capturedAt],
  );
  await db.query(
    `UPDATE plate_edge_clients SET last_seen_at = NOW() WHERE id = $1 AND (last_seen_at IS NULL OR last_seen_at < NOW() - make_interval(secs => $2))`,
    [client.id, SEEN_WRITE_THROTTLE_SECONDS],
  );
  const watched = (
    await db.query(`SELECT 1 FROM plate_snapshot_watch WHERE site_code = $1 AND watched_at > NOW() - make_interval(secs => $2)`, [client.siteCode, watchWindowSeconds(settings)])
  ).rows[0];
  return { ok: true, watched: Boolean(watched), next_seconds: watched ? settings.snapshot_interval_seconds : settings.snapshot_idle_interval_seconds };
}

/** Yönetici ucu: kameranın son karesi (site kapsamlı, etkin kamera, saklama süresi içinde) ya da 404 NO_SNAPSHOT. */
export async function readSnapshot({ siteCode, rawId }) {
  const cameraId = parsePositive(rawId, 'Kamera', 'CAMERA_NOT_FOUND');
  const settings = await loadSiteSettings(pool, siteCode);
  const row = (
    await pool.query(
      `SELECT sn.jpeg, sn.captured_at FROM plate_camera_snapshots sn
         INNER JOIN camera_devices c ON c.id = sn.camera_id AND c.site_code = sn.site_code
        WHERE sn.camera_id = $1 AND sn.site_code = $2 AND c.is_active AND sn.received_at > NOW() - make_interval(mins => $3)`,
      [cameraId, siteCode, settings.snapshot_keep_minutes],
    )
  ).rows[0];
  await markWatched(pool, siteCode);
  if (!row) throw new PlatformError(404, 'NO_SNAPSHOT', 'Bu kamera için güncel görüntü yok.');
  const capturedAt = new Date(row.captured_at);
  return { jpeg: row.jpeg, capturedAt, etag: `"${capturedAt.getTime()}"` };
}

// --- Bakım -------------------------------------------------------------------------------------------------------------------------------

/** Bakım turu: saklama süresi geçmiş / pasif kamera kareleri silinir (KVKK), komutların süresi dolar, eski komut kayıtları silinir. */
export async function runCamerasHousekeeping(db = pool) {
  const stale = await db.query(
    `DELETE FROM plate_camera_snapshots sn
      WHERE sn.received_at < NOW() - make_interval(mins => COALESCE((SELECT s.snapshot_keep_minutes FROM plate_site_settings s WHERE s.site_code = sn.site_code), $1))
         OR NOT EXISTS (SELECT 1 FROM camera_devices c WHERE c.id = sn.camera_id AND c.is_active)`,
    [DEFAULT_SITE_SETTINGS.snapshot_keep_minutes],
  );
  const commands = await housekeepCommands(db, { defaultTtlSeconds: DEFAULT_SITE_SETTINGS.command_ttl_seconds });
  return { snapshotsRemoved: stale.rowCount ?? 0, commandsExpired: commands.expired, commandsRemoved: commands.removed };
}

// --- Kenarın sync'te aldığı kamera tanımları --------------------------------------------------------------------------------

/** Sync `config.cameras`: etkin, RTSP adresi olan kameralar. Parola burada (TLS, no-store) açık iner; çözülemezse null. */
export async function loadEdgeCameras(db, siteCode) {
  const result = await db.query(
    `SELECT c.id, c.name, c.brand, c.host, c.port, c.rtsp_url, c.username, c.password_enc, gc.gate_id, gc.direction
       FROM camera_devices c LEFT JOIN plate_gate_cameras gc ON gc.camera_id = c.id
      WHERE c.site_code = $1 AND c.is_active AND c.rtsp_url IS NOT NULL ORDER BY c.id`,
    [siteCode],
  );
  return result.rows.map((row) => {
    let password = null;
    if (row.password_enc) {
      try {
        password = decryptSecret(row.password_enc);
      } catch {
        password = null;
      }
    }
    return {
      camera_id: Number(row.id),
      name: row.name,
      brand: row.brand,
      host: row.host,
      port: row.port ?? null,
      rtsp_url: row.rtsp_url,
      username: row.username ?? null,
      password,
      gate_id: idOrNull(row.gate_id),
      direction: row.gate_id === null || row.gate_id === undefined ? null : row.direction,
    };
  });
}
