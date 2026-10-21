// Faaliyet raporu (R2) hizmeti. Sözleşme: docs/PLATFORM_FAALIYET_RAPORU.md.
// Sistem taslağı kayıtlardan HER okumada hesaplanır (salt okur; defter, gider, iş, sözleşme, karar, duyuru tablolarına yazılmaz).
// Saklanan tek şey yöneticinin bölüm metni düzenlemeleri (annual_reports.edits) ve gelecek yıl büyüme oranıdır.
// Para tamsayı kuruş (BigInt toplam, JSON'a sayı). Günlüğe metin YAZILMAZ.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { isModuleEnabled } from './module_service.js';
import { computeIncomeExpense, rateBp, withReportSnapshot } from './finance_reports.js';
import { minorToNumber } from './finance_money.js';
import { getComparison } from './budget_service.js';

export const ANNUAL_REPORT_MODULE = 'annual_report';
export const SECTION_KEYS = Object.freeze(['general', 'finance', 'collections', 'works', 'maintenance', 'contracts', 'decisions', 'announcements', 'forecast']);
export const EDIT_MAX = 4000;
export const MIN_YEAR = 2000;
export const MAX_YEAR = 2100;
export const GROWTH_MIN_BP = -5000;
export const GROWTH_MAX_BP = 50000;
export const LIST_LIMIT = 30;
export const MAX_BODY_BYTES = 64 * 1024;
const INVISIBLE_RE = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f​-‏‪-‮⁠﻿]/g;

export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Faaliyet Raporu modülü kapalı.', { module: ANNUAL_REPORT_MODULE });
const invalid = (field, message) => new PlatformError(400, 'INVALID_FIELD', message, { field });

// --- Saf yardımcılar ------------------------------------------------------------------------------------------

export function parseYear(raw, now = new Date()) {
  const text = String(raw ?? '').trim();
  if (!/^\d{4}$/.test(text)) throw invalid('year', 'Yıl dört haneli olmalı.');
  const year = Number(text);
  if (year < MIN_YEAR || year > Math.min(MAX_YEAR, now.getUTCFullYear())) throw invalid('year', 'Geçersiz yıl.');
  return year;
}

export function parseGrowth(raw) {
  if (raw === undefined || raw === null || raw === '') return null;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < GROWTH_MIN_BP || n > GROWTH_MAX_BP) throw invalid('growth_bp', 'Büyüme oranı geçersiz.');
  return n;
}

/** Yalnız bilinen bölüm anahtarları; metin temizlenir, boş metin = düzenlemeyi kaldır (anahtar atılır). */
export function sanitizeEdits(raw) {
  if (raw === undefined || raw === null) return {};
  if (typeof raw !== 'object' || Array.isArray(raw)) throw invalid('edits', 'Düzenlemeler nesne olmalı.');
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!SECTION_KEYS.includes(key)) throw invalid('edits', `Bilinmeyen bölüm: ${key}`);
    if (value === null) continue;
    if (typeof value !== 'string') throw invalid(key, 'Bölüm metni yazı olmalı.');
    const text = value.replace(INVISIBLE_RE, '').replace(/\r\n?/g, '\n').trim();
    if (text.length > EDIT_MAX) throw invalid(key, `Bölüm metni en fazla ${EDIT_MAX} karakter olmalı.`);
    if (text.length > 0) out[key] = text;
  }
  return out;
}

/** Gelecek yıl tahmini: bu yılın gideri * (1 + oran). Tamsayı kuruş, yarıma yuvarlama. */
export function forecastExpense(expenseMinor, growthBp) {
  const base = BigInt(expenseMinor);
  const num = base * BigInt(10000 + growthBp);
  const sign = num < 0n ? -1n : 1n;
  return Number(((num * sign + 5000n) / 10000n) * sign);
}

const yearStart = (y) => `${y}-01-01`;
const yearEnd = (y) => `${y}-12-31`;
const monthsOf = (y) => Array.from({ length: 12 }, (_, i) => `${y}-${String(i + 1).padStart(2, '0')}-01`);
const big = (v) => BigInt(v ?? '0');

// --- Bölüm toplayıcılar (db: pool ya da istemci) ---------------------------------------------------------------

async function general(db, siteCode, year) {
  const site = await db.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
  const blocks = await db.query(`SELECT COUNT(*)::INT AS n FROM site_blocks WHERE site_code = $1`, [siteCode]);
  const apts = await db.query(`SELECT COUNT(*)::INT AS n FROM apartments WHERE site_code = $1 AND is_active`, [siteCode]);
  return { available: true, site_name: site.rows?.[0]?.name ?? '', year, block_count: blocks.rows?.[0]?.n ?? 0, apartment_count: apts.rows?.[0]?.n ?? 0 };
}

