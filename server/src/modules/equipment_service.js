// Ekipman, bakim ve teklif is mantigi. Sozlesme: docs/PLATFORM_EKIPMAN.md.
// Para tamsayi kurus. Bakim kaydi yalniz eklemelidir (duzeltme yeni kayitla). Gider satiri degismez: ekipman baglantisi yan tablodadir (equipment_expense_links).
// Tahsilat/defter yazilmaz; kabul edilen teklif gidere ya da sozlesmeye YALNIZ createExpense / createContract ile donusur.
// Teklifler (098 + 099): karsilastirma alanlari (teslim suresi, kapsam / not, KDV esasi) ve K14 revizyon modeli: kabul edilmis (onayli) teklif yerinde DEGISMEZ
// (veritabani tetikleyicisi de reddeder); degisiklik, onceki surume baglanan YENI SURUM satiri olusturur (previous_id, revision_no, revision_reason).
// Onaysiz (acik) teklif yerinde duzenlenir; her duzenleme denetim kaydina eski / yeni tutarla yazilir.

import { createHash, randomBytes } from 'node:crypto';
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
export const LIMITS = Object.freeze({ items: 1000, plansPerItem: 30, quotes: 3000, revisionsPerQuote: 50 });
export const MAX_BODY_BYTES = 16384;
const MAX_KURUS = 1_000_000_000_000;
export const MAX_DELIVERY_DAYS = 1095;
export const QUOTE_NOTE_MAX = 500;

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

/** Teslim suresi (gun): tam sayi 0..1095; bos / null = belirtilmedi. */
export function deliveryDays(value, field = 'delivery_days') {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > MAX_DELIVERY_DAYS) {
    throw invalid(field, `Teslim süresi 0 ile ${MAX_DELIVERY_DAYS} gün arasında tam sayı olmalı.`);
  }
  return value;
}

/** KDV esasi: true = KDV dahil, false = KDV haric, null = belirtilmedi; undefined = alan gonderilmedi. */
export function vatFlag(value, field = 'vat_included') {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'boolean') throw invalid(field, 'KDV durumu dahil, hariç ya da boş olmalı.');
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

const QUOTE_COLS = `q.id, q.topic, q.vendor_name, q.amount_kurus, to_char(q.valid_until, 'YYYY-MM-DD') AS valid_until, q.document_note, q.equipment_id, q.status, q.accepted_as, q.expense_id, q.contract_id, q.decided_at, q.created_at,
  q.delivery_days, q.note, q.vat_included, q.revision_no, q.previous_id, q.revision_reason`;

const nullableNumber = (v) => (v === null || v === undefined ? null : Number(v));

export function mapQuote(r, today) {
  const validUntil = r.valid_until ?? null;
  return {
    id: Number(r.id),
    topic: r.topic,
    vendor_name: r.vendor_name,
    amount_kurus: Number(r.amount_kurus),
    valid_until: validUntil,
    expired: r.status === 'open' && validUntil !== null && validUntil < today,
    document_note: r.document_note ?? null,
    equipment_id: nullableNumber(r.equipment_id),
    status: r.status,
    accepted_as: r.accepted_as ?? null,
    expense_id: nullableNumber(r.expense_id),
    contract_id: nullableNumber(r.contract_id),
    decided_at: r.decided_at ?? null,
    created_at: r.created_at,
    delivery_days: nullableNumber(r.delivery_days),
    note: r.note ?? null,
    vat_included: r.vat_included === null || r.vat_included === undefined ? null : r.vat_included === true,
    revision_no: r.revision_no === null || r.revision_no === undefined ? 1 : Number(r.revision_no),
    previous_id: nullableNumber(r.previous_id),
    revision_reason: r.revision_reason ?? null,
  };
}

/**
 * Teklifin degisebilen alanlari (tutar, gecerlilik, teslim suresi, kapsam / not, KDV esasi, belge notu). partial=false (olusturma): tutar zorunlu, gonderilmeyen
 * alanlar `undefined` kalir. partial=true (duzenleme / revizyon): yalniz gonderilen alanlar doner; null / "" = temizle (tutar temizlenemez).
 */
export function parseQuoteFields(body, { partial = false } = {}) {
  const b = bodyOf(body);
  const out = {};
  const has = (key) => b[key] !== undefined;
  if (!partial || has('amount_kurus')) out.amount_kurus = kurus(b.amount_kurus, 'amount_kurus', 'Tutar', { required: true, min: 1 });
  if (has('valid_until')) out.valid_until = isoDate(b.valid_until, 'valid_until', 'Geçerlilik tarihi');
  if (has('delivery_days')) out.delivery_days = deliveryDays(b.delivery_days);
  if (has('note')) out.note = text(b.note, 'note', 'Kapsam / not', QUOTE_NOTE_MAX);
  if (has('vat_included')) out.vat_included = vatFlag(b.vat_included);
  if (has('document_note')) out.document_note = text(b.document_note, 'document_note', 'Belge notu', 300);
  return out;
}

/** Karsilastirmaya giren alanlarin karsilastirma anahtarlari: eski / yeni deger farki (null ve undefined ayni sayilmaz: undefined = gonderilmedi). */
const COMPARE_KEYS = Object.freeze(['amount_kurus', 'valid_until', 'delivery_days', 'note', 'vat_included', 'document_note']);

function changedKeys(patch, current) {
  return COMPARE_KEYS.filter((k) => patch[k] !== undefined && patch[k] !== current[k]);
}

