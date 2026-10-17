// Gider kaydı (Faz 4b Ö3): kategoriler, tedarikçiler, gider (nakit esaslı), iptal (void) ve düzeltme.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö3". Gider NAKİT esaslıdır: her gider bir hesaptan (`account_id`) çıkar ve AYNI işlemde `expense` hareketi yazar.
// Gider SİLİNMEZ (KMK m.36): iptal = `expense_voids` + ayna hareket (AÇIK ayda bugünün tarihiyle); düzeltme = iptal + yeni gider (`corrects_expense_id`) tek işlemde.
// Çift kayıt önlemleri (kilit altında, sırayla): idempotency_key, fatura/belge no tekilliği (tedarikçi + normalize no), 24 saatte doğal anahtar (allow_duplicate ile aşılır).
// Kategori / tedarikçi adları kayıtta ANLIK GÖRÜNTÜDÜR. KDV tutara DAHİLDİR. Audit `details`: yalnız kimlik / tutar / kod (ad, açıklama, neden ASLA).
// KİLİT SIRASI: sites KEY SHARE -> finance_post advisory -> users(işlem yapan) -> hesap satırı (KEY SHARE) -> finans satırları.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  CATEGORY_LIMIT,
  SUPPLIER_LIMIT,
  accountInactive,
  accountNotFound,
  beforeOpeningDate,
  categoryInactive,
  categoryLimitReached,
  categoryNameTaken,
  categoryNotFound,
  duplicateDocumentNo,
  duplicateExpense,
  expenseAlreadyVoided,
  expenseNotFound,
  fingerprintOf,
  noAccount,
  objectOf,
  optionalId,
  present,
  queryBool,
  queryDate,
  queryEnum,
  queryId,
  queryInt,
  supplierLimitReached,
  supplierNameTaken,
  supplierNotFound,
} from './finance_4b_common.js';
import { loadAccountPolicy, lockAccountRows } from './finance_accounts.js';
import { assertWritableDate, resolveOpenPeriod } from './finance_4b_guard.js';
import {
  idempotencyConflict,
  invalidBody,
  normalizeFreeText,
  parseBooleanFlag,
  parseIdempotencyKey,
  parseIsoDate,
  requireMinor,
  today,
} from './finance_common.js';
import { minorToNumber } from './finance_money.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { escapeLike, foldSql, foldText, parsePositiveId, toIso } from './people_common.js';

export const DEFAULT_EXPENSE_CATEGORIES = Object.freeze([
  'Personel',
  'Elektrik',
  'Su',
  'Doğalgaz/Yakıt',
  'Asansör bakım',
  'Bakım-onarım',
  'Temizlik malzemesi',
  'Sigorta',
  'Yönetici aylığı',
  'Vergi/harç',
  'Banka/noter masrafı',
  'Diğer',
]);
export const DOCUMENT_KINDS = Object.freeze(['invoice', 'receipt', 'contract', 'other', 'none']);
export const MAX_EXPENSE_MINOR = 1_000_000_000_000;
const DEFAULT_VOID_REASON = 'Gider düzeltmesi';

// --- Kategoriler ---------------------------------------------------------------------------------------------------------------------------

