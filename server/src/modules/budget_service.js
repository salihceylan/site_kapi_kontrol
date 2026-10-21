// İşletme projesi (bütçe): kalemler (kategori bazlı yıllık tutar), durum makinesi Taslak -> Tebliğ -> Kesin, geçici proje sayacı, planlanan-gerçekleşen.
//
// Sözleşme: docs/PLATFORM_BUTCE.md. Süreler kurallar tablosundan: budget.objection_days (itiraz süresi), budget.provisional_max_days (geçici proje üst süresi).
//  - Taslak: kalemler ve başlık serbestçe değişir, silinebilir. Tebliğ: kalem değişmez; tebliğ tarihi + itiraz süresi (anlık değer saklanır) kayıtlıdır; itiraz
//    gelirse taslağa geri alınır. Kesin: itiraz süresi bitmeden kesinleştirilemez; kesin proje değişmez ve silinmez; (site, yıl) başına tek kesin proje.
//  - Geçici proje: onaylı (kesin) proje yokken en çok provisional_max_days gün geçerlidir; kalan gün `getBudgetAttention` ile yönetici ana sayfasının dikkat özetine verilir.
//  - Para tamsayı kuruştur. Her sorguda site_code vardır (başka sitenin projesi 404). Audit `details` yalnız kimlik / durum / yıl taşır.
//  - Hukuki süreler ve adımlar [AVUKAT DOĞRULASIN] (KMK m.37, 7579 sayılı Kanun ile değişik).

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { getRule } from './platform_rules.js';
import { invalidBody, normalizeDateInput, parsePositiveId, todayIso } from './people_common.js';

export const BUDGET_MODULE = 'budget';
export const STATUSES = Object.freeze(['taslak', 'teblig', 'kesin']);
export const TITLE_MAX = 160;
export const NOTE_MAX = 1000;
export const MAX_ITEMS = 100;
export const MAX_AMOUNT_MINOR = 1_000_000_000_000;
export const MAX_PROJECTS_PER_SITE = 200;
export const MAX_BODY_BYTES = 65536;

export const projectNotFound = () => new PlatformError(404, 'BUDGET_NOT_FOUND', 'İşletme projesi bulunamadı ya da erişiminiz yok.');
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'İşletme Projesi modülü kapalı.', { module: BUDGET_MODULE });
const wrongStatus = (message) => new PlatformError(409, 'BUDGET_WRONG_STATUS', message);

// --- Saf yardımcılar ---------------------------------------------------------------------------------------------

const DAY_MS = 86_400_000;
const isoToMs = (iso) => Date.parse(`${iso}T00:00:00Z`);

/** 'YYYY-MM-DD' + n gün. */
export function addDays(iso, days) {
  return new Date(isoToMs(iso) + days * DAY_MS).toISOString().slice(0, 10);
}

/** a'dan b'ye gün farkı (b - a). */
export function daysBetween(a, b) {
  return Math.round((isoToMs(b) - isoToMs(a)) / DAY_MS);
}

/** Geçici proje kalan günü: bitiş günü dahil; bitmişse 0. */
export function provisionalRemainingDays(untilIso, today) {
  return Math.max(0, daysBetween(today, untilIso));
}

/** Kural tablosundan gelen değeri güvenli tamsayıya çevirir (kırpma getRule içinde yapılır). */
const ruleInt = (value, fallback) => (Number.isInteger(Number(value)) ? Number(value) : fallback);

function parseText(value, field, { max, required }) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalidBody(field, `${field} zorunludur.`);
    return null;
  }
  if (typeof value !== 'string') throw invalidBody(field);
  const text = value.trim().replace(/\s+/g, ' ');
  if (text === '' && required) throw invalidBody(field, `${field} zorunludur.`);
  if (text.length > max) throw invalidBody(field, `${field} en çok ${max} karakter olabilir.`);
  return text === '' ? null : text;
}

function parseYear(value) {
  const year = Number(value);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) throw invalidBody('year', 'year 2000-2100 arasında bir yıl olmalıdır.');
  return year;
}

/** POST gövdesi: { year, title, is_provisional?, provisional_start?, note? }. */
export function parseCreateInput(body, { today }) {
  const isProvisional = body.is_provisional === true;
  if (body.is_provisional !== undefined && typeof body.is_provisional !== 'boolean') throw invalidBody('is_provisional');
  const start = normalizeDateInput(body.provisional_start, 'provisional_start');
  return {
    year: parseYear(body.year),
    title: parseText(body.title, 'title', { max: TITLE_MAX, required: true }),
    note: parseText(body.note, 'note', { max: NOTE_MAX, required: false }),
    isProvisional,
    provisionalStart: isProvisional ? (start ?? today) : null,
  };
}