const approvedRef = (q) => ({
  id: q.id,
  revision_no: q.revision_no,
  amount_kurus: q.amount_kurus,
  decided_at: q.decided_at,
  accepted_as: q.accepted_as,
  expense_id: q.expense_id,
  contract_id: q.contract_id,
});

/**
 * Surum zincirlerinden yalniz EN SON surumleri (baslari) dondurur: bir teklifin halefi varsa o satir listede gorunmez, gecmis `quoteHistory` ile okunur.
 * Her basa eklenir: version_count, approved_version (basin kendisi onayli degilse zincirdeki en yakin ONAYLI onceki surum; yoksa null), editable (acik teklif yerinde
 * duzenlenir), revisable (onayli son surum ya da onayli bir surumden turemis reddedilmis revizyon yeni surum alabilir).
 */
export function buildQuoteHeads(items) {
  const byId = new Map(items.map((q) => [q.id, q]));
  const hasSuccessor = new Set();
  for (const q of items) if (q.previous_id !== null) hasSuccessor.add(q.previous_id);
  return items
    .filter((q) => !hasSuccessor.has(q.id))
    .map((head) => {
      let approved = null;
      if (head.status !== 'accepted') {
        let cur = head.previous_id === null ? undefined : byId.get(head.previous_id);
        for (let guard = 0; cur && guard < 100; guard += 1) {
          if (cur.status === 'accepted') {
            approved = cur;
            break;
          }
          cur = cur.previous_id === null ? undefined : byId.get(cur.previous_id);
        }
      }
      return {
        ...head,
        version_count: head.revision_no,
        has_history: head.revision_no > 1,
        approved_version: approved ? approvedRef(approved) : null,
        editable: head.status === 'open',
        revisable: head.status === 'accepted' || (head.status === 'rejected' && head.revision_no > 1 && approved !== null),
      };
    });
}

const vatBasis = (q) => (q.vat_included === null ? 'unspecified' : q.vat_included ? 'included' : 'excluded');

/**
 * Karsilastirma isaretleri (yalniz ayni konudaki ACIK, suresi dolmamis, ilk surum teklifler; bekleyen revizyon rakip degil degisikliktir):
 *  - lowest: en dusuk tutar. Konudaki teklifler FARKLI KDV esasindaysa (dahil / haric / belirtilmedi karisik) tutarlar kiyaslanamaz: hicbiri isaretlenmez, basis_mixed = true.
 *  - fastest: en kisa teslim suresi (en az iki tekliften teslim suresi girilmisse).
 */
export function markComparison(items) {
  const groups = new Map();
  for (const q of items) {
    if (q.status !== 'open' || q.expired || q.revision_no > 1) continue;
    const key = q.topic.toLowerCase();
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(q);
  }
  const marks = new Map();
  for (const list of groups.values()) {
    const mixed = new Set(list.map(vatBasis)).size > 1;
    const min = Math.min(...list.map((q) => q.amount_kurus));
    const withDelivery = list.filter((q) => q.delivery_days !== null);
    const fastestDays = withDelivery.length >= 2 ? Math.min(...withDelivery.map((q) => q.delivery_days)) : null;
    for (const q of list) {
      marks.set(q.id, { lowest: !mixed && q.amount_kurus === min, fastest: fastestDays !== null && q.delivery_days === fastestDays, basis_mixed: mixed });
    }
  }
  return items.map((q) => ({ ...q, lowest: false, fastest: false, basis_mixed: false, ...(marks.get(q.id) ?? {}) }));
}

export async function listQuotes(siteCode, query = {}) {
  const status = ['open', 'accepted', 'rejected'].includes(query.status) ? query.status : null;
  const topic = typeof query.topic === 'string' && query.topic.trim() !== '' ? clean(query.topic).slice(0, 160) : null;
  const r = await pool.query(
    `SELECT ${QUOTE_COLS} FROM equipment_quotes q
      WHERE q.site_code = $1 AND ($2::TEXT IS NULL OR lower(q.topic) = lower($2))
      ORDER BY lower(q.topic), q.amount_kurus, q.id LIMIT 2000`,
    [siteCode, topic],
  );
  const today = todayIstanbul();
  // Surum zincirleri: listede yalniz en son surumler gorunur (onceki surumler `quotes/:id/history`); durum suzgeci son surume uygulanir.
  const heads = markComparison(buildQuoteHeads(r.rows.map((x) => mapQuote(x, today))));
  return { items: (status === null ? heads : heads.filter((q) => q.status === status)).slice(0, 500) };
}

