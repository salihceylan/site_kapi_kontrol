// Dekont bildirimi (geçici kabul; 066) servisi: sakin bildirimi, yönetici karşılaştırma / onay / bağla / iptal, elden giriş, dikkat sayacı.
//
// Kural: bildirim deftere YAZILMAZ; onayda finance_parties.postPayment (kaynak 'payment_notice', anahtar 'pn:<id>') tek işlemde tahsilat + (ayar açıksa) makbuz yazar.
// Tahsilat tarihi dekont tarihidir; ayı kapalıysa yönetici açıkça "açık döneme yaz" derse bugüne yazılır, dekont tarihi açıklamada kalır.
// Kilit sırası finans yazmalarıyla aynıdır: sites KEY SHARE -> finance_post -> apartments -> users(işlemi yapan) -> bildirim satırı.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { newStorageKey } from './document_storage.js';
import { apartmentNotFound, moduleDisabled, periodOfDate, today } from './finance_common.js';
import { accountBalances, accountPartySql, defaultPaymentParty, loadAccountBalance, postPayment } from './finance_parties.js';
import { findRefs } from './finance_payment_ref.js';
import { enabledFinanceSites, loadVisibleAccounts } from './finance_read_service.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';
import { syncUserPeopleSafe } from './people_sync.js';
import {
  BULK_MAX,
  MAX_PENDING_PER_USER,
  MAX_PER_APARTMENT_30D,
  NOTICE_COLUMNS,
  NOTICE_MAX_BYTES,
  NOTICE_MIMES,
  NOTICE_STATUSES,
  STRONG_WARNINGS,
  WARNING_TEXT,
  computeWarnings,
  fingerprintOf,
  mapNotice,
  noticeConflict,
  noticeInvalidState,
  noticeLimit,
  noticeNotFound,
  noticePeriodClosed,
  noticeQuota,
  noticesDisabled,
  parseApproveInput,
  parseIdList,
  parseNoticeInput,
  parseRejectInput,
  siteQuotaBytes,
  warningsUnacknowledged,
} from './payment_notice_common.js';
import { PlatformError } from './errors.js';

const LABEL_JOIN = `
  INNER JOIN apartments a ON a.id = n.apartment_id
  INNER JOIN site_blocks b ON b.id = a.block_id
`;
const SELECT_NOTICE = `SELECT ${NOTICE_COLUMNS}, b.block_name, a.unit_label FROM payment_notices n ${LABEL_JOIN}`;

const withLabel = (row) => (row ? { ...row, apartment_label: apartmentLabel(row.block_name, row.unit_label) } : row);
const publicNotice = (row) => mapNotice(withLabel(row));

