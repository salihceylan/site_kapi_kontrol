// Plaka Tanıma sözleşme sürüm 3: UZAKTAN KOMUT KUYRUĞU ("ağda kamera ara", "kamerayı sına").
//
// Sunucu yerel ağı taramaz ve RTSP izlemez; kenar PC köprüdür. Yönetici uygulamadan komut verir -> plate_edge_commands (site + kenar istemci hedefli) ->
// kenar `GET /commands` ya da kalp atışı yanıtıyla ATOMİK talep eder (pending -> running; bir komut iki kez verilmez) -> yerelde çalıştırır -> sonucu
// `POST /commands/:id/result` ile bildirir. Komut ömrü site ayarıdır (command_ttl_seconds): alınmayan / tamamlanmayan komut `expired` olur; kenar PC
// çevrimdışıysa uygulama bunu dürüstçe söyler (sahte başarı yok).
//
// Kamera parolası kuyruğa DÜZ yazılmaz: probe komutunun yükü yalnız camera_id taşır; kenara verilirken şifre çözülüp yanıta konur (kayıtlı kalmaz).

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { decryptSecret } from './device_integrations_service.js';
import { loadSiteSettings } from './plate_gates_service.js';
import { ageSecondsOf, healthOf, parseCommandResult } from './plate_gates_common.js';
import { isOnlineColor } from './plate_cameras_common.js';
import { iso, notFound } from './plate_recognition_common.js';

/** Bir talepte kenara verilen en çok komut (toplu işlem boyutu; ürün sınırı değil). */
export const CLAIM_BATCH = 5;
/** Tamamlanmış komut kayıtlarının tutulma günü (bakım turu siler; keşif sonucu yerel ağ adresleri taşır). */
export const COMMAND_HISTORY_DAYS = 7;
/** `last_seen_at` yazma sıklığı sınırı: hızlı komut yoklaması her istekte satır yazmasın. */
export const SEEN_WRITE_THROTTLE_SECONDS = 10;

const NEVER = Object.freeze({ state: 'hic_baglanmadi', color: 'gri' });

/** Sitenin etkin kenar istemcileri, kalp atışı rozeti ve çevrimiçi bilgisiyle. */
export async function loadEdgeClients(db, siteCode, settings, now = Date.now()) {
  const result = await db.query(
    `SELECT id, name, last_seen_at, recognition_ready, recognition_note, app_version, schema_version
       FROM plate_edge_clients WHERE site_code = $1 AND is_active AND revoked_at IS NULL ORDER BY id`,
    [siteCode],
  );
  const thresholds = { warn: settings.heartbeat_warn_seconds, crit: settings.heartbeat_crit_seconds };
  return result.rows.map((row) => {
    const status = row.last_seen_at ? healthOf(ageSecondsOf(row.last_seen_at, now), thresholds) : NEVER;
    return {
      id: Number(row.id),
      name: row.name,
      status,
      online: isOnlineColor(status.color),
      last_seen_at: iso(row.last_seen_at),
      recognition_ready: row.recognition_ready === null || row.recognition_ready === undefined ? null : row.recognition_ready === true,
      recognition_note: row.recognition_note ?? null,
      app_version: row.app_version ?? null,
      schema_version: row.schema_version ?? null,
    };
  });
}

/** Komut verilecek kenar istemci: açıkça seçilen, yoksa tek etkin olan; hiç yoksa 409, birden çoksa 400 (seçim gerekir). */
export function pickTargetEdge(clients, requestedId) {
  if (requestedId !== null && requestedId !== undefined) {
    const found = clients.find((c) => c.id === requestedId);
    if (!found) throw notFound('Kenar istemci', 'EDGE_CLIENT_NOT_FOUND');
    return found;
  }
  if (!clients.length) {
    throw new PlatformError(409, 'NO_EDGE_CLIENT', 'Bu site için kenar uygulama tanımlı değil. Plaka Tanıma > Geçiş noktaları bölümünden kenar istemci ekleyin.');
  }
  if (clients.length > 1) {
    throw new PlatformError(400, 'EDGE_CLIENT_REQUIRED', 'Birden çok kenar istemci var; komutun hangisine verileceğini seçin.', {
      clients: clients.map((c) => ({ id: c.id, name: c.name, online: c.online })),
    });
  }
  return clients[0];
}