export async function createQuote({ siteCode, actor, access, body }) {
  const b = bodyOf(body);
  const topic = text(b.topic, 'topic', 'Konu', 160, { required: true });
  const vendorName = text(b.vendor_name, 'vendor_name', 'Firma', 120, { required: true });
  const fields = parseQuoteFields(b);
  const equipmentId = id(b.equipment_id, 'equipment_id', 'Ekipman');
  if (equipmentId !== null) await loadItem(siteCode, equipmentId);
  const count = await pool.query(`SELECT COUNT(*)::INTEGER AS n FROM equipment_quotes WHERE site_code = $1`, [siteCode]);
  if (Number(count.rows[0].n) >= LIMITS.quotes) throw new PlatformError(409, 'LIMIT_REACHED', 'Bir sitede en fazla 3000 teklif kaydedilebilir.', { limit: LIMITS.quotes });
  const r = await pool.query(
    `INSERT INTO equipment_quotes (site_code, topic, vendor_name, amount_kurus, valid_until, document_note, equipment_id, created_by, delivery_days, note, vat_included)
     VALUES ($1, $2, $3, $4, $5::DATE, $6, $7, $8, $9, $10, $11) RETURNING id`,
    [
      siteCode,
      topic,
      vendorName,
      fields.amount_kurus,
      fields.valid_until ?? null,
      fields.document_note ?? null,
      equipmentId,
      userOf(access),
      fields.delivery_days ?? null,
      fields.note ?? null,
      fields.vat_included ?? null,
    ],
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

const quoteLocked = (status) =>
  new PlatformError(409, 'QUOTE_LOCKED', 'Karara bağlanmış teklif düzenlenemez. Onaylı teklifte değişiklik için revizyon oluşturun.', { status });

/** Denetim ayrintisi: degisen alan adlari + (tutar degistiyse) eski / yeni tutar. Serbest metin (kapsam, gerekce, not) gunluge YAZILMAZ. */
function changeDetails(keys, before, after) {
  const details = { fields: keys };
  if (keys.includes('amount_kurus')) {
    details.amount_before = before.amount_kurus;
    details.amount_after = after.amount_kurus;
  }
  return details;
}

/**
 * Onaysiz (acik) teklifi YERINDE duzenler (PATCH quotes/:id). Karara baglanmis (kabul / red) teklif duzenlenemez: 409 QUOTE_LOCKED; onayli teklifte degisiklik
 * `reviseQuote` ile yeni surum olarak yapilir. Bekleyen revizyonda konu, firma ve ekipman degismez (surum zinciri tutarli kalir). Degisiklik yoksa yazilmaz.
 */
export async function updateQuote({ siteCode, rawId, actor, body }) {
  const quoteId = id(rawId, 'id', 'Teklif', { required: true });
  const b = bodyOf(body);
  const patch = parseQuoteFields(b, { partial: true });
  if (b.topic !== undefined) patch.topic = text(b.topic, 'topic', 'Konu', 160, { required: true });
  if (b.vendor_name !== undefined) patch.vendor_name = text(b.vendor_name, 'vendor_name', 'Firma', 120, { required: true });
  if (b.equipment_id !== undefined) patch.equipment_id = id(b.equipment_id, 'equipment_id', 'Ekipman');
  const current = await loadQuote(siteCode, quoteId);
  if (current.status !== 'open') throw quoteLocked(current.status);
  const keys = [...COMPARE_KEYS, 'topic', 'vendor_name', 'equipment_id'].filter((k) => patch[k] !== undefined && patch[k] !== current[k]);
  if (current.revision_no > 1 && keys.some((k) => k === 'topic' || k === 'vendor_name' || k === 'equipment_id')) {
    throw invalid('topic', 'Revizyonda konu, firma ve ekipman değişmez.');
  }
  if (keys.includes('equipment_id') && patch.equipment_id !== null) await loadItem(siteCode, patch.equipment_id);
  if (keys.length === 0) return { quote: current };
  const sets = keys.map((k, i) => `${k} = $${i + 3}${k === 'valid_until' ? '::DATE' : ''}`).join(', ');
  const r = await pool.query(`UPDATE equipment_quotes SET ${sets} WHERE id = $1 AND site_code = $2 AND status = 'open' RETURNING id`, [quoteId, siteCode, ...keys.map((k) => patch[k])]);
  if (!r.rows[0]) {
    // Aradan biri kabul / red etti: guncel durumu okuyup kilitli yanit ver.
    const latest = await loadQuote(siteCode, quoteId);
    throw quoteLocked(latest.status);
  }
  await audit(actor, 'quote.updated', siteCode, 'equipment_quote', quoteId, changeDetails(keys, current, patch));
  return { quote: await loadQuote(siteCode, quoteId) };
}

/**
 * K14: onayli teklifte degisiklik = YENI SURUM (POST quotes/:id/revise). Onayli satir DEGISMEZ; yeni satir `previous_id` ile bir onceki surume baglanir, `revision_no`
 * artar, gerekce (`reason`, zorunlu) saklanir. Konu, firma ve ekipman onceki surumden kopyalanir; gonderilmeyen alanlar da kopyalanir. Yeni surum ACIKTIR:
 * kabul / red icin yeniden yonetici karari gerekir; reddedilirse onceki onay gecerli kalir. Revize edilebilir olanlar: onayli son surum ve onayli bir surumden
 * turemis reddedilmis son revizyon. Sunucu: site basina advisory kilit + FOR UPDATE + benzersiz `previous_id` dizini => es zamanli cift revizyon 409 QUOTE_NOT_LATEST.
 */
export async function reviseQuote({ siteCode, rawId, actor, access, body }) {
  const baseId = id(rawId, 'id', 'Teklif', { required: true });
  const b = bodyOf(body);
  const reason = text(b.reason, 'reason', 'Değişiklik gerekçesi', 300, { required: true });
  if (reason.length < 3) throw invalid('reason', 'Değişiklik gerekçesi en az 3 karakter olmalı.');
  const patch = parseQuoteFields(b, { partial: true });
  const client = await pool.connect();
  let newId;
  let base;
  let keys;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`equipment_quotes:${siteCode}`]);
    const found = await client.query(`SELECT ${QUOTE_COLS} FROM equipment_quotes q WHERE q.id = $1 AND q.site_code = $2 FOR UPDATE`, [baseId, siteCode]);
    if (!found.rows[0]) throw notFound('Teklif');
    base = mapQuote(found.rows[0], todayIstanbul());
    const successor = await client.query(`SELECT id FROM equipment_quotes WHERE previous_id = $1 AND site_code = $2 LIMIT 1`, [baseId, siteCode]);
    if (successor.rows[0]) {
      throw new PlatformError(409, 'QUOTE_NOT_LATEST', 'Bu teklifin daha yeni bir sürümü var; en son sürümü revize edin.', { latest_hint_id: Number(successor.rows[0].id) });
    }
    if (base.status === 'open') {
      throw new PlatformError(409, 'QUOTE_NOT_REVISABLE', 'Onaylanmamış teklif doğrudan düzenlenir; revizyon yalnız onaylı tekliflerde açılır.', { status: base.status });
    }
    if (base.status === 'rejected' && base.revision_no === 1) {
      throw new PlatformError(409, 'QUOTE_NOT_REVISABLE', 'Reddedilmiş teklif revize edilemez; yeni teklif ekleyin.', { status: base.status });
    }
    if (base.revision_no >= LIMITS.revisionsPerQuote) {
      throw new PlatformError(409, 'LIMIT_REACHED', `Bir teklif en fazla ${LIMITS.revisionsPerQuote} sürüm alabilir.`, { limit: LIMITS.revisionsPerQuote });
    }
    keys = changedKeys(patch, base);
    if (keys.length === 0) throw new PlatformError(400, 'NO_CHANGE', 'Revizyon için en az bir alan değişmeli.');
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM equipment_quotes WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows[0].n) >= LIMITS.quotes) throw new PlatformError(409, 'LIMIT_REACHED', 'Bir sitede en fazla 3000 teklif kaydedilebilir.', { limit: LIMITS.quotes });
    const pick = (key) => (patch[key] !== undefined ? patch[key] : base[key]);
    const ins = await client.query(
      `INSERT INTO equipment_quotes (site_code, topic, vendor_name, amount_kurus, valid_until, document_note, equipment_id, delivery_days, note, vat_included, revision_no, previous_id, revision_reason, created_by)
       VALUES ($1, $2, $3, $4, $5::DATE, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id`,
      [
        siteCode,
        base.topic,
        base.vendor_name,
        pick('amount_kurus'),
        pick('valid_until'),
        pick('document_note'),
        base.equipment_id,
        pick('delivery_days'),
        pick('note'),
        pick('vat_included'),
        base.revision_no + 1,
        base.id,
        reason,
        userOf(access),
      ],
    );
    newId = Number(ins.rows[0].id);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    if (error?.code === '23505') {
      throw new PlatformError(409, 'QUOTE_NOT_LATEST', 'Bu teklifin daha yeni bir sürümü var; en son sürümü revize edin.');
    }
    throw error;
  } finally {
    client.release();
  }
  await audit(actor, 'quote.revised', siteCode, 'equipment_quote', newId, {
    ...changeDetails(keys, base, { amount_kurus: patch.amount_kurus ?? base.amount_kurus }),
    from_id: base.id,
    revision_no: base.revision_no + 1,
  });
  return { quote: await loadQuote(siteCode, newId) };
}

