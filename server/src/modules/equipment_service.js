// Ekipman, bakim ve teklif is mantigi. Sozlesme: docs/PLATFORM_EKIPMAN.md.
// Para tamsayi kurus. Bakim kaydi yalniz eklemelidir (duzeltme yeni kayitla). Gider satiri degismez: ekipman baglantisi yan tablodadir (equipment_expense_links).
// Tahsilat/defter yazilmaz; kabul edilen teklif gidere ya da sozlesmeye YALNIZ createExpense / createContract ile donusur.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { recordAudit } from './audit_service.js';
import { isModuleEnabled } from './module_service.js';
import { createExpense } from './finance_expenses.js';
import { createContract } from './contracts_service.js';
import { todayIstanbul } from './reservation_time.js';

export const EQUIPMENT_MODULE = 'equipment';
export const DEFAULT_KINDS = Object.freeze([
  { code: 'asansor', name: 'Asansör', legal_months: 12, legal_title: 'Yıllık asansör periyodik kontrolü' },
  { code: 'interkom', name: 'İnterkom' },
  { code: 'kamera', name: 'Kamera' },
  { code: 'bariyer', name: 'Bariyer' },
  { code: 'yangin_algilama', name: 'Yangın algılama', legal_months: 12, legal_title: 'Yıllık yangın sistemi kontrolü' },
  { code: 'hidrofor', name: 'Hidrofor' },
  { code: 'jenerator', name: 'Jeneratör' },
  { code: 'kazan', name: 'Kazan', legal_months: 12, legal_title: 'Yıllık kazan periyodik kontrolü' },
  { code: 'havuz', name: 'Havuz' },
]);
export const INTERVALS = Object.freeze([1, 3, 6, 12]);
export const LIMITS = Object.freeze({ items: 1000, plansPerItem: 30, quotes: 3000 });
export const MAX_BODY_BYTES = 16384;
const MAX_KURUS = 1_000_000_000_000;

const invalid = (field, message) => new PlatformError(400, 'INVALID_FIELD', message, { field });
const notFound = (what = 'Kayıt') => new PlatformError(404, 'NOT_FOUND', `${what} bulunamadı ya da erişiminiz yok.`);
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Ekipman ve Bakım modülü kapalı.', { module: EQUIPMENT_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

// --- Girdi yardimcilari ---------------------------------------------------------------------------------------------

const clean = (v) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim() : v);

export function text(value, field, label, max, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  if (typeof value !== 'string') throw invalid(field, `${label} geçersiz.`);
  const out = clean(value);
  if (out === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  if (out.length > max) throw invalid(field, `${label} en çok ${max} karakter olabilir.`);
  return out;
}

export function isoDate(value, field, label, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw invalid(field, `${label} YYYY-AA-GG biçiminde olmalı.`);
  const d = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value) throw invalid(field, `${label} geçersiz.`);
  return value;
}

export function kurus(value, field, label, { required = false, min = 0 } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > MAX_KURUS) {
    throw invalid(field, `${label} kuruş cinsinden tam sayı olmalı.`);
  }
  return value;
}

function id(value, field, label, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw invalid(field, `${label} zorunludur.`);
    return null;
  }
  const n = typeof value === 'string' && /^\d{1,16}$/.test(value) ? Number(value) : value;
  if (!Number.isSafeInteger(n) || n <= 0) throw invalid(field, `${label} geçersiz.`);
  return n;
}

function bool(value, field, label) {
  if (value === undefined) return undefined;
  if (typeof value !== 'boolean') throw invalid(field, `${label} true/false olmalı.`);
  return value;
}

function interval(value, { required = false } = {}) {
  if (value === undefined || value === null) {
    if (required) throw invalid('interval_months', 'Bakım sıklığı zorunludur.');
    return undefined;
  }
  if (!INTERVALS.includes(value)) throw invalid('interval_months', 'Bakım sıklığı 1, 3, 6 ya da 12 ay olmalı.');
  return value;
}

const bodyOf = (b) => {
  if (!b || typeof b !== 'object' || Array.isArray(b)) throw new PlatformError(400, 'INVALID_BODY', 'Gövde geçersiz.');
  return b;
};

async function audit(actor, action, siteCode, type, targetId, details) {
  await recordAudit(pool, { actor, action, siteCode, targetType: type, targetId: String(targetId), details });
}

const userOf = (access) => access.userCode ?? null;

// --- Ekipman --------------------------------------------------------------------------------------------------------