/** İlk kullanımda varsayılan küme eklenir (kategori yoksa; ON CONFLICT DO NOTHING; sabit sıra: eşzamanlı çağrılar kilitlenmez). */
export async function ensureDefaultCategories(db, siteCode) {
  const exists = await db.query(`SELECT 1 FROM expense_categories WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (exists.rows?.[0]) {
    return;
  }
  await db.query(
    `
      INSERT INTO expense_categories (site_code, name, is_system, sort_order)
      SELECT $1, t.name, TRUE, t.ord::INTEGER
      FROM unnest($2::TEXT[]) WITH ORDINALITY AS t(name, ord)
      ORDER BY t.ord
      ON CONFLICT DO NOTHING
    `,
    [siteCode, [...DEFAULT_EXPENSE_CATEGORIES]],
  );
}

const mapCategory = (row) => ({
  id: Number(row.id),
  name: row.name,
  is_system: row.is_system === true,
  is_active: row.is_active === true,
  sort_order: Number(row.sort_order),
});

/** GET expense-categories?active= -> { items }. */
export async function listCategories(siteCode, query = {}, db = pool) {
  const activeOnly = query.active === undefined || query.active === '' ? null : queryBool(query.active);
  await ensureDefaultCategories(db, siteCode);
  const result = await db.query(
    `SELECT id, name, is_system, is_active, sort_order FROM expense_categories WHERE site_code = $1 AND ($2::BOOLEAN IS NULL OR is_active = $2) ORDER BY sort_order, id`,
    [siteCode, activeOnly],
  );
  return { items: (result.rows ?? []).map(mapCategory) };
}

export function parseCategoryBody(body, { create }) {
  const input = objectOf(body);
  const patch = {};
  if (create || present(input.name)) {
    patch.name = normalizeFreeText(input.name, { label: 'Kategori adı', max: 60, required: true });
  }
  if (!create) {
    if (Object.prototype.hasOwnProperty.call(input, 'is_active')) {
      if (typeof input.is_active !== 'boolean') {
        throw invalidBody('Aktiflik değeri geçersiz (evet veya hayır olmalıdır).');
      }
      patch.isActive = input.is_active;
    }
    if (present(input.sort_order)) {
      if (typeof input.sort_order !== 'number' || !Number.isInteger(input.sort_order) || input.sort_order < 0 || input.sort_order > 10000) {
        throw invalidBody('Sıra değeri geçersiz.');
      }
      patch.sortOrder = input.sort_order;
    }
    if (Object.keys(patch).length === 0) {
      throw invalidBody('Güncellenecek bir alan gönderilmedi.');
    }
  }
  return patch;
}

/** POST expense-categories { name } -> { category }. */
export async function createCategory({ siteCode, body, actor }) {
  const patch = parseCategoryBody(body, { create: true });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    await ensureDefaultCategories(client, siteCode);
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM expense_categories WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows[0].n) >= CATEGORY_LIMIT) {
      throw categoryLimitReached();
    }
    const taken = await client.query(`SELECT 1 FROM expense_categories WHERE site_code = $1 AND lower(name) = lower($2)`, [siteCode, patch.name]);
    if (taken.rows?.[0]) {
      throw categoryNameTaken();
    }
    const inserted = await client.query(
      `INSERT INTO expense_categories (site_code, name, sort_order) VALUES ($1, $2, $3) RETURNING id, name, is_system, is_active, sort_order`,
      [siteCode, patch.name, Number(count.rows[0].n)],
    );
    await recordFinanceAudit(client, actor, 'finance.category.created', siteCode, inserted.rows[0].id, {});
    return { category: mapCategory(inserted.rows[0]) };
  });
}

/** PATCH expense-categories/:id { name?, is_active?, sort_order? } -> { category }. Silme YOK. */
export async function updateCategory({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw categoryNotFound();
  }
  const patch = parseCategoryBody(body, { create: false });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const current = await client.query(`SELECT id, name, is_system, is_active, sort_order FROM expense_categories WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    if (!current.rows?.[0]) {
      throw categoryNotFound();
    }
    if (patch.name !== undefined) {
      const taken = await client.query(`SELECT 1 FROM expense_categories WHERE site_code = $1 AND lower(name) = lower($2) AND id <> $3`, [siteCode, patch.name, id]);
      if (taken.rows?.[0]) {
        throw categoryNameTaken();
      }
    }
    const row = current.rows[0];
    const updated = await client.query(
      `UPDATE expense_categories SET name = $3, is_active = $4, sort_order = $5, updated_at = NOW() WHERE id = $1 AND site_code = $2 RETURNING id, name, is_system, is_active, sort_order`,
      [id, siteCode, patch.name ?? row.name, patch.isActive ?? row.is_active, patch.sortOrder ?? row.sort_order],
    );
    await recordFinanceAudit(client, actor, 'finance.category.updated', siteCode, id, { fields: Object.keys(patch) });
    return { category: mapCategory(updated.rows[0]) };
  });
}

// --- Tedarikçiler -------------------------------------------------------------------------------------------------------------------------

function mapSupplier(row) {
  return {
    id: Number(row.id),
    name: row.name,
    tax_id: row.tax_id ?? null,
    phone: row.phone ?? null,
    note: row.note ?? null,
    is_active: row.is_active === true,
    created_at: toIso(row.created_at),
  };
}

/** Kurul yanıtı: tax_id / phone / note null. */
export const redactSupplierForBoard = (supplier) => ({ ...supplier, tax_id: null, phone: null, note: null });

