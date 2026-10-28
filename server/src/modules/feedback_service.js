// Geri bildirim (103): yazma işlemleri (kayıt aç, yüklemeyi tamamla), yönetim / platform sahibi listesi ve indirme çözümlemesi.
//
// Sözleşme: docs/PLATFORM_GERI_BILDIRIM.md.
//  - Gönderen: kimliği doğrulanmış her aktif kullanıcı (modül kapısı yok: platform düzeyi bir özelliktir). `site_code` verilirse gönderen o siteyle ilişkili olmalı
//    (yönetici bağı, site üyeliği ya da CRM kişisi); süper kullanıcı her siteyi verebilir. Yabancı site 403 FORBIDDEN_SITE. ROL istemciden ALINMAZ, sunucuda türetilir.
//  - Ekran bağlamı (ekran adı + rota) kayda GİRER ve sonradan değiştirilemez (güncelleme ucu yok).
//  - KİLİT SIRASI: sites FOR KEY SHARE -> users FOR KEY SHARE (silinmiş hesaba yazma yok) -> feedback_user:<kod> advisory (saatlik sayım + günlük bayt kotası) -> satırlar.
//    Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Ekler iş takibi fotoğraf eki deseniyle iki adımlıdır: kayıt açılırken her dosya `uploading` satırı olur (storage_key sunucuda üretilir), içerik ayrı PUT ile gelir
//    (feedback_upload.js). Yüklenemeyen ek geri bildirimi bozmaz: listede yalnız `ready` ekler görünür; 2 saati aşan `uploading` satırı bakım işi siler.
//  - Okuma: site yöneticisi (yönetici / SITE_OWNER / SITE_ADMIN) ve süper kullanıcı. Kurul / görevli / sakin okuyamaz (rota katmanı 403).
//  - Audit `details` yalnız kimlik / tür / boyut / rota taşır: metin ve dosya adı ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { uploadAlreadyCompleted, uploadExpired } from './document_common.js';
import { newStorageKey } from './document_storage.js';
import {
  FEEDBACK_NO_SITE_BUCKET,
  FEEDBACK_PER_USER_PER_HOUR,
  FEEDBACK_UPLOAD_TTL_MINUTES,
  FEEDBACK_USER_DAILY_BYTES,
  feedbackAccountDeleted,
  feedbackAttachmentNotFound,
  feedbackForbiddenSite,
  feedbackQuotaExceeded,
  feedbackRateLimited,
  feedbackSiteNotFound,
  mapFeedback,
  mapFeedbackAttachment,
  parseFeedbackAttachmentId,
  parseFeedbackId,
  parseFeedbackInput,
  parseListQuery,
} from './feedback_common.js';

export const feedbackUserLockKey = (userCode) => `feedback_user:${Number(userCode)}`;

// --- Transaction ----------------------------------------------------------------------------------------------------

async function runTransactionOnce(work) {
  const client = await pool.connect();
  let began = false;
  let result;
  try {
    await client.query('BEGIN');
    began = true;
    result = await work(client);
    await client.query('COMMIT');
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
  return result;
}

/** Yazma işlemi. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). */
export async function withFeedbackTransaction(work) {
  try {
    return await runTransactionOnce(work);
  } catch (error) {
    if (error?.code === '40P01') {
      return runTransactionOnce(work);
    }
    throw error;
  }
}

// --- Gönderen rolü ----------------------------------------------------------------------------------------------------

const MEMBER_ROLE_ORDER = `CASE sm.role WHEN 'SITE_OWNER' THEN 1 WHEN 'SITE_ADMIN' THEN 2 WHEN 'BOARD_MEMBER' THEN 3 WHEN 'STAFF' THEN 4 ELSE 5 END`;

/**
 * Gönderenin rolü (kayda yazılır) ve site ilişkisi denetimi. Süper kullanıcı: 'super_user' (site verilmişse var olmalı). Siteyle gönderen: yönetici bağı ->
 * 'site_manager'; aktif site üyeliği -> rolü küçük harfle (site_owner, site_admin, board_member, staff, resident); CRM kişisi -> 'resident'; ilişki yoksa 403.
 * Site verilmediyse hesap rolü (users.role) olduğu gibi yazılır.
 */
async function resolveSenderRole(client, authUser, userCode, siteCode) {
  const accountRole = String(authUser?.role ?? '').trim().slice(0, 60) || 'unknown';
  if (siteCode === null) {
    return accountRole;
  }
  if (authUser?.role === 'super_user') {
    const exists = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!exists.rows?.[0]) throw feedbackSiteNotFound();
    return 'super_user';
  }
  const relation = await client.query(
    `
      SELECT
        EXISTS (SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2) AS is_manager,
        (
          SELECT sm.role FROM site_memberships sm
          WHERE sm.site_code = $1 AND sm.user_code = $2 AND sm.is_active = TRUE
          ORDER BY ${MEMBER_ROLE_ORDER}
          LIMIT 1
        ) AS member_role,
        EXISTS (SELECT 1 FROM site_people sp WHERE sp.site_code = $1 AND sp.user_code = $2 AND sp.is_active = TRUE) AS is_person
    `,
    [siteCode, userCode],
  );
  const row = relation.rows?.[0] ?? {};
  let role = null;
  if (row.is_manager === true) role = 'site_manager';
  else if (typeof row.member_role === 'string' && row.member_role !== '') role = row.member_role.toLowerCase();
  else if (row.is_person === true) role = 'resident';
  if (role === null) throw feedbackForbiddenSite();
  const exists = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
  if (!exists.rows?.[0]) throw feedbackSiteNotFound();
  return role;
}