export function mapCommand(row, { edgeById = new Map(), ttlSeconds }) {
  const edge = edgeById.get(Number(row.edge_client_id)) ?? null;
  const createdMs = new Date(row.created_at).getTime();
  return {
    id: Number(row.id),
    kind: row.kind,
    status: row.status,
    camera_id: row.camera_id === null || row.camera_id === undefined ? null : Number(row.camera_id),
    created_at: iso(row.created_at),
    picked_at: iso(row.picked_at),
    completed_at: iso(row.completed_at),
    expires_at: Number.isNaN(createdMs) ? null : new Date(createdMs + ttlSeconds * 1000).toISOString(),
    ttl_seconds: ttlSeconds,
    message: row.message ?? null,
    result: row.result ?? null,
    edge: edge ? { id: edge.id, name: edge.name, online: edge.online, last_seen_at: edge.last_seen_at } : null,
    waiting_offline: row.status === 'pending' && !(edge?.online === true),
  };
}

// --- Süre dolumu -------------------------------------------------------------------------------------------------------------------

const EXPIRED_MESSAGE = 'Kenar uygulama komutu zamanında tamamlamadı (süre doldu).';

/** Ömrü dolan bekleyen / çalışan komutlar `expired` olur; sınaması bekleyen kameranın durumu "başarısız" yapılır. @returns {Promise<number>} süresi dolan komut sayısı */
export async function expireStaleCommands(db, siteCode, ttlSeconds) {
  const expired = await db.query(
    `UPDATE plate_edge_commands SET status = 'expired', completed_at = NOW(), message = COALESCE(message, $3)
      WHERE site_code = $1 AND status IN ('pending', 'running') AND created_at < NOW() - make_interval(secs => $2)
      RETURNING kind, camera_id`,
    [siteCode, ttlSeconds, EXPIRED_MESSAGE],
  );
  const cameraIds = expired.rows.filter((r) => r.kind === 'probe' && r.camera_id !== null && r.camera_id !== undefined).map((r) => Number(r.camera_id));
  if (cameraIds.length) {
    await db.query(
      `UPDATE camera_devices SET probe_status = 'failed', probe_message = $3, probe_at = NOW()
        WHERE site_code = $1 AND id = ANY($2::BIGINT[]) AND probe_status = 'pending'`,
      [siteCode, cameraIds, 'Kenar uygulama sınamayı zamanında yapmadı (kenar PC çevrimdışı olabilir).'],
    );
  }
  return expired.rows.length;
}

/** Bakım turu (tüm siteler): süresi dolanları kapatır, eski tamamlanmış kayıtları siler. */
export async function housekeepCommands(db, { defaultTtlSeconds }) {
  const expired = await db.query(
    `UPDATE plate_edge_commands c SET status = 'expired', completed_at = NOW(), message = COALESCE(c.message, $2)
      WHERE c.status IN ('pending', 'running')
        AND c.created_at < NOW() - make_interval(secs => COALESCE((SELECT s.command_ttl_seconds FROM plate_site_settings s WHERE s.site_code = c.site_code), $1))
      RETURNING c.kind, c.camera_id, c.site_code`,
    [defaultTtlSeconds, EXPIRED_MESSAGE],
  );
  for (const row of expired.rows) {
    if (row.kind !== 'probe' || row.camera_id === null || row.camera_id === undefined) continue;
    await db.query(
      `UPDATE camera_devices SET probe_status = 'failed', probe_message = $3, probe_at = NOW() WHERE site_code = $1 AND id = $2 AND probe_status = 'pending'`,
      [row.site_code, row.camera_id, 'Kenar uygulama sınamayı zamanında yapmadı (kenar PC çevrimdışı olabilir).'],
    );
  }
  const removed = await db.query(
    `DELETE FROM plate_edge_commands WHERE completed_at IS NOT NULL AND completed_at < NOW() - make_interval(days => $1)`,
    [COMMAND_HISTORY_DAYS],
  );
  return { expired: expired.rows.length, removed: removed.rowCount ?? 0 };
}

