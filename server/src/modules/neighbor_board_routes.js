// Komşu panosu (modül `neighbor_board`, varsayılan KAPALI). Sözleşme: docs/PLATFORM_KOMSU_PANOSU.md.
//
//   Sakin    GET  /app/neighbor-board?site_code=   yayındaki ilanlar (+ benim bekleyen/reddedilenlerim `mine`)
//            POST /app/neighbor-board              { site_code, title, body } -> 201, durum `pending` (yönetici onayı bekler)
//            POST /app/neighbor-board/:id/report   { reason } -> şikayet (kişi başına bir kez; kendi ilanı olmaz)
//            POST /app/neighbor-board/:id/withdraw yazar kendi ilanını geri çeker
//   Yönetim  GET  /manager/sites/:siteCode/neighbor-board?status=pending|published|rejected|removed|reported
//            POST .../:id/approve | /reject { note } | /remove { note }
// Yetki: sakin = sitenin onaylı sakini (mySitesCte); yönetim = yönetici / süper (kurul, görevli 403). Modül kapalıysa 403 MODULE_DISABLED.
// Günlüğe başlık / metin YAZILMAZ. Ad görünümü: "Ad S." (soyad baş harfi).

import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { parseId } from '../utils/ids.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { FORBIDDEN_ROLE_BODY, FORBIDDEN_SITE_BODY, SITE_NOT_FOUND_BODY, getPeopleAccessKind } from './people_access.js';
import { mySitesCte } from './decision_book_resident.js';
import { INVISIBLE_RE } from './document_common.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const NEIGHBOR_BOARD_MODULE = 'neighbor_board';
export const TITLE_MIN = 3;
export const TITLE_MAX = 120;
export const BODY_MIN = 3;
export const BODY_MAX = 2000;
export const NOTE_MAX = 300;
export const REASON_MAX = 200;
export const MAX_PENDING_PER_AUTHOR = 5;
export const LIST_LIMIT = 100;
export const MANAGER_STATUSES = Object.freeze(['pending', 'published', 'rejected', 'removed', 'reported']);

export const neighborBoardRouter = express.Router();

const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla komşu panosu işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// --- Saf yardımcılar ---------------------------------------------------------------------------------------------

const invalidField = (field, message) => new PlatformError(400, 'INVALID_FIELD', message, { field });
const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Komşu Panosu modülü kapalı.', { module: NEIGHBOR_BOARD_MODULE });
const postNotFound = () => new PlatformError(404, 'POST_NOT_FOUND', 'İlan bulunamadı ya da erişiminiz yok.');

/** Düz yazı: görünmez karakterleri atar, boşlukları kırpar; satır sonu korunur. */
export function cleanText(value) {
  return String(value ?? '').replace(INVISIBLE_RE, (ch) => (ch === '\n' ? '\n' : '')).replace(/\r\n?/g, '\n').trim();
}

export function normalizePostInput(body) {
  const title = cleanText(body?.title).replace(/\s+/g, ' ');
  const text = cleanText(body?.body);
  if (title.length < TITLE_MIN || title.length > TITLE_MAX) {
    throw invalidField('title', `Başlık ${TITLE_MIN}-${TITLE_MAX} karakter olmalı.`);
  }
  if (text.length < BODY_MIN || text.length > BODY_MAX) {
    throw invalidField('body', `Metin ${BODY_MIN}-${BODY_MAX} karakter olmalı.`);
  }
  return { title, text };
}

export function normalizeNote(value, field, { required = false } = {}) {
  const note = cleanText(value).replace(/\s+/g, ' ');
  if (required && note.length === 0) {
    throw invalidField(field, 'Gerekçe yazın.');
  }
  if (note.length > (field === 'reason' ? REASON_MAX : NOTE_MAX)) {
    throw invalidField(field, 'Metin çok uzun.');
  }
  return note;
}

/** "Ayşe Yılmaz" -> "Ayşe Y."; silinmiş kullanıcı -> "Silinmiş Kullanıcı". */
export function shortName(fullName) {
  const parts = String(fullName ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'Silinmiş Kullanıcı';
  if (parts.length === 1) return parts[0];
  return `${parts.slice(0, -1).join(' ')} ${Array.from(parts[parts.length - 1])[0]}.`;
}

function mapPost(row, { manager = false } = {}) {
  const base = {
    id: Number(row.id),
    site_code: Number(row.site_code),
    title: row.title,
    body: row.body,
    status: row.status,
    author_name: shortName(row.author_deleted ? null : row.author_name),
    created_at: row.created_at,
    is_mine: row.is_mine === true,
  };
  if (manager || row.is_mine === true) {
    base.decision_note = row.decision_note ?? null;
    base.decided_at = row.decided_at ?? null;
  }
  if (manager) {
    base.report_count = Number(row.report_count ?? 0);
    base.report_reasons = Array.isArray(row.report_reasons) ? row.report_reasons : [];
  }
  return base;
}

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});
const userCodeOf = (req) => {
  const code = actorFromAuthUser(req.authUser).userCode;
  if (code === null) throw new PlatformError(403, 'ACCOUNT_DELETED', 'Hesap silinmiş.');
  return code;
};
const wrap = (context, fallback, run) => async (req, res) => {
  try {
    const result = await run(req, res);
    if (result !== undefined) res.status(result.status ?? 200).json(result.body);
  } catch (error) {
    respondError(res, context, error, fallback);
  }
};