async function withTx(work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
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

export function parseNoticeId(raw) {
  const id = parsePositiveId(raw);
  if (id === null) throw noticeNotFound();
  return id;
}

const extensionOf = (type) => NOTICE_MIMES[type];
const uploadDescriptor = (row, base) => ({
  method: 'PUT',
  path: `${base}/${row.id}/content`,
  content_type: 'application/octet-stream',
  size_bytes: Number(row.size_bytes),
  max_bytes: NOTICE_MAX_BYTES,
});

function displayNameOf(file) {
  const ext = extensionOf(file.type);
  const base = file.name.replace(/\.[A-Za-z0-9]{1,5}$/, '').slice(0, 100) || 'dekont';
  return `${base}.${ext}`;
}

async function siteQuotaUsed(client, siteCode) {
  const used = await client.query(
    `SELECT COALESCE(SUM(size_bytes), 0)::TEXT AS total FROM payment_notices WHERE site_code = $1 AND status IN ('uploading', 'pending', 'approved') AND storage_key IS NOT NULL`,
    [siteCode],
  );
  return Number(used.rows[0]?.total ?? 0);
}

/** Ortak ekleme: sınırlar + kota + idempotans (çağıran advisory kilidini almış olmalı). Dönüş { row, replayed }. */
async function insertNotice(client, { siteCode, userCode, input, accountParty }) {
  const fingerprint = fingerprintOf(input);
  const existing = await client.query(`${SELECT_NOTICE} WHERE n.site_code = $1 AND n.apartment_id = $2 AND n.idempotency_key = $3`, [siteCode, input.apartmentId, input.idempotencyKey]);
  if (existing.rows[0]) {
    if (existing.rows[0].request_fingerprint !== fingerprint || Number(existing.rows[0].submitted_by) !== Number(userCode)) throw noticeConflict();
    return { row: existing.rows[0], replayed: true };
  }
  const pending = await client.query(
    `SELECT count(*)::INT AS n FROM payment_notices WHERE submitted_by = $1 AND origin <> 'manager' AND (status = 'pending' OR (status = 'uploading' AND submitted_at > NOW() - INTERVAL '2 hours'))`,
    [userCode],
  );
  if (input.origin !== 'manager' && pending.rows[0].n >= MAX_PENDING_PER_USER) {
    throw noticeLimit(`İncelemede en fazla ${MAX_PENDING_PER_USER} bildiriminiz olabilir. Yönetim karar verdikten sonra yenisini gönderin.`);
  }
  const recent = await client.query(
    `SELECT count(*)::INT AS n FROM payment_notices WHERE apartment_id = $1 AND origin <> 'manager' AND submitted_at > NOW() - INTERVAL '30 days'`,
    [input.apartmentId],
  );
  if (input.origin !== 'manager' && recent.rows[0].n >= MAX_PER_APARTMENT_30D) {
    throw noticeLimit('Bu daire için son 30 günde çok fazla bildirim gönderildi. Yönetimle görüşün.');
  }
  const file = input.file;
  if (file && (await siteQuotaUsed(client, siteCode)) + file.size > siteQuotaBytes()) throw noticeQuota();
  const inserted = await client.query(
    `
      INSERT INTO payment_notices (
        site_code, apartment_id, account_party, origin, submitted_by, amount_minor, paid_on, method, sender_name, sender_iban, description, note,
        status, file_required, storage_key, display_name, mime_type, size_bytes, idempotency_key, request_fingerprint
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7::DATE, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20)
      RETURNING id
    `,
    [
      siteCode,
      input.apartmentId,
      accountParty,
      input.origin,
      userCode,
      input.amountMinor,
      input.paidOn,
      input.method,
      input.senderName,
      input.senderIban,
      input.description,
      input.note,
      file ? 'uploading' : 'pending',
      Boolean(file),
      file ? newStorageKey(siteCode) : null,
      file ? displayNameOf(file) : null,
      file ? file.type : null,
      file ? file.size : null,
      input.idempotencyKey,
      fingerprint,
    ],
  );
  const row = await client.query(`${SELECT_NOTICE} WHERE n.id = $1`, [inserted.rows[0].id]);
  return { row: row.rows[0], replayed: false };
}

const userCodeOf = (authUser) => parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id);

// --- Sakin ------------------------------------------------------------------------------------------------

export const RESIDENT_BASE = '/app/my-finance/payment-notices';

/** POST /app/my-finance/payment-notices -> { notice, upload, replayed }. */
export async function createMyNotice(authUser, body, { now = new Date() } = {}) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) throw noticeNotFound();
  const input = parseNoticeInput(body, { manager: false, now });
  await syncUserPeopleSafe(userCode);
  const visible = await loadVisibleAccounts(pool, userCode);
  const apartment = visible.find((row) => Number(row.apartment_id) === input.apartmentId);
  const own = apartment?.views?.find((view) => view.role === 'own');
  if (!apartment || !own) throw apartmentNotFound();
  const siteCode = Number(apartment.site_code);
  if (!(await enabledFinanceSites(pool, [siteCode])).has(siteCode)) throw moduleDisabled();
  const settings = await pool.query(`SELECT notices_enabled FROM finance_payment_settings WHERE site_code = $1`, [siteCode]);
  if (settings.rows[0]?.notices_enabled !== true) throw noticesDisabled();
  const { row, replayed } = await withTx(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`payment_notice_user:${userCode}`]);
    return insertNotice(client, { siteCode, userCode, input, accountParty: own.party });
  });
  return { replayed, notice: publicNotice(row), upload: row.status === 'uploading' ? uploadDescriptor(row, RESIDENT_BASE) : null };
}

