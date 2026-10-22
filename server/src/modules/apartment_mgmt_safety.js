// Daire guvenligi: gizli guvenlik talebi ve kapi erisimini askiya alma. Sozlesme: docs/PLATFORM_DAIRE_GUVENLIK_POLITIKASI.md.
//
//  - Guvenlik talebini YALNIZ site yoneticisi ve super gorur. Kurul, gorevli, daire admini, malik ve diger uyeler GORMEZ; talep acildigi
//    haneden kimseye bildirilmez; denetim kaydinin hedef turu 'safety_request' / 'access_suspension'dir (Kisi / Daire gecmisi uclari bunlari OKUMAZ).
//  - Sistem iddiayi DOGRULAYAMAZ ve otomatik kilitleme YAPMAZ: karari insan (site yoneticisi) verir. Askiya alinan kisiye bildirim gitmez.
//  - Askiya alma MEVCUT uyelik servisini cagirir (toggleApartmentMemberStatus: gecici pasife alma, baglari/iliskileri korur); kapi acma koduna dokunulmaz.

import { pool } from '../db.js';
import { toggleApartmentMemberStatus } from '../services/membership_service.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { SAFETY_CONTACTS, SAFETY_REASONS, SAFETY_STATUSES } from './apartment_mgmt_rules.js';
import { loadApartmentState } from './apartment_mgmt_core.js';
import { apartmentLabel, invalidBody, parsePositiveId } from './people_common.js';
import { withSiteTransaction } from './people_service.js';

const SAFETY_OPEN_LIMIT = 3;
const notFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı ya da bu daireyle bağınız yok.');

function cleanText(value, max, field) {
  // eslint-disable-next-line no-control-regex
  const text = String(value ?? '').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '').replace(/\r\n?/g, '\n').trim();
  if (text === '' || Array.from(text).length > max) {
    throw invalidBody(field, `${field} 1-${max} karakter olmalı.`);
  }
  return text;
}

async function auditSafety(client, authUser, action, siteCode, targetType, targetId, details) {
  await recordAudit(client, { actor: authUser, action, siteCode, targetType, targetId: String(targetId), details }, { inTransaction: true });
}

// ---------------------------------------------------------------------------
// Sakin: gizli guvenlik talebi
// ---------------------------------------------------------------------------

/**
 * POST /app/apartments/:id/safety-requests  { message, contact_pref? }
 * Yetiskin her uye (aile uyesi dahil, hesabi olan) acabilir; 18 yasindan kucuk isaretli uye acamaz. Yanit YALNIZ { ok: true } (talebin icerigi,
 * kimligi, durumu geri donmez); hicbir bildirim, e-posta ya da uygulama ici ileti uretilmez.
 */
