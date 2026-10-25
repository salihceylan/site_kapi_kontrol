// Sayac faturalandirma: onizleme ve deftere borc kalemi. Hesap: metering_calc.js (saf). Tahsilat BURADA YOK (yalniz finance_parties.postPayment).
// Borc, dairenin OTURANIN hesabina (resolveChargeParty ile ayni kural: occupantAccount) yazilir; defter yalniz eklemelidir (duzeltme = ters kayit, 4a).
// Kilit sirasi: finans danisma kilidi -> sayac danisma kilidi -> daireler (id sirasiyla FOR KEY SHARE) -> islemi yapan kullanici.

import { createHash } from 'node:crypto';
import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { canonicalJson } from './bulk_import_body.js';
import { assertFinanceEnabled } from './finance_access.js';
import { resolveOpenPeriod } from './finance_4b_guard.js';
import { periodClosed, today } from './finance_common.js';
import { MAX_AMOUNT_MINOR, minorToNumber } from './finance_money.js';
import { occupantAccount, tenantOnDateSql } from './finance_parties.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';
import { getRule } from './platform_rules.js';
import { buildMeterPlan, consumptionByApartment, planHash } from './metering_calc.js';
import {
  KIND_LABELS,
  METHODS,
  billingNotFound,
  billingOverlap,
  idempotencyConflict,
  incompleteReadings,
  invalid,
  milliOf,
  milliText,
  nothingToPost,
  objectOf,
  parseDate,
  parseKey,
  parseKind,
  parseMoney,
  previewStale,
} from './metering_common.js';
import { meteringLockKey } from './metering_service.js';

/** Dagitim girdisi (onizleme ve kayit ortak). */
export function parseBillingInput(body, { commit = false } = {}) {
  const input = objectOf(body);
  const kind = parseKind(input.kind);
  const method = input.method;
  if (!METHODS.includes(method)) throw invalid('Dağıtım yöntemi geçersiz (birim fiyat, fatura tutarı, ısı payı).', 'method');
  if (method === 'heat' && kind !== 'heat') throw invalid('Isı payı yöntemi yalnız ısı sayaçları için kullanılabilir.', 'method');
  const from = parseDate(input.period_from, 'Başlangıç tarihi', 'period_from');
  const to = parseDate(input.period_to, 'Bitiş tarihi', 'period_to');
  if (to <= from) throw invalid('Bitiş tarihi başlangıçtan sonra olmalıdır.', 'period_to');
  const parsed = { kind, method, from, to, skipMissing: input.skip_missing === true, unitPriceMinor: null, totalMinor: null, dueDate: null };
  if (method === 'unit_price') parsed.unitPriceMinor = parseMoney(input.unit_price_minor, 'unit_price_minor', 'Birim fiyat');
  else parsed.totalMinor = parseMoney(input.total_minor, 'total_minor', 'Tutar');
  if (input.due_date !== undefined && input.due_date !== null) parsed.dueDate = parseDate(input.due_date, 'Son ödeme tarihi', 'due_date');
  if (commit) {
    parsed.key = parseKey(input.idempotency_key);
    if (!Number.isSafeInteger(input.expected_total_minor) || !Number.isSafeInteger(input.expected_count) || typeof input.expected_hash !== 'string') {
      throw invalid('Önizleme bilgisi (expected_total_minor, expected_count, expected_hash) zorunludur.');
    }
    parsed.expected = { total: input.expected_total_minor, count: input.expected_count, hash: input.expected_hash };
  }
  return parsed;
}

const fingerprintOf = (input) =>
  createHash('sha256')
    .update(canonicalJson({ ...input, key: undefined, expected: undefined }))
    .digest('hex');