// --- POST /app/feedback -------------------------------------------------------------------------------------------

/**
 * Geri bildirimi kaydeder -> { feedback } (ekler `uploading`; içerik feedback_upload.js ile gelir). Sınırlar (adet / dosya / toplam) parseFeedbackInput'ta 400 olur,
 * veritabanına gitmeden. Kullanıcı başına saatte 5 kayıt (429) ve 24 saatte 100 MB bildirilen ek (429) DB düzeyinde sayılır.
 */
export async function createFeedback({ actor, body }) {
  const input = parseFeedbackInput(body);
  const userCode = actorFromAuthUser(actor).userCode;
  if (userCode === null) {
    throw feedbackAccountDeleted();
  }
  const declaredTotal = input.attachments.reduce((sum, item) => sum + item.sizeBytes, 0);
  const created = await withFeedbackTransaction(async (client) => {
    const sender = await client.query(`SELECT user_code, full_name FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [userCode]);
    if (!sender.rows?.[0]) {
      throw feedbackAccountDeleted();
    }
    const role = await resolveSenderRole(client, actor, userCode, input.siteCode);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [feedbackUserLockKey(userCode)]);
    const hourly = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM feedback_reports WHERE user_code = $1 AND created_at > NOW() - INTERVAL '1 hour'`,
      [userCode],
    );
    if (Number(hourly.rows?.[0]?.n ?? 0) >= FEEDBACK_PER_USER_PER_HOUR) {
      throw feedbackRateLimited();
    }
    if (declaredTotal > 0) {
      const daily = await client.query(
        `
          SELECT COALESCE(SUM(a.size_bytes), 0)::BIGINT AS used
          FROM feedback_attachments a
          INNER JOIN feedback_reports r ON r.id = a.feedback_id
          WHERE r.user_code = $1 AND r.created_at > NOW() - INTERVAL '24 hours'
        `,
        [userCode],
      );
      if (Number(daily.rows?.[0]?.used ?? 0) + declaredTotal > FEEDBACK_USER_DAILY_BYTES) {
        throw feedbackQuotaExceeded();
      }
    }
    const inserted = await client.query(
      `
        INSERT INTO feedback_reports (site_code, user_code, role, screen_name, screen_route, message, app_version, platform)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id, created_at
      `,
      [input.siteCode, userCode, role, input.screenName, input.screenRoute, input.message, input.appVersion, input.platform],
    );
    const feedbackId = Number(inserted.rows[0].id);
    const attachments = [];
    for (const item of input.attachments) {
      const row = await client.query(
        `
          INSERT INTO feedback_attachments (feedback_id, file_name, mime_type, size_bytes, status, storage_key)
          VALUES ($1, $2, $3, $4, 'uploading', $5)
          RETURNING id
        `,
        [feedbackId, item.fileName, item.mimeType, item.sizeBytes, newStorageKey(input.siteCode ?? FEEDBACK_NO_SITE_BUCKET)],
      );
      attachments.push(
        mapFeedbackAttachment({
          id: row.rows[0].id,
          feedback_id: feedbackId,
          file_name: item.fileName,
          mime_type: item.mimeType,
          size_bytes: item.sizeBytes,
          status: 'uploading',
        }),
      );
    }
    await recordAudit(
      client,
      {
        actor,
        action: 'feedback.created',
        siteCode: input.siteCode,
        targetType: 'feedback',
        targetId: String(feedbackId),
        details: { role, screen_route: input.screenRoute, attachments: attachments.length, attachment_bytes: declaredTotal },
      },
      { inTransaction: true },
    );
    return {
      row: {
        id: feedbackId,
        site_code: input.siteCode,
        user_code: userCode,
        user_name: sender.rows[0].full_name,
        role,
        screen_name: input.screenName,
        screen_route: input.screenRoute,
        message: input.message,
        app_version: input.appVersion,
        platform: input.platform,
        created_at: inserted.rows[0].created_at,
      },
      attachments,
    };
  });
  return { feedback: mapFeedback(created.row, created.attachments) };
}

