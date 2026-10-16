// İstemci hata raporu: doğrulama, KİŞİSEL VERİ TEMİZLEME, parmak izi, tekilleştirme, listeleme, 90 gün sonra silme.
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.3). Tablo: client_error_reports (migrations/035).
//
// GİZLİLİK: kullanıcı kodu, IP, cihaz kimliği (install_id) SAKLANMAZ (install_id yalnız bellek içi hız sınırı anahtarıdır). Metin alanları
// (message, stack, route, error_type, os_version) saklanmadan ÖNCE temizlenir: e-posta, telefon, JWT / Bearer / kimlik bilgisi, sorgu
// dizesindeki gizli değerler, IPv4, uzun sayı dizileri ve uzun belirteç benzeri diziler maskelenir. Ad / adres gibi serbest metin
// kişisel veriyi her koşulda yakalayamaz: istemci mesajlara kullanıcı verisi koymamalıdır (F3 raporlayıcı yalnız istisna türü + yığın yollar).
//
// Tekilleştirme: parmak izi = sha256(sürüm + platform + hata türü + sayısı normalleştirilmiş mesaj + yığının ilk kareleri). Aynı parmak izi
// tek satırdır (count++). Tablo büyümesi: satır tavanı (varsayılan 20000) KESİNDİR; dolunca en az görülen / en eski satırlar atılarak yer açılır (yeni parmak izi reddedilmez).

import crypto from 'node:crypto';
import { pool } from '../db.js';
import { PlatformError } from './errors.js';