async function financeSection(db, siteCode, year, summary, budgetOn) {
  const rows = summary;
  const totals = rows.reduce((a, r) => ({ charged: a.charged + r.charged + r.lateFee, collected: a.collected + r.collected, expense: a.expense + r.expense }), { charged: 0n, collected: 0n, expense: 0n });
  const byCategory = new Map();
  for (const row of rows) for (const c of row.categories) byCategory.set(c.category_name, (byCategory.get(c.category_name) ?? 0n) + c.total);
  const categories = [...byCategory.entries()]
    .filter(([, t]) => t !== 0n)
    .sort((a, b) => a[0].localeCompare(b[0], 'tr'))
    .map(([category_name, t]) => ({ category_name, total_minor: minorToNumber(t) }));
  let budget = null;
  if (budgetOn) {
    const project = await db.query(`SELECT id FROM budget_projects WHERE site_code = $1 AND year = $2 ORDER BY id DESC LIMIT 1`, [siteCode, year]);
    if (project.rows?.[0]) {
      const cmp = await getComparison(siteCode, project.rows[0].id, db);
      budget = { status: cmp.project.status, rows: cmp.rows, totals: cmp.totals };
    }
  }
  return {
    available: true,
    income_minor: minorToNumber(totals.collected),
    expense_minor: minorToNumber(totals.expense),
    net_minor: minorToNumber(totals.collected - totals.expense),
    expense_by_category: categories,
    budget,
  };
}

async function collectionsSection(db, siteCode, year, summary) {
  const t = summary.reduce((a, r) => ({ charged: a.charged + r.charged + r.lateFee, collected: a.collected + r.collected }), { charged: 0n, collected: 0n });
  const bal = await db.query(
    `SELECT COALESCE(SUM(b) FILTER (WHERE b > 0), 0)::TEXT AS debt, COALESCE(-SUM(b) FILTER (WHERE b < 0), 0)::TEXT AS credit, COUNT(*) FILTER (WHERE b > 0)::INT AS debtors
     FROM (SELECT apartment_id, SUM(amount_minor) AS b FROM ledger_entries WHERE site_code = $1 AND entry_date <= $2::DATE GROUP BY apartment_id) x`,
    [siteCode, yearEnd(year)],
  );
  const row = bal.rows?.[0] ?? {};
  return {
    available: true,
    charged_minor: minorToNumber(t.charged),
    collected_minor: minorToNumber(t.collected),
    collection_rate_bp: rateBp(t.collected, t.charged),
    open_debt_minor: minorToNumber(big(row.debt)),
    open_credit_minor: minorToNumber(big(row.credit)),
    debtor_apartment_count: row.debtors ?? 0,
  };
}

async function worksSection(db, siteCode, year) {
  const byCat = await db.query(
    `SELECT category, COUNT(*)::INT AS total, COUNT(*) FILTER (WHERE status IN ('cozuldu', 'kapandi'))::INT AS done
     FROM work_items WHERE site_code = $1 AND created_at >= $2::DATE AND created_at < ($3::DATE + 1) GROUP BY category ORDER BY category`,
    [siteCode, yearStart(year), yearEnd(year)],
  );
  const photos = await db.query(
    `SELECT COUNT(*)::INT AS n FROM work_item_attachments a JOIN work_items w ON w.id = a.work_item_id AND w.site_code = a.site_code
     WHERE a.site_code = $1 AND a.status = 'ready' AND w.created_at >= $2::DATE AND w.created_at < ($3::DATE + 1)`,
    [siteCode, yearStart(year), yearEnd(year)],
  );
  const recent = await db.query(
    `SELECT w.id, w.title, w.category, to_char(w.closed_at, 'YYYY-MM-DD') AS closed_on,
       (SELECT COUNT(*)::INT FROM work_item_attachments a WHERE a.work_item_id = w.id AND a.status = 'ready') AS photo_count
     FROM work_items w WHERE w.site_code = $1 AND w.status IN ('cozuldu', 'kapandi') AND w.closed_at >= $2::DATE AND w.closed_at < ($3::DATE + 1)
     ORDER BY w.closed_at DESC, w.id DESC LIMIT ${LIST_LIMIT}`,
    [siteCode, yearStart(year), yearEnd(year)],
  );
  const cats = (byCat.rows ?? []).map((r) => ({ category: r.category, total: r.total, done: r.done }));
  return {
    available: true,
    total: cats.reduce((s, c) => s + c.total, 0),
    done: cats.reduce((s, c) => s + c.done, 0),
    by_category: cats,
    photo_count: photos.rows?.[0]?.n ?? 0,
    closed_items: (recent.rows ?? []).map((r) => ({ id: Number(r.id), title: r.title, category: r.category, closed_on: r.closed_on, photo_count: r.photo_count })),
  };
}