// --- PUT .../attachments/:attId/content: hedef ve tamamlama -----------------------------------------------------

/**
 * PUT ön kontrolü (gövde okunmadan): ek, ÇAĞIRANIN açtığı geri bildirime ait, `uploading` ve süresi dolmamış olmalı. Başkasının kaydı 404 (varlık sızmaz);
 * hazırsa 409 UPLOAD_ALREADY_COMPLETED; süresi dolmuşsa 410 UPLOAD_EXPIRED.
 * @returns {Promise<{ attId: number, feedbackId: number, siteCode: number|null, storageKey: string, sizeBytes: number, mimeType: string, fileName: string }>}
 */
export async function findFeedbackUploadTarget({ rawId, rawAttId, userCode }, db = pool) {
  const feedbackId = parseFeedbackId(rawId);
  const attId = parseFeedbackAttachmentId(rawAttId);
  const result = await db.query(
    `
      SELECT a.id, a.status, a.storage_key, a.size_bytes, a.mime_type, a.file_name, r.site_code, r.user_code,
             (a.created_at < NOW() - make_interval(mins => $3::INTEGER)) AS expired
      FROM feedback_attachments a
      INNER JOIN feedback_reports r ON r.id = a.feedback_id
      WHERE a.id = $1 AND a.feedback_id = $2
      LIMIT 1
    `,
    [attId, feedbackId, FEEDBACK_UPLOAD_TTL_MINUTES],
  );
  const row = result.rows?.[0];
  if (!row || row.user_code === null || Number(row.user_code) !== Number(userCode)) {
    throw feedbackAttachmentNotFound();
  }
  if (row.status === 'ready') {
    throw uploadAlreadyCompleted();
  }
  if (row.expired === true) {
    throw uploadExpired();
  }
  return {
    attId,
    feedbackId,
    siteCode: row.site_code === null || row.site_code === undefined ? null : Number(row.site_code),
    storageKey: row.storage_key,
    sizeBytes: Number(row.size_bytes),
    mimeType: row.mime_type,
    fileName: row.file_name,
  };
}

/**
 * Dosya diskte (son yolda) ve doğrulandı: kaydı `ready` yapar (tek işlem) + audit. Satır artık yoksa / anahtarı başkaysa / hazırsa / süresi dolmuşsa hata
 * fırlatır: çağıran son dosyayı siler.
 */
export async function completeFeedbackUpload({ target, actor, sha256 }) {
  const row = await withFeedbackTransaction(async (client) => {
    const userCode = actorFromAuthUser(actor).userCode;
    const sender = await client.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [userCode]);
    if (!sender.rows?.[0]) {
      throw feedbackAccountDeleted();
    }
    const found = await client.query(
      `
        SELECT id, feedback_id, file_name, mime_type, size_bytes, status, storage_key, (created_at < NOW() - make_interval(mins => $3::INTEGER)) AS expired
        FROM feedback_attachments WHERE id = $1 AND feedback_id = $2 FOR UPDATE
      `,
      [target.attId, target.feedbackId, FEEDBACK_UPLOAD_TTL_MINUTES],
    );
    const current = found.rows?.[0];
    if (!current || current.storage_key !== target.storageKey) {
      throw feedbackAttachmentNotFound();
    }
    if (current.status === 'ready') {
      throw uploadAlreadyCompleted();
    }
    // satır kilidi altında süre denetimi: bakım işinin silmek üzere olduğu bayat satır `ready` OLAMAZ (bakım DELETE'i aynı satırı kilitler; kim önce gelirse)
    if (current.expired === true) {
      throw uploadExpired();
    }
    await client.query(`UPDATE feedback_attachments SET status = 'ready', sha256 = $2, ready_at = NOW() WHERE id = $1`, [current.id, sha256]);
    await recordAudit(
      client,
      {
        actor,
        action: 'feedback.attachment_added',
        siteCode: target.siteCode,
        targetType: 'feedback',
        targetId: String(target.feedbackId),
        details: { attachment_id: Number(current.id), mime_type: current.mime_type, size_bytes: Number(current.size_bytes) },
      },
      { inTransaction: true },
    );
    return { ...current, status: 'ready' };
  });
  return { attachment: mapFeedbackAttachment(row) };
}