const ITEM_COLS = `i.id, i.kind, i.name, i.location, i.vendor_id, i.serial_no, to_char(i.installed_on, 'YYYY-MM-DD') AS installed_on, i.note, i.is_active, i.created_at`;

function mapItem(r) {
  return {
    id: Number(r.id),
    kind: r.kind,
    name: r.name,
    location: r.location,
    vendor_id: r.vendor_id === null ? null : Number(r.vendor_id),
    serial_no: r.serial_no,
    installed_on: r.installed_on,
    note: r.note,
    is_active: r.is_active,
    created_at: r.created_at,
    ...(r.next_due !== undefined ? { next_due: r.next_due, overdue: r.overdue === true } : {}),
  };
}

export function metaInfo() {
  return { kinds: DEFAULT_KINDS, intervals: INTERVALS, reminders: 'soon' };
}

export async function listEquipment(siteCode, query = {}) {
  const active = query.active === 'all' ? null : query.active === '0' ? false : true;
  const r = await pool.query(
    `SELECT ${ITEM_COLS},
            (SELECT to_char(MIN(p.next_due), 'YYYY-MM-DD') FROM equipment_plans p WHERE p.equipment_id = i.id AND p.is_active) AS next_due,
            COALESCE((SELECT MIN(p.next_due) FROM equipment_plans p WHERE p.equipment_id = i.id AND p.is_active) < $3::DATE, FALSE) AS overdue
       FROM equipment_items i
      WHERE i.site_code = $1 AND ($2::BOOLEAN IS NULL OR i.is_active = $2)
      ORDER BY i.is_active DESC, lower(i.name), i.id
      LIMIT 500`,
    [siteCode, active, todayIstanbul()],
  );
  return { items: r.rows.map(mapItem) };
}

function parseItem(body, { create }) {
  const b = bodyOf(body);
  const out = {};
  const set = (key, value) => {
    if (value !== undefined) out[key] = value;
  };
  if (create || b.kind !== undefined) set('kind', text(b.kind, 'kind', 'Ekipman türü', 40, { required: true }));
  if (create || b.name !== undefined) set('name', text(b.name, 'name', 'Ekipman adı', 120, { required: true }));
  if (b.location !== undefined) set('location', text(b.location, 'location', 'Konum', 120));
  if (b.vendor_id !== undefined) set('vendor_id', id(b.vendor_id, 'vendor_id', 'Firma'));
  if (b.serial_no !== undefined) set('serial_no', text(b.serial_no, 'serial_no', 'Seri no', 60));
  if (b.installed_on !== undefined) set('installed_on', isoDate(b.installed_on, 'installed_on', 'Kurulum tarihi'));
  if (b.note !== undefined) set('note', text(b.note, 'note', 'Not', 1000));
  if (!create && b.is_active !== undefined) set('is_active', bool(b.is_active, 'is_active', 'Durum'));
  return out;
}

async function assertVendor(db, siteCode, vendorId) {
  if (vendorId === null || vendorId === undefined) return;
  const r = await db.query(`SELECT 1 FROM contract_vendors WHERE id = $1 AND site_code = $2`, [vendorId, siteCode]);
  if (!r.rows[0]) throw invalid('vendor_id', 'Firma bu sitede bulunamadı.');
}

export async function createEquipment({ siteCode, actor, access, body }) {
  const input = parseItem(body, { create: true });
  await assertVendor(pool, siteCode, input.vendor_id);
  const count = await pool.query(`SELECT COUNT(*)::INTEGER AS n FROM equipment_items WHERE site_code = $1`, [siteCode]);
  if (Number(count.rows[0].n) >= LIMITS.items) throw new PlatformError(409, 'LIMIT_REACHED', `Bir sitede en fazla ${LIMITS.items} ekipman kaydedilebilir.`, { limit: LIMITS.items });
  const r = await pool.query(
    `INSERT INTO equipment_items (site_code, kind, name, location, vendor_id, serial_no, installed_on, note, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7::DATE, $8, $9) RETURNING id`,
    [siteCode, input.kind, input.name, input.location ?? null, input.vendor_id ?? null, input.serial_no ?? null, input.installed_on ?? null, input.note ?? null, userOf(access)],
  );
  const equipmentId = Number(r.rows[0].id);
  await audit(actor, 'equipment.created', siteCode, 'equipment', equipmentId, { kind: input.kind });
  return { equipment: await loadItem(siteCode, equipmentId) };
}

async function loadItem(siteCode, equipmentId) {
  const r = await pool.query(`SELECT ${ITEM_COLS} FROM equipment_items i WHERE i.id = $1 AND i.site_code = $2`, [equipmentId, siteCode]);
  if (!r.rows[0]) throw notFound('Ekipman');
  return mapItem(r.rows[0]);
}