/** PUT items gövdesi: { items: [{ category_id, annual_minor }] }. Tutar tamsayı kuruş, 0..1e12; aynı kategori iki kez olamaz. */
export function parseItemsInput(body) {
  const list = body.items;
  if (!Array.isArray(list)) throw invalidBody('items', 'items bir liste olmalıdır.');
  if (list.length > MAX_ITEMS) throw invalidBody('items', `En çok ${MAX_ITEMS} kalem girilebilir.`);
  const seen = new Set();
  return list.map((entry, index) => {
    const categoryId = parsePositiveId(entry?.category_id);
    if (categoryId === null) throw invalidBody(`items[${index}].category_id`, 'Gider kategorisi geçersiz.');
    if (seen.has(categoryId)) throw invalidBody(`items[${index}].category_id`, 'Aynı kategori bir kez girilebilir.');
    seen.add(categoryId);
    const amount = entry?.annual_minor;
    if (typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount < 0 || amount > MAX_AMOUNT_MINOR) {
      throw invalidBody(`items[${index}].annual_minor`, 'Tutar 0 ile 10 milyar TL arasında, kuruş cinsinden tamsayı olmalıdır.');
    }
    return { categoryId, annualMinor: amount };
  });
}

/** Karşılaştırma satırı: sapma = gerçekleşen - planlanan; oran (yüzde, 1 ondalık) planlanan 0 ise null. */
export function comparisonRow({ categoryId, categoryName, plannedMinor, actualMinor }) {
  return {
    category_id: categoryId,
    category_name: categoryName,
    planned_minor: plannedMinor,
    actual_minor: actualMinor,
    variance_minor: actualMinor - plannedMinor,
    used_pct: plannedMinor > 0 ? Math.round((actualMinor / plannedMinor) * 1000) / 10 : null,
  };
}

const dateOf = (value) => (value === null || value === undefined ? null : value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10));

export function mapProject(row, today = todayIso()) {
  const provisionalUntil = dateOf(row.provisional_until);
  const open = row.status !== 'kesin';
  return {
    id: Number(row.id),
    year: row.year,
    title: row.title,
    status: row.status,
    is_provisional: row.is_provisional,
    provisional_start: dateOf(row.provisional_start),
    provisional_until: provisionalUntil,
    provisional_remaining_days: row.is_provisional && open && provisionalUntil ? provisionalRemainingDays(provisionalUntil, today) : null,
    notified_at: dateOf(row.notified_at),
    objection_days: row.objection_days ?? null,
    objection_ends: dateOf(row.objection_ends),
    finalized_at: row.finalized_at ? new Date(row.finalized_at).toISOString() : null,
    note: row.note ?? null,
    item_count: row.item_count === undefined ? undefined : Number(row.item_count),
    total_minor: row.total_minor === undefined ? undefined : Number(row.total_minor),
    created_at: row.created_at ? new Date(row.created_at).toISOString() : null,
  };
}

// --- İşlem çerçevesi ---------------------------------------------------------------------------------------------

async function withTx(work) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı kopmuş olabilir; asıl hata fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

