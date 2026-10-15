// Modül talebi akışı (Faz 1.1): site yöneticisi modülü KENDİ açmaz; TALEP eder, sistem yöneticisi (süper kullanıcı)
// onaylar ya da reddeder. Satın alma sistemi gelince bu akış otomatikleşecek.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Faz 1.1"). Tablo: module_requests (migrations/030).
//  - Aynı (site, modül) için TEK bekleyen talep: kısmi tekil indeks uq_module_requests_pending (+ servis kontrolü).
//  - Onay: AYNI transaction'da site_modules upsert (enabled=true) + audit (module.enabled, module_request.approved) +
//    talep güncelleme; talep satırı FOR UPDATE ile kilitlenir (eşzamanlı onay/ret/geri çekme yarışı olmaz).
//  - Modül açma/kapama ile aynı advisory kilit anahtarı (`site_module:<site>:<modül>`) kullanılır.

import { pool } from '../db.js';
import { sendModuleRequestNotificationEmail } from '../mailer.js';
import { actorFromAuthUser, clampAuditLimit, recordAudit } from './audit_service.js';
import { computeModuleEnabled, getModuleDefinition, MODULE_STATUS_COMING_SOON } from './catalog.js';
import { PlatformError } from './errors.js';
import { moduleLockKey } from './module_service.js';

export const MODULE_REQUEST_NOTE_MAX = 500;
export const MODULE_REQUEST_STATUSES = Object.freeze(['pending', 'approved', 'rejected', 'cancelled']);
export const MODULE_REQUEST_LIST_LIMIT = 50;

const REQUEST_SELECT = `
  SELECT
    r.id,
    r.site_code,
    s.name AS site_name,
    r.module_code,
    r.status,
    r.note,
    r.requested_by_name,
    r.created_at,
    r.decided_by_name,
    r.decided_at,
    r.decision_note
  FROM module_requests r
  LEFT JOIN sites s ON s.site_code = r.site_code
`;

function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function toPositiveInt(value, max = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= max ? parsed : null;
}

/** `request` nesnesi: sözleşmedeki alanlar (ve yalnız onlar). */
export function mapModuleRequestRow(row) {
  const definition = getModuleDefinition(row.module_code);
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name ?? null,
    module_code: row.module_code,
    module_name: definition ? definition.name : row.module_code,
    status: row.status,
    note: row.note ?? null,
    requested_by_name: row.requested_by_name ?? null,
    created_at: toIso(row.created_at),
    decided_by_name: row.decided_by_name ?? null,
    decided_at: toIso(row.decided_at),
    decision_note: row.decision_note ?? null,
  };
}

// Kaynakta Unicode kaçış dizisi kullanılmaz (araç zinciri bunları görünmez karaktere çevirebilir): kod noktaları sayıyla denetlenir.
const CHAR_TAB = 9;
const CHAR_LF = 10;
const CHAR_CR = 13;
const CHAR_DEL = 127;
const CHAR_LINE_SEPARATOR = 8232;
const CHAR_PARAGRAPH_SEPARATOR = 8233;

function stripControlCharacters(text) {
  let out = '';
  for (const ch of text) {
    const code = ch.codePointAt(0);
    const isControl = code < 32 && code !== CHAR_TAB && code !== CHAR_LF && code !== CHAR_CR;
    if (isControl || code === CHAR_DEL || code === CHAR_LINE_SEPARATOR || code === CHAR_PARAGRAPH_SEPARATOR) {
      continue;
    }
    out += ch;
  }
  return out;
}

/**
 * İsteğe bağlı not: metin olmalı, kontrol karakterleri (satır sonu ve sekme hariç) atılır, kırpılır, en çok 500 karakter.
 * Boş -> null. Geçersiz -> 400 INVALID_BODY.
 */
export function normalizeRequestNote(value, label = 'Not') {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new PlatformError(400, 'INVALID_BODY', `${label} metin olmalıdır.`);
  }
  const text = stripControlCharacters(value).replace(/\r\n?/g, '\n').trim();
  if (Array.from(text).length > MODULE_REQUEST_NOTE_MAX) {
    throw new PlatformError(400, 'INVALID_BODY', `${label} en fazla ${MODULE_REQUEST_NOTE_MAX} karakter olabilir.`);
  }
  return text === '' ? null : text;
}

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_error) {
    // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
  }
}

async function loadRequestView(requestId, db = pool) {
  const result = await db.query(`${REQUEST_SELECT} WHERE r.id = $1 LIMIT 1`, [requestId]);
  const row = result.rows?.[0];
  return row ? mapModuleRequestRow(row) : null;
}