/** GET /app/my-finance/payment-notices?apartment_id= -> { items, pending_total_minor, unseen_count }. */
export async function listMyNotices(authUser, query = {}) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) return { items: [], pending_total_minor: 0, unseen_count: 0 };
  const apartmentId = query.apartment_id === undefined ? null : parsePositiveId(query.apartment_id);
  const rows = await pool.query(
    `${SELECT_NOTICE} WHERE n.submitted_by = $1 AND n.origin <> 'manager' AND n.status <> 'uploading' AND ($2::BIGINT IS NULL OR n.apartment_id = $2) ORDER BY n.id DESC LIMIT 50`,
    [userCode, apartmentId],
  );
  const items = rows.rows.map(publicNotice);
  return {
    items,
    pending_total_minor: items.filter((n) => n.status === 'pending').reduce((sum, n) => sum + n.amount_minor, 0),
    unseen_count: items.filter((n) => n.unseen_decision).length,
  };
}

export async function withdrawMyNotice(authUser, rawId) {
  const userCode = userCodeOf(authUser);
  const id = parseNoticeId(rawId);
  return withTx(async (client) => {
    const found = await client.query(`SELECT id, status FROM payment_notices WHERE id = $1 AND submitted_by = $2 AND origin <> 'manager' FOR UPDATE`, [id, userCode]);
    const current = found.rows[0];
    if (!current) throw noticeNotFound();
    if (current.status === 'withdrawn') return { replayed: true };
    if (!['uploading', 'pending'].includes(current.status)) throw noticeInvalidState('Karara bağlanmış bildirim geri çekilemez.');
    await client.query(`UPDATE payment_notices SET status = 'withdrawn', decided_at = NOW() WHERE id = $1`, [id]);
    return { replayed: false };
  });
}

export async function markMyNoticesSeen(authUser) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) return { updated: 0 };
  const result = await pool.query(
    `UPDATE payment_notices SET resident_seen_at = NOW() WHERE submitted_by = $1 AND status IN ('approved', 'rejected') AND resident_seen_at IS NULL`,
    [userCode],
  );
  return { updated: result.rowCount ?? 0 };
}

// --- Yönetici: okuma ---------------------------------------------------------------------------------------

export async function listNotices(siteCode, query = {}) {
  const status = typeof query.status === 'string' && NOTICE_STATUSES.includes(query.status) && query.status !== 'uploading' ? query.status : query.status === 'all' ? null : 'pending';
  const apartmentId = query.apartment_id === undefined ? null : parsePositiveId(query.apartment_id);
  const before = query.before_id === undefined ? null : parsePositiveId(query.before_id);
  const rows = await pool.query(
    `${SELECT_NOTICE}
     WHERE n.site_code = $1 AND n.status <> 'uploading' AND ($2::TEXT IS NULL OR n.status = $2) AND ($3::BIGINT IS NULL OR n.apartment_id = $3) AND ($4::BIGINT IS NULL OR n.id < $4)
     ORDER BY n.id DESC LIMIT 51`,
    [siteCode, status, apartmentId, before],
  );
  const page = rows.rows.slice(0, 50);
  const counts = await pool.query(`SELECT status, count(*)::INT AS n FROM payment_notices WHERE site_code = $1 AND status <> 'uploading' GROUP BY status`, [siteCode]);
  return {
    items: page.map(publicNotice),
    has_more: rows.rows.length > 50,
    counts: Object.fromEntries(counts.rows.map((r) => [r.status, r.n])),
  };
}

/** Dikkat sayacı (2F kayıt defterine takılacak tek satır): bekleyen dekont adedi ve toplamı. */
export async function paymentNoticeAttention(siteCode, db = pool) {
  const r = await db.query(
    `SELECT count(*)::INT AS n, COALESCE(SUM(amount_minor), 0)::TEXT AS total, MIN(submitted_at) AS oldest FROM payment_notices WHERE site_code = $1 AND status = 'pending'`,
    [siteCode],
  );
  return {
    code: 'payment_notices',
    count: r.rows[0].n,
    total_minor: Number(r.rows[0].total),
    oldest_at: r.rows[0].oldest ? new Date(r.rows[0].oldest).toISOString() : null,
  };
}

export async function noticeSummary(siteCode) {
  return { attention: await paymentNoticeAttention(siteCode) };
}