export const REPORT_LIMITS = Object.freeze({
  message: 500,
  stack: 8000,
  errorType: 100,
  route: 200,
  osVersion: 40,
  build: 20,
  appVersion: 32,
});
export const RETENTION_DAYS = 90;
export const LIST_DEFAULT_LIMIT = 50;
export const LIST_MAX_LIMIT = 200;
const DEFAULT_MAX_ROWS = 20000;
const PLATFORMS = Object.freeze(['android', 'ios', 'web', 'other']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const APP_VERSION_RE = /^[0-9A-Za-z][0-9A-Za-z._+-]{0,31}$/;

// ---------------------------------------------------------------------------
// Kişisel veri temizleme (tüm kalıplar sınırlı nicelikli: doğrusal zaman, ReDoS yok)
// ---------------------------------------------------------------------------

const RE_JWT = /\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}(?:\.[A-Za-z0-9_-]*)?/g;
const RE_BEARER = /\bBearer\s+\S{3,}/gi;
const RE_URL_CREDENTIALS = /\/\/[^\s/@:]{1,64}:[^\s/@]{1,64}@/g;
const RE_EMAIL = /[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63}){1,5}/g;
const RE_SECRET_PARAM =
  /([?&;\s](?:access_token|id_token|refresh_token|token|apikey|api_key|key|password|passwd|pwd|secret|authorization|auth|code|otp|pin|sig|signature|t)=)[^&\s"')]{1,200}/gi;
const RE_IPV4 = /\b(?:\d{1,3}\.){3}\d{1,3}\b/g;
const RE_PHONE_INTL = /(?<![\w.])(?:\+|00)\d{1,3}(?:[\s().-]{0,2}\d){8,12}(?!\d)/g;
const RE_PHONE_TR = /(?<![\w.])\(?(?:0\s?)?\(?[2-5]\d{2}\)?[\s.-]?\d{3}[\s.-]?\d{2}[\s.-]?\d{2}(?!\d)/g;
const RE_DIGITS_SEPARATED = /\d(?:[ .-]?\d){8,}/g;
const RE_DIGITS_LONG = /\d{6,}/g;
const RE_HEX_LONG = /\b[A-Fa-f0-9]{32,}\b/g;
const RE_TOKEN_RUN = /[A-Za-z0-9_-]{40,}/g;
// eslint-disable-next-line no-control-regex
const RE_CONTROL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g;

/** Metindeki kişisel veriyi / gizli değerleri maskeler. Boyut sınırlaması YAPMAZ (çağıran sınırlar). */
export function scrubPersonalData(input) {
  let text = String(input ?? '');
  text = text.replace(RE_JWT, '[jwt]').replace(RE_BEARER, 'Bearer [token]').replace(RE_URL_CREDENTIALS, '//[credentials]@');
  if (text.includes('@')) {
    text = text.replace(RE_EMAIL, '[email]');
  }
  text = text.replace(RE_SECRET_PARAM, '$1[redacted]').replace(RE_IPV4, '[ip]').replace(RE_HEX_LONG, '[hex]');
  // Uzun harf+rakam karışık diziler (erişim anahtarı, oturum kimliği); yalnız harf ya da yalnız rakam olanlar (uzun sembol adı) korunur.
  // Sayı maskelerinden ÖNCE çalışır (belirteç içindeki rakam öbekleri parçalanmasın).
  text = text.replace(RE_TOKEN_RUN, (run) => (/\d/.test(run) && /[A-Za-z]/.test(run) ? '[token]' : run));
  return text
    .replace(RE_PHONE_INTL, '[phone]')
    .replace(RE_PHONE_TR, '[phone]')
    .replace(RE_DIGITS_SEPARATED, '[num]')
    .replace(RE_DIGITS_LONG, '[num]');
}

function cleanLine(value, max) {
  return scrubPersonalData(String(value).slice(0, max * 2).replace(RE_CONTROL, ' '))
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function cleanBlock(value, max) {
  const lines = String(value)
    .slice(0, max * 2)
    .replace(/\r\n?/g, '\n')
    .replace(RE_CONTROL, ' ')
    .split('\n')
    .map((line) => line.replace(/[ \t]+$/g, ''));
  return scrubPersonalData(lines.join('\n')).trim().slice(0, max);
}

// ---------------------------------------------------------------------------
// Doğrulama
// ---------------------------------------------------------------------------

const asText = (value) => (typeof value === 'string' ? value : typeof value === 'number' && Number.isFinite(value) ? String(value) : '');

/** Rota: yalnız yol kısmı (sorgu dizesi / parça atılır; kimlik / belirteç sızmasın). */
function cleanRoute(value) {
  const path = asText(value).split(/[?#]/)[0];
  return cleanLine(path, REPORT_LIMITS.route);
}

/**
 * POST gövdesini doğrular ve temizler.
 * @returns {{ report: object } | { error: string }}
 */
export function normalizeReport(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return { error: 'Gövde bir nesne olmalıdır.' };
  }
  const installId = asText(body.install_id).trim();
  if (!UUID_RE.test(installId)) {
    return { error: 'install_id geçerli bir UUID olmalıdır.' };
  }
  const appVersion = asText(body.app_version).trim();
  if (!APP_VERSION_RE.test(appVersion)) {
    return { error: 'app_version geçersiz.' };
  }
  const message = cleanLine(asText(body.message), REPORT_LIMITS.message);
  const stack = cleanBlock(asText(body.stack), REPORT_LIMITS.stack);
  if (message === '' && stack === '') {
    return { error: 'message ya da stack gereklidir.' };
  }
  const platformRaw = asText(body.platform).trim().toLowerCase();
  const build = cleanLine(asText(body.build), REPORT_LIMITS.build);
  const osVersion = cleanLine(asText(body.os_version), REPORT_LIMITS.osVersion);
  const route = cleanRoute(body.route);
  return {
    report: {
      installId: installId.toLowerCase(),
      appVersion,
      build: build === '' ? null : build,
      platform: PLATFORMS.includes(platformRaw) ? platformRaw : 'other',
      osVersion: osVersion === '' ? null : osVersion,
      errorType: cleanLine(asText(body.error_type), REPORT_LIMITS.errorType) || 'Error',
      message: message === '' ? '(mesaj yok)' : message,
      stack: stack === '' ? null : stack,
      fatal: body.fatal === true,
      route: route === '' ? null : route,
    },
  };
}

/** Parmak izi: sürüm + platform + tür + sayısı normalleştirilmiş mesaj + yığının ilk 5 karesi (satır / sütun numaraları yok sayılır). */
export function fingerprintOf(report) {
  const squash = (text) =>
    text
      .toLowerCase()
      .replace(/0x[0-9a-f]+/g, '0x')
      .replace(/\d+/g, '#')
      .replace(/\s+/g, ' ')
      .trim();
  const frames = (report.stack ?? '')
    .split('\n')
    .map((line) => squash(line))
    .filter((line) => line !== '')
    .slice(0, 5);
  return crypto
    .createHash('sha256')
    .update(['v1', report.appVersion, report.platform, squash(report.errorType), squash(report.message).slice(0, 200), frames.join('|')].join('\n'))
    .digest('hex');
}

// ---------------------------------------------------------------------------
// Veritabanı
// ---------------------------------------------------------------------------

export function maxRows(env = process.env) {
  const configured = Number(env.CLIENT_ERROR_MAX_ROWS);
  return Number.isSafeInteger(configured) && configured > 0 ? configured : DEFAULT_MAX_ROWS;
}

/** Tavan dolduğunda tek seferde atılacak ek satır payı (tavanın %5'i, en az 1): çıkarma her yeni parmak izinde değil, seyrek çalışır. */
export function evictionBatch(max) {
  return Math.max(1, Math.ceil(max * 0.05));
}

// Yazıcılar tek advisory kilidiyle SIRALANIR: tavan denetimi (COUNT) ile ekleme arasında başka yazıcı giremez -> tavan süreçler arası da KESİN
// (ön bellekli sayıma güvenen önceki sürümde eşzamanlı 600 rapor tavanı 6 kat aşmıştı). İki-int anahtar, sınıf "CLER" (silme işi: 1, yazma: 2).
export const WRITE_LOCK_JOB = 2;

/**
 * Eşzamanlı yazıcı sınırı: raporlar bağlantı havuzunu (API'nin geri kalanıyla ORTAK) tüketmesin diye en çok `max` yazma aynı anda çalışır, en çok
 * `queueLimit` bekler; kuyruk doluysa rapor ATILIR (istemciye yine 202; telemetri kaybı havuz açlığından iyidir).
 *
 * VARSAYILAN max = 1 (R7): yazmalar zaten TEK advisory kilitle sıralanır; süreç içinde birden çok yazıcıya izin vermek ek verim sağlamaz, yalnız
 * fazla bağlantıyı kilit beklerken boşa tutar (max 4 iken bağlantıların %75'i iş üretmeden bekliyordu). Tek yazıcı + kuyruk, kilidi süreç içinde
 * bekletmeden (kilit yalnız PM2 küme / çok süreç durumunda başka süreçle çekişir) bir bağlantıyla işi eritir. Kilit BLOKLAYAN kalır
 * (pg_try_advisory_xact_lock + atma tercih edilmedi): aksi halde çok süreçli kurulumda iki yazıcı çakıştığında geçerli rapor sebepsiz atılırdı.
 */
export function createWriteGate({ max = 1, queueLimit = 200 } = {}) {
  let active = 0;
  const waiting = [];
  const release = () => {
    active -= 1;
    const next = waiting.shift();
    if (next) {
      active += 1;
      next();
    }
  };
  return {
    stats: () => ({ active, waiting: waiting.length }),
    /** @returns {Promise<{ dropped: true } | { dropped: false, value: any }>} */
    async run(task) {
      if (active >= max) {
        if (waiting.length >= queueLimit) {
          return { dropped: true };
        }
        await new Promise((resolve) => waiting.push(resolve));
      } else {
        active += 1;
      }
      try {
        return { dropped: false, value: await task() };
      } finally {
        release();
      }
    },
  };
}

const defaultWriteGate = createWriteGate();

async function storeReportTx(client, report, fingerprint, max) {
  await client.query('BEGIN');
  try {
    await client.query('SELECT pg_advisory_xact_lock($1::int, $2::int)', [PURGE_LOCK_CLASS, WRITE_LOCK_JOB]);
    // 1. Var olan parmak izi: sayaç artar (tavandan bağımsız).
    const hit = await client.query(
      `
        UPDATE client_error_reports
        SET count = LEAST(count, 2147483646) + 1,
            last_seen = NOW(),
            fatal = fatal OR $2,
            build = COALESCE($3, build),
            os_version = COALESCE($4, os_version),
            route = COALESCE($5, route)
        WHERE fingerprint = $1
      `,
      [fingerprint, report.fatal, report.build, report.osVersion, report.route],
    );
    let evicted = 0;
    if ((hit.rowCount ?? 0) === 0) {
      // 2. Yeni parmak izi: tavan doluysa ÖNCE yer açılır. Çıkarma sırası: en az görülen (count), eşitlikte en eski (last_seen). Tekrarlayan GERÇEK
      // çökmeler yüksek sayaçla korunur; tek seferlik (kimliksiz, içeriği değiştirilmiş) çöp raporlar önce gider -> tablo "körleşmez".
      const total = Number((await client.query('SELECT COUNT(*)::int AS n FROM client_error_reports')).rows?.[0]?.n ?? 0);
      if (total >= max) {
        const removed = await client.query(
          `
            DELETE FROM client_error_reports
            WHERE id IN (SELECT id FROM client_error_reports ORDER BY count ASC, last_seen ASC, id ASC LIMIT $1)
          `,
          [total - max + evictionBatch(max)],
        );
        evicted = removed.rowCount ?? 0;
      }
      await client.query(
        `
          INSERT INTO client_error_reports (fingerprint, error_type, message, app_version, build, platform, os_version, route, fatal, sample_stack)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
          ON CONFLICT (fingerprint) DO UPDATE SET count = LEAST(client_error_reports.count, 2147483646) + 1, last_seen = NOW()
        `,
        [
          fingerprint,
          report.errorType,
          report.message,
          report.appVersion,
          report.build,
          report.platform,
          report.osVersion,
          report.route,
          report.fatal,
          report.stack,
        ],
      );
    }
    await client.query('COMMIT');
    return { stored: true, inserted: (hit.rowCount ?? 0) === 0, evicted };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

/**
 * Raporu kaydeder: aynı parmak izi -> count + 1; yeni parmak izi -> eklenir. Satır tavanı (CLIENT_ERROR_MAX_ROWS, varsayılan 20000) KESİNDİR:
 * tavan doluysa en az görülen / en eski satırlar atılarak (tavanın %5'i kadar) yer açılır, yeni parmak izi asla reddedilmez.
 * @returns {Promise<{ stored: boolean, dropped?: boolean, inserted?: boolean, evicted?: number, fingerprint: string }>}
 */
export async function storeReport(report, { connect = () => pool.connect(), max = maxRows(), gate = defaultWriteGate } = {}) {
  const fingerprint = fingerprintOf(report);
  const outcome = await gate.run(async () => {
    const client = await connect();
    try {
      return await storeReportTx(client, report, fingerprint, max);
    } finally {
      client.release();
    }
  });
  if (outcome.dropped) {
    return { stored: false, dropped: true, fingerprint };
  }
  return { ...outcome.value, fingerprint };
}

const CURSOR_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

export function encodeCursor(lastSeenText, id) {
  return Buffer.from(JSON.stringify([lastSeenText, String(id)]), 'utf8').toString('base64url');
}

/** @returns {{ lastSeen: string, id: string } | null} biçimsizse null */
export function decodeCursor(cursor) {
  try {
    const parsed = JSON.parse(Buffer.from(String(cursor), 'base64url').toString('utf8'));
    if (Array.isArray(parsed) && parsed.length === 2 && CURSOR_RE.test(parsed[0]) && /^\d{1,18}$/.test(parsed[1])) {
      return { lastSeen: parsed[0], id: parsed[1] };
    }
  } catch (_error) {
    // aşağıda null
  }
  return null;
}

export function clampListLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return LIST_DEFAULT_LIMIT;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return LIST_DEFAULT_LIMIT;
  }
  return Math.min(LIST_MAX_LIMIT, Math.max(1, Math.floor(parsed)));
}

const iso = (value) => (value instanceof Date ? value.toISOString() : new Date(value).toISOString());

/**
 * Süper kullanıcı listesi: son görülene göre yeniden eskiye, imleçli (anahtar kümesi: last_seen DESC, id DESC).
 * Geçersiz imleç -> 400 INVALID_CURSOR.
 * @returns {Promise<{ items: object[], next_cursor: string|null }>}
 */
export async function listReports({ limit, cursor } = {}, db = pool) {
  const pageSize = clampListLimit(limit);
  const decoded = cursor === undefined || cursor === null || cursor === '' ? null : decodeCursor(cursor);
  if (cursor !== undefined && cursor !== null && cursor !== '' && !decoded) {
    throw new PlatformError(400, 'INVALID_CURSOR', 'Geçersiz imleç.');
  }
  const result = await db.query(
    `
      SELECT
        id, fingerprint, error_type, message, app_version, platform, fatal, count, first_seen, last_seen, sample_stack,
        to_char(last_seen AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS last_seen_text
      FROM client_error_reports
      WHERE ($1::timestamptz IS NULL OR (last_seen, id) < ($1::timestamptz, $2::bigint))
      ORDER BY last_seen DESC, id DESC
      LIMIT $3
    `,
    [decoded?.lastSeen ?? null, decoded?.id ?? null, pageSize + 1],
  );
  const rows = result.rows ?? [];
  const page = rows.slice(0, pageSize);
  const last = page.at(-1);
  return {
    items: page.map((row) => ({
      fingerprint: row.fingerprint,
      error_type: row.error_type,
      message: row.message,
      app_version: row.app_version,
      platform: row.platform,
      fatal: row.fatal === true,
      count: Number(row.count),
      first_seen: iso(row.first_seen),
      last_seen: iso(row.last_seen),
      sample_stack: row.sample_stack ?? null,
    })),
    next_cursor: rows.length > pageSize && last ? encodeCursor(last.last_seen_text, last.id) : null,
  };
}

// ---------------------------------------------------------------------------
// 90 gün sonra silme (tek çalışan)
// ---------------------------------------------------------------------------

/** İki-int advisory kilit anahtarı: sınıf "CLER". Süreçler arası TEK çalışan (transaction kilidi: süreç ölürse kilit düşer). */
export const PURGE_LOCK_CLASS = 0x434c4552;
export const PURGE_LOCK_JOB = 1;
const PURGE_BATCH = 2000;
const PURGE_MAX_BATCHES = 50;

/**
 * first_seen'i `retentionDays` günden eski satırları siler (kalıcı saklama sınırı: bir hata kaydı ilk görüldüğünden 90 gün sonra silinir; hâlâ
 * sürüyorsa bir sonraki raporda yeni satır olarak başlar). Başka bir süreç çalıştırıyorsa atlanır.
 * @returns {Promise<{ skipped: boolean, deleted: number }>}
 */
export async function purgeOldReports({ retentionDays = RETENTION_DAYS, connect = () => pool.connect() } = {}) {
  const client = await connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const lock = await client.query('SELECT pg_try_advisory_xact_lock($1::int, $2::int) AS locked', [PURGE_LOCK_CLASS, PURGE_LOCK_JOB]);
    if (lock.rows?.[0]?.locked !== true) {
      await client.query('ROLLBACK');
      return { skipped: true, deleted: 0 };
    }
    let deleted = 0;
    for (let batch = 0; batch < PURGE_MAX_BATCHES; batch += 1) {
      const result = await client.query(
        `
          DELETE FROM client_error_reports
          WHERE id IN (
            SELECT id FROM client_error_reports
            WHERE first_seen < NOW() - make_interval(days => $1::int)
            ORDER BY id
            LIMIT ${PURGE_BATCH}
          )
        `,
        [retentionDays],
      );
      deleted += result.rowCount ?? 0;
      if ((result.rowCount ?? 0) < PURGE_BATCH) {
        break;
      }
    }
    await client.query('COMMIT');
    return { skipped: false, deleted };
  } catch (error) {
    if (began) {
      await client.query('ROLLBACK').catch(() => {});
    }
    throw error;
  } finally {
    client.release();
  }
}
