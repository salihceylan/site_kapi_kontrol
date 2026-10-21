// Kamera (CCTV) baglantisi is mantigi. Sozlesme: docs/PLATFORM_KAMERA_CCTV.md.
//
// Video sunucuda SAKLANMAZ ve kayit sistemine sunucudan baglanilmaz (kameralar sitenin yerel agindadir). Yalniz: kamera kaydi, kayit-izleme baglanti
// sablonu (https), istege bagli herkese acik https anlik goruntu adresi ve kapi eslemesi saklanir. Kapi gunlugu (door_access_logs) SALT OKUNUR kullanilir.
// Kimlik bilgisi (kullanici / parola) API yanitlarinda ASLA donmez; parola AES-256-GCM ile sifreli (device_integrations_service.encryptSecret).
// Her anlik goruntu ve her kayit baglantisi acma denetim kaydina yazilir (kamera goruntusu kisisel veridir).

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { recordAudit } from './audit_service.js';
import { decryptSecret, encryptSecret } from './device_integrations_service.js';
import { fetchSnapshot, parseSnapshotUrl } from './cctv_snapshot.js';

export const CCTV_MODULE = 'cctv_link';
export const CAMERA_KINDS = Object.freeze(['ip_camera', 'nvr_channel']);
export const LIMITS = Object.freeze({ cameras: 50, doorsPerCamera: 20, events: 100, eventsDefault: 30 });
export const MAX_BODY_BYTES = 4096;
export const CLIP_BEFORE_SECONDS = 30;
export const CLIP_AFTER_SECONDS = 30;
export const SNAPSHOT_UNAVAILABLE_MESSAGE = 'Bu kameraya sunucudan ulaşılamıyor; kayıt bağlantısını kullanın.';
export const PLACEHOLDERS = Object.freeze(['start', 'end', 'start_unix', 'end_unix', 'channel', 'camera']);
export const KVKK_NOTE = 'Kamera görüntüsü kişisel veridir; aydınlatma ve saklama sorumluluğu site yönetimindedir.';

const invalid = (field, message) => new PlatformError(400, 'INVALID_FIELD', message, { field });
const notFound = (what = 'Kayıt') => new PlatformError(404, 'NOT_FOUND', `${what} bulunamadı ya da erişiminiz yok.`);
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Kamera (CCTV) Bağlantısı modülü kapalı.', { module: CCTV_MODULE });
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');
export const snapshotUnavailable = () => new PlatformError(424, 'SNAPSHOT_UNAVAILABLE', SNAPSHOT_UNAVAILABLE_MESSAGE);

// --- Girdi yardimcilari ---------------------------------------------------------------------------------------------

// eslint-disable-next-line no-control-regex
const CONTROL = /[\x00-\x1f\x7f]+/g;
const clean = (v) => (typeof v === 'string' ? v.replace(CONTROL, ' ').replace(/\s+/g, ' ').trim() : v);

export function text(value, field, label, max, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  if (typeof value !== 'string') throw invalid(field, `${label} geçersiz.`);
  const out = clean(value);
  if (out === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  if (out.length > max) throw invalid(field, `${label} en çok ${max} karakter olabilir.`);
  return out;
}

/** Kanal / kamera kimligi: kayit sistemindeki kanal numarasi ya da adi; adrese kodlanarak girer. */
function channelText(value) {
  const out = text(value, 'channel', 'Kanal', 40);
  if (out !== null && !/^[A-Za-z0-9._-]+$/.test(out)) throw invalid('channel', 'Kanal yalnız harf, rakam, nokta, tire ve alt çizgi içerebilir.');
  return out;
}

/** Ham URL metni: bosluk / kontrol karakteri yok, uzunluk siniri. */
function rawUrlText(value, field, label, max) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw invalid(field, `${label} geçersiz.`);
  const out = value.trim();
  if (out === '') return null;
  if (out.length > max) throw invalid(field, `${label} en çok ${max} karakter olabilir.`);
  // eslint-disable-next-line no-control-regex
  if (/[\s\x00-\x1f\x7f]/.test(out)) throw invalid(field, `${label} boşluk ya da denetim karakteri içeremez.`);
  return out;
}

const SAMPLE = Object.freeze({ start: '2026-01-01T00:00:00Z', end: '2026-01-01T00:01:00Z', start_unix: '1767225600', end_unix: '1767225660', channel: '1', camera: 'kamera' });