/** Uyarı gerçekleri + hesap (db: havuz ya da işlem bağlantısı). */
export async function computeNoticeWarnings(db, row, now = new Date()) {
  const siteCode = Number(row.site_code);
  const apartmentId = Number(row.apartment_id);
  let otherApartmentRef = false;
  const text = [row.description, row.note].filter(Boolean).join(' ');
  if (text) {
    const prefixes = await db.query(`SELECT prefix, site_code FROM finance_site_ref_prefixes WHERE site_code = $1`, [siteCode]);
    const codes = await db.query(`SELECT site_code, code, apartment_id FROM finance_apartment_ref_codes WHERE site_code = $1`, [siteCode]);
    const found = findRefs(text, { prefixes: prefixes.rows, codes: codes.rows });
    otherApartmentRef = found.status === 'unique' && Number(found.match.apartment_id) !== apartmentId;
  }
  let sameFileCount = 0;
  if (row.sha256) {
    const same = await db.query(`SELECT count(*)::INT AS n FROM payment_notices WHERE site_code = $1 AND sha256 = $2 AND id <> $3 AND status IN ('pending', 'approved')`, [siteCode, row.sha256, row.id]);
    sameFileCount = same.rows[0].n;
  }
  const dup = await db.query(
    `
      SELECT (
        SELECT count(*) FROM ledger_entries l
        WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.kind = 'payment' AND l.amount_minor = -$3::BIGINT
          AND l.entry_date BETWEEN $4::DATE - 3 AND $4::DATE + 3 AND ${accountPartySql('l')} = $5
          AND NOT EXISTS (SELECT 1 FROM ledger_entries r WHERE r.reverses_entry_id = l.id)
          AND NOT EXISTS (SELECT 1 FROM payment_notices pn WHERE pn.ledger_entry_id = l.id)
      )::INT + (
        SELECT count(*) FROM payment_notices o
        WHERE o.site_code = $1 AND o.apartment_id = $2 AND o.id <> $6 AND o.status = 'pending' AND o.amount_minor = $3::BIGINT
          AND o.account_party = $5 AND o.paid_on BETWEEN $4::DATE - 3 AND $4::DATE + 3
      )::INT AS n
    `,
    [siteCode, apartmentId, row.amount_minor, row.paid_on, row.account_party, row.id],
  );
  const people = await db.query(
    `SELECT sp.full_name FROM apartment_residencies r INNER JOIN site_people sp ON sp.id = r.person_id WHERE r.apartment_id = $1 AND r.is_current = TRUE AND sp.is_active = TRUE AND sp.full_name IS NOT NULL`,
    [apartmentId],
  );
  const balance = await loadAccountBalance(db, { siteCode, apartmentId, accountParty: row.account_party });
  return computeWarnings({
    notice: row,
    otherApartmentRef,
    sameFileCount,
    duplicateCount: dup.rows[0].n,
    peopleNames: people.rows.map((p) => p.full_name),
    accountBalanceMinor: balance,
    now,
  }).map((w) => ({ ...w, message: WARNING_TEXT[w.code] }));
}

async function loadNoticeRow(db, siteCode, id, { lock = false } = {}) {
  const rows = await db.query(`${SELECT_NOTICE} WHERE n.id = $1 AND n.site_code = $2 ${lock ? 'FOR UPDATE OF n' : ''}`, [id, siteCode]);
  if (!rows.rows[0]) throw noticeNotFound();
  return rows.rows[0];
}

/** GET .../:id: bildirim + daire bilgisi (kişiler, hesap bakiyeleri, son tahsilatlar) + uyarılar. */
export async function getNoticeDetail(siteCode, rawId, { now = new Date() } = {}) {
  const row = await loadNoticeRow(pool, siteCode, parseNoticeId(rawId));
  const apartmentId = Number(row.apartment_id);
  const people = await pool.query(
    `SELECT sp.full_name AS name, r.relation FROM apartment_residencies r INNER JOIN site_people sp ON sp.id = r.person_id
     WHERE r.apartment_id = $1 AND r.is_current = TRUE AND sp.is_active = TRUE ORDER BY r.id`,
    [apartmentId],
  );
  const recent = await pool.query(
    `SELECT l.id, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, (-l.amount_minor)::TEXT AS amount_minor, l.method, ${accountPartySql('l')} AS account_party
     FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.kind = 'payment'
       AND NOT EXISTS (SELECT 1 FROM ledger_entries r WHERE r.reverses_entry_id = l.id)
     ORDER BY l.entry_date DESC, l.id DESC LIMIT 5`,
    [siteCode, apartmentId],
  );
  const open = row.status === 'pending';
  return {
    notice: publicNotice(row),
    apartment: {
      id: apartmentId,
      label: apartmentLabel(row.block_name, row.unit_label),
      people: people.rows.map((p) => ({ name: p.name, relation: p.relation })),
      balances: await accountBalances(pool, { siteCode, apartmentId }),
      recent_payments: recent.rows.map((r) => ({ ...r, id: Number(r.id), amount_minor: Number(r.amount_minor) })),
    },
    warnings: open ? await computeNoticeWarnings(pool, row, now) : [],
  };
}