export async function createSafetyRequest({ authUser, apartmentId, body }) {
  const uc = actorFromAuthUser(authUser).userCode;
  const aptId = parsePositiveId(apartmentId);
  if (uc === null || aptId === null) {
    throw notFound();
  }
  const message = cleanText(body?.message, 1000, 'message');
  const contact = body?.contact_pref === undefined || body?.contact_pref === null || body?.contact_pref === '' ? null : body.contact_pref;
  if (contact !== null && !SAFETY_CONTACTS.includes(contact)) {
    throw invalidBody('contact_pref', 'İletişim tercihi "app", "phone" ya da "email" olmalı.');
  }
  const pre = await loadApartmentState(pool, aptId);
  if (!pre || pre.apartment.approval_status !== 'approved') {
    throw notFound();
  }
  return withSiteTransaction(pre.apartment.site_code, async (client) => {
    const state = await loadApartmentState(client, aptId);
    if (!state) {
      throw notFound();
    }
    const mine = state.residencies.filter((r) => r.user_code === uc);
    const related = state.members.some((m) => Number(m.user_code) === uc) || mine.length > 0 || state.apartment.resident_user_code === uc;
    if (!related) {
      throw notFound();
    }
    if (mine.some((r) => r.is_minor === true)) {
      throw new PlatformError(403, 'FORBIDDEN_ROLE', 'Güvenlik talebini yalnızca yetişkin üyeler açabilir.');
    }
    const open = await client.query(
      `SELECT COUNT(*)::int AS n FROM apartment_safety_requests WHERE requested_by = $1 AND apartment_id = $2 AND status <> 'resolved'`,
      [uc, aptId],
    );
    if ((open.rows?.[0]?.n ?? 0) >= SAFETY_OPEN_LIMIT) {
      throw new PlatformError(409, 'SAFETY_LIMIT', 'Açık talepleriniz var. Site yönetimi ilgilenene kadar bekleyin.');
    }
    const inserted = await client.query(
      `INSERT INTO apartment_safety_requests (site_code, apartment_id, requested_by, message, contact_pref) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [state.apartment.site_code, aptId, uc, message, contact],
    );
    // Denetim kaydi: talep metni ve talep eden adi YAZILMAZ; hedef turu 'safety_request' (Kisi / Daire gecmisi uclarinda gorunmez).
    await auditSafety(client, authUser, 'safety_request.created', state.apartment.site_code, 'safety_request', inserted.rows[0].id, { apartment_id: aptId });
    return { ok: true };
  });
}

// ---------------------------------------------------------------------------
// Site yoneticisi / super: talepler
// ---------------------------------------------------------------------------

const REQUESTS_SQL = `
  SELECT r.id, r.apartment_id, r.message, r.contact_pref, r.status, r.created_at, r.updated_at, r.resolved_at,
         a.unit_label, b.block_name,
         u.full_name AS requester_name, u.phone_number AS requester_phone, u.email AS requester_email
  FROM apartment_safety_requests r
  INNER JOIN apartments a ON a.id = r.apartment_id
  LEFT JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN users u ON u.user_code = r.requested_by
  WHERE r.site_code = $1 AND ($2::TEXT IS NULL OR r.status = $2)
  ORDER BY (r.status = 'resolved'), r.id DESC
  LIMIT 100
`;

const iso = (v) => (v ? new Date(v).toISOString() : null);

/** GET /manager/sites/:siteCode/safety-requests?status= */
export async function listSafetyRequests({ siteCode, status }) {
  if (status !== undefined && status !== null && status !== '' && !SAFETY_STATUSES.includes(status)) {
    throw invalidBody('status', 'Durum geçersiz.');
  }
  const rows = (await pool.query(REQUESTS_SQL, [siteCode, status || null])).rows ?? [];
  const ids = rows.map((r) => Number(r.id));
  const notes = ids.length === 0
    ? []
    : (await pool.query(
      `SELECT n.id, n.request_id, n.note, n.created_at, u.full_name AS author_name
       FROM apartment_safety_notes n LEFT JOIN users u ON u.user_code = n.author_user_code
       WHERE n.request_id = ANY($1::BIGINT[]) ORDER BY n.id`,
      [ids],
    )).rows ?? [];
  return {
    items: rows.map((r) => ({
      id: Number(r.id),
      apartment_id: Number(r.apartment_id),
      label: apartmentLabel(r.block_name, r.unit_label),
      message: r.message,
      contact_pref: r.contact_pref,
      status: r.status,
      created_at: iso(r.created_at),
      updated_at: iso(r.updated_at),
      resolved_at: iso(r.resolved_at),
      requester: { name: r.requester_name ?? null, phone: r.requester_phone ?? null, email: r.requester_email ?? null },
      notes: notes
        .filter((n) => Number(n.request_id) === Number(r.id))
        .map((n) => ({ id: Number(n.id), note: n.note, author_name: n.author_name ?? null, created_at: iso(n.created_at) })),
    })),
  };
}

/** PUT /manager/sites/:siteCode/safety-requests/:id  { status?, note? } */
export async function updateSafetyRequest({ siteCode, requestId, body, authUser }) {
  const id = parsePositiveId(requestId);
  const status = body?.status;
  if (status !== undefined && !SAFETY_STATUSES.includes(status)) {
    throw invalidBody('status', 'Durum geçersiz.');
  }
  const note = body?.note === undefined || body?.note === null || body?.note === '' ? null : cleanText(body.note, 1000, 'note');
  if (status === undefined && note === null) {
    throw invalidBody('status', 'Durum ya da not gerekli.');
  }
  const uc = actorFromAuthUser(authUser).userCode;
  return withSiteTransaction(Number(siteCode), async (client) => {
    const found = id === null ? null : (await client.query(
      `SELECT id FROM apartment_safety_requests WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [id, Number(siteCode)],
    )).rows?.[0];
    if (!found) {
      throw new PlatformError(404, 'SAFETY_REQUEST_NOT_FOUND', 'Talep bulunamadı.');
    }
    if (status !== undefined) {
      await client.query(
        `UPDATE apartment_safety_requests
         SET status = $2, updated_at = NOW(),
             resolved_at = CASE WHEN $2 = 'resolved' THEN COALESCE(resolved_at, NOW()) ELSE NULL END,
             resolved_by = CASE WHEN $2 = 'resolved' THEN $3::INTEGER ELSE NULL END
         WHERE id = $1`,
        [id, status, uc],
      );
    }
    if (note !== null) {
      await client.query(
        `INSERT INTO apartment_safety_notes (request_id, site_code, author_user_code, note) VALUES ($1, $2, $3, $4)`,
        [id, Number(siteCode), uc, note],
      );
      await client.query(`UPDATE apartment_safety_requests SET updated_at = NOW() WHERE id = $1`, [id]);
    }
    await auditSafety(client, authUser, 'safety_request.updated', Number(siteCode), 'safety_request', id, { status: status ?? null, note_added: note !== null });
    return { ok: true };
  });
}