/** Plani hesaplar. `lock`: gercek kayit (danisma kilidi zaten alinmis, kural onbellegi atlanir). */
export async function computeBillingPlan(client, siteCode, input, { entryDate, lock = false } = {}) {
  const params = {};
  let measuredPct = 0;
  if (input.method === 'heat') {
    measuredPct = Number(await getRule(client, 'heat.measured_share_pct', { siteCode, onDate: input.to, fresh: lock }));
    params.measured_pct = measuredPct;
    params.area_pct = 100 - measuredPct;
  }
  if (input.method === 'unit_price') params.unit_price_minor = input.unitPriceMinor;
  else params.total_minor = input.totalMinor;
  const result = await client.query(
    `
      SELECT m.id AS meter_id, m.apartment_id, a.responsible_party, a.unit_label, b.block_name, NULL::TEXT AS area,
             ${tenantOnDateSql('a', '$5::DATE')} AS has_tenant,
             (SELECT r.value::TEXT FROM meter_readings r WHERE r.meter_id = m.id AND r.reading_date <= $3::DATE ORDER BY r.reading_date DESC LIMIT 1) AS opening,
             (SELECT to_char(r.reading_date, 'YYYY-MM-DD') FROM meter_readings r WHERE r.meter_id = m.id AND r.reading_date <= $3::DATE ORDER BY r.reading_date DESC LIMIT 1) AS opening_date,
             (SELECT r.value::TEXT FROM meter_readings r WHERE r.meter_id = m.id AND r.reading_date <= $4::DATE ORDER BY r.reading_date DESC LIMIT 1) AS closing,
             (SELECT to_char(r.reading_date, 'YYYY-MM-DD') FROM meter_readings r WHERE r.meter_id = m.id AND r.reading_date <= $4::DATE ORDER BY r.reading_date DESC LIMIT 1) AS closing_date
      FROM meters m
      INNER JOIN apartments a ON a.id = m.apartment_id
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE m.site_code = $1 AND m.kind = $2 AND m.is_active = TRUE AND a.is_active = TRUE
      ORDER BY m.apartment_id, m.id
    `,
    [siteCode, input.kind, input.from, input.to, entryDate],
  );
  const apartments = new Map();
  for (const row of result.rows) {
    apartments.set(Number(row.apartment_id), {
      id: Number(row.apartment_id),
      label: apartmentLabel(row.block_name, row.unit_label),
      responsibleParty: row.responsible_party,
      hasTenant: row.has_tenant === true,
      areaX100: row.area === null || row.area === undefined ? null : BigInt(Math.round(Number(row.area) * 100)),
    });
  }
  const { byApartment, missing: missingMap } = consumptionByApartment(
    result.rows.map((row) => ({
      apartmentId: Number(row.apartment_id),
      opening: row.opening === null ? null : milliOf(row.opening),
      closing: row.closing === null ? null : milliOf(row.closing),
      openingDate: row.opening_date,
      closingDate: row.closing_date,
    })),
  );
  const participants = [...byApartment.keys()].map((id) => ({ id, areaX100: apartments.get(id).areaX100 }));
  const missingList = () => [
    ...[...missingMap].map(([id, reason]) => ({ apartment_id: id, label: apartments.get(id).label, reason })),
  ];
  if (participants.length === 0) {
    return { params, lines: [], total: 0n, zeroCount: 0, missing: missingList(), hash: planHash({ kind: input.kind, method: input.method, from: input.from, to: input.to, params, lines: [] }) };
  }
  const calc = buildMeterPlan({
    method: input.method,
    apartments: participants,
    consumption: byApartment,
    unitPriceMinor: input.unitPriceMinor,
    totalMinor: input.totalMinor,
    measuredPct,
  });
  const lines = calc.lines.map((line) => {
    const apartment = apartments.get(line.apartmentId);
    if (line.amount > BigInt(MAX_AMOUNT_MINOR)) throw invalid('Hesaplanan tutar çok büyük; girdileri kontrol edin.');
    return {
      ...line,
      label: apartment.label,
      payerParty: apartment.responsibleParty,
      accountParty: occupantAccount(apartment.responsibleParty, apartment.hasTenant),
    };
  });
  const missing = [
    ...missingList(),
    ...calc.areaMissing.map((id) => ({ apartment_id: id, label: apartments.get(id).label, reason: 'area_missing' })),
  ];
  return {
    params,
    lines,
    total: calc.total,
    zeroCount: calc.zeroCount,
    missing,
    hash: planHash({ kind: input.kind, method: input.method, from: input.from, to: input.to, params, lines }),
  };
}