/** Bir teklifin tum surumleri (eskiden yeniye) — zincirdeki herhangi bir surumun kimligiyle sorulur; sakin ve ilgisiz kullanicilar rotada zaten elenir. */
export async function quoteHistory(siteCode, rawId) {
  const quoteId = id(rawId, 'id', 'Teklif', { required: true });
  const r = await pool.query(
    `WITH RECURSIVE up AS (
       SELECT id, previous_id, 1 AS depth FROM equipment_quotes WHERE id = $1 AND site_code = $2
       UNION ALL
       SELECT p.id, p.previous_id, up.depth + 1 FROM equipment_quotes p INNER JOIN up ON p.id = up.previous_id WHERE p.site_code = $2 AND up.depth < 100
     ), down AS (
       SELECT id, 1 AS depth FROM equipment_quotes WHERE id = $1 AND site_code = $2
       UNION ALL
       SELECT n.id, down.depth + 1 FROM equipment_quotes n INNER JOIN down ON n.previous_id = down.id WHERE n.site_code = $2 AND down.depth < 100
     )
     SELECT ${QUOTE_COLS} FROM equipment_quotes q
      WHERE q.site_code = $2 AND q.id IN (SELECT id FROM up UNION SELECT id FROM down)
      ORDER BY q.revision_no, q.id`,
    [quoteId, siteCode],
  );
  if (r.rows.length === 0) throw notFound('Teklif');
  const today = todayIstanbul();
  const items = r.rows.map((x) => mapQuote(x, today));
  const latest = items[items.length - 1];
  const approved = [...items].reverse().find((q) => q.status === 'accepted') ?? null;
  return { items, latest_id: latest.id, approved_id: approved ? approved.id : null };
}

/**
 * Revizyon kabulunden once: zincirde kabul edilip gider / sozlesmeye donusmus bir onceki surum varsa, yeni surumun kabulu AYRI bir kayit uretir (cift sayim riski).
 * Yonetici bunu `acknowledge_previous: true` ile bilerek onaylamadikca 409 PREVIOUS_VERSION_RECORDED doner; onceki kayit bu islemde DEGISTIRILMEZ.
 */