function parseSupplierFields(input, { create }) {
  const out = {};
  if (create || present(input.name)) out.name = normalizeFreeText(input.name, { label: 'Tedarikçi adı', max: 100, required: true });
  if (create || Object.prototype.hasOwnProperty.call(input, 'tax_id')) {
    const value = input.tax_id;
    if (value === null || value === undefined || value === '') {
      out.taxId = null;
    } else if (typeof value === 'string' && /^[0-9]{10,11}$/.test(value.trim())) {
      out.taxId = value.trim();
    } else {
      throw invalidBody('Vergi / kimlik numarası 10 veya 11 rakamdan oluşmalıdır.');
    }
  }
  if (create || Object.prototype.hasOwnProperty.call(input, 'phone')) out.phone = normalizeFreeText(input.phone, { label: 'Telefon', max: 20 });
  if (create || Object.prototype.hasOwnProperty.call(input, 'note')) out.note = normalizeFreeText(input.note, { label: 'Not', max: 200 });
  if (!create && Object.prototype.hasOwnProperty.call(input, 'is_active')) {
    if (typeof input.is_active !== 'boolean') {
      throw invalidBody('Aktiflik değeri geçersiz (evet veya hayır olmalıdır).');
    }
    out.isActive = input.is_active;
  }
  return out;
}

export function parseSuppliersQuery(query = {}) {
  return {
    q: typeof query.q === 'string' && query.q.trim() !== '' ? Array.from(query.q.trim()).slice(0, 60).join('') : null,
    active: query.active === undefined || query.active === '' ? null : queryBool(query.active),
    limit: queryInt(query.limit, { min: 1, max: 200, fallback: 50 }),
    offset: queryInt(query.offset, { min: 0, max: 100000, fallback: 0 }),
  };
}

/** GET suppliers -> { items, total }. */
export async function listSuppliers(siteCode, query = {}, db = pool) {
  const filters = parseSuppliersQuery(query);
  const params = [siteCode, filters.active];
  let search = '';
  if (filters.q !== null) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    search = ` AND ${foldSql('s.name')} LIKE $${params.length} ESCAPE '\\'`;
  }
  const where = `s.site_code = $1 AND ($2::BOOLEAN IS NULL OR s.is_active = $2)${search}`;
  const total = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM finance_suppliers s WHERE ${where}`, params);
  params.push(filters.limit, filters.offset);
  const result = await db.query(
    `SELECT s.id, s.name, s.tax_id, s.phone, s.note, s.is_active, s.created_at FROM finance_suppliers s WHERE ${where} ORDER BY lower(s.name), s.id LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  return { items: (result.rows ?? []).map(mapSupplier), total: Number(total.rows[0].n) };
}

/** POST suppliers -> { supplier }. */
export async function createSupplier({ siteCode, body, actor }) {
  const fields = parseSupplierFields(objectOf(body), { create: true });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM finance_suppliers WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows[0].n) >= SUPPLIER_LIMIT) {
      throw supplierLimitReached();
    }
    const taken = await client.query(`SELECT 1 FROM finance_suppliers WHERE site_code = $1 AND lower(name) = lower($2)`, [siteCode, fields.name]);
    if (taken.rows?.[0]) {
      throw supplierNameTaken();
    }
    const inserted = await client.query(
      `INSERT INTO finance_suppliers (site_code, name, tax_id, phone, note, created_by) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, name, tax_id, phone, note, is_active, created_at`,
      [siteCode, fields.name, fields.taxId, fields.phone, fields.note, actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.supplier.created', siteCode, inserted.rows[0].id, {});
    return { supplier: mapSupplier(inserted.rows[0]) };
  });
}