/** Kayit-izleme baglanti sablonu: https, kullanici bilgisi yok, bilinen yer tutucular, ana bilgisayar sabit (yer tutucu yalniz yol / sorguda). */
export function parseClipTemplate(value) {
  const out = rawUrlText(value, 'clip_url_template', 'Kayıt bağlantı şablonu', 1000);
  if (out === null) return null;
  const unknown = [...out.matchAll(/\{([^{}]*)\}/g)].map((m) => m[1]).filter((name) => !PLACEHOLDERS.includes(name));
  if (unknown.length > 0) throw invalid('clip_url_template', `Bilinmeyen yer tutucu: {${unknown[0]}}. Kullanılabilir: ${PLACEHOLDERS.map((p) => `{${p}}`).join(' ')}.`);
  const stripped = out.replace(/\{[a-z_]+\}/g, '');
  if (/[{}]/.test(stripped)) throw invalid('clip_url_template', 'Kayıt bağlantı şablonunda süslü parantez yer tutucu dışında kullanılamaz.');
  const authority = /^https:\/\/([^/?#]*)/i.exec(out);
  if (!authority) throw invalid('clip_url_template', 'Kayıt bağlantı şablonu https:// ile başlamalı.');
  if (authority[1].includes('{')) throw invalid('clip_url_template', 'Yer tutucu adres (ana bilgisayar) kısmında kullanılamaz.');
  let url;
  try {
    url = new URL(out.replace(/\{([a-z_]+)\}/g, (_m, name) => SAMPLE[name]));
  } catch {
    throw invalid('clip_url_template', 'Kayıt bağlantı şablonu geçerli bir adres değil.');
  }
  if (url.protocol !== 'https:' || url.hostname === '') throw invalid('clip_url_template', 'Kayıt bağlantı şablonu https:// ile başlamalı.');
  if (url.username !== '' || url.password !== '') throw invalid('clip_url_template', 'Adreste kullanıcı adı / parola bulunamaz; kimlik bilgisini ayrı alana yazın.');
  return out;
}

/** Anlik goruntu adresi: herkese acik https (ozel / yerel adres kayit sirasinda reddedilir; cekerken tekrar dogrulanir). */
export function parseSnapshotAddress(value) {
  const out = rawUrlText(value, 'snapshot_url', 'Anlık görüntü adresi', 500);
  if (out === null) return null;
  if (!parseSnapshotUrl(out)) {
    throw invalid('snapshot_url', 'Anlık görüntü adresi herkese açık bir https:// adresi olmalı (yerel ağ adresleri sunucudan açılamaz; yalnız kayıt bağlantısını kullanın).');
  }
  return out;
}

const isoNoMs = (date) => date.toISOString().replace(/\.\d{3}Z$/, 'Z');

/** Sablonu doldurur: degerler adres kodlamasindan gecer; sonuc yine https olmali. Doner { url, start, end }. */
export function fillClipTemplate(template, { openedAt, channel = null, cameraName = '' }) {
  const opened = openedAt instanceof Date ? openedAt : new Date(openedAt);
  if (Number.isNaN(opened.getTime())) throw invalid('opened_at', 'Olay zamanı geçersiz.');
  const start = new Date(opened.getTime() - CLIP_BEFORE_SECONDS * 1000);
  const end = new Date(opened.getTime() + CLIP_AFTER_SECONDS * 1000);
  const values = {
    start: isoNoMs(start),
    end: isoNoMs(end),
    start_unix: String(Math.floor(start.getTime() / 1000)),
    end_unix: String(Math.floor(end.getTime() / 1000)),
    channel: channel ?? '',
    camera: cameraName,
  };
  const url = String(template).replace(/\{([a-z_]+)\}/g, (match, name) => (name in values ? encodeURIComponent(values[name]) : match));
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw invalid('clip_url_template', 'Kayıt bağlantısı oluşturulamadı.');
  }
  if (parsed.protocol !== 'https:') throw invalid('clip_url_template', 'Kayıt bağlantısı oluşturulamadı.');
  return { url: parsed.href, start: start.toISOString(), end: end.toISOString() };
}

function idList(value, field, label, max) {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) throw invalid(field, `${label} liste olmalı.`);
  const out = [];
  for (const raw of value) {
    const n = typeof raw === 'string' && /^\d{1,16}$/.test(raw) ? Number(raw) : raw;
    if (!Number.isSafeInteger(n) || n <= 0) throw invalid(field, `${label} geçersiz.`);
    if (!out.includes(n)) out.push(n);
  }
  if (out.length > max) throw invalid(field, `${label} en çok ${max} öğe olabilir.`);
  return out;
}

