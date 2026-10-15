// Denetim kaydı (audit_log): yalnızca EKLENİR; güncelleme/silme yoktur ve bakım servisi temizlemez.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("GET /admin/audit-log").
// Bugünkü helpers.auditLog yalnızca console.log yazar; bu servis veritabanına yazar.

import { pool } from '../db.js';

export const AUDIT_DEFAULT_LIMIT = 50;
export const AUDIT_MAX_LIMIT = 200;

const ACTOR_NAME_MAX = 200;
const FIELD_MAX = 200;

function clipText(value, max) {
  if (value === null || value === undefined) {
    return null;
  }
  const text = String(value).replace(/\s+/g, ' ').trim();
  return text === '' ? null : text.slice(0, max);
}

function positiveIntOrNull(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

/** authUser nesnesinden denetim "kim" alanları. */
export function actorFromAuthUser(authUser) {
  return {
    userCode: positiveIntOrNull(authUser?.user_code ?? authUser?.userCode ?? authUser?.id),
    name: clipText(authUser?.full_name ?? authUser?.fullName ?? authUser?.name, ACTOR_NAME_MAX),
    role: clipText(authUser?.role, 60),
  };
}

/**
 * Denetim satırı yazar.
 *
 * `db`: pool veya transaction client'ı (query(text, params) olan herhangi bir nesne).
 * Başarısız olursa ana işlemi BOZMAZ: hata yutulur ve console'a yazılır, `false` döner.
 *  - Transaction içinde çağrılırken `{ inTransaction: true }` verin: ekleme SAVEPOINT içinde yapılır, böylece
 *    başarısız bir INSERT transaction'ı "aborted" durumuna sokmaz ve ana değişiklik yine de kaydedilebilir.
 *    Normal durumda değişiklik ve kayıt AYNI transaction'da birlikte işlenir/geri alınır.
 *
 * @param {{ query: Function }} db  `recordAudit(entry)` biçiminde çağrılırsa varsayılan havuz (pool) kullanılır
 * @param {{ actor?: object|null, action: string, siteCode?: number|string|null, targetType?: string|null,
 *           targetId?: string|number|null, details?: object }} entry  actor: authUser (veya actorFromAuthUser çıktısı)
 * @returns {Promise<boolean>}
 */
export async function recordAudit(db, entry, options) {
  if (db && typeof db.query !== 'function') {
    return recordAudit(pool, db, entry);
  }
  const { inTransaction = false } = options ?? {};
  const savepoint = 'audit_insert';
  try {
    const action = clipText(entry?.action, FIELD_MAX);
    if (!action) {
      throw new Error('audit action zorunlu');
    }
    const actor = actorFromAuthUser(entry?.actor);
    const details = entry?.details && typeof entry.details === 'object' ? entry.details : {};

    if (inTransaction) {
      await db.query(`SAVEPOINT ${savepoint}`);
    }
    try {
      await db.query(
        `
          INSERT INTO audit_log (
            actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
        `,
        [
          actor.userCode ?? null,
          actor.name ?? null,
          actor.role ?? null,
          action,
          positiveIntOrNull(entry?.siteCode),
          clipText(entry?.targetType, FIELD_MAX),
          clipText(entry?.targetId, FIELD_MAX),
          JSON.stringify(details),
        ],
      );
    } catch (insertError) {
      if (inTransaction) {
        await db.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
        await db.query(`RELEASE SAVEPOINT ${savepoint}`);
      }
      throw insertError;
    }
    if (inTransaction) {
      await db.query(`RELEASE SAVEPOINT ${savepoint}`);
    }
    return true;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[audit] denetim kaydi yazilamadi:', error?.code || error?.message || error);
    return false;
  }
}

/** `limit` sorgu değeri -> 1..200 (yok/sayı değilse 50). */
export function clampAuditLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return AUDIT_DEFAULT_LIMIT;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return AUDIT_DEFAULT_LIMIT;
  }
  return Math.min(AUDIT_MAX_LIMIT, Math.max(1, Math.floor(parsed)));
}

function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function mapAuditRow(row) {
  let details = row.details;
  if (typeof details === 'string') {
    try {
      details = JSON.parse(details);
    } catch (_error) {
      details = {};
    }
  }
  return {
    id: Number(row.id),
    created_at: toIso(row.created_at),
    actor_user_code:
      row.actor_user_code === null || row.actor_user_code === undefined ? null : Number(row.actor_user_code),
    actor_name: row.actor_name ?? null,
    actor_role: row.actor_role ?? null,
    action: row.action,
    site_code: row.site_code === null || row.site_code === undefined ? null : Number(row.site_code),
    site_name: row.site_name ?? null,
    target_type: row.target_type ?? null,
    target_id: row.target_id ?? null,
    details: details && typeof details === 'object' ? details : {},
  };
}

/**
 * Denetim kaydı sayfası (id DESC). Sonraki sayfa `beforeId = next_before_id`; son sayfada next_before_id null.
 * İsteğe bağlı süzgeçler: `siteCode`, `action` (tam eşleşme, ör. "module.disabled").
 * @returns {Promise<{ items: object[], next_before_id: number|null }>}
 */
export async function listAuditLog(
  { siteCode = null, limit = AUDIT_DEFAULT_LIMIT, beforeId = null, action = null } = {},
  db = pool,
) {
  const pageSize = clampAuditLimit(limit);
  // Bir fazla satır çekilir: fazlası varsa sonraki sayfa vardır.
  const result = await db.query(
    `
      SELECT
        a.id,
        a.created_at,
        a.actor_user_code,
        a.actor_name,
        a.actor_role,
        a.action,
        a.site_code,
        s.name AS site_name,
        a.target_type,
        a.target_id,
        a.details
      FROM audit_log a
      LEFT JOIN sites s ON s.site_code = a.site_code
      WHERE ($1::BIGINT IS NULL OR a.site_code = $1::BIGINT)
        AND ($2::BIGINT IS NULL OR a.id < $2::BIGINT)
        AND ($4::TEXT IS NULL OR a.action = $4::TEXT)
      ORDER BY a.id DESC
      LIMIT $3
    `,
    [siteCode ?? null, beforeId ?? null, pageSize + 1, action ?? null],
  );
  const rows = result.rows ?? [];
  const hasMore = rows.length > pageSize;
  const items = rows.slice(0, pageSize).map(mapAuditRow);
  return {
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
  };
}