/** PATCH suppliers/:id -> { supplier }. */
export async function updateSupplier({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw supplierNotFound();
  }
  const fields = parseSupplierFields(objectOf(body), { create: false });
  if (Object.keys(fields).length === 0) {
    throw invalidBody('Güncellenecek bir alan gönderilmedi.');
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const current = await client.query(`SELECT id, name, tax_id, phone, note, is_active, created_at FROM finance_suppliers WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    if (!current.rows?.[0]) {
      throw supplierNotFound();
    }
    if (fields.name !== undefined) {
      const taken = await client.query(`SELECT 1 FROM finance_suppliers WHERE site_code = $1 AND lower(name) = lower($2) AND id <> $3`, [siteCode, fields.name, id]);
      if (taken.rows?.[0]) {
        throw supplierNameTaken();
      }
    }
    const row = current.rows[0];
    const has = (key) => Object.prototype.hasOwnProperty.call(fields, key);
    const updated = await client.query(
      `
        UPDATE finance_suppliers SET name = $3, tax_id = $4, phone = $5, note = $6, is_active = $7, updated_at = NOW()
        WHERE id = $1 AND site_code = $2 RETURNING id, name, tax_id, phone, note, is_active, created_at
      `,
      [id, siteCode, fields.name ?? row.name, has('taxId') ? fields.taxId : row.tax_id, has('phone') ? fields.phone : row.phone, has('note') ? fields.note : row.note, fields.isActive ?? row.is_active],
    );
    await recordFinanceAudit(client, actor, 'finance.supplier.updated', siteCode, id, { fields: Object.keys(fields) });
    return { supplier: mapSupplier(updated.rows[0]) };
  });
}

// --- Gider ----------------------------------------------------------------------------------------------------------------------------------

/** Belge no normalizasyonu: Türkçe katlama + küçük harf + yalnız harf/rakam. Boş kalırsa null. */
export function normalizeDocumentNo(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const norm = foldText(value).replace(/[^a-z0-9]/g, '');
  return norm === '' ? null : norm;
}

export function parseExpenseInput(body, now = new Date()) {
  const input = objectOf(body);
  const categoryId = optionalId(input.category_id, 'Kategori');
  if (categoryId === null) {
    throw invalidBody('Kategori seçin.');
  }
  const amount = requireMinor(input.amount_minor, 'Tutar', { min: 1, max: MAX_EXPENSE_MINOR });
  const kind = input.document_kind === undefined || input.document_kind === null ? 'none' : input.document_kind;
  if (!DOCUMENT_KINDS.includes(kind)) {
    throw invalidBody('Belge türü geçersiz.');
  }
  const documentNo = normalizeFreeText(input.document_no, { label: 'Belge numarası', max: 40 });
  const expenseDate = parseIsoDate(input.expense_date, 'Gider tarihi');
  if (expenseDate > today(now)) {
    throw invalidBody('Gider tarihi gelecek bir tarih olamaz.');
  }
  return {
    categoryId,
    supplierId: optionalId(input.supplier_id, 'Tedarikçi'),
    description: normalizeFreeText(input.description, { label: 'Açıklama', max: 200, required: true }),
    amountMinor: amount,
    vatMinor: present(input.vat_minor) ? requireMinor(input.vat_minor, 'KDV', { min: 0, max: amount }) : null,
    expenseDate,
    accountId: optionalId(input.account_id, 'Hesap'),
    documentKind: kind,
    documentNo,
    allowDuplicate: parseBooleanFlag(input.allow_duplicate, 'Yinelenen gider seçeneği'),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export const expenseFingerprint = (input) =>
  fingerprintOf({
    v: 1,
    kind: 'expense',
    category_id: input.categoryId,
    supplier_id: input.supplierId,
    description: input.description,
    amount_minor: input.amountMinor,
    vat_minor: input.vatMinor,
    expense_date: input.expenseDate,
    account_id: input.accountId,
    document_kind: input.documentKind,
    document_no: input.documentNo,
  });

const EXPENSE_SELECT = `
  SELECT
    e.id, e.category_id, e.category_name, e.supplier_id, e.supplier_name, e.description, e.amount_minor::TEXT AS amount_minor, e.vat_minor::TEXT AS vat_minor,
    to_char(e.expense_date, 'YYYY-MM-DD') AS expense_date, e.account_id, a.name AS account_name, e.document_kind, e.document_no, e.corrects_expense_id,
    e.request_fingerprint, e.created_at, u.full_name AS created_by_name,
    v.voided_at, v.reason AS void_reason, to_char(v.period, 'YYYY-MM-DD') AS void_period,
    (SELECT COUNT(*) FROM expense_documents d WHERE d.expense_id = e.id AND d.status = 'ready' AND d.removed_at IS NULL)::INTEGER AS documents_count
  FROM expenses e
  INNER JOIN finance_accounts a ON a.id = e.account_id
  LEFT JOIN users u ON u.user_code = e.created_by
  LEFT JOIN expense_voids v ON v.expense_id = e.id
`;

export function mapExpenseRow(row) {
  return {
    id: Number(row.id),
    category_id: Number(row.category_id),
    category_name: row.category_name,
    supplier_id: row.supplier_id === null || row.supplier_id === undefined ? null : Number(row.supplier_id),
    supplier_name: row.supplier_name ?? null,
    description: row.description,
    amount_minor: minorToNumber(row.amount_minor),
    vat_minor: row.vat_minor === null || row.vat_minor === undefined ? null : minorToNumber(row.vat_minor),
    expense_date: row.expense_date,
    account: { id: Number(row.account_id), name: row.account_name },
    document_kind: row.document_kind,
    document_no: row.document_no ?? null,
    voided: row.voided_at ? { at: toIso(row.voided_at), reason: row.void_reason, period: row.void_period } : null,
    corrects_expense_id: row.corrects_expense_id === null || row.corrects_expense_id === undefined ? null : Number(row.corrects_expense_id),
    documents_count: Number(row.documents_count ?? 0),
    created_by_name: row.created_by_name ?? null,
    created_at: toIso(row.created_at),
  };
}

export async function loadExpenseRow(db, siteCode, id) {
  const result = await db.query(`${EXPENSE_SELECT} WHERE e.id = $1 AND e.site_code = $2`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function findExpenseByKey(db, siteCode, key) {
  const result = await db.query(`${EXPENSE_SELECT} WHERE e.site_code = $1 AND e.idempotency_key = $2`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

async function accountBalance(db, siteCode, accountId) {
  const result = await db.query(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS balance FROM account_movements WHERE site_code = $1 AND account_id = $2`, [siteCode, accountId]);
  return minorToNumber(result.rows[0].balance);
}

/**
 * Gider yazma çekirdeği (create ve correct ortak). Çağıran: işlem açık, finance_post kilidi alınmış, kullanıcı satırı kilitli.
 * @returns {Promise<{ replayed: boolean, row: object, movementId: number|null }>}
 */
async function writeExpense(client, { siteCode, input, actorInfo, actor, correctsExpenseId = null, now }) {
  const fingerprint = expenseFingerprint(input);
  const existing = await findExpenseByKey(client, siteCode, input.idempotencyKey);
  if (existing) {
    if (existing.request_fingerprint !== fingerprint) {
      throw idempotencyConflict();
    }
    return { replayed: true, row: existing, movementId: null };
  }
  const policy = await loadAccountPolicy(client, siteCode);
  if (policy.total === 0) {
    throw noAccount();
  }
  if (input.accountId === null) {
    throw invalidBody('Giderin çıkacağı hesabı seçin.');
  }
  const accounts = await lockAccountRows(client, siteCode, [input.accountId]);
  const account = accounts.get(input.accountId);
  const period = await assertWritableDate(client, siteCode, input.expenseDate, 'Gider tarihi', now);
  if (account.is_active !== true) {
    throw accountInactive();
  }
  if (input.expenseDate < account.opening_date) {
    throw beforeOpeningDate();
  }
  const category = await client.query(`SELECT name, is_active FROM expense_categories WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [input.categoryId, siteCode]);
  if (!category.rows?.[0]) {
    throw categoryNotFound();
  }
  if (category.rows[0].is_active !== true) {
    throw categoryInactive();
  }
  let supplierName = null;
  if (input.supplierId !== null) {
    const supplier = await client.query(`SELECT name FROM finance_suppliers WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [input.supplierId, siteCode]);
    if (!supplier.rows?.[0]) {
      throw supplierNotFound();
    }
    supplierName = supplier.rows[0].name;
  }
  const norm = normalizeDocumentNo(input.documentNo);
  if (norm !== null && input.supplierId !== null) {
    const dupNo = await client.query(
      `
        SELECT e.id FROM expenses e
        WHERE e.site_code = $1 AND e.supplier_id = $2 AND e.document_no_norm = $3 AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)
        ORDER BY e.id LIMIT 1
      `,
      [siteCode, input.supplierId, norm],
    );
    if (dupNo.rows?.[0]) {
      throw duplicateDocumentNo(Number(dupNo.rows[0].id));
    }
  }
  if (!input.allowDuplicate) {
    const dup = await client.query(
      `
        SELECT e.id FROM expenses e
        WHERE e.site_code = $1 AND e.supplier_id IS NOT DISTINCT FROM $2::BIGINT AND e.amount_minor = $3::BIGINT AND e.expense_date = $4::DATE AND e.category_id = $5
          AND e.created_at > NOW() - INTERVAL '24 hours' AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)
        ORDER BY e.id LIMIT 1
      `,
      [siteCode, input.supplierId, String(input.amountMinor), input.expenseDate, input.categoryId],
    );
    if (dup.rows?.[0]) {
      throw duplicateExpense(Number(dup.rows[0].id));
    }
  }
  const inserted = await client.query(
    `
      INSERT INTO expenses (
        site_code, category_id, category_name, supplier_id, supplier_name, description, amount_minor, vat_minor, expense_date, period, account_id,
        document_kind, document_no, document_no_norm, corrects_expense_id, idempotency_key, request_fingerprint, created_by
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7::BIGINT, $8::BIGINT, $9::DATE, $10::DATE, $11, $12, $13, $14, $15, $16, $17, $18)
      RETURNING id
    `,
    [
      siteCode,
      input.categoryId,
      category.rows[0].name,
      input.supplierId,
      supplierName,
      input.description,
      String(input.amountMinor),
      input.vatMinor === null ? null : String(input.vatMinor),
      input.expenseDate,
      period,
      input.accountId,
      input.documentKind,
      input.documentNo,
      norm,
      correctsExpenseId,
      input.idempotencyKey,
      fingerprint,
      actorInfo.userCode,
    ],
  );
  const id = Number(inserted.rows[0].id);
  const movement = await client.query(
    `
      INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, expense_id, created_by)
      VALUES ($1, $2, 'expense', $3::BIGINT, $4::DATE, $5::DATE, $6, $7)
      RETURNING id
    `,
    [siteCode, input.accountId, String(-input.amountMinor), input.expenseDate, period, id, actorInfo.userCode],
  );
  await recordFinanceAudit(client, actor, correctsExpenseId === null ? 'finance.expense.created' : 'finance.expense.corrected', siteCode, id, {
    category_id: input.categoryId,
    supplier_id: input.supplierId,
    amount_minor: input.amountMinor,
    account_id: input.accountId,
    corrects_expense_id: correctsExpenseId,
  });
  return { replayed: false, row: await loadExpenseRow(client, siteCode, id), movementId: Number(movement.rows[0].id) };
}