async function lockProject(client, siteCode, rawId) {
  const id = parsePositiveId(rawId);
  if (id === null) throw projectNotFound();
  const result = await client.query(`SELECT * FROM budget_projects WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
  if (!result.rows?.[0]) throw projectNotFound();
  return result.rows[0];
}

const audit = (client, actor, siteCode, action, id, details) =>
  recordAudit(client, { actor, action, siteCode, targetType: 'budget_project', targetId: String(id), details }, { inTransaction: true });

const ITEMS_SQL = `SELECT category_id, category_name, annual_minor FROM budget_items WHERE project_id = $1 AND site_code = $2 ORDER BY category_name, category_id`;

async function loadItems(db, siteCode, projectId) {
  const result = await db.query(ITEMS_SQL, [projectId, siteCode]);
  return (result.rows ?? []).map((r) => ({ category_id: Number(r.category_id), category_name: r.category_name, annual_minor: Number(r.annual_minor) }));
}

async function detail(db, siteCode, row) {
  const items = await loadItems(db, siteCode, row.id);
  const project = mapProject(row);
  project.item_count = items.length;
  project.total_minor = items.reduce((sum, item) => sum + item.annual_minor, 0);
  return { project, items };
}

// --- Dikkat özeti (2F) ---------------------------------------------------------------------------------------------

/**
 * Yönetici ana sayfasının dikkat özeti için sayaç: onaylı (kesin) proje yokken süren geçici projenin kalan günü.
 * Birden çok açık geçici proje varsa en az kalan gün olan döner. Açık geçici proje yoksa `provisional` = null.
 * @returns {Promise<{ provisional: null | { project_id: number, year: number, title: string, remaining_days: number, until: string } }>}
 */
export async function getBudgetAttention(siteCode, db = pool, now = new Date()) {
  const result = await db.query(
    `SELECT id, year, title, provisional_until FROM budget_projects
     WHERE site_code = $1 AND is_provisional = TRUE AND status <> 'kesin'
     ORDER BY provisional_until ASC, id ASC LIMIT 1`,
    [siteCode],
  );
  const row = result.rows?.[0];
  if (!row) return { provisional: null };
  const until = dateOf(row.provisional_until);
  return {
    provisional: { project_id: Number(row.id), year: row.year, title: row.title, remaining_days: provisionalRemainingDays(until, todayIso(now)), until },
  };
}

// --- Okuma ---------------------------------------------------------------------------------------------------------

export async function listProjects(siteCode, db = pool) {
  const result = await db.query(
    `SELECT p.*, COALESCE(i.cnt, 0) AS item_count, COALESCE(i.total, 0) AS total_minor
     FROM budget_projects p
     LEFT JOIN (SELECT project_id, COUNT(*) AS cnt, SUM(annual_minor) AS total FROM budget_items WHERE site_code = $1 GROUP BY project_id) i ON i.project_id = p.id
     WHERE p.site_code = $1 ORDER BY p.year DESC, p.id DESC LIMIT ${MAX_PROJECTS_PER_SITE}`,
    [siteCode],
  );
  const today = todayIso();
  return { items: (result.rows ?? []).map((row) => mapProject(row, today)), attention: await getBudgetAttention(siteCode, db) };
}

export async function getProject(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) throw projectNotFound();
  const result = await db.query(`SELECT * FROM budget_projects WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!result.rows?.[0]) throw projectNotFound();
  return detail(db, siteCode, result.rows[0]);
}

/** Planlanan (proje kalemleri) - gerçekleşen (yılın iptal edilmemiş giderleri, kategori bazlı). Kalemi olmayan ama gideri olan kategori planlanan 0 ile gelir. */
export async function getComparison(siteCode, rawId, db = pool) {
  const { project, items } = await getProject(siteCode, rawId, db);
  const actual = await db.query(
    `SELECT e.category_id, MAX(e.category_name) AS category_name, SUM(e.amount_minor)::TEXT AS total
     FROM expenses e
     LEFT JOIN expense_voids v ON v.expense_id = e.id
     WHERE e.site_code = $1 AND v.expense_id IS NULL AND e.expense_date >= make_date($2, 1, 1) AND e.expense_date <= make_date($2, 12, 31)
     GROUP BY e.category_id`,
    [siteCode, project.year],
  );
  const byCategory = new Map();
  for (const item of items) {
    byCategory.set(item.category_id, { categoryId: item.category_id, categoryName: item.category_name, plannedMinor: item.annual_minor, actualMinor: 0 });
  }
  for (const row of actual.rows ?? []) {
    const key = Number(row.category_id);
    const entry = byCategory.get(key) ?? { categoryId: key, categoryName: row.category_name, plannedMinor: 0, actualMinor: 0 };
    entry.actualMinor = Number(row.total);
    byCategory.set(key, entry);
  }
  const rows = [...byCategory.values()].sort((a, b) => a.categoryName.localeCompare(b.categoryName, 'tr')).map(comparisonRow);
  const planned = rows.reduce((s, r) => s + r.planned_minor, 0);
  const actualTotal = rows.reduce((s, r) => s + r.actual_minor, 0);
  return { project, rows, totals: comparisonRow({ categoryId: 0, categoryName: 'Toplam', plannedMinor: planned, actualMinor: actualTotal }) };
}

// --- Yazma ---------------------------------------------------------------------------------------------------------