// --- Sakin -------------------------------------------------------------------------------------------------------

async function residentSite(req, rawSite) {
  const siteCode = parseId(rawSite);
  if (siteCode === null) throw invalidField('site_code', 'Geçersiz site kodu.');
  const userCode = userCodeOf(req);
  const related = await pool.query(`WITH ${mySitesCte('$1')} SELECT EXISTS (SELECT 1 FROM my_sites WHERE site_code = $2) AS ok`, [userCode, siteCode]);
  if (related.rows?.[0]?.ok !== true) throw postNotFound();
  if (!(await isModuleEnabled(siteCode, NEIGHBOR_BOARD_MODULE))) throw moduleDisabled();
  return { siteCode, userCode };
}

const POST_SELECT = `
  p.id, p.site_code, p.title, p.body, p.status, p.decision_note, p.decided_at, p.created_at,
  u.full_name AS author_name, (u.user_code IS NULL OR u.deleted_at IS NOT NULL) AS author_deleted`;

neighborBoardRouter.get(
  '/app/neighbor-board',
  authRequired,
  readLimiter,
  wrap('neighbor_list', 'İlanlar yüklenemedi.', async (req) => {
    const { siteCode, userCode } = await residentSite(req, req.query.site_code);
    const result = await pool.query(
      `SELECT ${POST_SELECT}, (p.author_user_code = $2) AS is_mine
       FROM neighbor_posts p LEFT JOIN users u ON u.user_code = p.author_user_code
       WHERE p.site_code = $1 AND (p.status = 'published' OR (p.author_user_code = $2 AND p.status IN ('pending', 'rejected', 'removed')))
       ORDER BY p.id DESC LIMIT ${LIST_LIMIT}`,
      [siteCode, userCode],
    );
    return { body: { items: result.rows.map((row) => mapPost(row)) } };
  }),
);

neighborBoardRouter.post(
  '/app/neighbor-board',
  authRequired,
  writeLimiter,
  wrap('neighbor_create', 'İlan kaydedilemedi.', async (req) => {
    const body = bodyOf(req);
    const { title, text } = normalizePostInput(body);
    const { siteCode, userCode } = await residentSite(req, body.site_code);
    const pending = await pool.query(`SELECT COUNT(*)::INT AS n FROM neighbor_posts WHERE site_code = $1 AND author_user_code = $2 AND status = 'pending'`, [siteCode, userCode]);
    if ((pending.rows?.[0]?.n ?? 0) >= MAX_PENDING_PER_AUTHOR) {
      throw new PlatformError(409, 'PENDING_LIMIT', `Onay bekleyen en fazla ${MAX_PENDING_PER_AUTHOR} ilanınız olabilir.`, { limit: MAX_PENDING_PER_AUTHOR });
    }
    const inserted = await pool.query(
      `INSERT INTO neighbor_posts (site_code, author_user_code, title, body) VALUES ($1, $2, $3, $4) RETURNING id, status`,
      [siteCode, userCode, title, text],
    );
    return { status: 201, body: { id: Number(inserted.rows[0].id), status: inserted.rows[0].status } };
  }),
);

neighborBoardRouter.post(
  '/app/neighbor-board/:id/report',
  authRequired,
  writeLimiter,
  wrap('neighbor_report', 'Şikayet kaydedilemedi.', async (req) => {
    const id = parseId(req.params.id);
    if (id === null) throw postNotFound();
    const reason = normalizeNote(bodyOf(req).reason, 'reason', { required: true });
    const userCode = userCodeOf(req);
    const post = await pool.query(`SELECT site_code, author_user_code FROM neighbor_posts WHERE id = $1 AND status = 'published'`, [id]);
    const row = post.rows?.[0];
    if (!row) throw postNotFound();
    await residentSite(req, row.site_code);
    if (Number(row.author_user_code) === userCode) {
      throw new PlatformError(409, 'OWN_POST', 'Kendi ilanınızı şikayet edemezsiniz.');
    }
    await pool.query(
      `INSERT INTO neighbor_post_reports (post_id, reporter_user_code, reason) VALUES ($1, $2, $3) ON CONFLICT (post_id, reporter_user_code) WHERE reporter_user_code IS NOT NULL DO NOTHING`,
      [id, userCode, reason],
    );
    return { body: { reported: true } };
  }),
);