/** POST expenses -> { replayed, expense, movement, account_balance_minor }. */
export async function createExpense({ siteCode, body, actor, now = new Date() }) {
  const input = parseExpenseInput(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const result = await writeExpense(client, { siteCode, input, actorInfo, actor, now });
    return {
      replayed: result.replayed,
      expense: mapExpenseRow(result.row),
      movement: result.movementId === null ? null : { id: result.movementId, kind: 'expense', account_id: input.accountId, amount_minor: -input.amountMinor },
      account_balance_minor: await accountBalance(client, siteCode, Number(result.row.account_id)),
    };
  });
}

export function parseVoidInput(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Neden', max: 200, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

/** İptal çekirdeği: expense_voids + ayna hareket (AÇIK ay, bugün). Çağıran kilitleri almıştır. */
async function voidExpenseRow(client, { siteCode, row, reason, idempotencyKey, actorInfo, actor, now }) {
  const original = await client.query(`SELECT id, account_id, amount_minor::TEXT AS amount_minor FROM account_movements WHERE kind = 'expense' AND expense_id = $1`, [Number(row.id)]);
  if (!original.rows?.[0]) {
    throw new Error('gider hareketi bulunamadi');
  }
  await lockAccountRows(client, siteCode, [Number(row.account_id)]);
  const openPeriod = await resolveOpenPeriod(client, siteCode, now);
  try {
    await client.query(`INSERT INTO expense_voids (expense_id, site_code, reason, period, voided_by) VALUES ($1, $2, $3, $4::DATE, $5)`, [Number(row.id), siteCode, reason, openPeriod, actorInfo.userCode]);
  } catch (error) {
    if (error?.code === '23505') {
      throw expenseAlreadyVoided();
    }
    throw error;
  }
  const movement = original.rows[0];
  await client.query(
    `
      INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reverses_movement_id, note, idempotency_key, created_by)
      VALUES ($1, $2, 'reversal', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8, $9)
    `,
    [siteCode, Number(movement.account_id), String(-BigInt(movement.amount_minor)), today(now), openPeriod, Number(movement.id), reason, idempotencyKey, actorInfo.userCode],
  );
  await recordFinanceAudit(client, actor, 'finance.expense.voided', siteCode, Number(row.id), {
    amount_minor: minorToNumber(row.amount_minor),
    account_id: Number(row.account_id),
    period: openPeriod.slice(0, 7),
  });
}

/** POST expenses/:id/void -> { replayed, expense, account_balance_minor }. */
export async function voidExpense({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw expenseNotFound();
  }
  const input = parseVoidInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const row = await loadExpenseRow(client, siteCode, id);
    if (!row) {
      throw expenseNotFound();
    }
    const replay = await client.query(`SELECT reverses_movement_id FROM account_movements WHERE site_code = $1 AND idempotency_key = $2`, [siteCode, input.idempotencyKey]);
    if (replay.rows?.[0]) {
      const original = await client.query(`SELECT expense_id FROM account_movements WHERE id = $1`, [Number(replay.rows[0].reverses_movement_id)]);
      // aynı anahtar + farklı neden = çakışma (R15 P2-4)
      if (Number(original.rows?.[0]?.expense_id) !== id || (row.void_reason ?? null) !== input.reason) {
        throw idempotencyConflict();
      }
      return { replayed: true, expense: mapExpenseRow(row), account_balance_minor: await accountBalance(client, siteCode, Number(row.account_id)) };
    }
    if (row.voided_at) {
      throw expenseAlreadyVoided();
    }
    await voidExpenseRow(client, { siteCode, row, reason: input.reason, idempotencyKey: input.idempotencyKey, actorInfo, actor, now });
    return {
      replayed: false,
      expense: mapExpenseRow(await loadExpenseRow(client, siteCode, id)),
      account_balance_minor: await accountBalance(client, siteCode, Number(row.account_id)),
    };
  });
}