export async function updateEquipment({ siteCode, rawId, actor, body }) {
  const equipmentId = id(rawId, 'id', 'Ekipman', { required: true });
  const input = parseItem(body, { create: false });
  await loadItem(siteCode, equipmentId);
  if (input.vendor_id !== undefined) await assertVendor(pool, siteCode, input.vendor_id);
  const keys = Object.keys(input);
  if (keys.length > 0) {
    const cast = { installed_on: '::DATE' };
    const sets = keys.map((k, i) => `${k} = $${i + 3}${cast[k] ?? ''}`).join(', ');
    await pool.query(`UPDATE equipment_items SET ${sets}, updated_at = NOW() WHERE id = $1 AND site_code = $2`, [equipmentId, siteCode, ...keys.map((k) => input[k])]);
    await audit(actor, 'equipment.updated', siteCode, 'equipment', equipmentId, { fields: keys });
  }
  return { equipment: await loadItem(siteCode, equipmentId) };
}

function mapPlan(r) {
  return {
    id: Number(r.id),
    equipment_id: Number(r.equipment_id),
    title: r.title,
    interval_months: r.interval_months,
    legal: r.legal,
    next_due: r.next_due,
    last_done: r.last_done,
    is_active: r.is_active,
    days_left: r.days_left === undefined || r.days_left === null ? undefined : Number(r.days_left),
  };
}

const PLAN_COLS = `p.id, p.equipment_id, p.title, p.interval_months, p.legal, to_char(p.next_due, 'YYYY-MM-DD') AS next_due, to_char(p.last_done, 'YYYY-MM-DD') AS last_done, p.is_active`;

function mapLog(r) {
  return {
    id: Number(r.id),
    equipment_id: Number(r.equipment_id),
    plan_id: r.plan_id === null ? null : Number(r.plan_id),
    done_on: r.done_on,
    vendor_name: r.vendor_name,
    cost_kurus: r.cost_kurus === null ? null : Number(r.cost_kurus),
    expense_id: r.expense_id === null ? null : Number(r.expense_id),
    note: r.note,
    created_at: r.created_at,
  };
}

export async function getEquipment(siteCode, rawId) {
  const equipmentId = id(rawId, 'id', 'Ekipman', { required: true });
  const equipment = await loadItem(siteCode, equipmentId);
  const today = todayIstanbul();
  const [plans, logs, expenses] = await Promise.all([
    pool.query(`SELECT ${PLAN_COLS}, (p.next_due - $2::DATE) AS days_left FROM equipment_plans p WHERE p.equipment_id = $1 ORDER BY p.is_active DESC, p.next_due, p.id`, [equipmentId, today]),
    pool.query(
      `SELECT l.id, l.equipment_id, l.plan_id, to_char(l.done_on, 'YYYY-MM-DD') AS done_on, l.vendor_name, l.cost_kurus, l.expense_id, l.note, l.created_at
         FROM equipment_maintenance_logs l WHERE l.equipment_id = $1 AND l.site_code = $2 ORDER BY l.done_on DESC, l.id DESC LIMIT 100`,
      [equipmentId, siteCode],
    ),
    pool.query(`SELECT expense_id FROM equipment_expense_links WHERE equipment_id = $1 AND site_code = $2 ORDER BY expense_id DESC LIMIT 100`, [equipmentId, siteCode]),
  ]);
  return { equipment, plans: plans.rows.map(mapPlan), logs: logs.rows.map(mapLog), expense_ids: expenses.rows.map((x) => Number(x.expense_id)) };
}

// --- Bakim plani ----------------------------------------------------------------------------------------------------

export async function createPlan({ siteCode, rawId, actor, body }) {
  const equipmentId = id(rawId, 'id', 'Ekipman', { required: true });
  const b = bodyOf(body);
  const title = text(b.title, 'title', 'Plan başlığı', 120, { required: true });
  const months = interval(b.interval_months, { required: true });
  const legal = bool(b.legal, 'legal', 'Yasal kontrol') ?? false;
  const nextDue = isoDate(b.next_due, 'next_due', 'İlk bakım tarihi', { required: true });
  await loadItem(siteCode, equipmentId);
  const count = await pool.query(`SELECT COUNT(*)::INTEGER AS n FROM equipment_plans WHERE equipment_id = $1`, [equipmentId]);
  if (Number(count.rows[0].n) >= LIMITS.plansPerItem) throw new PlatformError(409, 'LIMIT_REACHED', 'Bir ekipmana en çok 30 plan eklenebilir.', { limit: LIMITS.plansPerItem });
  const r = await pool.query(
    `INSERT INTO equipment_plans (site_code, equipment_id, title, interval_months, legal, next_due) VALUES ($1, $2, $3, $4, $5, $6::DATE) RETURNING id`,
    [siteCode, equipmentId, title, months, legal, nextDue],
  );
  const planId = Number(r.rows[0].id);
  await audit(actor, 'equipment.plan_created', siteCode, 'equipment_plan', planId, { equipment_id: equipmentId, interval_months: months, legal });
  return { plan: await loadPlan(siteCode, planId) };
}