const bodyOf = (b) => {
  if (!b || typeof b !== 'object' || Array.isArray(b)) throw new PlatformError(400, 'INVALID_BODY', 'Gövde geçersiz.');
  return b;
};

/** Gövdeden yalnız verilen alanları ayrıştırır (PATCH için kısmi); create kendi zorunluluklarını sonra denetler. */
export function parseCameraInput(rawBody) {
  const body = bodyOf(rawBody);
  const out = {};
  if (body.name !== undefined) out.name = text(body.name, 'name', 'Ad', 80, { required: true });
  if (body.location !== undefined) out.location = text(body.location, 'location', 'Konum', 160);
  if (body.kind !== undefined) {
    if (!CAMERA_KINDS.includes(body.kind)) throw invalid('kind', 'Tür IP kamera ya da NVR kanalı olmalı.');
    out.kind = body.kind;
  }
  if (body.channel !== undefined) out.channel = channelText(body.channel);
  if (body.clip_url_template !== undefined) out.clip_url_template = parseClipTemplate(body.clip_url_template);
  if (body.snapshot_url !== undefined) out.snapshot_url = parseSnapshotAddress(body.snapshot_url);
  if (body.username !== undefined) out.username = text(body.username, 'username', 'Kullanıcı adı', 80);
  if (body.password !== undefined) {
    if (body.password !== null && typeof body.password !== 'string') throw invalid('password', 'Parola geçersiz.');
    if (typeof body.password === 'string' && body.password.length > 120) throw invalid('password', 'Parola en çok 120 karakter olabilir.');
    out.password = body.password === null || body.password === '' ? null : body.password;
  }
  if (body.clear_credentials !== undefined) {
    if (typeof body.clear_credentials !== 'boolean') throw invalid('clear_credentials', 'clear_credentials true/false olmalı.');
    out.clear_credentials = body.clear_credentials;
  }
  if (body.is_active !== undefined) {
    if (typeof body.is_active !== 'boolean') throw invalid('is_active', 'is_active true/false olmalı.');
    out.is_active = body.is_active;
  }
  const doorIds = idList(body.door_ids, 'door_ids', 'Kapılar', LIMITS.doorsPerCamera);
  if (doorIds !== undefined) out.door_ids = doorIds;
  return out;
}

/** Kayıt durumunun tutarliligi: en az bir baglanti, parola icin kullanici adi. */
function assertConsistent(state) {
  if (!state.clip_url_template && !state.snapshot_url) {
    throw invalid('clip_url_template', 'En az bir bağlantı gerekli: kayıt bağlantı şablonu ya da anlık görüntü adresi.');
  }
  if (state.has_password && !state.username) throw invalid('username', 'Parola için kullanıcı adı gerekli.');
}

// --- Cikti ------------------------------------------------------------------------------------------------------------

/** Kimlik bilgisi (kullanici adi / parola) ASLA donmez. Sablon ve adres (belirtec icerebilir) yalniz yazma yetkisi olana. */
export function mapCamera(row, doors, canWrite) {
  return {
    id: Number(row.id),
    name: row.name,
    location: row.location ?? null,
    kind: row.kind,
    channel: row.channel ?? null,
    is_active: row.is_active,
    has_clip_link: Boolean(row.clip_url_template),
    has_snapshot: Boolean(row.snapshot_url),
    has_credentials: Boolean(row.username || row.password_enc),
    ...(canWrite ? { clip_url_template: row.clip_url_template ?? null, snapshot_url: row.snapshot_url ?? null } : {}),
    doors: doors.map((d) => ({ id: Number(d.door_id), name: d.door_name })),
    created_at: new Date(row.created_at).toISOString(),
  };
}

const CAMERA_COLUMNS = `id, name, location, kind, channel, clip_url_template, snapshot_url, username, password_enc, is_active, created_at`;

async function audit(db, actor, action, siteCode, targetId, details) {
  await recordAudit(db, { actor, action, siteCode, targetType: 'cctv_camera', targetId: String(targetId), details });
}

async function loadDoors(db, siteCode, cameraIds) {
  if (cameraIds.length === 0) return new Map();
  const result = await db.query(
    `SELECT cd.camera_id, cd.door_id, d.door_name
       FROM cctv_camera_doors cd JOIN site_doors d ON d.id = cd.door_id
      WHERE cd.site_code = $1 AND cd.camera_id = ANY($2::BIGINT[]) ORDER BY d.door_index, d.id`,
    [siteCode, cameraIds],
  );
  const map = new Map();
  for (const row of result.rows) {
    const key = Number(row.camera_id);
    map.set(key, [...(map.get(key) ?? []), row]);
  }
  return map;
}