/** POST expenses/:id/correct { …yeni alanlar…, idempotency_key } -> { replayed, voided, expense }. İptal + yeni gider TEK işlemde (yarım kalmaz). */
export async function correctExpense({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw expenseNotFound();
  }
  const input = parseExpenseInput(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const row = await loadExpenseRow(client, siteCode, id);
    if (!row) {
      throw expenseNotFound();
    }
    const existing = await findExpenseByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (existing.request_fingerprint !== expenseFingerprint(input) || Number(existing.corrects_expense_id) !== id) {
        throw idempotencyConflict();
      }
      return { replayed: true, voided: mapExpenseRow(await loadExpenseRow(client, siteCode, id)), expense: mapExpenseRow(existing) };
    }
    if (row.voided_at) {
      throw expenseAlreadyVoided();
    }
    // KİLİT SIRASI: eski ve yeni giderin hesapları TEK seferde id sırasıyla (iptal eskisini, yeni gider yenisini ayrı kilitlerse ters sıra doğabilir; R10 P2-15)
    await lockAccountRows(client, siteCode, [Number(row.account_id), input.accountId].filter((value) => value !== null && value !== undefined));
    await voidExpenseRow(client, { siteCode, row, reason: DEFAULT_VOID_REASON, idempotencyKey: null, actorInfo, actor, now });
    const result = await writeExpense(client, { siteCode, input, actorInfo, actor, correctsExpenseId: id, now });
    return { replayed: false, voided: mapExpenseRow(await loadExpenseRow(client, siteCode, id)), expense: mapExpenseRow(result.row) };
  });
}