async function assertPreviousRecordAcknowledged(siteCode, quote, body) {
  const r = await pool.query(
    `WITH RECURSIVE anc AS (
       SELECT id, previous_id, status, expense_id, contract_id, revision_no, 1 AS depth FROM equipment_quotes WHERE id = $1 AND site_code = $2
       UNION ALL
       SELECT p.id, p.previous_id, p.status, p.expense_id, p.contract_id, p.revision_no, anc.depth + 1
         FROM equipment_quotes p INNER JOIN anc ON p.id = anc.previous_id WHERE p.site_code = $2 AND anc.depth < 100
     )
     SELECT id, revision_no, expense_id, contract_id FROM anc
      WHERE id <> $1 AND status = 'accepted' AND (expense_id IS NOT NULL OR contract_id IS NOT NULL)
      ORDER BY revision_no DESC LIMIT 1`,
    [quote.id, siteCode],
  );
  const previous = r.rows[0];
  if (!previous || body.acknowledge_previous === true) return;
  const kind = previous.expense_id !== null && previous.expense_id !== undefined ? 'gider' : 'sözleşme';
  throw new PlatformError(
    409,
    'PREVIOUS_VERSION_RECORDED',
    `Önceki sürüm (${Number(previous.revision_no)}. sürüm) zaten ${kind} olarak kaydedilmiş. Bu sürümü de kabul ederseniz ayrı bir kayıt oluşur; önceki kaydı gerekirse ilgili bölümden siz iptal edin ya da feshedin.`,
    {
      previous_quote_id: Number(previous.id),
      previous_revision_no: Number(previous.revision_no),
      previous_expense_id: nullableNumber(previous.expense_id),
      previous_contract_id: nullableNumber(previous.contract_id),
    },
  );
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
  if (quote.revision_no > 1) await assertPreviousRecordAcknowledged(siteCode, quote, b);
  const targetModule = as === 'expense' ? 'finance' : 'contracts';
  if (!(await isModuleEnabled(siteCode, targetModule))) {
    throw new PlatformError(403, 'MODULE_DISABLED', as === 'expense' ? 'Finans modülü kapalı.' : 'Firma ve Sözleşme Takibi modülü kapalı.', { module: targetModule });
  }
  // Atomik "claim": gider / sozlesme KABUL ANINDA kilitlenen satirdan okunan degerlerle olusur (arada yerinde duzenleme olsa bile tutarsizlik olmaz);
  // gecerlilik de ayni ifadede denetlenir.
  const claim = await pool.query(
    `UPDATE equipment_quotes SET status = 'accepted', accepted_as = $3, decided_at = NOW()
      WHERE id = $1 AND site_code = $2 AND status = 'open' AND (valid_until IS NULL OR valid_until >= $4::DATE)
      RETURNING topic, vendor_name, amount_kurus, equipment_id, revision_no`,
    [quoteId, siteCode, as, todayIstanbul()],
  );
  if (!claim.rows[0]) {
    const latest = await loadQuote(siteCode, quoteId);
    if (latest.status === 'open' && latest.expired) throw new PlatformError(409, 'QUOTE_EXPIRED', 'Teklifin geçerlilik süresi dolmuş.');
    throw new PlatformError(409, 'QUOTE_NOT_OPEN', 'Teklif zaten karara bağlanmış.');
  }
  const accepted = {
    topic: claim.rows[0].topic,
    vendor_name: claim.rows[0].vendor_name,
    amount_kurus: Number(claim.rows[0].amount_kurus),
    equipment_id: nullableNumber(claim.rows[0].equipment_id),
    revision_no: claim.rows[0].revision_no === null || claim.rows[0].revision_no === undefined ? 1 : Number(claim.rows[0].revision_no),
  };
  const revisionSuffix = accepted.revision_no > 1 ? ` (revizyon ${accepted.revision_no})` : '';
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
          description: `Teklif: ${accepted.topic} - ${accepted.vendor_name}${revisionSuffix}`.slice(0, 200),
          amount_minor: accepted.amount_kurus,
          expense_date: e.expense_date ?? todayIstanbul(),
          document_kind: e.document_kind,
          document_no: e.document_no,
          idempotency_key: `quote-${quoteId}`,
        },
      });
      expenseId = Number(created.expense.id);
      if (accepted.equipment_id !== null) {
        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          await linkExpenseTx(client, siteCode, accepted.equipment_id, expenseId, userOf(access));
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
          title: c.title ?? `${accepted.topic} (${accepted.vendor_name})${revisionSuffix}`.slice(0, 160),
          start_date: c.start_date,
          end_date: c.end_date,
          period: c.period,
          auto_renew: c.auto_renew,
          note: c.note,
          amount: kurusToAmount(accepted.amount_kurus),
        },
      });
      contractId = Number(created.contract.id);
    }
    await pool.query(`UPDATE equipment_quotes SET expense_id = $3, contract_id = $4 WHERE id = $1 AND site_code = $2`, [quoteId, siteCode, expenseId, contractId]);
    await pool.query(
      `UPDATE equipment_quotes SET status = 'rejected', decided_at = NOW() WHERE site_code = $1 AND status = 'open' AND id <> $2 AND lower(topic) = lower($3)`,
      [siteCode, quoteId, accepted.topic],
    );
    await audit(actor, 'quote.accepted', siteCode, 'equipment_quote', quoteId, {
      as,
      expense_id: expenseId,
      contract_id: contractId,
      ...(accepted.revision_no > 1 ? { revision_no: accepted.revision_no, acknowledged_previous: b.acknowledge_previous === true } : {}),
    });
  } catch (error) {
    await pool.query(`UPDATE equipment_quotes SET status = 'open', accepted_as = NULL, decided_at = NULL WHERE id = $1 AND site_code = $2 AND expense_id IS NULL AND contract_id IS NULL`, [quoteId, siteCode]).catch(() => {});
    throw error;
  }
  return { quote: await loadQuote(siteCode, quoteId) };
}