// --- Yönetici: yazma ---------------------------------------------------------------------------------------

/** Elden makbuz / dekont girişi. Dosya isteğe bağlı; kayıt yine geçici kabuldedir (onay bekler). */
export async function createManagerNotice(siteCode, actor, body, { now = new Date() } = {}) {
  const input = parseNoticeInput(body, { manager: true, now });
  const userCode = actorFromAuthUser(actor).userCode;
  const apt = await pool.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2`, [input.apartmentId, siteCode]);
  if (!apt.rows[0]) throw apartmentNotFound();
  const party = input.accountParty ?? (await defaultPaymentParty(pool, { siteCode, apartmentId: input.apartmentId, onDate: input.paidOn }));
  const { row, replayed } = await withTx(async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`payment_notice_user:${userCode}`]);
    const result = await insertNotice(client, { siteCode, userCode, input, accountParty: party });
    if (!result.replayed) await recordFinanceAudit(client, actor, 'finance.payment_notice.manual_created', siteCode, result.row.id, { apartment_id: input.apartmentId, amount_minor: input.amountMinor });
    return result;
  });
  return { replayed, notice: publicNotice(row), upload: row.status === 'uploading' ? uploadDescriptor(row, `/manager/sites/${siteCode}/finance/payment-notices`) : null };
}

const trDate = (iso) => `${iso.slice(8, 10)}.${iso.slice(5, 7)}.${iso.slice(0, 4)}`;

async function lockForDecision(client, siteCode, id) {
  const peek = await client.query(`SELECT apartment_id FROM payment_notices WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!peek.rows[0]) throw noticeNotFound();
  await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [peek.rows[0].apartment_id, siteCode]);
}

/** POST .../:id/approve: postPayment (dekont tarihiyle) + makbuz; tek işlemde. Tekrar onay AYNI sonucu döner. */
export async function approveNotice({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parseNoticeId(rawId);
  const input = parseApproveInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockForDecision(client, siteCode, id);
    await lockActorRow(client, actorInfo);
    const row = await loadNoticeRow(client, siteCode, id, { lock: true });
    if (row.status === 'approved') return { replayed: true, notice: publicNotice(row), entry_id: Number(row.ledger_entry_id), receipt_id: null };
    if (row.status !== 'pending') throw noticeInvalidState();
    const warnings = await computeNoticeWarnings(client, row, now);
    const unacknowledged = warnings.filter((w) => STRONG_WARNINGS.includes(w.code) && !input.acknowledged.includes(w.code));
    if (unacknowledged.length > 0) throw warningsUnacknowledged(warnings);
    let paidOn = row.paid_on;
    let description = row.description || (row.sender_name ? `Dekont - ${row.sender_name}` : 'Dekont');
    if (await isPeriodClosed(client, siteCode, periodOfDate(paidOn))) {
      if (!input.bookInOpenPeriod) throw noticePeriodClosed();
      description = `${description} (Dekont tarihi: ${trDate(paidOn)})`;
      paidOn = today(now);
    }
    let accountId = input.accountId;
    if (accountId === null && row.method === 'transfer') {
      const settings = await client.query(`SELECT resident_account_id FROM finance_payment_settings WHERE site_code = $1`, [siteCode]);
      accountId = settings.rows[0]?.resident_account_id ? Number(settings.rows[0].resident_account_id) : null;
    }
    const party = input.accountParty ?? row.account_party;
    const posted = await postPayment(client, {
      siteCode,
      apartmentId: Number(row.apartment_id),
      accountParty: party,
      amountMinor: Number(row.amount_minor),
      paidOn,
      method: row.method,
      description: description.slice(0, 200),
      sourceKind: 'payment_notice',
      sourceId: id,
      idempotencyKey: `pn:${id}`,
      cashAccountId: accountId,
      actor,
      now,
    });
    await client.query(
      `UPDATE payment_notices SET status = 'approved', ledger_entry_id = $2, decided_by = $3, decided_at = NOW(), account_party = $4 WHERE id = $1`,
      [id, posted.entryId, actorInfo.userCode, party],
    );
    await recordFinanceAudit(client, actor, 'finance.payment_notice.approved', siteCode, id, {
      apartment_id: Number(row.apartment_id),
      amount_minor: Number(row.amount_minor),
      entry_id: posted.entryId,
      account_party: party,
      party_changed: party !== row.account_party,
      acknowledged: warnings.filter((w) => w.level === 'strong').length,
      booked_in_open_period: paidOn !== row.paid_on,
    });
    return { replayed: false, notice: publicNotice(await loadNoticeRow(client, siteCode, id)), entry_id: posted.entryId, receipt_id: posted.receiptId };
  });
}