// ---------------------------------------------------------------------------
// Site yoneticisi / super: kapi erisimini askiya alma
// ---------------------------------------------------------------------------

async function stateForSite(db, siteCode, apartmentId) {
  const aptId = parsePositiveId(apartmentId);
  const state = aptId === null ? null : await loadApartmentState(db, aptId);
  if (!state || state.apartment.site_code !== Number(siteCode)) {
    throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
  }
  return state;
}

/** GET /manager/sites/:siteCode/apartments/:id/suspensions */
export async function listSuspensions({ siteCode, apartmentId }) {
  const state = await stateForSite(pool, siteCode, apartmentId);
  const rows = (await pool.query(
    `SELECT s.id, s.user_code, s.reason_code, s.note, s.suspended_at, s.lifted_at, s.lift_note, u.full_name
     FROM apartment_access_suspensions s LEFT JOIN users u ON u.user_code = s.user_code
     WHERE s.apartment_id = $1 ORDER BY s.id DESC LIMIT 50`,
    [state.apartment.id],
  )).rows ?? [];
  return {
    items: rows.map((r) => ({
      id: Number(r.id),
      user_code: Number(r.user_code),
      name: r.full_name ?? null,
      reason_code: r.reason_code,
      note: r.note,
      suspended_at: iso(r.suspended_at),
      lifted_at: iso(r.lifted_at),
      lift_note: r.lift_note ?? null,
      active: !r.lifted_at,
    })),
  };
}

/**
 * POST /manager/sites/:siteCode/apartments/:id/members/:userCode/suspend  { reason_code, note }
 * Kisinin bu daireye KAPI ERISIMI askiya alinir (uyelik gecici pasif; iliskileri ve baglari korunur). Kisiye bildirim GITMEZ.
 */
