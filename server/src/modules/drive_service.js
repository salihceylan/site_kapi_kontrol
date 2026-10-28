// Site Drive deposu (D1) servisi: bağlantı (OAuth drive.file), şifreli yenileme belirteci, klasör/dosya adı kuralları, yükleme/indirme vekili ve bekleme kuyruğu.
// Sözleşme: docs/PLATFORM_DRIVE_DEPOLAMA.md "D1 uygulaması". Mevcut belge/fotoğraf yüklemeleri bu aşamada DEĞİŞMEZ (kendi yolu: /drive/files).
// Sunucuda kalıcı dosya yoktur: yalnız bağlantı kopukken geçici bekleme alanı (site başına 100 MB).
//
// "Silmeyi biz yapmayız" (karar K6, P1-8):
//  - Bekleyen dosya SÜRE DOLDU DİYE SİLİNMEZ. Drive'a ulaşana kadar "bekliyor" kalır; PENDING_WARN_DAYS'i aşan dosya yalnız yönetici uyarısına girer (getStatus.warnings).
//  - Bekleme alanı (PENDING_MAX_BYTES) dolunca YENİ yükleme reddedilir (503 DRIVE_QUEUE_FULL); bekleyen / kayıtlı hiçbir dosyaya dokunulmaz.
//  - Sunucudaki geçici dosya YALNIZ Drive teyidinden SONRA silinir (driveConfirmed: dosya kimliği + varsa boyut). Teyitsizse dosya durur ve yeniden denenir.
//  - Kullanıcının kendi cihazındaki kopyaya sunucu hiçbir koşulda dokunmaz (istemci de otomatik silmez).
// Kaynak bağı (P1-11): upload({ source: { type, id } }) dosya adına kayıt kimliği önekini (IS-123_...) ekler ve drive_files.source_type / source_id'yi doldurur.

import crypto from 'node:crypto';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { createDriveClient, DriveError } from './drive_client.js';
import {
  DRIVE_KINDS,
  DRIVE_MIME_EXTENSIONS,
  MAX_UPLOAD_BYTES,
  OAUTH_STATE_MINUTES,
  PENDING_MAX_BYTES,
  PENDING_WARN_DAYS,
  decryptToken,
  driveConfig,
  driveConfirmed,
  driveNotConfigured,
  encryptToken,
  fileBaseName,
  folderNameFor,
  hashState,
  mimeMatchesContent,
  newOauthState,
  parseDriveSource,
  parseIsoDate,
  queueWarnings,
} from './drive_common.js';
import { PlatformError } from './errors.js';

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_SERIAL = 50;
/** Aynı site ve aynı uyarı türü için denetim kaydı en sık bu aralıkla yazılır (kalabalık yüklemede günlüğü doldurmasın). */
const WARN_AUDIT_INTERVAL_MS = 60 * 60 * 1000;

/** Geçici (bekleme) dosyası gönderilemedi / doğrulanamadı: dosya DURUR, bekleme satırına neden yazılır, yeniden denenir. */
class PendingFileError extends Error {}

const sha256Of = (data) => crypto.createHash('sha256').update(data).digest('hex');

function todayParts(now) {
  const d = now();
  return { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate() };
}

const disconnectedError = () => new PlatformError(503, 'DRIVE_DISCONNECTED', 'Sitenin Drive bağlantısı kopuk; yönetiminize bildirin.');

/**
 * @param {object} [deps] test düzeneği: db, client (Drive istemcisi), config, pendingDir, now
 */