async function loadPlan(siteCode, planId) {
  const r = await pool.query(`SELECT ${PLAN_COLS} FROM equipment_plans p WHERE p.id = $1 AND p.site_code = $2`, [planId, siteCode]);
  if (!r.rows[0]) throw notFound('Plan');
  return mapPlan(r.rows[0]);
}

export async function updatePlan({ siteCode, rawPlanId, actor, body }) {
  const planId = id(rawPlanId, 'planId', 'Plan', { required: true });
  const b = bodyOf(body);
  const patch = {};
  if (b.title !== undefined) patch.title = text(b.title, 'title', 'Plan başlığı', 120, { required: true });
  if (b.interval_months !== undefined) patch.interval_months = interval(b.interval_months, { required: true });
  if (b.legal !== undefined) patch.legal = bool(b.legal, 'legal', 'Yasal kontrol');
  if (b.next_due !== undefined) patch.next_due = isoDate(b.next_due, 'next_due', 'Sonraki bakım tarihi', { required: true });
  if (b.is_active !== undefined) patch.is_active = bool(b.is_active, 'is_active', 'Durum');
  await loadPlan(siteCode, planId);
  const keys = Object.keys(patch);
  if (keys.length > 0) {
    const sets = keys.map((k, i) => `${k} = $${i + 3}${k === 'next_due' ? '::DATE' : ''}`).join(', ');
    await pool.query(`UPDATE equipment_plans SET ${sets}, updated_at = NOW() WHERE id = $1 AND site_code = $2`, [planId, siteCode, ...keys.map((k) => patch[k])]);
    await audit(actor, 'equipment.plan_updated', siteCode, 'equipment_plan', planId, { fields: keys });
  }
  return { plan: await loadPlan(siteCode, planId) };
}

/** Yaklasan / gecikmis bakimlar (yasal kontroller dahil). days: bakim tarihine kalan en cok gun (varsayilan 60). Hatirlatma bildirimi "Yakinda". */
export async function dueList(siteCode, query = {}) {
  const days = Math.min(Math.max(Number.parseInt(query.days ?? '60', 10) || 60, 1), 400);
  const today = todayIstanbul();
  const r = await pool.query(
    `SELECT ${PLAN_COLS}, (p.next_due - $2::DATE) AS days_left, i.name AS equipment_name, i.kind AS equipment_kind
       FROM equipment_plans p INNER JOIN equipment_items i ON i.id = p.equipment_id
      WHERE p.site_code = $1 AND p.is_active AND i.is_active AND p.next_due <= ($2::DATE + $3::INTEGER)
      ORDER BY p.next_due, p.id LIMIT 300`,
    [siteCode, today, days],
  );
  return {
    items: r.rows.map((x) => ({ ...mapPlan(x), equipment_name: x.equipment_name, equipment_kind: x.equipment_kind, state: Number(x.days_left) < 0 ? 'overdue' : 'soon' })),
    days,
  };
}

// --- Bakim kaydi (yalniz ekleme) -----------------------------------------------------------------------------------

async function assertExpenseInSite(db, siteCode, expenseId) {
  const r = await db.query(`SELECT 1 FROM expenses WHERE id = $1 AND site_code = $2`, [expenseId, siteCode]);
  if (!r.rows[0]) throw invalid('expense_id', 'Gider bu sitede bulunamadı.');
}

async function linkExpenseTx(client, siteCode, equipmentId, expenseId, userCode) {
  await assertExpenseInSite(client, siteCode, expenseId);
  const ins = await client.query(
    `INSERT INTO equipment_expense_links (expense_id, site_code, equipment_id, created_by) VALUES ($1, $2, $3, $4) ON CONFLICT (expense_id) DO NOTHING RETURNING expense_id`,
    [expenseId, siteCode, equipmentId, userCode],
  );
  if (!ins.rows[0]) {
    const cur = await client.query(`SELECT equipment_id FROM equipment_expense_links WHERE expense_id = $1 AND site_code = $2`, [expenseId, siteCode]);
    if (Number(cur.rows[0]?.equipment_id) !== equipmentId) throw new PlatformError(409, 'EXPENSE_ALREADY_LINKED', 'Bu gider başka bir ekipmana bağlı.');
  }
}