// --- Liste / detay ------------------------------------------------------------------------------------------------------------------------

export function parseExpensesQuery(query = {}) {
  const from = queryDate(query.from);
  const to = queryDate(query.to);
  if (from !== null && to !== null && from > to) {
    throw invalidBody('Tarih aralığı geçersiz.');
  }
  return {
    from,
    to,
    categoryId: queryId(query.category_id),
    supplierId: queryId(query.supplier_id),
    accountId: queryId(query.account_id),
    status: queryEnum(query.status, ['active', 'voided', 'all'], 'all'),
    q: typeof query.q === 'string' && query.q.trim() !== '' ? Array.from(query.q.trim()).slice(0, 60).join('') : null,
    limit: queryInt(query.limit, { min: 1, max: 200, fallback: 50 }),
    beforeId: queryId(query.before_id),
  };
}

/** Gider süzgeçleri (liste, dışa aktarma ve rapor AYNI mantığı paylaşır). */
export function expenseFilterSql(filters, startParams = []) {
  const params = [...startParams];
  const clauses = [];
  const add = (sql, value) => {
    params.push(value);
    clauses.push(sql.replace('?', `$${params.length}`));
  };
  if (filters.from !== null) add('e.expense_date >= ?::DATE', filters.from);
  if (filters.to !== null) add('e.expense_date <= ?::DATE', filters.to);
  if (filters.categoryId !== null) add('e.category_id = ?', filters.categoryId);
  if (filters.supplierId !== null) add('e.supplier_id = ?', filters.supplierId);
  if (filters.accountId !== null) add('e.account_id = ?', filters.accountId);
  if (filters.status === 'active') clauses.push('v.expense_id IS NULL');
  if (filters.status === 'voided') clauses.push('v.expense_id IS NOT NULL');
  if (filters.q !== null) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const like = `$${params.length}`;
    clauses.push(`(${foldSql('e.description')} LIKE ${like} ESCAPE '\\' OR ${foldSql('e.category_name')} LIKE ${like} ESCAPE '\\' OR ${foldSql('e.supplier_name')} LIKE ${like} ESCAPE '\\' OR ${foldSql('e.document_no')} LIKE ${like} ESCAPE '\\')`);
  }
  return { params, clauses };
}