// ---------------------------------------------------------------------------
// Bildirim (e-posta) — fire-and-forget; hata talebi bozmaz
// ---------------------------------------------------------------------------

/** Tüm AKTİF süper kullanıcılara yeni talep e-postası gönderir (her biri bağımsız; hatalar loglanır). */
export async function notifySuperUsersOfRequest(request) {
  const result = await pool.query(
    `
      SELECT full_name, email
      FROM users
      WHERE role = 'super_user'
        AND is_active = TRUE
        AND email IS NOT NULL
        AND email <> ''
    `,
  );
  const recipients = result.rows ?? [];
  const outcomes = await Promise.allSettled(
    recipients.map((recipient) =>
      sendModuleRequestNotificationEmail({
        to: recipient.email,
        fullName: recipient.full_name,
        siteName: request.site_name,
        moduleName: request.module_name,
        requesterName: request.requested_by_name,
        note: request.note,
      }),
    ),
  );
  for (const outcome of outcomes) {
    if (outcome.status === 'rejected') {
      // eslint-disable-next-line no-console
      console.error('[module_request] bildirim e-postasi gonderilemedi:', outcome.reason?.code || outcome.reason?.message || 'hata');
    }
  }
  return outcomes.filter((outcome) => outcome.status === 'fulfilled').length;
}

/** Test/entegrasyon kancası: yeni talep bildirimi (varsayılan: süper kullanıcılara e-posta). */
export const moduleRequestHooks = {
  notifyCreated: notifySuperUsersOfRequest,
};

function fireAndForgetNotification(request) {
  Promise.resolve()
    .then(() => moduleRequestHooks.notifyCreated(request))
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error('[module_request] bildirim basarisiz:', error?.code || error?.message || 'hata');
    });
}

// ---------------------------------------------------------------------------
// Site yöneticisi: talep et / listele / geri çek
// ---------------------------------------------------------------------------

/**
 * POST: modül talebi oluşturur. Hata sırası: INVALID_BODY, MODULE_NOT_FOUND (404), core -> MODULE_NOT_TOGGLEABLE (400),
 * yakında -> MODULE_COMING_SOON (409), zaten açık -> MODULE_ALREADY_ENABLED (409), bekleyen var -> MODULE_REQUEST_PENDING (409).
 * @returns {Promise<object>} request nesnesi
 */
export async function createModuleRequest({ siteCode, moduleCode, note, actor }) {
  if (typeof moduleCode !== 'string' || moduleCode.trim() === '') {
    throw new PlatformError(400, 'INVALID_BODY', 'module_code zorunludur.');
  }
  const noteText = normalizeRequestNote(note);
  const code = moduleCode.trim();
  const definition = getModuleDefinition(code);
  if (!definition) {
    throw new PlatformError(404, 'MODULE_NOT_FOUND', 'Modül bulunamadı.');
  }
  if (definition.core) {
    throw new PlatformError(400, 'MODULE_NOT_TOGGLEABLE', 'Bu modül her sitede hep açıktır; talep edilemez.');
  }
  if (definition.status === MODULE_STATUS_COMING_SOON) {
    throw new PlatformError(409, 'MODULE_COMING_SOON', 'Bu modül yakında.');
  }
  const site = toPositiveInt(siteCode);
  if (site === null) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  let requestId;
  try {
    await client.query('BEGIN');
    // KİLİT SIRASI (modül aç/kapa ve onayla ortak): 1) site satırı FOR SHARE, 2) site+modül advisory kilidi (aç/kapa
    // ile AYNI anahtar: eşzamanlı talep/onay/toggle sıraya girer), 3) talep satırı.
    const siteResult = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [site]);
    if (!siteResult.rows?.[0]) {
      throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
    }
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [moduleLockKey(site, code)]);

    const currentResult = await client.query(
      `SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = $2 LIMIT 1`,
      [site, code],
    );
    if (computeModuleEnabled(definition, currentResult.rows?.[0])) {
      throw new PlatformError(409, 'MODULE_ALREADY_ENABLED', 'Bu modül zaten açık.');
    }

    const pendingResult = await client.query(
      `SELECT id FROM module_requests WHERE site_code = $1 AND module_code = $2 AND status = 'pending' LIMIT 1`,
      [site, code],
    );
    if (pendingResult.rows?.[0]) {
      throw new PlatformError(409, 'MODULE_REQUEST_PENDING', 'Bu modül için bekleyen bir talebiniz var.');
    }

    let insertResult;
    try {
      insertResult = await client.query(
        `
          INSERT INTO module_requests (site_code, module_code, status, requested_by, requested_by_name, note)
          VALUES ($1, $2, 'pending', $3, $4, $5)
          RETURNING id
        `,
        [site, code, actorInfo.userCode, actorInfo.name, noteText],
      );
    } catch (error) {
      // kısmi tekil indeks (eşzamanlı çift talep): 23505 -> bekleyen talep var
      if (error?.code === '23505') {
        throw new PlatformError(409, 'MODULE_REQUEST_PENDING', 'Bu modül için bekleyen bir talebiniz var.');
      }
      throw error;
    }
    requestId = toPositiveInt(insertResult.rows?.[0]?.id);

    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'module_request.created',
        siteCode: site,
        targetType: 'module_request',
        targetId: String(requestId),
        details: { module_code: code },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }

  const request = await loadRequestView(requestId);
  if (request) {
    fireAndForgetNotification(request);
  }
  return request;
}