// --- Komut açma (yönetici tarafı) -------------------------------------------------------------------------------------------

export async function findOpenCommand(db, { edgeClientId, kind, cameraId = null }) {
  const result = await db.query(
    `SELECT * FROM plate_edge_commands
      WHERE edge_client_id = $1 AND kind = $2 AND status IN ('pending', 'running') AND camera_id IS NOT DISTINCT FROM $3::BIGINT
      ORDER BY id DESC LIMIT 1`,
    [edgeClientId, kind, cameraId],
  );
  return result.rows[0] ?? null;
}

export async function insertCommand(db, { siteCode, edgeClientId, kind, payload = {}, cameraId = null, userCode = null }) {
  const result = await db.query(
    `INSERT INTO plate_edge_commands (site_code, edge_client_id, kind, payload, camera_id, requested_by)
     VALUES ($1, $2, $3, $4::jsonb, $5, $6) RETURNING *`,
    [siteCode, edgeClientId, kind, JSON.stringify(payload), cameraId, userCode],
  );
  return result.rows[0];
}

/** Son komut (türe göre) ya da null. */
export async function latestCommand(db, siteCode, kind) {
  const result = await db.query(`SELECT * FROM plate_edge_commands WHERE site_code = $1 AND kind = $2 ORDER BY id DESC LIMIT 1`, [siteCode, kind]);
  return result.rows[0] ?? null;
}

// --- Kenar tarafı: talep ve sonuç --------------------------------------------------------------------------------------------

async function probePayload(db, siteCode, row) {
  const camera = (
    await db.query(
      `SELECT id, name, brand, host, port, rtsp_url, username, password_enc, is_active FROM camera_devices WHERE id = $1 AND site_code = $2`,
      [row.camera_id, siteCode],
    )
  ).rows[0];
  if (!camera || !camera.is_active) return null;
  let password = null;
  if (camera.password_enc) {
    try {
      password = decryptSecret(camera.password_enc);
    } catch {
      password = null; // şifre çözülemezse kenar parolasız dener; sonuç dürüst hata verir
    }
  }
  return {
    camera_id: Number(camera.id),
    name: camera.name,
    brand: camera.brand,
    host: camera.host,
    port: camera.port ?? null,
    rtsp_url: camera.rtsp_url ?? null,
    username: camera.username ?? null,
    password,
  };
}

/**
 * Kenar istemcinin bekleyen komutlarını ATOMİK talep eder (FOR UPDATE SKIP LOCKED): `GET /commands` ve kalp atışı yanıtı aynı işlevi kullanır, bir komut
 * iki kez verilmez. Probe yükü burada (parola çözülerek) üretilir, DB'de düz kalmaz. Kamerası bulunamayan probe komutu hemen `failed` yapılır.
 * @returns {Promise<Array<{ id: number, kind: string, created_at: string|null, payload: object }>>}
 */