async function validateDoors(db, siteCode, doorIds) {
  if (doorIds.length === 0) return;
  const found = await db.query(`SELECT id FROM site_doors WHERE site_code = $1 AND id = ANY($2::BIGINT[])`, [siteCode, doorIds]);
  if (found.rows.length !== doorIds.length) throw invalid('door_ids', 'Seçilen kapılardan biri bu sitede bulunamadı.');
}

async function writeDoors(db, siteCode, cameraId, doorIds) {
  await db.query(`DELETE FROM cctv_camera_doors WHERE camera_id = $1`, [cameraId]);
  for (const doorId of doorIds) {
    await db.query(`INSERT INTO cctv_camera_doors (camera_id, door_id, site_code) VALUES ($1, $2, $3)`, [cameraId, doorId, siteCode]);
  }
}

function toNumberId(raw) {
  const id = Number(raw);
  if (!Number.isSafeInteger(id) || id <= 0) throw notFound('Kamera');
  return id;
}

// --- Kameralar ------------------------------------------------------------------------------------------------------

export function metaInfo() {
  return {
    kinds: [
      { code: 'ip_camera', name: 'IP kamera' },
      { code: 'nvr_channel', name: 'NVR kanalı' },
    ],
    placeholders: [...PLACEHOLDERS],
    clip_window_seconds: { before: CLIP_BEFORE_SECONDS, after: CLIP_AFTER_SECONDS },
    kvkk_note: KVKK_NOTE,
    limits: { cameras: LIMITS.cameras, doors_per_camera: LIMITS.doorsPerCamera },
  };
}

export async function listCameras(siteCode, { canWrite }, db = pool) {
  const result = await db.query(`SELECT ${CAMERA_COLUMNS} FROM cctv_cameras WHERE site_code = $1 ORDER BY id DESC LIMIT ${LIMITS.cameras}`, [siteCode]);
  const doors = await loadDoors(db, siteCode, result.rows.map((r) => Number(r.id)));
  return { cameras: result.rows.map((row) => mapCamera(row, doors.get(Number(row.id)) ?? [], canWrite)), kvkk_note: KVKK_NOTE };
}

export async function listDoors(siteCode, db = pool) {
  const result = await db.query(`SELECT id, door_name FROM site_doors WHERE site_code = $1 AND is_active ORDER BY door_index, id`, [siteCode]);
  return { doors: result.rows.map((r) => ({ id: Number(r.id), name: r.door_name })) };
}

export async function createCamera({ siteCode, actor, userCode, body }, db = pool) {
  const input = parseCameraInput(body);
  if (input.name === undefined) throw invalid('name', 'Ad zorunludur.');
  const state = {
    clip_url_template: input.clip_url_template ?? null,
    snapshot_url: input.snapshot_url ?? null,
    username: input.username ?? null,
    has_password: Boolean(input.password),
  };
  assertConsistent(state);
  const count = await db.query(`SELECT COUNT(*)::INT AS n FROM cctv_cameras WHERE site_code = $1`, [siteCode]);
  if ((count.rows[0]?.n ?? 0) >= LIMITS.cameras) throw new PlatformError(409, 'LIMIT_REACHED', `Bir sitede en çok ${LIMITS.cameras} kamera kaydedilebilir.`);
  await validateDoors(db, siteCode, input.door_ids ?? []);
  const inserted = await db.query(
    `INSERT INTO cctv_cameras (site_code, name, location, kind, channel, clip_url_template, snapshot_url, username, password_enc, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING ${CAMERA_COLUMNS}`,
    [
      siteCode,
      input.name,
      input.location ?? null,
      input.kind ?? 'ip_camera',
      input.channel ?? null,
      state.clip_url_template,
      state.snapshot_url,
      state.username,
      input.password ? encryptSecret(input.password) : null,
      userCode ?? null,
    ],
  );
  const row = inserted.rows[0];
  await writeDoors(db, siteCode, Number(row.id), input.door_ids ?? []);
  await audit(db, actor, 'cctv.camera_created', siteCode, row.id, { door_count: (input.door_ids ?? []).length });
  const doors = await loadDoors(db, siteCode, [Number(row.id)]);
  return { camera: mapCamera(row, doors.get(Number(row.id)) ?? [], true) };
}