function previewBody(input, plan) {
  return {
    kind: input.kind,
    method: input.method,
    period_from: input.from,
    period_to: input.to,
    params: plan.params,
    total_minor: minorToNumber(plan.total),
    apartment_count: plan.lines.length,
    zero_count: plan.zeroCount,
    lines: plan.lines.map((l) => ({
      apartment_id: l.apartmentId,
      label: l.label,
      consumption: milliText(l.consumptionMilli),
      amount_minor: minorToNumber(l.amount),
      account_party: l.accountParty,
    })),
    missing: plan.missing,
    preview_hash: plan.hash,
    can_post: plan.lines.length > 0 && (plan.missing.length === 0 || input.skipMissing),
  };
}

export async function previewBilling({ siteCode, body, now = new Date() }) {
  const input = parseBillingInput(body);
  const plan = await computeBillingPlan(pool, siteCode, input, { entryDate: today(now) });
  return previewBody(input, plan);
}

const mapBilling = (row) => ({
  id: Number(row.id),
  kind: row.kind,
  method: row.method,
  period_from: row.period_from,
  period_to: row.period_to,
  total_minor: minorToNumber(row.total_minor),
  apartment_count: Number(row.apartment_count),
  params: row.params,
  posted_at: row.posted_at instanceof Date ? row.posted_at.toISOString() : row.posted_at,
});

const BILLING_SELECT = `
  SELECT id, kind, method, to_char(period_from, 'YYYY-MM-DD') AS period_from, to_char(period_to, 'YYYY-MM-DD') AS period_to,
         total_minor, apartment_count, params, posted_at, request_fingerprint
  FROM meter_billings
`;