neighborBoardRouter.post(
  '/app/neighbor-board/:id/withdraw',
  authRequired,
  writeLimiter,
  wrap('neighbor_withdraw', 'İlan geri çekilemedi.', async (req) => {
    const id = parseId(req.params.id);
    if (id === null) throw postNotFound();
    const userCode = userCodeOf(req);
    const result = await pool.query(
      `UPDATE neighbor_posts SET status = 'withdrawn', decided_at = NOW() WHERE id = $1 AND author_user_code = $2 AND status IN ('pending', 'published') RETURNING id`,
      [id, userCode],
    );
    if (!result.rows?.[0]) throw postNotFound();
    return { body: { status: 'withdrawn' } };
  }),
);

// --- Yönetim -----------------------------------------------------------------------------------------------------

async function managerAccess(req, res) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getPeopleAccessKind(req.authUser, siteCode);
  if (kind !== 'super' && kind !== 'manager') {
    res.status(403).json(kind === 'other_site' ? FORBIDDEN_SITE_BODY : FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT 1 FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  if (!(await isModuleEnabled(siteCode, NEIGHBOR_BOARD_MODULE))) {
    throw moduleDisabled();
  }
  return siteCode;
}

const MBASE = '/manager/sites/:siteCode/neighbor-board';

neighborBoardRouter.get(
  MBASE,
  authRequired,
  readLimiter,
  wrap('neighbor_manager_list', 'İlanlar yüklenemedi.', async (req, res) => {
    const siteCode = await managerAccess(req, res);
    if (siteCode === null) return undefined;
    const status = String(req.query.status ?? 'pending');
    if (!MANAGER_STATUSES.includes(status)) throw invalidField('status', 'Geçersiz durum.');
    const filter = status === 'reported' ? `p.status = 'published' AND EXISTS (SELECT 1 FROM neighbor_post_reports r0 WHERE r0.post_id = p.id)` : `p.status = $2`;
    const params = status === 'reported' ? [siteCode] : [siteCode, status];
    const result = await pool.query(
      `SELECT ${POST_SELECT}, FALSE AS is_mine,
         (SELECT COUNT(*) FROM neighbor_post_reports r WHERE r.post_id = p.id) AS report_count,
         COALESCE((SELECT array_agg(r.reason ORDER BY r.id) FROM neighbor_post_reports r WHERE r.post_id = p.id), '{}') AS report_reasons
       FROM neighbor_posts p LEFT JOIN users u ON u.user_code = p.author_user_code
       WHERE p.site_code = $1 AND ${filter}
       ORDER BY p.id DESC LIMIT ${LIST_LIMIT}`,
      params,
    );
    return { body: { items: result.rows.map((row) => mapPost(row, { manager: true })) } };
  }),
);

/** Karar ucu: izinli önceki durumlardan hedef duruma geçer (yarış güvenli: tek koşullu UPDATE). */
function decisionRoute(action, { from, to, noteRequired }) {
  neighborBoardRouter.post(
    `${MBASE}/:id/${action}`,
    authRequired,
    writeLimiter,
    wrap(`neighbor_${action}`, 'İşlem tamamlanamadı.', async (req, res) => {
      const siteCode = await managerAccess(req, res);
      if (siteCode === null) return undefined;
      const id = parseId(req.params.id);
      if (id === null) throw postNotFound();
      const note = normalizeNote(bodyOf(req).note, 'note', { required: noteRequired });
      const result = await pool.query(
        `UPDATE neighbor_posts SET status = $4, decision_note = $5, decided_by = $6, decided_at = NOW()
         WHERE id = $1 AND site_code = $2 AND status = ANY($3::TEXT[]) RETURNING id, status`,
        [id, siteCode, from, to, note || null, actorFromAuthUser(req.authUser).userCode],
      );
      if (!result.rows?.[0]) {
        const exists = await pool.query(`SELECT status FROM neighbor_posts WHERE id = $1 AND site_code = $2`, [id, siteCode]);
        if (!exists.rows?.[0]) throw postNotFound();
        throw new PlatformError(409, 'POST_STATE', 'İlan bu işlem için uygun durumda değil.', { status: exists.rows[0].status });
      }
      return { body: { id: Number(result.rows[0].id), status: result.rows[0].status } };
    }),
  );
}

decisionRoute('approve', { from: ['pending'], to: 'published', noteRequired: false });
decisionRoute('reject', { from: ['pending'], to: 'rejected', noteRequired: true });
decisionRoute('remove', { from: ['published'], to: 'removed', noteRequired: true });