export async function createLog({ siteCode, rawId, actor, access, body }) {
  const equipmentId = id(rawId, 'id', 'Ekipman', { required: true });
  const b = bodyOf(body);
  const doneOn = isoDate(b.done_on, 'done_on', 'Bakım tarihi', { required: true });
  if (doneOn > todayIstanbul()) throw invalid('done_on', 'Bakım tarihi gelecek bir tarih olamaz.');
  const planId = id(b.plan_id, 'plan_id', 'Plan');
  const vendorName = text(b.vendor_name, 'vendor_name', 'Firma', 120);
  const cost = kurus(b.cost_kurus, 'cost_kurus', 'Maliyet');
  const expenseId = id(b.expense_id, 'expense_id', 'Gider');
  const note = text(b.note, 'note', 'Not', 1000);
  await loadItem(siteCode, equipmentId);
  const client = await pool.connect();
  let logId;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`equipment:${siteCode}`]);
    let plan = null;
    if (planId !== null) {
      const p = await client.query(`SELECT interval_months, to_char(last_done, 'YYYY-MM-DD') AS last_done FROM equipment_plans WHERE id = $1 AND equipment_id = $2 AND site_code = $3 FOR UPDATE`, [planId, equipmentId, siteCode]);
      if (!p.rows[0]) throw invalid('plan_id', 'Plan bu ekipmanda bulunamadı.');
      plan = p.rows[0];
    }
    const ins = await client.query(
      `INSERT INTO equipment_maintenance_logs (site_code, equipment_id, plan_id, done_on, vendor_name, cost_kurus, expense_id, note, created_by)
       VALUES ($1, $2, $3, $4::DATE, $5, $6, $7, $8, $9) RETURNING id`,
      [siteCode, equipmentId, planId, doneOn, vendorName, cost, expenseId, note, userOf(access)],
    );
    logId = Number(ins.rows[0].id);
    if (plan && (plan.last_done === null || doneOn >= plan.last_done)) {
      await client.query(
        `UPDATE equipment_plans SET last_done = $2::DATE, next_due = ($2::DATE + make_interval(months => interval_months))::DATE, updated_at = NOW() WHERE id = $1`,
        [planId, doneOn],
      );
    }
    if (expenseId !== null) await linkExpenseTx(client, siteCode, equipmentId, expenseId, userOf(access));
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
  await audit(actor, 'equipment.maintenance_logged', siteCode, 'equipment', equipmentId, { log_id: logId, plan_id: planId, has_cost: cost !== null });
  return getEquipment(siteCode, equipmentId);
}

// --- Gider baglantisi ve 2E kirilimi ---------------------------------------------------------------------------------