// --- Firma teklif formu (113, P2-8): dis firma icin bagimsiz, tek kullanimlik form --------------------------------------------------------------------------
// Davet kalibi (team_schema.js person_invitations): 32 bayt CSPRNG hex belirtec, veritabaninda YALNIZ SHA-256 ozeti, sure, tek kullanim (atomik UPDATE).
// Teklif Pro API'sine BAGLANMAZ. Firma girisi `equipment_quote_requests`a TASLAK olarak duser; yonetici onaylayana kadar `equipment_quotes`a, gidere ya da
// sozlesmeye HICBIR sey yazilmaz. Onay yalniz ACIK bir teklif olusturur: kabul (gider / sozlesme) yine ayri ve yine yonetici karari (acceptQuote).
// Belirtec ve baglanti yalniz olusturma yanitinda doner; liste / ayrinti yanitlari hicbir zaman belirtec ya da ozet tasimaz. Dis giris metni denetim gunlugune YAZILMAZ.

export const QUOTE_REQUEST_LIMITS = Object.freeze({ open: 100, defaultDays: 14, maxDays: 30, list: 200 });
export const QUOTE_REQUEST_TOKEN = /^[0-9a-f]{64}$/;
export const QUOTE_FORM_PATH = '/firma-teklif';
const QUOTE_REQUEST_PHONE = /^[0-9+()\-.\s]{3,32}$/;
const QUOTE_REQUEST_STATUS_FILTER = Object.freeze(['invited', 'draft', 'approved', 'rejected', 'revoked']);

export const hashQuoteRequestToken = (token) => createHash('sha256').update(String(token)).digest('hex');
const publicBaseUrl = () => String(process.env.PUBLIC_APP_URL || process.env.PUBLIC_BASE_URL || 'https://api.gudeteknoloji.com.tr').replace(/\/+$/, '');
const unusableForm = () => new PlatformError(410, 'QUOTE_FORM_UNUSABLE', 'Bu form bağlantısı geçersiz, süresi dolmuş, iptal edilmiş ya da daha önce kullanılmış.');
const requestNotPending = () => new PlatformError(409, 'QUOTE_REQUEST_NOT_PENDING', 'Bu form bağlantısı artık beklemede değil.');
const requestNotDraft = () => new PlatformError(409, 'QUOTE_REQUEST_NOT_DRAFT', 'Bu taslak teklif zaten karara bağlanmış ya da henüz gönderilmemiş.');

const REQUEST_COLS = `r.id, r.topic, r.equipment_id, r.vendor_hint, r.status, r.expires_at, r.created_at, r.submitted_at, r.vendor_name, r.vendor_contact, r.vendor_phone,
  r.amount_kurus, to_char(r.valid_until, 'YYYY-MM-DD') AS valid_until, r.delivery_days, r.note, r.vat_included, r.decided_at, r.quote_id`;

const isoOrNull = (v) => (v === null || v === undefined ? null : v instanceof Date ? v.toISOString() : String(v));

/** Liste / ayrinti satiri: belirtec ve ozeti ASLA donmez. `expired` = bekleyen baglantinin suresi dolmus (okuma anindaki turetilmis durum). */
export function mapQuoteRequest(r, now = new Date()) {
  const expiresAt = r.expires_at ? new Date(r.expires_at) : null;
  return {
    id: Number(r.id),
    topic: r.topic,
    equipment_id: nullableNumber(r.equipment_id),
    vendor_hint: r.vendor_hint ?? null,
    status: r.status,
    expired: r.status === 'invited' && expiresAt !== null && expiresAt <= now,
    expires_at: isoOrNull(r.expires_at),
    created_at: isoOrNull(r.created_at),
    submitted_at: isoOrNull(r.submitted_at),
    vendor_name: r.vendor_name ?? null,
    vendor_contact: r.vendor_contact ?? null,
    vendor_phone: r.vendor_phone ?? null,
    amount_kurus: nullableNumber(r.amount_kurus),
    valid_until: r.valid_until ?? null,
    delivery_days: nullableNumber(r.delivery_days),
    note: r.note ?? null,
    vat_included: r.vat_included === null || r.vat_included === undefined ? null : r.vat_included === true,
    decided_at: isoOrNull(r.decided_at),
    quote_id: nullableNumber(r.quote_id),
  };
}

async function loadQuoteRequest(siteCode, requestId) {
  const r = await pool.query(`SELECT ${REQUEST_COLS} FROM equipment_quote_requests r WHERE r.id = $1 AND r.site_code = $2`, [requestId, siteCode]);
  if (!r.rows[0]) throw notFound('Firma formu');
  return mapQuoteRequest(r.rows[0]);
}

export async function listQuoteRequests(siteCode, query = {}) {
  const status = QUOTE_REQUEST_STATUS_FILTER.includes(query.status) ? query.status : null;
  const r = await pool.query(
    `SELECT ${REQUEST_COLS} FROM equipment_quote_requests r WHERE r.site_code = $1 AND ($2::TEXT IS NULL OR r.status = $2) ORDER BY r.id DESC LIMIT ${QUOTE_REQUEST_LIMITS.list}`,
    [siteCode, status],
  );
  const now = new Date();
  return { items: r.rows.map((x) => mapQuoteRequest(x, now)) };
}

/**
 * Yeni form baglantisi. Yanit `link` (tam adres + yol) YALNIZ burada doner; yonetici firmaya kendisi iletir (e-posta / mesaj). Ayni anda en fazla 100 bekleyen
 * (suresi dolmamis baglanti + onay bekleyen taslak) olabilir.
 */