export async function postBilling({ siteCode, body, actor, now = new Date() }) {
  const input = parseBillingInput(body, { commit: true });
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = fingerprintOf(input);
  return withFinanceTransaction(siteCode, async (client) => {
    await assertFinanceEnabled(siteCode, client);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [meteringLockKey(siteCode)]);
    const replay = await client.query(`${BILLING_SELECT} WHERE site_code = $1 AND idempotency_key = $2`, [siteCode, input.key]);
    if (replay.rows[0]) {
      if (replay.rows[0].request_fingerprint !== fingerprint) throw idempotencyConflict();
      return { replayed: true, billing: mapBilling(replay.rows[0]) };
    }
    const overlap = await client.query(
      `SELECT 1 FROM meter_billings WHERE site_code = $1 AND kind = $2 AND period_from < $4::DATE AND period_to > $3::DATE LIMIT 1`,
      [siteCode, input.kind, input.from, input.to],
    );
    if (overlap.rows[0]) throw billingOverlap();
    const entryDate = today(now);
    const plan = await computeBillingPlan(client, siteCode, input, { entryDate, lock: true });
    if (plan.lines.length === 0) throw nothingToPost();
    if (
      plan.total !== BigInt(input.expected.total) ||
      plan.lines.length !== input.expected.count ||
      plan.hash !== input.expected.hash
    ) {
      throw previewStale({ total_minor: minorToNumber(plan.total), apartment_count: plan.lines.length, preview_hash: plan.hash });
    }
    if (plan.missing.length > 0 && !input.skipMissing) throw incompleteReadings(plan.missing.length);
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    if (await isPeriodClosed(client, siteCode, openPeriod)) throw periodClosed();
    const dueDate = input.dueDate ?? entryDate;
    const apartmentIds = plan.lines.map((l) => l.apartmentId).sort((a, b) => a - b);
    await client.query(`SELECT id FROM apartments WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR KEY SHARE`, [apartmentIds.map(String)]);
    await lockActorRow(client, actorInfo);
    const inserted = await client.query(
      `
        INSERT INTO meter_billings (site_code, kind, method, period_from, period_to, total_minor, apartment_count, params, preview_hash, idempotency_key, request_fingerprint, posted_by)
        VALUES ($1, $2, $3, $4::DATE, $5::DATE, $6::BIGINT, $7, $8::JSONB, $9, $10, $11, $12)
        RETURNING id
      `,
      [siteCode, input.kind, input.method, input.from, input.to, plan.total.toString(), plan.lines.length, JSON.stringify(plan.params), plan.hash, input.key, fingerprint, actorInfo.userCode],
    );
    const billingId = Number(inserted.rows[0].id);
    const lines = [...plan.lines].sort((a, b) => a.apartmentId - b.apartmentId);
    const name = `${KIND_LABELS[input.kind]} sayacı`;
    const written = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, description, payer_party, created_by, account_party
        )
        SELECT $1, t.apartment_id, 'charge', t.amount, $2::DATE, $3::DATE, $4::DATE, $5::TEXT, t.descr, t.payer, $6, t.account
        FROM unnest($7::BIGINT[], $8::BIGINT[], $9::TEXT[], $10::TEXT[], $11::TEXT[]) AS t(apartment_id, amount, payer, account, descr)
        ORDER BY t.apartment_id
        RETURNING id, apartment_id
      `,
      [
        siteCode,
        openPeriod,
        entryDate,
        dueDate,
        name,
        actorInfo.userCode,
        lines.map((l) => String(l.apartmentId)),
        lines.map((l) => l.amount.toString()),
        lines.map((l) => l.payerParty),
        lines.map((l) => l.accountParty),
        lines.map((l) => `${name} ${input.from} - ${input.to} (${milliText(l.consumptionMilli)} birim)`.slice(0, 200)),
      ],
    );
    if (written.rowCount !== lines.length) throw new Error(`sayac borc satir sayisi uyusmuyor (${written.rowCount} / ${lines.length})`);
    const entryByApartment = new Map(written.rows.map((r) => [Number(r.apartment_id), Number(r.id)]));
    await client.query(
      `
        INSERT INTO meter_billing_lines (billing_id, site_code, apartment_id, consumption, amount_minor, account_party, ledger_entry_id)
        SELECT $1, $2, t.apartment_id, t.consumption::NUMERIC, t.amount, t.account, t.entry_id
        FROM unnest($3::BIGINT[], $4::TEXT[], $5::BIGINT[], $6::TEXT[], $7::BIGINT[]) AS t(apartment_id, consumption, amount, account, entry_id)
      `,
      [
        billingId,
        siteCode,
        lines.map((l) => String(l.apartmentId)),
        lines.map((l) => milliText(l.consumptionMilli)),
        lines.map((l) => l.amount.toString()),
        lines.map((l) => l.accountParty),
        lines.map((l) => String(entryByApartment.get(l.apartmentId))),
      ],
    );
    await recordFinanceAudit(client, actor, 'metering.billing.posted', siteCode, billingId, {
      kind: input.kind,
      method: input.method,
      total_minor: minorToNumber(plan.total),
      apartment_count: lines.length,
      skipped_missing_count: plan.missing.length,
    });
    const row = await client.query(`${BILLING_SELECT} WHERE id = $1`, [billingId]);
    return { replayed: false, billing: mapBilling(row.rows[0]), entries_count: lines.length };
  });
}

export async function listBillings(siteCode) {
  const result = await pool.query(`${BILLING_SELECT} WHERE site_code = $1 ORDER BY posted_at DESC, id DESC LIMIT 100`, [siteCode]);
  return { items: result.rows.map(mapBilling) };
}

export async function getBilling(siteCode, rawId) {
  const id = parsePositiveId(rawId);
  if (id === null) throw billingNotFound();
  const found = await pool.query(`${BILLING_SELECT} WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!found.rows[0]) throw billingNotFound();
  const lines = await pool.query(
    `
      SELECT l.apartment_id, l.consumption::TEXT AS consumption, l.amount_minor, l.account_party, l.ledger_entry_id, a.unit_label, b.block_name
      FROM meter_billing_lines l
      INNER JOIN apartments a ON a.id = l.apartment_id
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE l.billing_id = $1 ORDER BY b.sort_order, a.sort_order
    `,
    [id],
  );
  return {
    billing: mapBilling(found.rows[0]),
    lines: lines.rows.map((r) => ({
      apartment_id: Number(r.apartment_id),
      label: apartmentLabel(r.block_name, r.unit_label),
      consumption: r.consumption,
      amount_minor: minorToNumber(r.amount_minor),
      account_party: r.account_party,
      ledger_entry_id: r.ledger_entry_id === null ? null : Number(r.ledger_entry_id),
    })),
  };
}