// --- Liste (yönetici / platform sahibi) ---------------------------------------------------------------------------

/**
 * Geri bildirim listesi, yeniden eskiye (id azalan). `siteCode` verilirse yalnız o site (yönetici ucu); null ise tüm kayıtlar (platform sahibi; `site_code` sorgusu süzer).
 * Yalnız `ready` ekler listelenir. Sayfalama: `cursor` = önceki sayfanın son kimliği, `limit` 1..100.
 * @returns {Promise<{ items: object[], next_cursor: number|null }>}
 */
export async function listFeedback({ siteCode = null, query = {} }, db = pool) {
  const { limit, cursor, siteCode: siteFilter } = parseListQuery(query);
  const params = [];
  const where = [];
  const scopedSite = siteCode !== null ? siteCode : siteFilter;
  if (scopedSite !== null) {
    params.push(scopedSite);
    where.push(`r.site_code = $${params.length}`);
  }
  if (cursor !== null) {
    params.push(cursor);
    where.push(`r.id < $${params.length}`);
  }
  params.push(limit + 1);
  const rows = await db.query(
    `
      SELECT r.id, r.site_code, r.user_code, r.role, r.screen_name, r.screen_route, r.message, r.app_version, r.platform, r.created_at,
             CASE WHEN u.user_code IS NULL OR u.deleted_at IS NOT NULL THEN NULL ELSE u.full_name END AS user_name,
             s.name AS site_name
      FROM feedback_reports r
      LEFT JOIN users u ON u.user_code = r.user_code
      LEFT JOIN sites s ON s.site_code = r.site_code
      ${where.length > 0 ? `WHERE ${where.join(' AND ')}` : ''}
      ORDER BY r.id DESC
      LIMIT $${params.length}
    `,
    params,
  );
  const all = rows.rows ?? [];
  const page = all.slice(0, limit);
  const byFeedback = new Map();
  if (page.length > 0) {
    const attachments = await db.query(
      `
        SELECT id, feedback_id, file_name, mime_type, size_bytes, status
        FROM feedback_attachments
        WHERE feedback_id = ANY($1::BIGINT[]) AND status = 'ready'
        ORDER BY id
      `,
      [page.map((row) => Number(row.id))],
    );
    for (const row of attachments.rows ?? []) {
      const key = Number(row.feedback_id);
      if (!byFeedback.has(key)) byFeedback.set(key, []);
      byFeedback.get(key).push(mapFeedbackAttachment(row));
    }
  }
  const includeSite = siteCode === null;
  const items = page.map((row) => mapFeedback(row, byFeedback.get(Number(row.id)) ?? [], { includeSite }));
  const nextCursor = all.length > limit && page.length > 0 ? Number(page[page.length - 1].id) : null;
  return { items, next_cursor: nextCursor };
}

// --- GET .../attachments/:attId/content ------------------------------------------------------------------------

/**
 * İndirme çözümlemesi: HAZIR ek (+ `siteCode` verildiyse o sitenin geri bildirimi); aksi 404 (varlık sızmaz).
 * @returns {Promise<{ id: number, feedbackId: number, siteCode: number|null, storageKey: string, sizeBytes: number, fileName: string, mimeType: string }>}
 */
export async function resolveFeedbackDownload({ siteCode = null, rawId, rawAttId }, db = pool) {
  const feedbackId = parseFeedbackId(rawId);
  const attId = parseFeedbackAttachmentId(rawAttId);
  const params = [attId, feedbackId];
  let siteSql = '';
  if (siteCode !== null) {
    params.push(siteCode);
    siteSql = ' AND r.site_code = $3';
  }
  const result = await db.query(
    `
      SELECT a.id, a.feedback_id, a.storage_key, a.size_bytes, a.mime_type, a.file_name, r.site_code
      FROM feedback_attachments a
      INNER JOIN feedback_reports r ON r.id = a.feedback_id
      WHERE a.id = $1 AND a.feedback_id = $2 AND a.status = 'ready'${siteSql}
      LIMIT 1
    `,
    params,
  );
  const row = result.rows?.[0];
  if (!row || !row.storage_key) {
    throw feedbackAttachmentNotFound();
  }
  return {
    id: Number(row.id),
    feedbackId,
    siteCode: row.site_code === null || row.site_code === undefined ? null : Number(row.site_code),
    storageKey: row.storage_key,
    sizeBytes: Number(row.size_bytes),
    fileName: row.file_name,
    mimeType: row.mime_type,
  };
}