async function maintenanceSection(db, siteCode, year, worksOn, contractsOn) {
  const out = { available: worksOn || contractsOn, work_items: null, contracts: [], equipment: 'soon' };
  if (worksOn) {
    const r = await db.query(
      `SELECT COUNT(*)::INT AS total, COUNT(*) FILTER (WHERE status IN ('cozuldu', 'kapandi'))::INT AS done
       FROM work_items WHERE site_code = $1 AND category = 'bakim' AND created_at >= $2::DATE AND created_at < ($3::DATE + 1)`,
      [siteCode, yearStart(year), yearEnd(year)],
    );
    out.work_items = { total: r.rows?.[0]?.total ?? 0, done: r.rows?.[0]?.done ?? 0 };
  }
  if (contractsOn) {
    const c = await db.query(
      `SELECT c.title, c.category, v.name AS vendor_name FROM site_contracts c LEFT JOIN contract_vendors v ON v.id = c.vendor_id AND v.site_code = c.site_code
       WHERE c.site_code = $1 AND c.category IN ('asansor', 'teknik_bakim', 'havuz', 'bahce')
         AND c.start_date <= $3::DATE AND (c.end_date IS NULL OR c.end_date >= $2::DATE) ORDER BY c.category, c.title LIMIT ${LIST_LIMIT}`,
      [siteCode, yearStart(year), yearEnd(year)],
    );
    out.contracts = (c.rows ?? []).map((r) => ({ title: r.title, category: r.category, vendor_name: r.vendor_name ?? '' }));
  }
  return out;
}

async function contractsSection(db, siteCode, year) {
  const c = await db.query(
    `SELECT c.title, c.category, c.status, v.name AS vendor_name, to_char(c.start_date, 'YYYY-MM-DD') AS start_date, to_char(c.end_date, 'YYYY-MM-DD') AS end_date,
       c.period, ROUND(c.amount * 100)::TEXT AS amount_minor
     FROM site_contracts c LEFT JOIN contract_vendors v ON v.id = c.vendor_id AND v.site_code = c.site_code
     WHERE c.site_code = $1 AND c.start_date <= $3::DATE AND (c.end_date IS NULL OR c.end_date >= $2::DATE)
     ORDER BY c.category, c.title LIMIT ${LIST_LIMIT}`,
    [siteCode, yearStart(year), yearEnd(year)],
  );
  const items = (c.rows ?? []).map((r) => ({
    title: r.title, category: r.category, status: r.status, vendor_name: r.vendor_name ?? '', start_date: r.start_date, end_date: r.end_date,
    period: r.period, amount_minor: r.amount_minor === null || r.amount_minor === undefined ? null : Number(r.amount_minor),
  }));
  return { available: true, items };
}

async function decisionsSection(db, siteCode, year) {
  const d = await db.query(
    `SELECT decision_no, title, meeting_type, vote_result, to_char(meeting_date, 'YYYY-MM-DD') AS meeting_date
     FROM board_decisions WHERE site_code = $1 AND year = $2 AND status = 'kesin' ORDER BY meeting_date, id LIMIT ${LIST_LIMIT}`,
    [siteCode, year],
  );
  const n = await db.query(`SELECT COUNT(*)::INT AS n FROM board_decisions WHERE site_code = $1 AND year = $2 AND status = 'kesin'`, [siteCode, year]);
  return {
    available: true,
    total: n.rows?.[0]?.n ?? 0,
    items: (d.rows ?? []).map((r) => ({ decision_no: r.decision_no, title: r.title, meeting_type: r.meeting_type, vote_result: r.vote_result, meeting_date: r.meeting_date })),
  };
}

async function announcementsSection(db, siteCode, year) {
  const a = await db.query(
    `SELECT title, importance, to_char(published_at, 'YYYY-MM-DD') AS published_on FROM announcements
     WHERE site_code = $1 AND status = 'published' AND published_at >= $2::DATE AND published_at < ($3::DATE + 1) ORDER BY published_at, id LIMIT ${LIST_LIMIT}`,
    [siteCode, yearStart(year), yearEnd(year)],
  );
  const n = await db.query(
    `SELECT COUNT(*)::INT AS n FROM announcements WHERE site_code = $1 AND status = 'published' AND published_at >= $2::DATE AND published_at < ($3::DATE + 1)`,
    [siteCode, yearStart(year), yearEnd(year)],
  );
  return { available: true, total: n.rows?.[0]?.n ?? 0, items: (a.rows ?? []).map((r) => ({ title: r.title, importance: r.importance, published_on: r.published_on })) };
}