/** GET expenses -> { items, next_before_id, totals: { active_minor, voided_minor } }. */
export async function listExpenses(siteCode, query = {}, db = pool) {
  const filters = parseExpensesQuery(query);
  const base = expenseFilterSql(filters, [siteCode]);
  const totals = await db.query(
    `
      SELECT COALESCE(SUM(e.amount_minor) FILTER (WHERE v.expense_id IS NULL), 0)::TEXT AS active,
             COALESCE(SUM(e.amount_minor) FILTER (WHERE v.expense_id IS NOT NULL), 0)::TEXT AS voided
      FROM expenses e LEFT JOIN expense_voids v ON v.expense_id = e.id
      WHERE e.site_code = $1${base.clauses.map((c) => ` AND ${c}`).join('')}
    `,
    base.params,
  );
  const params = [...base.params];
  const clauses = [...base.clauses];
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`e.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const result = await db.query(
    `${EXPENSE_SELECT} WHERE e.site_code = $1${clauses.map((c) => ` AND ${c}`).join('')} ORDER BY e.id DESC LIMIT $${params.length}`,
    params,
  );
  const rows = result.rows ?? [];
  const page = rows.slice(0, filters.limit);
  return {
    items: page.map(mapExpenseRow),
    next_before_id: rows.length > filters.limit && page.length > 0 ? Number(page[page.length - 1].id) : null,
    totals: { active_minor: minorToNumber(totals.rows[0].active), voided_minor: minorToNumber(totals.rows[0].voided) },
  };
}

/** Dışa aktarma: liste süzgeçleriyle AYNI mantık, sayfalamasız (en çok limit satır; çağıran üst sınırı denetler). */
export async function exportExpenseRows(siteCode, query = {}, db = pool, limit = 20001) {
  const filters = parseExpensesQuery({ ...query, limit: undefined, before_id: undefined });
  const base = expenseFilterSql(filters, [siteCode]);
  const params = [...base.params, limit];
  const result = await db.query(
    `${EXPENSE_SELECT} WHERE e.site_code = $1${base.clauses.map((c) => ` AND ${c}`).join('')} ORDER BY e.expense_date DESC, e.id DESC LIMIT $${params.length}`,
    params,
  );
  return (result.rows ?? []).map(mapExpenseRow);
}

/** GET expenses/:id -> { expense, documents }. */
export async function getExpense(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw expenseNotFound();
  }
  const row = await loadExpenseRow(db, siteCode, id);
  if (!row) {
    throw expenseNotFound();
  }
  const docs = await db.query(
    `
      SELECT d.id, d.status, d.kind, d.display_name, d.mime_type, d.size_bytes::TEXT AS size_bytes, d.sha256, d.added_at, d.completed_at
      FROM expense_documents d WHERE d.expense_id = $1 AND d.site_code = $2 AND d.removed_at IS NULL ORDER BY d.id
    `,
    [id, siteCode],
  );
  return {
    ...mapExpenseRow(row),
    documents: (docs.rows ?? []).map((d) => ({
      id: Number(d.id),
      status: d.status,
      kind: d.kind,
      display_name: d.display_name,
      mime_type: d.mime_type,
      size_bytes: minorToNumber(d.size_bytes),
      sha256: d.sha256 ?? null,
      added_at: toIso(d.added_at),
      completed_at: toIso(d.completed_at),
    })),
  };
}

void accountNotFound;