export async function createQuoteRequest({ siteCode, actor, access, body }) {
  const b = bodyOf(body);
  const topic = text(b.topic, 'topic', 'Konu', 160, { required: true });
  const vendorHint = text(b.vendor_hint, 'vendor_hint', 'Beklenen firma', 120);
  const equipmentId = id(b.equipment_id, 'equipment_id', 'Ekipman');
  if (equipmentId !== null) await loadItem(siteCode, equipmentId);
  const rawDays = b.valid_days === undefined || b.valid_days === null || b.valid_days === '' ? QUOTE_REQUEST_LIMITS.defaultDays : b.valid_days;
  if (!Number.isSafeInteger(rawDays) || rawDays < 1 || rawDays > QUOTE_REQUEST_LIMITS.maxDays) {
    throw invalid('valid_days', `Bağlantı süresi 1 ile ${QUOTE_REQUEST_LIMITS.maxDays} gün arasında tam sayı olmalı.`);
  }
  const open = await pool.query(
    `SELECT COUNT(*)::INTEGER AS n FROM equipment_quote_requests WHERE site_code = $1 AND (status = 'draft' OR (status = 'invited' AND expires_at > NOW()))`,
    [siteCode],
  );
  if (Number(open.rows[0].n) >= QUOTE_REQUEST_LIMITS.open) {
    throw new PlatformError(409, 'LIMIT_REACHED', `Bir sitede aynı anda en fazla ${QUOTE_REQUEST_LIMITS.open} bekleyen firma formu olabilir. Eskileri iptal edin ya da taslakları karara bağlayın.`, {
      limit: QUOTE_REQUEST_LIMITS.open,
    });
  }
  const token = randomBytes(32).toString('hex');
  const r = await pool.query(
    `INSERT INTO equipment_quote_requests (site_code, topic, equipment_id, vendor_hint, token_hash, expires_at, created_by)
     VALUES ($1, $2, $3, $4, $5, NOW() + ($6::INTEGER * INTERVAL '1 day'), $7) RETURNING id`,
    [siteCode, topic, equipmentId, vendorHint, hashQuoteRequestToken(token), rawDays, userOf(access)],
  );
  const requestId = Number(r.rows[0].id);
  await audit(actor, 'quote.request_created', siteCode, 'equipment_quote_request', requestId, { topic, valid_days: rawDays });
  const request = await loadQuoteRequest(siteCode, requestId);
  const path = `${QUOTE_FORM_PATH}/${token}`;
  return { request, link: { url: `${publicBaseUrl()}${path}`, path, expires_at: request.expires_at } };
}

/** Henuz kullanilmamis baglantiyi iptal eder (yalniz `invited`). */
export async function revokeQuoteRequest({ siteCode, rawId, actor, access }) {
  const requestId = id(rawId, 'id', 'Firma formu', { required: true });
  const r = await pool.query(
    `UPDATE equipment_quote_requests SET status = 'revoked', decided_by = $3, decided_at = NOW() WHERE id = $1 AND site_code = $2 AND status = 'invited' RETURNING id`,
    [requestId, siteCode, userOf(access)],
  );
  if (!r.rows[0]) {
    await loadQuoteRequest(siteCode, requestId);
    throw requestNotPending();
  }
  await audit(actor, 'quote.request_revoked', siteCode, 'equipment_quote_request', requestId, {});
  return { request: await loadQuoteRequest(siteCode, requestId) };
}

/** Firma taslagini reddeder (yalniz `draft`); hicbir teklif / gider / sozlesme olusmaz. */
export async function rejectQuoteRequest({ siteCode, rawId, actor, access }) {
  const requestId = id(rawId, 'id', 'Firma formu', { required: true });
  const r = await pool.query(
    `UPDATE equipment_quote_requests SET status = 'rejected', decided_by = $3, decided_at = NOW() WHERE id = $1 AND site_code = $2 AND status = 'draft' RETURNING id`,
    [requestId, siteCode, userOf(access)],
  );
  if (!r.rows[0]) {
    await loadQuoteRequest(siteCode, requestId);
    throw requestNotDraft();
  }
  await audit(actor, 'quote.request_rejected', siteCode, 'equipment_quote_request', requestId, {});
  return { request: await loadQuoteRequest(siteCode, requestId) };
}

const requestDocumentNote = (contact, phone) => {
  const parts = [contact, phone].filter(Boolean).join(', ');
  return `Firma formundan geldi${parts ? ` (irtibat: ${parts})` : ''}`.slice(0, 300);
};

/**
 * Taslagi onaylar: AYNI islemde (kilitli satirdan okunan degerlerle) ACIK bir teklif (`equipment_quotes`) olusur ve taslak `approved` olur. Gider / sozlesme OLUSMAZ;
 * teklifin kabulu ayri bir yonetici karari olarak `acceptQuote` ile yapilir. Cift tiklama / yaris: ikinci cagri 409 QUOTE_REQUEST_NOT_DRAFT.
 */