export async function claimCommands(client, db = pool) {
  const settings = await loadSiteSettings(db, client.siteCode);
  await expireStaleCommands(db, client.siteCode, settings.command_ttl_seconds);
  await db.query(
    `UPDATE plate_edge_clients SET last_seen_at = NOW()
      WHERE id = $1 AND (last_seen_at IS NULL OR last_seen_at < NOW() - make_interval(secs => $2))`,
    [client.id, SEEN_WRITE_THROTTLE_SECONDS],
  );
  const claimed = await db.query(
    `UPDATE plate_edge_commands SET status = 'running', picked_at = NOW()
      WHERE id IN (
        SELECT id FROM plate_edge_commands
         WHERE edge_client_id = $1 AND site_code = $2 AND status = 'pending'
         ORDER BY id LIMIT $3 FOR UPDATE SKIP LOCKED
      )
      RETURNING id, kind, payload, camera_id, created_at`,
    [client.id, client.siteCode, CLAIM_BATCH],
  );
  const out = [];
  for (const row of claimed.rows.sort((a, b) => Number(a.id) - Number(b.id))) {
    let payload = row.payload ?? {};
    if (row.kind === 'probe') {
      const enriched = await probePayload(db, client.siteCode, row);
      if (!enriched) {
        await db.query(`UPDATE plate_edge_commands SET status = 'failed', completed_at = NOW(), message = $2 WHERE id = $1`, [row.id, 'Kamera bulunamadı ya da pasif.']);
        continue;
      }
      payload = enriched;
    }
    out.push({ id: Number(row.id), kind: row.kind, created_at: iso(row.created_at), payload });
  }
  return out;
}

/**
 * Sonuç bildirimi (idempotent): zaten tamamlanmışsa `{ ok, duplicate }`; süresi dolmuşsa 409 COMMAND_EXPIRED (KALICI: yeniden deneme); talep edilmemişse
 * 409 COMMAND_NOT_RUNNING. probe sonucu kameranın sınama sütunlarına yazılır (ONVIF ile çözülen kimliksiz RTSP adresi kamerada boşsa kaydedilir).
 */
export async function completeCommand(client, rawId, body, db = pool) {
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound('Komut', 'COMMAND_NOT_FOUND');
  const conn = await db.connect();
  try {
    await conn.query('BEGIN');
    const found = await conn.query(`SELECT id, kind, status, camera_id FROM plate_edge_commands WHERE id = $1 AND site_code = $2 AND edge_client_id = $3 FOR UPDATE`, [
      id,
      client.siteCode,
      client.id,
    ]);
    const row = found.rows[0];
    if (!row) throw notFound('Komut', 'COMMAND_NOT_FOUND');
    const parsed = parseCommandResult(body, row.kind);
    if (row.status === 'done' || row.status === 'failed') {
      await conn.query('ROLLBACK');
      return { ok: true, duplicate: true };
    }
    if (row.status === 'expired') throw new PlatformError(409, 'COMMAND_EXPIRED', 'Komutun süresi dolmuş.');
    if (row.status !== 'running') throw new PlatformError(409, 'COMMAND_NOT_RUNNING', 'Komut henüz talep edilmemiş.');
    let message = parsed.message;
    if (row.kind === 'probe' && row.camera_id !== null && row.camera_id !== undefined) {
      const probe = parsed.status === 'done' ? parsed.result : { ok: false, width: null, height: null, reason: null, message: parsed.message, rtsp_url: null };
      const ok = probe.ok === true;
      message = probe.message ?? parsed.message;
      await conn.query(
        `UPDATE camera_devices SET probe_status = $3, probe_message = $4, probe_width = $5, probe_height = $6, probe_at = NOW(), rtsp_url = COALESCE(rtsp_url, $7)
          WHERE id = $1 AND site_code = $2`,
        [row.camera_id, client.siteCode, ok ? 'ok' : 'failed', ok ? null : message ?? 'Sınama başarısız.', ok ? probe.width : null, ok ? probe.height : null, probe.rtsp_url],
      );
    }
    await conn.query(`UPDATE plate_edge_commands SET status = $2, message = $3, result = $4::jsonb, completed_at = NOW() WHERE id = $1`, [
      id,
      parsed.status,
      message,
      parsed.result === null ? null : JSON.stringify(parsed.result),
    ]);
    await conn.query('COMMIT');
    return { ok: true, duplicate: false };
  } catch (error) {
    await conn.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    conn.release();
  }
}