export function createDriveService(deps = {}) {
  const db = deps.db ?? pool;
  const now = deps.now ?? (() => new Date());
  const getConfig = () => deps.config ?? driveConfig();
  const getClient = () => deps.client ?? createDriveClient({ config: getConfig() });
  const pendingRoot = () =>
    deps.pendingDir ?? (String(process.env.DRIVE_PENDING_DIR ?? '').trim() || path.join(os.homedir(), 'kapi-drive-pending'));
  const tokenCache = new Map(); // siteCode -> { token, exp }
  const lastWarned = new Map(); // `${siteCode}:${action}` -> ms

  /** Yönetici uyarısının denetim kaydı (aynı site + tür için saatte en çok bir kez). Kayıt hatası asıl işi bozmaz (recordAudit yutar). */
  async function warnManagers(siteCode, action, actor, details) {
    const key = `${siteCode}:${action}`;
    const at = now().getTime();
    if (at - (lastWarned.get(key) ?? 0) < WARN_AUDIT_INTERVAL_MS) return;
    lastWarned.set(key, at);
    await recordAudit(db, { actor, action, siteCode, targetType: 'drive', details });
  }

  async function getConnection(siteCode) {
    const result = await db.query(`SELECT * FROM site_drive_connections WHERE site_code = $1`, [siteCode]);
    return result.rows[0] ?? null;
  }

  async function markError(siteCode, message) {
    tokenCache.delete(siteCode);
    await db.query(
      `UPDATE site_drive_connections SET status = 'error', last_error = $2, updated_at = NOW() WHERE site_code = $1 AND status = 'connected'`,
      [siteCode, message],
    );
  }

  /** Geçerli erişim belirteci; izin kaldırılmışsa bağlantıyı 'error' yapar ve DriveError('auth') fırlatır. */
  async function accessToken(conn) {
    const cached = tokenCache.get(conn.site_code);
    if (cached && cached.exp > now().getTime() + 60_000) return cached.token;
    if (!conn.refresh_token_enc) throw new DriveError('auth', 'Yenileme belirteci yok.');
    try {
      const refreshed = await getClient().refreshAccess(decryptToken(conn.refresh_token_enc, getConfig().tokenKey));
      tokenCache.set(conn.site_code, { token: refreshed.accessToken, exp: now().getTime() + refreshed.expiresIn * 1000 });
      return refreshed.accessToken;
    } catch (error) {
      if (error instanceof DriveError && error.kind === 'auth') {
        await markError(conn.site_code, 'Google erişimi kaldırılmış ya da geçersiz; Drive yeniden bağlanmalı.');
      }
      throw error instanceof DriveError ? error : new DriveError('auth', 'Yenileme belirteci çözülemedi.');
    }
  }

  async function folderIdFor(token, conn, folderName) {
    let rootId = conn.root_folder_id;
    if (!rootId) {
      const site = await db.query(`SELECT name FROM sites WHERE site_code = $1`, [conn.site_code]);
      rootId = await getClient().ensureFolder(token, `SmartKeyPass — ${site.rows[0]?.name ?? conn.site_code}`, null);
      await db.query(`UPDATE site_drive_connections SET root_folder_id = $2, updated_at = NOW() WHERE site_code = $1`, [conn.site_code, rootId]);
      conn.root_folder_id = rootId;
    }
    const known = conn.folder_ids?.[folderName];
    if (known) return known;
    const id = await getClient().ensureFolder(token, folderName, rootId);
    await db.query(`UPDATE site_drive_connections SET folder_ids = folder_ids || $2::jsonb WHERE site_code = $1`, [conn.site_code, JSON.stringify({ [folderName]: id })]);
    conn.folder_ids = { ...(conn.folder_ids ?? {}), [folderName]: id };
    return id;
  }

  /** Drive'a gönderir; üst klasör silinmişse (404) önbelleği sıfırlayıp bir kez daha dener. */
  async function sendToDrive(conn, file, data) {
    const token = await accessToken(conn);
    for (let attempt = 1; ; attempt += 1) {
      try {
        const parentId = await folderIdFor(token, conn, file.folder_name);
        return await getClient().uploadFile(token, { name: file.name, mimeType: file.mime_type, parentId, data });
      } catch (error) {
        if (!(error instanceof DriveError) || error.kind !== 'not_found' || attempt > 1) throw error;
        await db.query(`UPDATE site_drive_connections SET root_folder_id = NULL, folder_ids = '{}'::jsonb WHERE site_code = $1`, [conn.site_code]);
        conn.root_folder_id = null;
        conn.folder_ids = {};
      }
    }
  }

  async function touchOk(siteCode) {
    await db.query(`UPDATE site_drive_connections SET last_ok_at = NOW(), last_error = NULL WHERE site_code = $1 AND status = 'connected'`, [siteCode]);
  }

  // --- Durum / bağlantı ---

  async function getStatus(siteCode) {
    const config = getConfig();
    const conn = await getConnection(siteCode);
    // Bekleyen dosyalar: sayı, bayt, PENDING_WARN_DAYS'i aşanlar (silinmez, yalnız uyarı) ve en eskisi.
    const pending = await db.query(
      `SELECT COUNT(*)::int AS n, COALESCE(SUM(f.size_bytes), 0)::bigint AS bytes,
              COUNT(*) FILTER (WHERE p.expires_at < $2)::int AS overdue, MIN(f.created_at) AS oldest
         FROM drive_pending_uploads p JOIN drive_files f ON f.id = p.file_id WHERE p.site_code = $1`,
      [siteCode, now()],
    );
    const stored = await db.query(`SELECT COUNT(*)::int AS n FROM drive_files WHERE site_code = $1 AND status = 'stored'`, [siteCode]);
    const row = pending.rows[0];
    const pendingBytes = Number(row.bytes);
    return {
      configured: config.configured,
      status: conn?.status ?? 'disconnected',
      connected: conn?.status === 'connected',
      account_email: conn?.account_email ?? null,
      connected_at: conn?.connected_at ?? null,
      last_ok_at: conn?.last_ok_at ?? null,
      last_error: conn?.last_error ?? null,
      stored_count: stored.rows[0].n,
      pending_count: row.n,
      pending_bytes: pendingBytes,
      pending_limit_bytes: PENDING_MAX_BYTES,
      pending_overdue_count: row.overdue ?? 0,
      oldest_pending_at: row.oldest ?? null,
      // K6: yönetici uyarıları (bekleyen / uzun süredir bekleyen / bekleme alanı dolu). Hiçbiri dosya silmez.
      warnings: queueWarnings({ pendingCount: row.n, pendingBytes, overdueCount: row.overdue ?? 0 }),
      kinds: Object.keys(DRIVE_KINDS),
    };
  }

  async function startConnect(siteCode, actor) {
    const config = getConfig();
    if (!config.configured) throw driveNotConfigured();
    const { state, hash } = newOauthState();
    await db.query(`DELETE FROM drive_oauth_states WHERE expires_at < NOW()`);
    await db.query(`INSERT INTO drive_oauth_states (state_hash, site_code, user_code, expires_at) VALUES ($1, $2, $3, $4)`, [
      hash,
      siteCode,
      actor?.userCode ?? null,
      new Date(now().getTime() + OAUTH_STATE_MINUTES * 60_000),
    ]);
    return { url: getClient().authUrl(state) };
  }

  /** Google yönlendirmesi: state tek kullanımlıktır. Başarıda { siteCode }. */
  async function completeConnect({ code, state }) {
    const config = getConfig();
    if (!config.configured) throw driveNotConfigured();
    if (!code || !state) throw new PlatformError(400, 'INVALID_OAUTH', 'Bağlantı yanıtı eksik.');
    const consumed = await db.query(`DELETE FROM drive_oauth_states WHERE state_hash = $1 RETURNING site_code, user_code, expires_at`, [hashState(state)]);
    const row = consumed.rows[0];
    if (!row || new Date(row.expires_at).getTime() < now().getTime()) {
      throw new PlatformError(400, 'INVALID_OAUTH', 'Bağlantı isteğinin süresi doldu; uygulamadan yeniden deneyin.');
    }
    const siteCode = Number(row.site_code);
    const client = getClient();
    let tokens;
    try {
      tokens = await client.exchangeCode(code);
    } catch {
      throw new PlatformError(400, 'INVALID_OAUTH', 'Google bağlantısı kurulamadı; yeniden deneyin.');
    }
    if (!tokens.refreshToken) {
      throw new PlatformError(400, 'NO_REFRESH_TOKEN', 'Google kalıcı erişim vermedi; Drive iznini yeniden onaylayın.');
    }
    if (!tokens.scope.split(' ').includes('https://www.googleapis.com/auth/drive.file')) {
      throw new PlatformError(400, 'SCOPE_MISSING', 'Drive izni verilmedi.');
    }
    const email = await client.accountEmail(tokens.accessToken).catch(() => null);
    const previous = await getConnection(siteCode);
    const sameAccount = previous && previous.account_email && previous.account_email === email;
    await db.query(
      `INSERT INTO site_drive_connections (site_code, status, account_email, refresh_token_enc, root_folder_id, folder_ids, connected_by, connected_at, last_ok_at, last_error, updated_at)
       VALUES ($1, 'connected', $2, $3, $4, $5::jsonb, $6, NOW(), NOW(), NULL, NOW())
       ON CONFLICT (site_code) DO UPDATE SET status = 'connected', account_email = EXCLUDED.account_email, refresh_token_enc = EXCLUDED.refresh_token_enc,
         root_folder_id = EXCLUDED.root_folder_id, folder_ids = EXCLUDED.folder_ids, connected_by = EXCLUDED.connected_by, connected_at = NOW(),
         last_ok_at = NOW(), last_error = NULL, updated_at = NOW()`,
      [siteCode, email, encryptToken(tokens.refreshToken, config.tokenKey), sameAccount ? previous.root_folder_id : null, JSON.stringify(sameAccount ? previous.folder_ids ?? {} : {}), row.user_code],
    );
    tokenCache.set(siteCode, { token: tokens.accessToken, exp: now().getTime() + tokens.expiresIn * 1000 });
    await recordAudit(db, { actor: { user_code: row.user_code }, action: 'drive.connected', siteCode, targetType: 'drive', details: { account_email: email } });
    // Yeniden bağlanınca bekleyenler artan bekleme sürelerine takılmadan hemen denenir (hiçbiri süre doldu diye silinmez).
    await flushPending(siteCode, { force: true }).catch(() => {});
    return { siteCode };
  }

  async function disconnect(siteCode, actor) {
    const conn = await getConnection(siteCode);
    if (!conn || conn.status === 'disconnected') return { status: 'disconnected' };
    if (conn.refresh_token_enc && getConfig().configured) {
      try {
        await getClient().revoke(decryptToken(conn.refresh_token_enc, getConfig().tokenKey));
      } catch {
        // Google'a ulaşılamasa da yerel bağlantı kesilir.
      }
    }
    tokenCache.delete(siteCode);
    await db.query(
      `UPDATE site_drive_connections SET status = 'disconnected', refresh_token_enc = NULL, last_error = NULL, updated_at = NOW() WHERE site_code = $1`,
      [siteCode],
    );
    await recordAudit(db, { actor, action: 'drive.disconnected', siteCode, targetType: 'drive', details: {} });
    return { status: 'disconnected' };
  }

  // --- Yükleme ---

  function viewOf(row) {
    return {
      id: Number(row.id),
      kind: row.kind,
      folder: row.folder_name,
      name: row.name,
      mime_type: row.mime_type,
      size_bytes: Number(row.size_bytes),
      status: row.status,
      created_at: row.created_at,
      // P1-11: dosyanın ait olduğu kayıt (yoksa null). Eski istemciler bu alanları yok sayar.
      source_type: row.source_type ?? null,
      source_id: row.source_id === undefined || row.source_id === null ? null : Number(row.source_id),
    };
  }

  async function allocateRow({ siteCode, kind, folder, base, ext, mime, size, sha256, userCode, source }) {
    for (let serial = 1; serial <= MAX_SERIAL; serial += 1) {
      const name = `${fileBaseName({ ...base, serial })}.${ext}`;
      const inserted = await db.query(
        `INSERT INTO drive_files (site_code, kind, folder_name, name, mime_type, size_bytes, sha256, status, uploaded_by, source_type, source_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending', $8, $9, $10) ON CONFLICT DO NOTHING RETURNING *`,
        [siteCode, kind, folder, name, mime, size, sha256, userCode, source?.type ?? null, source?.id ?? null],
      );
      if (inserted.rows[0]) return inserted.rows[0];
    }
    throw new PlatformError(409, 'NAME_EXHAUSTED', 'Aynı gün için çok fazla aynı adlı dosya var.');
  }

  /**
   * Drive'a gidemeyen yeni dosyayı bekleme alanına alır. Alan doluysa YENİ yükleme reddedilir (K6): yalnız bu isteğin henüz kuyruğa girmemiş satırı geri alınır;
   * bekleyen ve kayıtlı HİÇBİR dosyaya (satır ya da geçici dosya) dokunulmaz; yöneticiye uyarı düşer.
   */
  async function queue(row, data, actor) {
    const siteCode = Number(row.site_code);
    const used = await db.query(
      `SELECT COALESCE(SUM(f.size_bytes), 0)::bigint AS bytes FROM drive_pending_uploads p JOIN drive_files f ON f.id = p.file_id WHERE p.site_code = $1`,
      [siteCode],
    );
    const usedBytes = Number(used.rows[0].bytes);
    if (usedBytes + data.length > PENDING_MAX_BYTES) {
      await db.query(
        `DELETE FROM drive_files WHERE id = $1 AND status = 'pending' AND NOT EXISTS (SELECT 1 FROM drive_pending_uploads WHERE file_id = $1)`,
        [row.id],
      );
      await warnManagers(siteCode, 'drive.queue_full', actor, { pending_bytes: usedBytes, limit_bytes: PENDING_MAX_BYTES, rejected_bytes: data.length });
      throw new PlatformError(
        503,
        'DRIVE_QUEUE_FULL',
        'Sitenin Drive bağlantısı kopuk ve bekleme alanı doldu; yeni dosya kabul edilemiyor. Bekleyen dosyalar silinmedi. Yönetiminize bildirin.',
      );
    }
    const dir = path.join(pendingRoot(), String(siteCode));
    await fsp.mkdir(dir, { recursive: true, mode: 0o700 });
    const target = path.join(dir, String(row.id));
    await fsp.writeFile(target, data, { mode: 0o600 });
    // expires_at artık SİLME zamanı değil, "uzun süredir bekliyor" uyarı eşiğidir (K6; sütun eski sürümle uyum için korunur).
    await db.query(`INSERT INTO drive_pending_uploads (file_id, site_code, storage_path, expires_at) VALUES ($1, $2, $3, $4)`, [
      row.id,
      siteCode,
      target,
      new Date(now().getTime() + PENDING_WARN_DAYS * DAY_MS),
    ]);
  }

  /** query: { kind, date?, block?, apartment?, mime }. data: Buffer. source: { type, id } ya da yok (P1-11; yalnız sunucu içi çağıranlar verir, sorgudan alınmaz). */
  async function upload({ siteCode, actor, query, data, source = null }) {
    const kind = String(query.kind ?? '');
    if (!DRIVE_KINDS[kind]) throw new PlatformError(400, 'INVALID_KIND', 'Dosya türü geçersiz.');
    const date = query.date ? parseIsoDate(query.date) : todayParts(now);
    if (!date) throw new PlatformError(400, 'INVALID_DATE', 'Tarih geçersiz (YYYY-AA-GG).');
    const mime = String(query.mime ?? '').toLowerCase();
    const ext = DRIVE_MIME_EXTENSIONS[mime];
    if (!ext) throw new PlatformError(415, 'UNSUPPORTED_TYPE', 'Bu dosya türü desteklenmiyor.');
    if (!Buffer.isBuffer(data) || data.length === 0) throw new PlatformError(400, 'EMPTY_FILE', 'Dosya boş.');
    if (data.length > MAX_UPLOAD_BYTES) throw new PlatformError(413, 'FILE_TOO_LARGE', 'Dosya 10 MB sınırını aşıyor.');
    if (!mimeMatchesContent(mime, data)) throw new PlatformError(415, 'CONTENT_MISMATCH', 'Dosya içeriği bildirilen türle uyuşmuyor.');
    const link = parseDriveSource(source);

    const conn = await getConnection(siteCode);
    if (!conn || conn.status === 'disconnected') {
      throw new PlatformError(409, 'DRIVE_NOT_CONNECTED', 'Önce sitenin Google Drive hesabını bağlayın.');
    }
    const row = await allocateRow({
      siteCode,
      kind,
      folder: folderNameFor(kind, date),
      base: { kind, block: query.block, apartment: query.apartment, date, source: link },
      ext,
      mime,
      size: data.length,
      sha256: crypto.createHash('sha256').update(data).digest('hex'),
      userCode: actor?.userCode ?? null,
      source: link,
    });
    let result = row;
    try {
      if (conn.status !== 'connected') throw new DriveError('auth', 'bağlantı kopuk');
      const sent = await sendToDrive(conn, row, data);
      // Teyitsiz yanıt (kimlik yok / boyut tutmuyor) başarı sayılmaz: dosya sunucuda bekler, Drive'a sonra gider.
      if (!driveConfirmed(sent, data.length)) throw new DriveError('transient', 'Drive yüklemeyi doğrulamadı.');
      const updated = await db.query(`UPDATE drive_files SET status = 'stored', drive_file_id = $2, stored_at = NOW() WHERE id = $1 RETURNING *`, [row.id, sent.id]);
      result = updated.rows[0];
      await touchOk(siteCode);
    } catch (error) {
      if (!(error instanceof DriveError)) {
        await db.query(`DELETE FROM drive_files WHERE id = $1`, [row.id]).catch(() => {});
        throw error;
      }
      await queue(row, data, actor);
    }
    await recordAudit(db, { actor, action: 'drive.file_uploaded', siteCode, targetType: 'drive_file', targetId: row.id, details: { kind, status: result.status, size_bytes: data.length, ...(link ? { source_type: link.type, source_id: link.id } : {}) } });
    return { file: viewOf(result) };
  }

  /** Son dosyalar. filter: { source_type, source_id } ikisi birlikte verilirse yalnız o kayda bağlı dosyalar (belge ilgili kayıttan açılsın). */
  async function list(siteCode, limit = 50, filter = {}) {
    const size = Math.min(Math.max(Number(limit) || 50, 1), 200);
    const wantsSource = filter?.source_type !== undefined || filter?.source_id !== undefined;
    const link = wantsSource ? parseDriveSource({ type: filter.source_type, id: filter.source_id }) : null;
    const result = link
      ? await db.query(
          `SELECT * FROM drive_files WHERE site_code = $1 AND source_type = $3 AND source_id = $4 ORDER BY id DESC LIMIT $2`,
          [siteCode, size, link.type, link.id],
        )
      : await db.query(`SELECT * FROM drive_files WHERE site_code = $1 ORDER BY id DESC LIMIT $2`, [siteCode, size]);
    return { files: result.rows.map(viewOf) };
  }

  /**
   * Bekleyenleri göndermeyi dener; { sent, waiting, overdue, expired }. `force`: artan bekleme sürelerini yok sayıp hemen dener (elle gönder, yeniden bağlanma).
   * HİÇBİR dosya süre doldu diye silinmez (K6): gönderilemeyen dosya bekler; `overdue` yalnız "uzun süredir bekliyor" uyarı sayısıdır (`expired` eski istemci uyumu için hep 0).
   * Geçici dosya YALNIZ Drive teyidinden (driveConfirmed) ve veritabanına 'stored' yazıldıktan SONRA silinir; teyitsiz / hatalı turda dosya durur.
   */
  async function flushNow(siteCode, { force = false } = {}) {
    const conn = await getConnection(siteCode);
    let sent = 0;
    const due = await db.query(
      `SELECT p.*, f.name, f.folder_name, f.mime_type, f.sha256, f.status AS file_status FROM drive_pending_uploads p JOIN drive_files f ON f.id = p.file_id
        WHERE p.site_code = $1 AND ($2::boolean OR p.next_attempt_at <= NOW()) ORDER BY p.file_id LIMIT 20`,
      [siteCode, force === true],
    );
    for (const item of due.rows) {
      if (item.file_status === 'stored') {
        // Önceki tur Drive teyidini 'stored' yazmış ama bekleme satırını silmeden kesilmiş: dosya TEKRAR GÖNDERİLMEZ ("gönderim alındıysa tekrar gönderilmez");
        // teyit kayıtlı olduğundan artık gereksiz satır ve geçici dosya temizlenir.
        await db.query(`DELETE FROM drive_pending_uploads WHERE file_id = $1`, [item.file_id]);
        await fsp.unlink(item.storage_path).catch(() => {});
        continue;
      }
      if (!conn || conn.status !== 'connected') continue;
      try {
        const data = await fsp.readFile(item.storage_path).catch(() => {
          throw new PendingFileError('Geçici dosya bulunamadı.');
        });
        if (item.sha256 && sha256Of(data) !== item.sha256) throw new PendingFileError('Geçici dosyanın bütünlüğü doğrulanamadı.');
        const out = await sendToDrive(conn, { name: item.name, folder_name: item.folder_name, mime_type: item.mime_type }, data);
        if (!driveConfirmed(out, data.length)) throw new PendingFileError('Drive yüklemeyi doğrulamadı; dosya bekliyor.');
        await db.query(`UPDATE drive_files SET status = 'stored', drive_file_id = $2, stored_at = NOW() WHERE id = $1`, [item.file_id, out.id]);
        await db.query(`DELETE FROM drive_pending_uploads WHERE file_id = $1`, [item.file_id]);
        await fsp.unlink(item.storage_path).catch(() => {});
        sent += 1;
      } catch (error) {
        const wait = Math.min(2 ** Math.min(item.attempts, 10), 1440);
        await db.query(
          `UPDATE drive_pending_uploads SET attempts = attempts + 1, next_attempt_at = $2, last_error = $3 WHERE file_id = $1`,
          [item.file_id, new Date(now().getTime() + wait * 60_000), error instanceof DriveError || error instanceof PendingFileError ? error.message : 'beklenmeyen hata'],
        );
        if (error instanceof DriveError && error.kind === 'auth') break;
      }
    }
    if (sent > 0) await touchOk(siteCode);
    const left = await db.query(
      `SELECT COUNT(*)::int AS n, COUNT(*) FILTER (WHERE expires_at < $2)::int AS overdue FROM drive_pending_uploads WHERE site_code = $1`,
      [siteCode, now()],
    );
    const waiting = left.rows[0].n;
    const overdue = left.rows[0].overdue ?? 0;
    if (overdue > 0) await warnManagers(siteCode, 'drive.pending_overdue', null, { overdue, waiting });
    return { sent, waiting, overdue, expired: 0 };
  }

  // Aynı sitenin gönderimleri SIRAYLA çalışır: elle gönder + yeniden bağlanma aynı anda gelse bile bir dosya iki kez Drive'a gitmez.
  const flushChains = new Map();
  function flushPending(siteCode, options = {}) {
    const run = (flushChains.get(siteCode) ?? Promise.resolve()).then(() => flushNow(siteCode, options));
    const tail = run.catch(() => {});
    flushChains.set(siteCode, tail);
    tail.then(() => {
      if (flushChains.get(siteCode) === tail) flushChains.delete(siteCode);
    });
    return run;
  }

  /** İndirme: { name, mime_type, size_bytes, buffer } ya da { ..., stream (web ReadableStream) }. Yetki rota katmanında. */
  async function openContent(siteCode, rawId) {
    const id = Number(rawId);
    if (!Number.isSafeInteger(id) || id <= 0) throw new PlatformError(404, 'FILE_NOT_FOUND', 'Dosya bulunamadı.');
    const found = await db.query(`SELECT * FROM drive_files WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    const row = found.rows[0];
    if (!row) throw new PlatformError(404, 'FILE_NOT_FOUND', 'Dosya bulunamadı.');
    const head = { name: row.name, mime_type: row.mime_type, size_bytes: Number(row.size_bytes) };
    if (row.status === 'pending') {
      const pending = await db.query(`SELECT storage_path FROM drive_pending_uploads WHERE file_id = $1`, [id]);
      if (!pending.rows[0]) throw new PlatformError(404, 'FILE_NOT_FOUND', 'Dosya bulunamadı.');
      return { ...head, buffer: await fsp.readFile(pending.rows[0].storage_path) };
    }
    const conn = await getConnection(siteCode);
    if (!conn || conn.status !== 'connected') throw disconnectedError();
    try {
      const token = await accessToken(conn);
      const out = await getClient().downloadFile(token, row.drive_file_id);
      return { ...head, stream: out.body };
    } catch (error) {
      if (error instanceof DriveError && error.kind === 'not_found') {
        throw new PlatformError(404, 'DRIVE_FILE_MISSING', 'Dosya sitenin Drive\'ında bulunamadı.');
      }
      if (error instanceof DriveError) throw disconnectedError();
      throw error;
    }
  }

  return { getStatus, startConnect, completeConnect, disconnect, upload, list, flushPending, openContent };
}

export const driveService = createDriveService();