/** POST .../:id/link: bildirimi MEVCUT bir tahsilata bağlar (yeni defter satırı yazılmaz). */
export async function linkNotice({ siteCode, rawId, body, actor }) {
  const id = parseNoticeId(rawId);
  const entryId = parsePositiveId(body?.ledger_entry_id);
  if (entryId === null) throw new PlatformError(400, 'INVALID_BODY', 'Bağlanacak tahsilat seçimi geçersiz.');
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockForDecision(client, siteCode, id);
    await lockActorRow(client, actorInfo);
    const row = await loadNoticeRow(client, siteCode, id, { lock: true });
    if (row.status === 'approved' && Number(row.ledger_entry_id) === entryId) return { replayed: true, notice: publicNotice(row) };
    if (row.status !== 'pending') throw noticeInvalidState();
    const entry = await client.query(
      `SELECT l.id, ${accountPartySql('l')} AS account_party FROM ledger_entries l
       WHERE l.id = $1 AND l.site_code = $2 AND l.apartment_id = $3 AND l.kind = 'payment'
         AND NOT EXISTS (SELECT 1 FROM ledger_entries r WHERE r.reverses_entry_id = l.id)
         AND NOT EXISTS (SELECT 1 FROM payment_notices pn WHERE pn.ledger_entry_id = l.id)`,
      [entryId, siteCode, row.apartment_id],
    );
    if (!entry.rows[0]) throw noticeInvalidState('Bu tahsilat bağlanamaz (başka daireye ait, iptal edilmiş ya da başka bildirime bağlı).');
    await client.query(
      `UPDATE payment_notices SET status = 'approved', ledger_entry_id = $2, linked_existing = TRUE, decided_by = $3, decided_at = NOW(), account_party = $4 WHERE id = $1`,
      [id, entryId, actorInfo.userCode, entry.rows[0].account_party],
    );
    await recordFinanceAudit(client, actor, 'finance.payment_notice.linked', siteCode, id, { apartment_id: Number(row.apartment_id), entry_id: entryId });
    return { replayed: false, notice: publicNotice(await loadNoticeRow(client, siteCode, id)) };
  });
}

/** POST .../:id/reject: neden zorunlu; sakine gösterilir. Dosya silinmez (saklama süresi kararı bekliyor). */
export async function rejectNotice({ siteCode, rawId, body, actor }) {
  const id = parseNoticeId(rawId);
  const input = parseRejectInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockForDecision(client, siteCode, id);
    await lockActorRow(client, actorInfo);
    const row = await loadNoticeRow(client, siteCode, id, { lock: true });
    if (row.status === 'rejected') return { replayed: true, notice: publicNotice(row) };
    if (row.status !== 'pending') throw noticeInvalidState();
    await client.query(
      `UPDATE payment_notices SET status = 'rejected', reject_reason_code = $2, reject_note = $3, decided_by = $4, decided_at = NOW() WHERE id = $1`,
      [id, input.reasonCode, input.note, actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.payment_notice.rejected', siteCode, id, { apartment_id: Number(row.apartment_id), reason: input.reasonCode });
    return { replayed: false, notice: publicNotice(await loadNoticeRow(client, siteCode, id)) };
  });
}

const resultOf = (id, ok, payload) => ({ id, ok, ...payload });