export async function suspendMemberAccess({ siteCode, apartmentId, userCode, body, authUser }) {
  const target = parsePositiveId(userCode);
  const reason = body?.reason_code;
  if (!SAFETY_REASONS.includes(reason)) {
    throw invalidBody('reason_code', 'Neden "court_order", "safety" ya da "other" olmalı.');
  }
  const note = cleanText(body?.note, 500, 'note');
  const uc = actorFromAuthUser(authUser).userCode;
  const aptId = await withSiteTransaction(Number(siteCode), async (client) => {
    const state = await stateForSite(client, siteCode, apartmentId);
    if (target === null || !state.members.some((m) => Number(m.user_code) === target)) {
      throw new PlatformError(409, 'NOT_AN_ACTIVE_RESIDENT', 'Askıya alınacak kişi dairede aktif bağı olan bir sakin olmalıdır.');
    }
    const open = await client.query(
      `SELECT 1 FROM apartment_access_suspensions WHERE apartment_id = $1 AND user_code = $2 AND lifted_at IS NULL`,
      [state.apartment.id, target],
    );
    if (open.rows?.[0]) {
      throw new PlatformError(409, 'ALREADY_SUSPENDED', 'Bu kişinin erişimi zaten askıda.');
    }
    await client.query(
      `INSERT INTO apartment_access_suspensions (site_code, apartment_id, user_code, reason_code, note, suspended_by) VALUES ($1, $2, $3, $4, $5, $6)`,
      [Number(siteCode), state.apartment.id, target, reason, note, uc],
    );
    await auditSafety(client, authUser, 'access_suspension.created', Number(siteCode), 'access_suspension', `${state.apartment.id}:${target}`, { reason_code: reason });
    return state.apartment.id;
  });
  try {
    // Mevcut uyelik servisi: gecici pasife alma (iliskiler / baglar korunur, yonetici ise devir, kapi izin temizligi, anahtar dondurme).
    await toggleApartmentMemberStatus({ apartmentId: aptId, targetUserCode: target, isActive: false, authUser });
  } catch (error) {
    await pool.query(
      `UPDATE apartment_access_suspensions SET lifted_at = NOW(), lifted_by = $3, lift_note = 'islem basarisiz, geri alindi' WHERE apartment_id = $1 AND user_code = $2 AND lifted_at IS NULL`,
      [aptId, target, uc],
    );
    throw error;
  }
  return { ok: true };
}

/** POST /manager/sites/:siteCode/apartments/:id/members/:userCode/lift  { note? } */
export async function liftMemberSuspension({ siteCode, apartmentId, userCode, body, authUser }) {
  const target = parsePositiveId(userCode);
  const note = body?.note === undefined || body?.note === null || body?.note === '' ? null : cleanText(body.note, 500, 'note');
  const uc = actorFromAuthUser(authUser).userCode;
  const state = await stateForSite(pool, siteCode, apartmentId);
  const open = target === null ? null : (await pool.query(
    `SELECT id FROM apartment_access_suspensions WHERE apartment_id = $1 AND user_code = $2 AND lifted_at IS NULL`,
    [state.apartment.id, target],
  )).rows?.[0];
  if (!open) {
    throw new PlatformError(404, 'SUSPENSION_NOT_FOUND', 'Bu kişi için açık bir askıya alma yok.');
  }
  await toggleApartmentMemberStatus({ apartmentId: state.apartment.id, targetUserCode: target, isActive: true, authUser });
  await withSiteTransaction(Number(siteCode), async (client) => {
    await client.query(`UPDATE apartment_access_suspensions SET lifted_at = NOW(), lifted_by = $2, lift_note = $3 WHERE id = $1`, [open.id, uc, note]);
    // Askidayken baska bir admin atanmissa, geri acilan kisi ikinci admin olmasin.
    await client.query(
      `UPDATE apartment_memberships SET role = 'FAMILY_MEMBER', updated_at = NOW()
       WHERE apartment_id = $1 AND user_code = $2 AND role = 'APARTMENT_ADMIN'
         AND EXISTS (SELECT 1 FROM apartment_memberships o WHERE o.apartment_id = $1 AND o.user_code <> $2 AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE)`,
      [state.apartment.id, target],
    );
    await auditSafety(client, authUser, 'access_suspension.lifted', Number(siteCode), 'access_suspension', `${state.apartment.id}:${target}`, {});
  });
  return { ok: true };
}