export async function updateCamera({ siteCode, rawId, actor, body }, db = pool) {
  const id = toNumberId(rawId);
  const input = parseCameraInput(body);
  const existing = await db.query(`SELECT ${CAMERA_COLUMNS} FROM cctv_cameras WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  const row = existing.rows[0];
  if (!row) throw notFound('Kamera');
  const clear = input.clear_credentials === true;
  const merged = {
    name: input.name ?? row.name,
    location: input.location !== undefined ? input.location : row.location,
    kind: input.kind ?? row.kind,
    channel: input.channel !== undefined ? input.channel : row.channel,
    clip_url_template: input.clip_url_template !== undefined ? input.clip_url_template : row.clip_url_template,
    snapshot_url: input.snapshot_url !== undefined ? input.snapshot_url : row.snapshot_url,
    username: clear ? null : input.username !== undefined ? input.username : row.username,
    password_enc: clear ? null : input.password !== undefined ? (input.password ? encryptSecret(input.password) : null) : row.password_enc,
    is_active: input.is_active ?? row.is_active,
  };
  assertConsistent({ clip_url_template: merged.clip_url_template, snapshot_url: merged.snapshot_url, username: merged.username, has_password: Boolean(merged.password_enc) });
  if (input.door_ids !== undefined) await validateDoors(db, siteCode, input.door_ids);
  const updated = await db.query(
    `UPDATE cctv_cameras SET name = $3, location = $4, kind = $5, channel = $6, clip_url_template = $7, snapshot_url = $8,
            username = $9, password_enc = $10, is_active = $11, updated_at = NOW()
      WHERE id = $1 AND site_code = $2 RETURNING ${CAMERA_COLUMNS}`,
    [id, siteCode, merged.name, merged.location, merged.kind, merged.channel, merged.clip_url_template, merged.snapshot_url, merged.username, merged.password_enc, merged.is_active],
  );
  if (!updated.rows[0]) throw notFound('Kamera');
  if (input.door_ids !== undefined) await writeDoors(db, siteCode, id, input.door_ids);
  const fields = Object.keys(input).filter((k) => k !== 'password');
  await audit(db, actor, 'cctv.camera_updated', siteCode, id, { fields: input.password !== undefined ? [...fields, 'password'] : fields });
  const doors = await loadDoors(db, siteCode, [id]);
  return { camera: mapCamera(updated.rows[0], doors.get(id) ?? [], true) };
}

export async function deleteCamera({ siteCode, rawId, actor }, db = pool) {
  const id = toNumberId(rawId);
  const result = await db.query(`DELETE FROM cctv_cameras WHERE id = $1 AND site_code = $2 RETURNING id, name`, [id, siteCode]);
  if (!result.rows[0]) throw notFound('Kamera');
  await audit(db, actor, 'cctv.camera_deleted', siteCode, id, {});
  return { ok: true };
}

// --- Anlik goruntu --------------------------------------------------------------------------------------------------

/** Doner { contentType, body }; ulasilamazsa 424 SNAPSHOT_UNAVAILABLE. Her deneme denetim kaydina yazilir. */
export async function getSnapshot({ siteCode, rawId, actor }, { db = pool, fetcher = fetchSnapshot } = {}) {
  const id = toNumberId(rawId);
  const found = await db.query(`SELECT ${CAMERA_COLUMNS} FROM cctv_cameras WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  const row = found.rows[0];
  if (!row) throw notFound('Kamera');
  if (!row.is_active) throw new PlatformError(409, 'CAMERA_INACTIVE', 'Kamera pasif.');
  if (!row.snapshot_url) throw snapshotUnavailable();
  let password = null;
  if (row.password_enc) {
    try {
      password = decryptSecret(row.password_enc);
    } catch {
      password = null;
    }
  }
  const result = await fetcher(row.snapshot_url, { username: row.username || null, password });
  await audit(db, actor, 'cctv.snapshot_viewed', siteCode, id, { delivered: result.ok === true, ...(result.ok ? {} : { reason: result.reason }) });
  if (!result.ok) throw snapshotUnavailable();
  return { contentType: result.contentType, body: result.body };
}

// --- Kapi olaylari ve kayit baglantisi ----------------------------------------------------------------------------

/** Son kapi olaylari (door_access_logs SALT OKUNUR) + olayin kapisina eslenmis AKTIF kameralar. Kisi adi yalniz yazma yetkisi olana. */
export async function listEvents(siteCode, { canWrite }, query = {}, db = pool) {
  const limit = Math.min(Math.max(Number.parseInt(query.limit, 10) || LIMITS.eventsDefault, 1), LIMITS.events);
  const doorFilter = Number.parseInt(query.door_id, 10);
  const logs = await db.query(
    `SELECT id, door_id, door_name, user_name, apartment_label, trigger_type, opened_at
       FROM door_access_logs
      WHERE site_code = $1 AND ($2::BIGINT IS NULL OR door_id = $2)
      ORDER BY opened_at DESC, id DESC LIMIT $3`,
    [siteCode, Number.isSafeInteger(doorFilter) && doorFilter > 0 ? doorFilter : null, limit],
  );
  const doorIds = [...new Set(logs.rows.map((r) => (r.door_id === null || r.door_id === undefined ? null : Number(r.door_id))).filter((v) => v !== null))];
  const byDoor = new Map();
  if (doorIds.length > 0) {
    const links = await db.query(
      `SELECT cd.door_id, c.id, c.name, c.location, (c.clip_url_template IS NOT NULL) AS has_clip_link, (c.snapshot_url IS NOT NULL) AS has_snapshot
         FROM cctv_camera_doors cd JOIN cctv_cameras c ON c.id = cd.camera_id
        WHERE cd.site_code = $1 AND c.site_code = $1 AND c.is_active AND cd.door_id = ANY($2::BIGINT[]) ORDER BY c.id`,
      [siteCode, doorIds],
    );
    for (const row of links.rows) {
      const key = Number(row.door_id);
      byDoor.set(key, [
        ...(byDoor.get(key) ?? []),
        { id: Number(row.id), name: row.name, location: row.location ?? null, has_clip_link: Boolean(row.has_clip_link), has_snapshot: Boolean(row.has_snapshot) },
      ]);
    }
  }
  return {
    events: logs.rows.map((row) => ({
      id: Number(row.id),
      door_id: row.door_id === null || row.door_id === undefined ? null : Number(row.door_id),
      door_name: row.door_name,
      trigger_type: row.trigger_type,
      opened_at: new Date(row.opened_at).toISOString(),
      user_name: canWrite ? row.user_name : null,
      apartment_label: canWrite ? row.apartment_label ?? null : null,
      cameras: row.door_id === null || row.door_id === undefined ? [] : byDoor.get(Number(row.door_id)) ?? [],
    })),
    window_seconds: { before: CLIP_BEFORE_SECONDS, after: CLIP_AFTER_SECONDS },
    kvkk_note: KVKK_NOTE,
  };
}

/** Olay + kamera icin kayit baglantisini doldurur ve acma denetim kaydina yazar. Kamera olayin kapisina eslenmis ve aktif olmali. */
export async function openClipLink({ siteCode, actor, body }, db = pool) {
  const input = bodyOf(body);
  const cameraId = typeof input.camera_id === 'string' && /^\d{1,16}$/.test(input.camera_id) ? Number(input.camera_id) : input.camera_id;
  const logId = typeof input.log_id === 'string' && /^\d{1,16}$/.test(input.log_id) ? Number(input.log_id) : input.log_id;
  if (!Number.isSafeInteger(cameraId) || cameraId <= 0) throw invalid('camera_id', 'Kamera geçersiz.');
  if (!Number.isSafeInteger(logId) || logId <= 0) throw invalid('log_id', 'Olay geçersiz.');
  const log = await db.query(`SELECT id, door_id, opened_at FROM door_access_logs WHERE id = $1 AND site_code = $2`, [logId, siteCode]);
  const event = log.rows[0];
  if (!event) throw notFound('Olay');
  const camera = await db.query(
    `SELECT c.id, c.name, c.channel, c.clip_url_template
       FROM cctv_cameras c JOIN cctv_camera_doors cd ON cd.camera_id = c.id
      WHERE c.id = $1 AND c.site_code = $2 AND c.is_active AND cd.door_id = $3`,
    [cameraId, siteCode, event.door_id ?? 0],
  );
  const row = camera.rows[0];
  if (!row) throw notFound('Kamera');
  if (!row.clip_url_template) throw new PlatformError(409, 'NO_CLIP_LINK', 'Bu kamera için kayıt bağlantı şablonu tanımlı değil.');
  const filled = fillClipTemplate(row.clip_url_template, { openedAt: event.opened_at, channel: row.channel, cameraName: row.name });
  await audit(db, actor, 'cctv.clip_opened', siteCode, cameraId, { log_id: logId });
  return { url: filled.url, start: filled.start, end: filled.end };
}