export async function linkExpense({ siteCode, rawId, actor, access, body }) {
  const equipmentId = id(rawId, 'id', 'Ekipman', { required: true });
  const expenseId = id(bodyOf(body).expense_id, 'expense_id', 'Gider', { required: true });
  await loadItem(siteCode, equipmentId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await linkExpenseTx(client, siteCode, equipmentId, expenseId, userOf(access));
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
  await audit(actor, 'equipment.expense_linked', siteCode, 'equipment', equipmentId, { expense_id: expenseId });
  return getEquipment(siteCode, equipmentId);
}

export async function unlinkExpense({ siteCode, rawId, rawExpenseId, actor }) {
  const equipmentId = id(rawId, 'id', 'Ekipman', { required: true });
  const expenseId = id(rawExpenseId, 'expenseId', 'Gider', { required: true });
  const r = await pool.query(`DELETE FROM equipment_expense_links WHERE expense_id = $1 AND equipment_id = $2 AND site_code = $3 RETURNING expense_id`, [expenseId, equipmentId, siteCode]);
  if (!r.rows[0]) throw notFound('Bağlantı');
  await audit(actor, 'equipment.expense_unlinked', siteCode, 'equipment', equipmentId, { expense_id: expenseId });
  return getEquipment(siteCode, equipmentId);
}

const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;

/** Net gider (gider - iptal) ekipman bazinda; aylik gelir-gider / gider analiziyle ayni birlesim. from / to: YYYY-MM (varsayilan son 12 ay). */
export async function equipmentBreakdown(siteCode, query = {}, db = pool) {
  const now = todayIstanbul();
  const toMonth = query.to === undefined || query.to === '' ? now.slice(0, 7) : query.to;
  let fromMonth = query.from;
  if (fromMonth === undefined || fromMonth === '') {
    const [y, m] = toMonth.split('-').map(Number);
    const total = y * 12 + (m - 1) - 11;
    fromMonth = `${String(Math.floor(total / 12)).padStart(4, '0')}-${String((total % 12) + 1).padStart(2, '0')}`;
  }
  if (!MONTH.test(String(toMonth)) || !MONTH.test(String(fromMonth)) || fromMonth > toMonth) {
    throw new PlatformError(400, 'INVALID_QUERY', 'Dönem geçersiz (from / to: YYYY-AA, from <= to).');
  }
  const r = await db.query(
    `
      WITH net AS (
        SELECT e.id AS expense_id, e.amount_minor AS amount FROM expenses e
         WHERE e.site_code = $1 AND e.period >= $2::DATE AND e.period < ($3::DATE + INTERVAL '1 month')
        UNION ALL
        SELECT v.expense_id, -e.amount_minor FROM expense_voids v INNER JOIN expenses e ON e.id = v.expense_id
         WHERE v.site_code = $1 AND v.period >= $2::DATE AND v.period < ($3::DATE + INTERVAL '1 month')
      )
      SELECT l.equipment_id, i.name, i.kind, SUM(n.amount)::TEXT AS total
        FROM net n INNER JOIN equipment_expense_links l ON l.expense_id = n.expense_id AND l.site_code = $1
        INNER JOIN equipment_items i ON i.id = l.equipment_id
       GROUP BY l.equipment_id, i.name, i.kind ORDER BY SUM(n.amount) DESC, i.name
    `,
    [siteCode, `${fromMonth}-01`, `${toMonth}-01`],
  );
  const all = await db.query(
    `SELECT (COALESCE((SELECT SUM(e.amount_minor) FROM expenses e WHERE e.site_code = $1 AND e.period >= $2::DATE AND e.period < ($3::DATE + INTERVAL '1 month')), 0)
           - COALESCE((SELECT SUM(e.amount_minor) FROM expense_voids v INNER JOIN expenses e ON e.id = v.expense_id WHERE v.site_code = $1 AND v.period >= $2::DATE AND v.period < ($3::DATE + INTERVAL '1 month')), 0))::TEXT AS total`,
    [siteCode, `${fromMonth}-01`, `${toMonth}-01`],
  );
  const items = r.rows.map((x) => ({ equipment_id: Number(x.equipment_id), name: x.name, kind: x.kind, expense_minor: Number(x.total) }));
  const linked = items.reduce((s, x) => s + x.expense_minor, 0);
  const total = Number(all.rows[0]?.total ?? 0);
  return { from: fromMonth, to: toMonth, items, linked_minor: linked, unlinked_minor: total - linked, total_minor: total };
}

// --- Teklifler ------------------------------------------------------------------------------------------------------

const QUOTE_COLS = `q.id, q.topic, q.vendor_name, q.amount_kurus, to_char(q.valid_until, 'YYYY-MM-DD') AS valid_until, q.document_note, q.equipment_id, q.status, q.accepted_as, q.expense_id, q.contract_id, q.decided_at, q.created_at`;

function mapQuote(r, today) {
  const validUntil = r.valid_until;
  return {
    id: Number(r.id),
    topic: r.topic,
    vendor_name: r.vendor_name,
    amount_kurus: Number(r.amount_kurus),
    valid_until: validUntil,
    expired: r.status === 'open' && validUntil !== null && validUntil < today,
    document_note: r.document_note,
    equipment_id: r.equipment_id === null ? null : Number(r.equipment_id),
    status: r.status,
    accepted_as: r.accepted_as,
    expense_id: r.expense_id === null ? null : Number(r.expense_id),
    contract_id: r.contract_id === null ? null : Number(r.contract_id),
    decided_at: r.decided_at,
    created_at: r.created_at,
  };
}

export async function listQuotes(siteCode, query = {}) {
  const status = ['open', 'accepted', 'rejected'].includes(query.status) ? query.status : null;
  const topic = typeof query.topic === 'string' && query.topic.trim() !== '' ? clean(query.topic).slice(0, 160) : null;
  const r = await pool.query(
    `SELECT ${QUOTE_COLS} FROM equipment_quotes q
      WHERE q.site_code = $1 AND ($2::TEXT IS NULL OR q.status = $2) AND ($3::TEXT IS NULL OR lower(q.topic) = lower($3))
      ORDER BY lower(q.topic), q.amount_kurus, q.id LIMIT 500`,
    [siteCode, status, topic],
  );
  const today = todayIstanbul();
  const items = r.rows.map((x) => mapQuote(x, today));
  // Karsilastirma: ayni konudaki acik ve suresi dolmamis tekliflerden en dusuk tutar isaretlenir.
  const lowest = new Map();
  for (const q of items) {
    if (q.status !== 'open' || q.expired) continue;
    const key = q.topic.toLowerCase();
    if (!lowest.has(key) || q.amount_kurus < lowest.get(key)) lowest.set(key, q.amount_kurus);
  }
  return { items: items.map((q) => ({ ...q, lowest: q.status === 'open' && !q.expired && lowest.get(q.topic.toLowerCase()) === q.amount_kurus })) };
}

export async function createQuote({ siteCode, actor, access, body }) {
  const b = bodyOf(body);
  const topic = text(b.topic, 'topic', 'Konu', 160, { required: true });
  const vendorName = text(b.vendor_name, 'vendor_name', 'Firma', 120, { required: true });
  const amount = kurus(b.amount_kurus, 'amount_kurus', 'Tutar', { required: true, min: 1 });
  const validUntil = isoDate(b.valid_until, 'valid_until', 'Geçerlilik tarihi');
  const doc = text(b.document_note, 'document_note', 'Belge notu', 300);
  const equipmentId = id(b.equipment_id, 'equipment_id', 'Ekipman');
  if (equipmentId !== null) await loadItem(siteCode, equipmentId);
  const count = await pool.query(`SELECT COUNT(*)::INTEGER AS n FROM equipment_quotes WHERE site_code = $1`, [siteCode]);
  if (Number(count.rows[0].n) >= LIMITS.quotes) throw new PlatformError(409, 'LIMIT_REACHED', 'Bir sitede en fazla 3000 teklif kaydedilebilir.', { limit: LIMITS.quotes });
  const r = await pool.query(
    `INSERT INTO equipment_quotes (site_code, topic, vendor_name, amount_kurus, valid_until, document_note, equipment_id, created_by)
     VALUES ($1, $2, $3, $4, $5::DATE, $6, $7, $8) RETURNING id`,
    [siteCode, topic, vendorName, amount, validUntil, doc, equipmentId, userOf(access)],
  );
  const quoteId = Number(r.rows[0].id);
  await audit(actor, 'quote.created', siteCode, 'equipment_quote', quoteId, { topic });
  return { quote: await loadQuote(siteCode, quoteId) };
}

async function loadQuote(siteCode, quoteId) {
  const r = await pool.query(`SELECT ${QUOTE_COLS} FROM equipment_quotes q WHERE q.id = $1 AND q.site_code = $2`, [quoteId, siteCode]);
  if (!r.rows[0]) throw notFound('Teklif');
  return mapQuote(r.rows[0], todayIstanbul());
}

export async function rejectQuote({ siteCode, rawId, actor }) {
  const quoteId = id(rawId, 'id', 'Teklif', { required: true });
  const r = await pool.query(`UPDATE equipment_quotes SET status = 'rejected', decided_at = NOW() WHERE id = $1 AND site_code = $2 AND status = 'open' RETURNING id`, [quoteId, siteCode]);
  if (!r.rows[0]) {
    await loadQuote(siteCode, quoteId);
    throw new PlatformError(409, 'QUOTE_NOT_OPEN', 'Teklif zaten karara bağlanmış.');
  }
  await audit(actor, 'quote.rejected', siteCode, 'equipment_quote', quoteId, {});
  return { quote: await loadQuote(siteCode, quoteId) };
}

const kurusToAmount = (k) => `${Math.floor(k / 100)}.${String(k % 100).padStart(2, '0')}`;

/**
 * Kabul: teklif gidere (as = expense) ya da sozlesmeye (as = contract) donusur. Teklif once atomik olarak "accepted" alinir (cift kabul engeli);
 * olusturma basarisiz olursa "open"a geri alinir. Gider idempotency_key = quote-<id> oldugundan tekrar denemede cift gider yazilmaz.
 * Ayni konudaki diger acik teklifler reddedilir.
 */
export async function acceptQuote({ siteCode, rawId, actor, access, body }) {
  const quoteId = id(rawId, 'id', 'Teklif', { required: true });
  const b = bodyOf(body);
  const as = b.as;
  if (as !== 'expense' && as !== 'contract') throw invalid('as', 'as: expense ya da contract olmalı.');
  const quote = await loadQuote(siteCode, quoteId);
  if (quote.status !== 'open') throw new PlatformError(409, 'QUOTE_NOT_OPEN', 'Teklif zaten karara bağlanmış.');
  if (quote.expired) throw new PlatformError(409, 'QUOTE_EXPIRED', 'Teklifin geçerlilik süresi dolmuş.');
  const targetModule = as === 'expense' ? 'finance' : 'contracts';
  if (!(await isModuleEnabled(siteCode, targetModule))) {
    throw new PlatformError(403, 'MODULE_DISABLED', as === 'expense' ? 'Finans modülü kapalı.' : 'Firma ve Sözleşme Takibi modülü kapalı.', { module: targetModule });
  }
  const claim = await pool.query(
    `UPDATE equipment_quotes SET status = 'accepted', accepted_as = $3, decided_at = NOW() WHERE id = $1 AND site_code = $2 AND status = 'open' RETURNING id`,
    [quoteId, siteCode, as],
  );
  if (!claim.rows[0]) throw new PlatformError(409, 'QUOTE_NOT_OPEN', 'Teklif zaten karara bağlanmış.');
  try {
    let expenseId = null;
    let contractId = null;
    if (as === 'expense') {
      const e = bodyOf(b.expense ?? {});
      const created = await createExpense({
        siteCode,
        actor,
        body: {
          category_id: e.category_id,
          supplier_id: e.supplier_id,
          account_id: e.account_id,
          description: `Teklif: ${quote.topic} - ${quote.vendor_name}`.slice(0, 200),
          amount_minor: quote.amount_kurus,
          expense_date: e.expense_date ?? todayIstanbul(),
          document_kind: e.document_kind,
          document_no: e.document_no,
          idempotency_key: `quote-${quoteId}`,
        },
      });
      expenseId = Number(created.expense.id);
      if (quote.equipment_id !== null) {
        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          await linkExpenseTx(client, siteCode, quote.equipment_id, expenseId, userOf(access));
          await client.query('COMMIT');
        } catch (error) {
          await client.query('ROLLBACK').catch(() => {});
          throw error;
        } finally {
          client.release();
        }
      }
    } else {
      const c = bodyOf(b.contract ?? {});
      const created = await createContract({
        siteCode,
        actor,
        access: { canWrite: true, userCode: access.userCode },
        body: {
          vendor_id: c.vendor_id,
          title: c.title ?? `${quote.topic} (${quote.vendor_name})`.slice(0, 160),
          start_date: c.start_date,
          end_date: c.end_date,
          period: c.period,
          auto_renew: c.auto_renew,
          note: c.note,
          amount: kurusToAmount(quote.amount_kurus),
        },
      });
      contractId = Number(created.contract.id);
    }
    await pool.query(`UPDATE equipment_quotes SET expense_id = $3, contract_id = $4 WHERE id = $1 AND site_code = $2`, [quoteId, siteCode, expenseId, contractId]);
    await pool.query(
      `UPDATE equipment_quotes SET status = 'rejected', decided_at = NOW() WHERE site_code = $1 AND status = 'open' AND id <> $2 AND lower(topic) = lower($3)`,
      [siteCode, quoteId, quote.topic],
    );
    await audit(actor, 'quote.accepted', siteCode, 'equipment_quote', quoteId, { as, expense_id: expenseId, contract_id: contractId });
  } catch (error) {
    await pool.query(`UPDATE equipment_quotes SET status = 'open', accepted_as = NULL, decided_at = NULL WHERE id = $1 AND site_code = $2 AND expense_id IS NULL AND contract_id IS NULL`, [quoteId, siteCode]).catch(() => {});
    throw error;
  }
  return { quote: await loadQuote(siteCode, quoteId) };
}

/** 2E gider analizine ekipman kirilimi ekler (modul aciksa; analiz penceresiyle ayni donem). Hata analizi bozmaz. */
export async function withEquipmentBreakdown(siteCode, report) {
  try {
    if (!report || typeof report.to !== 'string' || !MONTH.test(report.to) || !(await isModuleEnabled(siteCode, EQUIPMENT_MODULE))) return report;
    const [y, m] = report.to.split('-').map(Number);
    const total = y * 12 + (m - 1) - ((Number(report.window) || 1) - 1);
    const from = `${String(Math.floor(total / 12)).padStart(4, '0')}-${String((total % 12) + 1).padStart(2, '0')}`;
    return { ...report, equipment_breakdown: await equipmentBreakdown(siteCode, { from, to: report.to }) };
  } catch {
    return report;
  }
}