export async function createProject({ siteCode, actor, body, now = new Date() }) {
  const today = todayIso(now);
  const input = parseCreateInput(body, { today });
  const actorInfo = actorFromAuthUser(actor);
  return withTx(async (client) => {
    const count = await client.query(`SELECT COUNT(*)::INT AS n FROM budget_projects WHERE site_code = $1`, [siteCode]);
    if ((count.rows?.[0]?.n ?? 0) >= MAX_PROJECTS_PER_SITE) {
      throw new PlatformError(409, 'BUDGET_LIMIT_REACHED', `Bir sitede en fazla ${MAX_PROJECTS_PER_SITE} işletme projesi tutulabilir.`);
    }
    let until = null;
    if (input.isProvisional) {
      const maxDays = ruleInt(await getRule(client, 'budget.provisional_max_days', { siteCode, onDate: today }), 90);
      until = addDays(input.provisionalStart, maxDays);
    }
    const inserted = await client.query(
      `INSERT INTO budget_projects (site_code, year, title, is_provisional, provisional_start, provisional_until, note, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [siteCode, input.year, input.title, input.isProvisional, input.provisionalStart, until, input.note, actorInfo.userCode],
    );
    const row = inserted.rows[0];
    await audit(client, actor, siteCode, 'budget.create', row.id, { year: input.year, provisional: input.isProvisional });
    return detail(client, siteCode, row);
  });
}

export async function updateProject({ siteCode, rawId, actor, body }) {
  const hasTitle = body.title !== undefined;
  const hasNote = body.note !== undefined;
  if (!hasTitle && !hasNote) throw invalidBody('title', 'Değiştirilecek alan yok.');
  const title = hasTitle ? parseText(body.title, 'title', { max: TITLE_MAX, required: true }) : null;
  const note = hasNote ? parseText(body.note, 'note', { max: NOTE_MAX, required: false }) : null;
  return withTx(async (client) => {
    const row = await lockProject(client, siteCode, rawId);
    if (row.status !== 'taslak') throw wrongStatus('Yalnız taslak proje değiştirilebilir.');
    const updated = await client.query(
      `UPDATE budget_projects SET title = CASE WHEN $3 THEN $4 ELSE title END, note = CASE WHEN $5 THEN $6 ELSE note END, updated_at = NOW()
       WHERE id = $1 AND site_code = $2 RETURNING *`,
      [row.id, siteCode, hasTitle, title, hasNote, note],
    );
    await audit(client, actor, siteCode, 'budget.update', row.id, { fields: [hasTitle && 'title', hasNote && 'note'].filter(Boolean) });
    return detail(client, siteCode, updated.rows[0]);
  });
}

export async function replaceItems({ siteCode, rawId, actor, body }) {
  const items = parseItemsInput(body);
  return withTx(async (client) => {
    const row = await lockProject(client, siteCode, rawId);
    if (row.status !== 'taslak') throw wrongStatus('Yalnız taslak projenin kalemleri değiştirilebilir.');
    let names = new Map();
    if (items.length > 0) {
      const cats = await client.query(`SELECT id, name FROM expense_categories WHERE site_code = $1 AND id = ANY($2::BIGINT[])`, [siteCode, items.map((i) => i.categoryId)]);
      names = new Map((cats.rows ?? []).map((c) => [Number(c.id), c.name]));
      const missing = items.findIndex((i) => !names.has(i.categoryId));
      if (missing >= 0) throw invalidBody(`items[${missing}].category_id`, 'Gider kategorisi bu sitede bulunamadı.');
    }
    await client.query(`DELETE FROM budget_items WHERE project_id = $1 AND site_code = $2`, [row.id, siteCode]);
    for (const item of items) {
      await client.query(`INSERT INTO budget_items (project_id, site_code, category_id, category_name, annual_minor) VALUES ($1, $2, $3, $4, $5)`, [
        row.id,
        siteCode,
        item.categoryId,
        names.get(item.categoryId),
        item.annualMinor,
      ]);
    }
    await client.query(`UPDATE budget_projects SET updated_at = NOW() WHERE id = $1`, [row.id]);
    await audit(client, actor, siteCode, 'budget.items', row.id, { count: items.length });
    return detail(client, siteCode, row);
  });
}

/** Taslak -> Tebliğ. Tebliğ tarihi bugünden ileri olamaz; itiraz süresi kurallar tablosundan alınıp projeye yazılır. */
export async function notifyProject({ siteCode, rawId, actor, body, now = new Date() }) {
  const today = todayIso(now);
  const notifiedAt = normalizeDateInput(body.notified_at, 'notified_at') ?? today;
  if (notifiedAt > today) throw invalidBody('notified_at', 'Tebliğ tarihi gelecekte olamaz.');
  return withTx(async (client) => {
    const row = await lockProject(client, siteCode, rawId);
    if (row.status !== 'taslak') throw wrongStatus('Yalnız taslak proje tebliğ edilebilir.');
    const count = await client.query(`SELECT COUNT(*)::INT AS n FROM budget_items WHERE project_id = $1`, [row.id]);
    if ((count.rows?.[0]?.n ?? 0) === 0) throw new PlatformError(409, 'BUDGET_NO_ITEMS', 'Tebliğ için en az bir bütçe kalemi girilmelidir.');
    const days = ruleInt(await getRule(client, 'budget.objection_days', { siteCode, onDate: today }), 7);
    const updated = await client.query(
      `UPDATE budget_projects SET status = 'teblig', notified_at = $3, objection_days = $4, objection_ends = $5, updated_at = NOW()
       WHERE id = $1 AND site_code = $2 RETURNING *`,
      [row.id, siteCode, notifiedAt, days, addDays(notifiedAt, days)],
    );
    await audit(client, actor, siteCode, 'budget.notify', row.id, { year: row.year, objection_days: days });
    return detail(client, siteCode, updated.rows[0]);
  });
}

/** Tebliğ -> Taslak (itiraz üzerine revize). Tebliğ bilgileri silinir. */
export async function revertProject({ siteCode, rawId, actor }) {
  return withTx(async (client) => {
    const row = await lockProject(client, siteCode, rawId);
    if (row.status !== 'teblig') throw wrongStatus('Yalnız tebliğ edilmiş proje taslağa geri alınabilir.');
    const updated = await client.query(
      `UPDATE budget_projects SET status = 'taslak', notified_at = NULL, objection_days = NULL, objection_ends = NULL, updated_at = NOW()
       WHERE id = $1 AND site_code = $2 RETURNING *`,
      [row.id, siteCode],
    );
    await audit(client, actor, siteCode, 'budget.revert', row.id, { year: row.year });
    return detail(client, siteCode, updated.rows[0]);
  });
}

/** Tebliğ -> Kesin: itiraz süresi (tebliğ + itiraz günü) geçmeden olmaz; yıl için başka kesin proje varsa 409. */
export async function finalizeProject({ siteCode, rawId, actor, now = new Date() }) {
  const today = todayIso(now);
  const actorInfo = actorFromAuthUser(actor);
  return withTx(async (client) => {
    const row = await lockProject(client, siteCode, rawId);
    if (row.status !== 'teblig') throw wrongStatus('Yalnız tebliğ edilmiş proje kesinleştirilebilir.');
    const ends = dateOf(row.objection_ends);
    if (today <= ends) {
      throw new PlatformError(409, 'BUDGET_OBJECTION_OPEN', `İtiraz süresi ${ends} tarihinde bitiyor; bundan sonra kesinleştirilebilir.`, { objection_ends: ends });
    }
    const other = await client.query(`SELECT 1 FROM budget_projects WHERE site_code = $1 AND year = $2 AND status = 'kesin' AND id <> $3 LIMIT 1`, [siteCode, row.year, row.id]);
    if (other.rows?.[0]) throw new PlatformError(409, 'BUDGET_YEAR_FINAL_EXISTS', `${row.year} yılı için kesin bir işletme projesi zaten var.`);
    let updated;
    try {
      updated = await client.query(
        `UPDATE budget_projects SET status = 'kesin', finalized_at = NOW(), finalized_by = $3, updated_at = NOW() WHERE id = $1 AND site_code = $2 RETURNING *`,
        [row.id, siteCode, actorInfo.userCode],
      );
    } catch (error) {
      if (error?.code === '23505') throw new PlatformError(409, 'BUDGET_YEAR_FINAL_EXISTS', `${row.year} yılı için kesin bir işletme projesi zaten var.`);
      throw error;
    }
    await audit(client, actor, siteCode, 'budget.finalize', row.id, { year: row.year });
    return detail(client, siteCode, updated.rows[0]);
  });
}

export async function deleteProject({ siteCode, rawId, actor }) {
  return withTx(async (client) => {
    const row = await lockProject(client, siteCode, rawId);
    if (row.status !== 'taslak') throw wrongStatus('Yalnız taslak proje silinebilir.');
    await client.query(`DELETE FROM budget_projects WHERE id = $1 AND site_code = $2`, [row.id, siteCode]);
    await audit(client, actor, siteCode, 'budget.delete', row.id, { year: row.year });
    return { deleted: true };
  });
}