/** Toplu onay / iptal: en çok 50; HER ÖĞE ayrı işlem. Önemli uyarılı öğe ayrıca incelenmeli (kodu NOTICE_WARNINGS_UNACKNOWLEDGED döner). */
export async function bulkDecide({ siteCode, body, actor, action, now = new Date() }) {
  const ids = parseIdList(body);
  const results = [];
  for (const id of ids) {
    try {
      const out =
        action === 'approve'
          ? await approveNotice({ siteCode, rawId: id, body: { account_id: body.account_id, book_in_open_period: body.book_in_open_period === true }, actor, now })
          : await rejectNotice({ siteCode, rawId: id, body, actor });
      results.push(resultOf(id, true, { replayed: out.replayed === true }));
    } catch (error) {
      if (!(error instanceof PlatformError)) throw error;
      results.push(resultOf(id, false, { code: error.code, message: error.message }));
    }
  }
  return { results, approved_or_rejected: results.filter((r) => r.ok).length, max: BULK_MAX };
}

// --- Dosya hedefleri (upload/download) ------------------------------------------------------------------

/** Yükleme hedefi: yalnız kaydı açan kişi, `uploading` durumunda. */
export async function findUploadTarget({ id, userCode, siteCode = null, manager }) {
  const rows = await pool.query(
    `SELECT id, site_code, storage_key, size_bytes::TEXT AS size_bytes, mime_type, status, submitted_at, (submitted_at < NOW() - INTERVAL '2 hours') AS stale
     FROM payment_notices WHERE id = $1 AND submitted_by = $2 AND (origin = 'manager') = $3 AND ($4::BIGINT IS NULL OR site_code = $4)`,
    [id, userCode, manager, siteCode],
  );
  const row = rows.rows[0];
  if (!row || !row.storage_key) throw noticeNotFound();
  if (row.status !== 'uploading') throw new PlatformError(409, 'UPLOAD_ALREADY_COMPLETED', 'Bu bildirimin dosyası zaten yüklendi.');
  if (row.stale) throw noticeInvalidState('Yükleme süresi doldu; bildirimi yeniden oluşturun.');
  return { id: Number(row.id), siteCode: Number(row.site_code), storageKey: row.storage_key, sizeBytes: Number(row.size_bytes), mimeType: row.mime_type };
}

/** Yüklemeyi tamamlar: uploading -> pending (sha256 + tamamlanma anı). */
export async function completeUpload({ id, sha256 }) {
  const done = await pool.query(
    `UPDATE payment_notices SET status = 'pending', sha256 = $2, file_completed_at = NOW() WHERE id = $1 AND status = 'uploading' RETURNING site_code`,
    [id, sha256],
  );
  if (!done.rows[0]) throw new PlatformError(409, 'UPLOAD_ALREADY_COMPLETED', 'Bu bildirimin dosyası zaten yüklendi.');
  const row = await loadNoticeRow(pool, Number(done.rows[0].site_code), id);
  return { notice: publicNotice(row) };
}

/** İndirme hedefi (dosyası tamamlanmış). Sakin: yalnız kendi gönderdiği; yönetici: sitedeki herhangi biri. */
export async function findFileTarget({ id, userCode = null, siteCode = null }) {
  const rows = await pool.query(
    `SELECT id, site_code, storage_key, size_bytes::TEXT AS size_bytes, mime_type, display_name FROM payment_notices
     WHERE id = $1 AND file_completed_at IS NOT NULL AND storage_key IS NOT NULL
       AND ($2::INTEGER IS NULL OR (submitted_by = $2 AND origin <> 'manager')) AND ($3::BIGINT IS NULL OR site_code = $3)`,
    [id, userCode, siteCode],
  );
  const row = rows.rows[0];
  if (!row) throw noticeNotFound();
  return { id: Number(row.id), siteCode: Number(row.site_code), storageKey: row.storage_key, sizeBytes: Number(row.size_bytes), mimeType: row.mime_type, displayName: row.display_name };
}

export async function auditFileView(actor, target) {
  try {
    await withTx((client) => recordFinanceAudit(client, actor, 'finance.payment_notice.file_viewed', target.siteCode, target.id, {}));
  } catch (_error) {
    // denetim kaydı indirmeyi engellemez
  }
}