/** GET: sitenin son 50 talebi (id DESC). Site yoksa 404 SITE_NOT_FOUND. */
export async function listSiteModuleRequests(siteCode, db = pool) {
  const site = toPositiveInt(siteCode);
  const siteResult = site === null ? null : await db.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [site]);
  if (!siteResult?.rows?.[0]) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const result = await db.query(
    `${REQUEST_SELECT} WHERE r.site_code = $1 ORDER BY r.id DESC LIMIT ${MODULE_REQUEST_LIST_LIMIT}`,
    [site],
  );
  return (result.rows ?? []).map(mapModuleRequestRow);
}

/**
 * DELETE: bekleyen talebi geri çeker (cancelled). Başka sitenin talebi 404 REQUEST_NOT_FOUND (varlık sızmaz);
 * bekleyen değilse 409 REQUEST_NOT_PENDING. decided_by/decided_at geri çekeni ve zamanı gösterir.
 */
export async function cancelModuleRequest({ siteCode, requestId, actor }) {
  const site = toPositiveInt(siteCode);
  const id = toPositiveInt(requestId);
  if (site === null) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  if (id === null) {
    throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
  }
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const found = await client.query(
      `SELECT id, site_code, module_code, status FROM module_requests WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [id, site],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
    }
    if (row.status !== 'pending') {
      throw new PlatformError(409, 'REQUEST_NOT_PENDING', 'Bu talep artık bekleyen durumda değil.');
    }
    await client.query(
      `
        UPDATE module_requests
        SET status = 'cancelled', decided_by = $2, decided_by_name = $3, decided_at = NOW()
        WHERE id = $1
      `,
      [id, actorInfo.userCode, actorInfo.name],
    );
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'module_request.cancelled',
        siteCode: site,
        targetType: 'module_request',
        targetId: String(id),
        details: { module_code: row.module_code },
      },
      { inTransaction: true },
    );
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
  return loadRequestView(id);
}

// ---------------------------------------------------------------------------
// Süper kullanıcı: listele / karar ver
// ---------------------------------------------------------------------------

/** `status` süzgeci: boş -> pending; pending|approved|rejected|cancelled|all; aksi 400 INVALID_QUERY. */
export function parseRequestStatusFilter(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return 'pending';
  }
  const text = typeof value === 'string' ? value.trim() : '';
  if (text === 'all' || MODULE_REQUEST_STATUSES.includes(text)) {
    return text;
  }
  throw new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
}

/**
 * GET /admin/module-requests: { items, next_before_id, pending_count }.
 * `pending_count` süzgeçten bağımsız toplam bekleyen sayısıdır.
 */
export async function listAdminModuleRequests({ status = 'pending', limit, beforeId = null } = {}, db = pool) {
  const filter = parseRequestStatusFilter(status);
  const pageSize = clampAuditLimit(limit);
  const result = await db.query(
    `
      ${REQUEST_SELECT}
      WHERE ($1::TEXT IS NULL OR r.status = $1::TEXT)
        AND ($2::BIGINT IS NULL OR r.id < $2::BIGINT)
      ORDER BY r.id DESC
      LIMIT $3
    `,
    [filter === 'all' ? null : filter, beforeId ?? null, pageSize + 1],
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > pageSize;
  const items = rows.slice(0, pageSize).map(mapModuleRequestRow);
  const countResult = await db.query(`SELECT COUNT(*)::INTEGER AS pending_count FROM module_requests WHERE status = 'pending'`);
  return {
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
    pending_count: Number(countResult.rows?.[0]?.pending_count ?? 0),
  };
}

/**
 * PUT /admin/module-requests/:id — approve | reject. Talep satırı FOR UPDATE ile kilitlenir.
 *  - Yok 404 REQUEST_NOT_FOUND; bekleyen değilse 409 REQUEST_NOT_PENDING.
 *  - approve: onay anında modül artık "yakında" ise 409 MODULE_COMING_SOON, zaten açıksa 409 MODULE_ALREADY_ENABLED
 *    (talep bekleyen KALIR). Aksi halde site_modules upsert + module.enabled (details {via:'request', request_id}) +
 *    module_request.approved audit + talep güncellemesi AYNI transaction'da.
 *  - reject: talep rejected + module_request.rejected audit.
 */
export async function decideModuleRequest({ requestId, decision, note, actor }) {
  const id = toPositiveInt(requestId);
  if (id === null) {
    throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
  }
  if (decision !== 'approve' && decision !== 'reject') {
    throw new PlatformError(400, 'INVALID_BODY', 'decision approve veya reject olmalıdır.');
  }
  const decisionNote = normalizeRequestNote(note, 'Gerekçe');
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    // KİLİT SIRASI (create ve modül aç/kapa ile aynı): site -> advisory -> talep satırı. Talep satırını kilitlemeden ÖNCE
    // site_code kilitsiz okunur; site silme (sites satırı -> CASCADE ile talep satırı) ile ters sıra deadlock'u olmaz.
    const peek = await client.query(
      `SELECT site_code, module_code FROM module_requests WHERE id = $1`,
      [id],
    );
    const peeked = peek.rows?.[0];
    if (!peeked) {
      throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
    }
    const siteCode = Number(peeked.site_code);
    const moduleCode = peeked.module_code;
    const siteLock = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [siteCode]);
    if (!siteLock.rows?.[0]) {
      throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
    }
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [moduleLockKey(siteCode, moduleCode)]);
    const found = await client.query(
      `SELECT id, site_code, module_code, status FROM module_requests WHERE id = $1 FOR UPDATE`,
      [id],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw new PlatformError(404, 'REQUEST_NOT_FOUND', 'Talep bulunamadı.');
    }
    if (row.status !== 'pending') {
      throw new PlatformError(409, 'REQUEST_NOT_PENDING', 'Bu talep artık bekleyen durumda değil.');
    }

    if (decision === 'approve') {
      const definition = getModuleDefinition(moduleCode);
      if (!definition) {
        throw new PlatformError(404, 'MODULE_NOT_FOUND', 'Modül bulunamadı.');
      }
      if (definition.status === MODULE_STATUS_COMING_SOON) {
        throw new PlatformError(409, 'MODULE_COMING_SOON', 'Bu modül yakında.');
      }
      const currentResult = await client.query(
        `SELECT enabled FROM site_modules WHERE site_code = $1 AND module_code = $2 LIMIT 1`,
        [siteCode, moduleCode],
      );
      if (computeModuleEnabled(definition, currentResult.rows?.[0])) {
        throw new PlatformError(409, 'MODULE_ALREADY_ENABLED', 'Bu modül zaten açık.');
      }
      await client.query(
        `
          INSERT INTO site_modules (site_code, module_code, enabled, updated_by, updated_at)
          VALUES ($1, $2, TRUE, $3, NOW())
          ON CONFLICT (site_code, module_code)
          DO UPDATE SET enabled = TRUE, updated_by = EXCLUDED.updated_by, updated_at = NOW()
        `,
        [siteCode, moduleCode, actorInfo.userCode],
      );
      await recordAudit(
        client,
        {
          actor: actorInfo,
          action: 'module.enabled',
          siteCode,
          targetType: 'module',
          targetId: moduleCode,
          details: { via: 'request', request_id: id },
        },
        { inTransaction: true },
      );
    }

    await client.query(
      `
        UPDATE module_requests
        SET status = $2, decided_by = $3, decided_by_name = $4, decision_note = $5, decided_at = NOW()
        WHERE id = $1
      `,
      [id, decision === 'approve' ? 'approved' : 'rejected', actorInfo.userCode, actorInfo.name, decisionNote],
    );
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: decision === 'approve' ? 'module_request.approved' : 'module_request.rejected',
        siteCode,
        targetType: 'module_request',
        targetId: String(id),
        details: { module_code: moduleCode },
      },
      { inTransaction: true },
    );
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
  return loadRequestView(id);
}