export async function approveQuoteRequest({ siteCode, rawId, actor, access }) {
  const requestId = id(rawId, 'id', 'Firma formu', { required: true });
  const client = await pool.connect();
  let quoteId;
  try {
    await client.query('BEGIN');
    const found = await client.query(
      `SELECT r.id, r.topic, r.equipment_id, r.status, r.vendor_name, r.vendor_contact, r.vendor_phone, r.amount_kurus, to_char(r.valid_until, 'YYYY-MM-DD') AS valid_until,
              r.delivery_days, r.note, r.vat_included
         FROM equipment_quote_requests r WHERE r.id = $1 AND r.site_code = $2 FOR UPDATE`,
      [requestId, siteCode],
    );
    const draft = found.rows[0];
    if (!draft) throw notFound('Firma formu');
    if (draft.status !== 'draft') throw requestNotDraft();
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM equipment_quotes WHERE site_code = $1`, [siteCode]);
    if (Number(count.rows[0].n) >= LIMITS.quotes) throw new PlatformError(409, 'LIMIT_REACHED', 'Bir sitede en fazla 3000 teklif kaydedilebilir.', { limit: LIMITS.quotes });
    const ins = await client.query(
      `INSERT INTO equipment_quotes (site_code, topic, vendor_name, amount_kurus, valid_until, document_note, equipment_id, created_by, delivery_days, note, vat_included)
       VALUES ($1, $2, $3, $4, $5::DATE, $6, $7, $8, $9, $10, $11) RETURNING id`,
      [
        siteCode,
        draft.topic,
        draft.vendor_name,
        Number(draft.amount_kurus),
        draft.valid_until ?? null,
        requestDocumentNote(draft.vendor_contact, draft.vendor_phone),
        nullableNumber(draft.equipment_id),
        userOf(access),
        nullableNumber(draft.delivery_days),
        draft.note ?? null,
        draft.vat_included === null || draft.vat_included === undefined ? null : draft.vat_included === true,
      ],
    );
    quoteId = Number(ins.rows[0].id);
    await client.query(`UPDATE equipment_quote_requests SET status = 'approved', decided_by = $3, decided_at = NOW(), quote_id = $4 WHERE id = $1 AND site_code = $2`, [
      requestId,
      siteCode,
      userOf(access),
      quoteId,
    ]);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
  await audit(actor, 'quote.request_approved', siteCode, 'equipment_quote_request', requestId, { quote_id: quoteId });
  return { request: await loadQuoteRequest(siteCode, requestId), quote: await loadQuote(siteCode, quoteId) };
}

/** Bir belirtecin satiri ve (ayni 410 ile) kullanilamaz durumlari: bilinmeyen, kullanilmis, suresi dolmus, iptal, modul kapali. Hicbiri ayirt edilmez. */
async function usableFormRow(rawToken) {
  const token = typeof rawToken === 'string' ? rawToken : '';
  if (!QUOTE_REQUEST_TOKEN.test(token)) throw unusableForm();
  const r = await pool.query(
    `SELECT r.id, r.site_code, r.topic, r.vendor_hint, r.status, r.expires_at, s.name AS site_name
       FROM equipment_quote_requests r JOIN sites s ON s.site_code = r.site_code WHERE r.token_hash = $1 LIMIT 1`,
    [hashQuoteRequestToken(token)],
  );
  const row = r.rows[0];
  if (!row || row.status !== 'invited' || new Date(row.expires_at) <= new Date()) throw unusableForm();
  if (!(await isModuleEnabled(Number(row.site_code), EQUIPMENT_MODULE))) throw unusableForm();
  return { token, row };
}

/** Herkese acik form sayfasinin verisi (kimlik yok): yalniz konu, site adi, beklenen firma ve son gecerlilik. */
export async function getPublicQuoteForm(rawToken) {
  const { row } = await usableFormRow(rawToken);
  return { topic: row.topic, site_name: row.site_name ?? '', vendor_hint: row.vendor_hint ?? null, expires_at: isoOrNull(row.expires_at) };
}

/**
 * Firma girisi (kimlik yok, belirtec yetkidir). Dogrulama ONCE yapilir (gecersiz alan belirteci tuketmez); sonra TEK atomik UPDATE `invited -> draft` yapar:
 * ayni baglantiyla ikinci gonderim (cift tiklama / yaris) 410 alir. Girdi taslaga yazilir; teklif / gider / sozlesme olusmaz.
 */
export async function submitPublicQuote(rawToken, body) {
  const b = bodyOf(body);
  const vendorName = text(b.vendor_name, 'vendor_name', 'Firma adı', 120, { required: true });
  const vendorContact = text(b.vendor_contact, 'vendor_contact', 'Yetkili kişi', 80);
  const vendorPhone = text(b.vendor_phone, 'vendor_phone', 'Telefon', 32);
  if (vendorPhone !== null && !QUOTE_REQUEST_PHONE.test(vendorPhone)) throw invalid('vendor_phone', 'Telefon yalnız rakam, + ( ) - . ve boşluk içerebilir (en az 3 karakter).');
  const fields = parseQuoteFields({ amount_kurus: b.amount_kurus, valid_until: b.valid_until, delivery_days: b.delivery_days, note: b.note, vat_included: b.vat_included });
  if (fields.valid_until && fields.valid_until < todayIstanbul()) throw invalid('valid_until', 'Geçerlilik tarihi geçmişte olamaz.');
  const { token, row } = await usableFormRow(rawToken);
  const claim = await pool.query(
    `UPDATE equipment_quote_requests
        SET status = 'draft', submitted_at = NOW(), vendor_name = $2, vendor_contact = $3, vendor_phone = $4, amount_kurus = $5, valid_until = $6::DATE,
            delivery_days = $7, note = $8, vat_included = $9
      WHERE token_hash = $1 AND status = 'invited' AND expires_at > NOW()
      RETURNING id, site_code`,
    [
      hashQuoteRequestToken(token),
      vendorName,
      vendorContact,
      vendorPhone,
      fields.amount_kurus,
      fields.valid_until ?? null,
      fields.delivery_days ?? null,
      fields.note ?? null,
      fields.vat_included ?? null,
    ],
  );
  if (!claim.rows[0]) throw unusableForm();
  await audit({ full_name: 'Dış firma (form bağlantısı)' }, 'quote.request_submitted', Number(claim.rows[0].site_code), 'equipment_quote_request', Number(claim.rows[0].id), {});
  return { submitted: true, topic: row.topic };
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