async function forecastSection(db, siteCode, year, finance, growthBp, budgetOn) {
  if (!finance.available) return { available: false };
  let nextBudget = null;
  if (budgetOn) {
    const p = await db.query(
      `SELECT COALESCE(SUM(i.annual_minor), 0)::TEXT AS total FROM budget_projects p JOIN budget_items i ON i.project_id = p.id AND i.site_code = p.site_code
       WHERE p.site_code = $1 AND p.year = $2`,
      [siteCode, year + 1],
    );
    const total = big(p.rows?.[0]?.total);
    if (total > 0n) nextBudget = minorToNumber(total);
  }
  return {
    available: true,
    next_year: year + 1,
    growth_bp: growthBp,
    base_expense_minor: finance.expense_minor,
    expected_expense_minor: forecastExpense(finance.expense_minor, growthBp),
    next_year_budget_minor: nextBudget,
  };
}

// --- Dış uçlar ------------------------------------------------------------------------------------------------

export async function getDraft(siteCode, year, db = pool) {
  const r = await db.query(`SELECT edits, growth_bp, updated_at FROM annual_reports WHERE site_code = $1 AND year = $2`, [siteCode, year]);
  const row = r.rows?.[0];
  if (!row) return { edits: {}, growth_bp: 0, saved: false, updated_at: null };
  return { edits: row.edits ?? {}, growth_bp: row.growth_bp, saved: true, updated_at: row.updated_at ? new Date(row.updated_at).toISOString() : null };
}

export async function buildReport({ siteCode, rawYear, rawGrowth, now = new Date() }) {
  const year = parseYear(rawYear ?? now.getUTCFullYear() - 1, now);
  const override = parseGrowth(rawGrowth);
  const [financeOn, budgetOn, worksOn, contractsOn, decisionsOn] = await Promise.all(
    ['finance', 'budget', 'work_tracking', 'contracts', 'decision_book'].map((code) => isModuleEnabled(siteCode, code)),
  );
  return withReportSnapshot(siteCode, async (db) => {
    const draft = await getDraft(siteCode, year, db);
    const growth = override ?? draft.growth_bp;
    const off = { available: false };
    const summary = financeOn ? await computeIncomeExpense(db, siteCode, monthsOf(year)) : null;
    const finance = financeOn ? await financeSection(db, siteCode, year, summary, budgetOn) : off;
    const sections = {
      general: await general(db, siteCode, year),
      finance,
      collections: financeOn ? await collectionsSection(db, siteCode, year, summary) : off,
      works: worksOn ? await worksSection(db, siteCode, year) : off,
      maintenance: await maintenanceSection(db, siteCode, year, worksOn, contractsOn),
      contracts: contractsOn ? await contractsSection(db, siteCode, year) : off,
      decisions: decisionsOn ? await decisionsSection(db, siteCode, year) : off,
      announcements: await announcementsSection(db, siteCode, year),
      forecast: await forecastSection(db, siteCode, year, finance, growth, budgetOn),
    };
    return { year, generated_at: now.toISOString(), draft: { edits: draft.edits, growth_bp: growth, saved: draft.saved, updated_at: draft.updated_at }, sections };
  });
}

export async function saveDraft({ siteCode, rawYear, actor, body, now = new Date() }) {
  const year = parseYear(rawYear, now);
  const edits = sanitizeEdits(body?.edits);
  const growth = parseGrowth(body?.growth_bp) ?? 0;
  const actorInfo = actorFromAuthUser(actor);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const saved = await client.query(
      `INSERT INTO annual_reports (site_code, year, edits, growth_bp, updated_by) VALUES ($1, $2, $3::jsonb, $4, $5)
       ON CONFLICT (site_code, year) DO UPDATE SET edits = EXCLUDED.edits, growth_bp = EXCLUDED.growth_bp, updated_by = EXCLUDED.updated_by, updated_at = NOW()
       RETURNING updated_at`,
      [siteCode, year, JSON.stringify(edits), growth, actorInfo.userCode],
    );
    await recordAudit(client, { actor, action: 'annual_report.save', siteCode, targetType: 'annual_report', targetId: String(year), details: { year, sections: Object.keys(edits).length } }, { inTransaction: true });
    await client.query('COMMIT');
    return { year, saved: true, edits, growth_bp: growth, updated_at: new Date(saved.rows[0].updated_at).toISOString() };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // yoksay
    }
    throw error;
  } finally {
    client.release();
  }
}
