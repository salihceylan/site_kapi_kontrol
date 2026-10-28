// Aidat ve Finans (Faz 4a): aidat / ek borç tanımları, önizleme, borçlandırma (post) ve ek borç.
//
// Sözleşme: docs/PLATFORM_FINANS.md.
//  - Para = tamsayı kuruş; dağıtım "en büyük kalan" yöntemiyle BigInt (finance_distribution.js): pay toplamı tutara BİREBİR eşit.
//  - Borçlandırma ATOMİKTİR ve İDEMPOTENTTİR: tek transaction, `finance_post:<site>` advisory kilidi altında; (tanım, dönem) UNIQUE; önizleme yazma anında
//    AYNI işlemde yeniden hesaplanır ve beklenenle (toplam, daire sayısı, `preview_hash`) uyuşmazsa 409 PREVIEW_STALE (hiçbir şey yazılmaz);
//    `idempotency_key` tekrarı AYNI istekse (parmak izi eşleşirse) aynı çalıştırmayı döndürür, farklı istekse 409 IDEMPOTENCY_CONFLICT. Ek borçta anahtar
//    ZORUNLUDUR ve son 24 saatteki aynı ek borç 409 DUPLICATE_CHARGE olur. Defter satırları TEK `INSERT ... SELECT ... FROM unnest(...)` ile yazılır
//    (3000 daire < 3 sn). Borçlandırma anındaki tanım adı defter satırına ANLIK GÖRÜNTÜ olarak yazılır (`definition_name`).
//  - Her sorguda site_code vardır (IDOR yok): başka sitenin tanımı 404 DEFINITION_NOT_FOUND.
//  - Audit `details` yalnız toplam / sayı / dönem / alan adı içerir: tanım adı, açıklama ve kişi adı ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';
import {
  MAX_FUTURE_PERIOD_MONTHS,
  addDays,
  addMonths,
  areaDefinitionUnusable,
  assertDefinitionShape,
  chargeNaturalKey,
  chargeRequestFingerprint,
  currentPeriod,
  definitionChargeParty,
  definitionInactive,
  definitionLocked,
  definitionNotFound,
  duplicateCharge,
  idempotencyConflict,
  invalidBody,
  invalidTarget,
  mapDefinitionRow,
  mapRunRow,
  mergeDefinitionPatch,
  nothingToPost,
  parseChargeInput,
  parseDefinitionCreate,
  parseDefinitionPatch,
  parseDefinitionsQuery,
  parsePostInput,
  parsePreviewInput,
  periodAlreadyPosted,
  periodClosed,
  periodLabel,
  periodOfDate,
  POSTED_PATCH_KEYS,
  postRequestFingerprint,
  previewIncomplete,
  previewStale,
  today,
} from './finance_common.js';
import { buildDistributionPlan, planHash, redistributesOnSkip } from './finance_distribution.js';
import { fundOfChargeParty } from './finance_funds.js';
import { MAX_RUN_TOTAL_MINOR, bigintsToSqlArray, minorToNumber } from './finance_money.js';
import { accountForCharge, tenantOnDateSql } from './finance_parties.js';
import { decisionAuditDetails, describeDecisionRequirement, resolveRunDecision } from './finance_run_decision.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';

// ---------------------------------------------------------------------------
// Tanım okuma
// ---------------------------------------------------------------------------

// İki hesap (İP-1A): hedef dairede borç tarihinde ($5) etkin kiracı var mı (loadTargetApartments).
const TENANT_ON_CHARGE_DATE = tenantOnDateSql('a', '$5::DATE');

const DEFINITION_SELECT = `
  SELECT
    d.id, d.name, d.kind, d.distribution, d.area_basis, d.amount_minor::text AS amount_minor, d.category_amounts, d.due_day,
    to_char(d.start_period, 'YYYY-MM-DD') AS start_period, to_char(d.end_period, 'YYYY-MM-DD') AS end_period,
    d.target_type, d.target_block_ids, d.target_apartment_ids, d.is_active, d.created_at, d.updated_at, d.charge_party,
    u.full_name AS created_by_name,
    EXISTS (SELECT 1 FROM fee_runs r WHERE r.definition_id = d.id) AS has_runs,
    (SELECT to_char(MAX(r.period), 'YYYY-MM-DD') FROM fee_runs r WHERE r.definition_id = d.id) AS last_posted_period
  FROM fee_definitions d
  LEFT JOIN users u ON u.user_code = d.created_by
`;

async function loadDefinitionRow(db, siteCode, id) {
  const result = await db.query(`${DEFINITION_SELECT} WHERE d.id = $1 AND d.site_code = $2 LIMIT 1`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

const idsOf = (value) => (Array.isArray(value) ? value.map((entry) => Number(entry)) : []);

/** Veritabanı satırı -> doğrulama/dağıtım için "şekil" (tarihler 'YYYY-MM-DD'). */
export function shapeOfRow(row) {
  return {
    kind: row.kind,
    name: row.name,
    distribution: row.distribution,
    areaBasis: row.area_basis ?? null,
    amountMinor: row.amount_minor === null || row.amount_minor === undefined ? null : minorToNumber(row.amount_minor),
    categoryAmounts: row.category_amounts && typeof row.category_amounts === 'object' ? row.category_amounts : null,
    dueDay: row.due_day === null || row.due_day === undefined ? null : Number(row.due_day),
    startPeriod: row.start_period,
    endPeriod: row.end_period ?? null,
    isActive: row.is_active === true,
    target: { type: row.target_type, blockIds: idsOf(row.target_block_ids), apartmentIds: idsOf(row.target_apartment_ids) },
    chargeParty: definitionChargeParty(row),
  };
}

/** Hedefteki blok / daire adlarını (yalnız bu siteye ait) tanım nesnelerine ekler: target.blocks [{id,name}], target.apartments [{id,label}]. */
async function attachTargetLabels(db, siteCode, definitions) {
  const blockIds = [...new Set(definitions.flatMap((entry) => entry.target.block_ids))];
  const apartmentIds = [...new Set(definitions.flatMap((entry) => entry.target.apartment_ids))];
  const blocks = new Map();
  const apartments = new Map();
  if (blockIds.length > 0) {
    const result = await db.query(`SELECT id, block_name FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[])`, [siteCode, blockIds]);
    for (const row of result.rows ?? []) blocks.set(Number(row.id), row.block_name);
  }
  if (apartmentIds.length > 0) {
    const result = await db.query(
      `
        SELECT a.id, a.unit_label, b.block_name
        FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.site_code = $1 AND a.id = ANY($2::BIGINT[])
        ORDER BY b.sort_order, a.sort_order, a.id
      `,
      [siteCode, apartmentIds],
    );
    for (const row of result.rows ?? []) apartments.set(Number(row.id), apartmentLabel(row.block_name, row.unit_label));
  }
  for (const entry of definitions) {
    entry.target.blocks = entry.target.block_ids.filter((id) => blocks.has(id)).map((id) => ({ id, name: blocks.get(id) }));
    entry.target.apartments = entry.target.apartment_ids.filter((id) => apartments.has(id)).map((id) => ({ id, label: apartments.get(id) }));
  }
  return definitions;
}

/**
 * GET definitions?kind=&active=&limit=&offset= -> { items: [Definition], total }. Sıra: aktifler önce, aylık (recurring) önce, yeni -> eski;
 * varsayılan ve azami sayfa 500 (aylık tanımlar yüzlerce ek borçla listeden düşmez; sayfalama `total` ile).
 */
export async function listDefinitions(siteCode, query = {}, db = pool) {
  const filters = parseDefinitionsQuery(query);
  const params = [siteCode];
  const clauses = ['d.site_code = $1'];
  if (filters.kind !== null) {
    params.push(filters.kind);
    clauses.push(`d.kind = $${params.length}`);
  }
  if (filters.active !== null) {
    params.push(filters.active);
    clauses.push(`d.is_active = $${params.length}`);
  }
  const where = clauses.join(' AND ');
  const count = await db.query(`SELECT COUNT(*)::INTEGER AS total FROM fee_definitions d WHERE ${where}`, params);
  const result = await db.query(
    `${DEFINITION_SELECT} WHERE ${where} ORDER BY d.is_active DESC, d.kind DESC, d.id DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, filters.limit, filters.offset],
  );
  const items = (result.rows ?? []).map(mapDefinitionRow);
  await attachTargetLabels(db, siteCode, items);
  return { items, total: Number(count.rows?.[0]?.total ?? 0) };
}

// ---------------------------------------------------------------------------
// Hedef ve dağıtım planı
// ---------------------------------------------------------------------------

/** Hedefteki blok/daire kimliklerinin TAMAMI bu siteye ait olmalı (aksi 400 INVALID_TARGET). */
async function assertTargetBelongsToSite(db, siteCode, target) {
  if (target.type === 'blocks') {
    const result = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[])`, [
      siteCode,
      target.blockIds,
    ]);
    if (Number(result.rows?.[0]?.n ?? 0) !== target.blockIds.length) {
      throw invalidTarget('Seçilen bloklar bu siteye ait değil.');
    }
  } else if (target.type === 'apartments') {
    const result = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM apartments WHERE site_code = $1 AND id = ANY($2::BIGINT[])`, [
      siteCode,
      target.apartmentIds,
    ]);
    if (Number(result.rows?.[0]?.n ?? 0) !== target.apartmentIds.length) {
      throw invalidTarget('Seçilen daireler bu siteye ait değil.');
    }
  }
}

/**
 * Hedefteki AKTİF daireler. lock: yazma yolunda satırlar id sırasıyla FOR KEY SHARE kilitlenir (daire silme ile sıra; kilit sırası kuralı:
 * apartments id sırasıyla). Alan değerleri SQL'de tamsayıya çevrilir (NUMERIC(8,2) x 100): kayan nokta yok.
 * İki hesap (İP-1A): `onDate` (borç tarihi) verilirse dairenin o gün etkin kiracısı olup olmadığı aynı sorguda okunur ve satırın hesabı
 * (`accountParty`) "kim öder" (`chargeParty`) kuralıyla çözülür (finance_parties.accountForCharge; 3000 daire tek sorgu).
 */
async function loadTargetApartments(db, siteCode, target, { lock = false, onDate = null, chargeParty = 'occupant' } = {}) {
  const result = await db.query(
    `
      SELECT
        a.id, a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort, a.responsible_party, a.category,
        NULL::BIGINT AS gross_x100, NULL::BIGINT AS net_x100,
        a.land_share_numerator, a.land_share_denominator,
        ($5::DATE IS NOT NULL AND ${TENANT_ON_CHARGE_DATE}) AS has_tenant
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.site_code = $1 AND a.is_active = TRUE
        AND (
          $2::TEXT = 'site'
          OR ($2::TEXT = 'blocks' AND a.block_id = ANY($3::BIGINT[]))
          OR ($2::TEXT = 'apartments' AND a.id = ANY($4::BIGINT[]))
        )
      ORDER BY a.id
      ${lock ? 'FOR KEY SHARE OF a' : ''}
    `,
    [siteCode, target.type, target.blockIds, target.apartmentIds, onDate],
  );
  return (result.rows ?? []).map((row) => ({
    id: Number(row.id),
    label: apartmentLabel(row.block_name, row.unit_label),
    blockName: row.block_name ?? null,
    blockSort: Number(row.block_sort),
    aptSort: Number(row.apt_sort),
    payerParty: row.responsible_party,
    category: row.category ?? null,
    grossX100: row.gross_x100 ?? null,
    netX100: row.net_x100 ?? null,
    landNumerator: row.land_share_numerator ?? null,
    landDenominator: row.land_share_denominator ?? null,
    ...(onDate === null ? {} : { accountParty: accountForCharge(chargeParty, row.responsible_party, row.has_tenant === true) }),
  }));
}

async function computePlan(db, siteCode, spec, options) {
  const apartments = await loadTargetApartments(db, siteCode, spec.target, { ...options, chargeParty: spec.chargeParty ?? 'occupant' });
  return buildDistributionPlan(
    { distribution: spec.distribution, areaBasis: spec.areaBasis, amountMinor: spec.amountMinor, categoryAmounts: spec.categoryAmounts },
    apartments,
  );
}

/**
 * Önizleme gövdesi (hem tanım hem ek borç için). `preview_hash`: satırlar + eksik veri kümesinin sha256 özeti (post / charges `expected_hash`).
 * `skipped_count` / `redistributed`: eksik verili daireler (skip_missing ile hariç tutulursa) ve paylarının kalanlara yeniden dağıtılıp dağıtılmayacağı.
 */
function previewBody({ plan, period, definitionId, alreadyPosted, closed, dueDate, distribution, duplicateOfRunId = null, decisionRequirement = null }) {
  return {
    period: periodLabel(period),
    definition_id: definitionId,
    due_date: dueDate,
    currency: 'TRY',
    total_minor: minorToNumber(plan.total),
    apartment_count: plan.lines.length,
    preview_hash: planHash(plan),
    lines: plan.lines.map((line) => ({
      apartment_id: line.apartmentId,
      label: line.label,
      block_name: line.blockName,
      payer_party: line.payerParty,
      // İki hesap (İP-1A): borcun yazılacağı hesap (owner = ev sahibi, tenant = kiracı)
      account_party: line.accountParty ?? null,
      amount_minor: minorToNumber(line.amount),
    })),
    missing_data: plan.missing.map((entry) => ({
      apartment_id: entry.apartmentId,
      label: entry.label,
      block_name: entry.blockName ?? null,
      reason: entry.reason,
      reason_code: entry.reasonCode,
    })),
    zero_amount_count: plan.zeroAmountCount,
    ...skipSummary(plan.missing.length, distribution),
    already_posted: alreadyPosted,
    duplicate_of_run_id: duplicateOfRunId,
    closed,
    // Tahakkuk dayanağı (K2): Fon hesabı borcunda Karar Defteri kaydı (modül açık) ya da gerekçe (modül kapalı) istenir; arayüz buna göre girdi gösterir
    decision_requirement: decisionRequirement,
  };
}

// ---------------------------------------------------------------------------
// Tanım yazma
// ---------------------------------------------------------------------------

const auditDefinitionDetails = (shape) => ({
  kind: shape.kind,
  distribution: shape.distribution,
  target_type: shape.target.type,
  start_period: periodLabel(shape.startPeriod),
});

function sqlParamsOfShape(shape) {
  return [
    shape.name,
    shape.kind,
    shape.distribution,
    shape.areaBasis,
    shape.amountMinor === null ? null : String(shape.amountMinor),
    shape.categoryAmounts === null ? null : JSON.stringify(shape.categoryAmounts),
    shape.dueDay,
    shape.startPeriod,
    shape.endPeriod,
    shape.target.type,
    shape.target.blockIds,
    shape.target.apartmentIds,
  ];
}

/** POST definitions -> Definition. */
export async function createDefinition({ siteCode, body, actor }) {
  const input = parseDefinitionCreate(body);
  const shape = {
    kind: input.kind,
    name: input.name,
    distribution: input.distribution,
    areaBasis: input.areaBasis,
    amountMinor: input.amountMinor,
    categoryAmounts: input.categoryAmounts,
    dueDay: input.dueDay,
    startPeriod: input.startPeriod,
    endPeriod: input.endPeriod,
    isActive: true,
    target: input.target,
    chargeParty: input.chargeParty,
  };
  assertDefinitionShape(shape);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await assertTargetBelongsToSite(client, siteCode, shape.target);
    await lockActorRow(client, actorInfo);
    const inserted = await client.query(
      `
        INSERT INTO fee_definitions (
          site_code, name, kind, distribution, area_basis, amount_minor, category_amounts, due_day, start_period, end_period,
          target_type, target_block_ids, target_apartment_ids, is_active, created_by, charge_party
        )
        VALUES ($1, $2, $3, $4, $5, $6::BIGINT, $7::JSONB, $8, $9::DATE, $10::DATE, $11, $12::BIGINT[], $13::BIGINT[], TRUE, $14, $15)
        RETURNING id
      `,
      [siteCode, ...sqlParamsOfShape(shape), actorInfo.userCode, shape.chargeParty],
    );
    const id = Number(inserted.rows[0].id);
    await recordFinanceAudit(client, actor, 'finance.definition.created', siteCode, id, auditDefinitionDetails(shape));
    const [definition] = await attachTargetLabels(client, siteCode, [mapDefinitionRow(await loadDefinitionRow(client, siteCode, id))]);
    return definition;
  });
}

/** PATCH definitions/:id -> Definition. Borçlandırılmışsa yalnız ad, bitiş dönemi, aktiflik ve vade günü değişir (409 DEFINITION_LOCKED). */
export async function updateDefinition({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw definitionNotFound();
  }
  const patch = parseDefinitionPatch(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    // KİLİT SIRASI: kullanıcı satırı (audit FK) tanım satırından ÖNCE; aksi halde updateDefinition x kullanıcı silme 40P01 verir.
    await lockActorRow(client, actorInfo);
    const locked = await client.query(`SELECT id FROM fee_definitions WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    if (!locked.rows?.[0]) {
      throw definitionNotFound();
    }
    const row = await loadDefinitionRow(client, siteCode, id);
    const existing = shapeOfRow(row);
    if (row.has_runs === true) {
      const forbidden = patch.keys.filter((key) => !POSTED_PATCH_KEYS.includes(key));
      if (forbidden.length > 0) {
        throw definitionLocked();
      }
      if (patch.keys.includes('end_period') && patch.endPeriod !== null && row.last_posted_period && patch.endPeriod < row.last_posted_period) {
        throw invalidBody('Bitiş dönemi son borçlandırılan dönemden önce olamaz.');
      }
    }
    const merged = mergeDefinitionPatch(existing, patch);
    assertDefinitionShape(merged);
    if (patch.keys.includes('target')) {
      await assertTargetBelongsToSite(client, siteCode, merged.target);
    }
    const params = sqlParamsOfShape(merged);
    await client.query(
      `
        UPDATE fee_definitions
        SET name = $3, kind = $4, distribution = $5, area_basis = $6, amount_minor = $7::BIGINT, category_amounts = $8::JSONB, due_day = $9,
            start_period = $10::DATE, end_period = $11::DATE, target_type = $12, target_block_ids = $13::BIGINT[], target_apartment_ids = $14::BIGINT[],
            is_active = $15, charge_party = $16, updated_at = NOW()
        WHERE id = $1 AND site_code = $2
      `,
      [id, siteCode, ...params, merged.isActive, merged.chargeParty],
    );
    const deactivated = existing.isActive && merged.isActive === false;
    await recordFinanceAudit(client, actor, deactivated ? 'finance.definition.deactivated' : 'finance.definition.updated', siteCode, id, {
      fields: patch.keys,
    });
    const [definition] = await attachTargetLabels(client, siteCode, [mapDefinitionRow(await loadDefinitionRow(client, siteCode, id))]);
    return definition;
  });
}

// ---------------------------------------------------------------------------
// Dönem / vade çözümü
// ---------------------------------------------------------------------------

/** Tanım için kayıt dönemi, kayıt tarihi ve vade tarihi. Dönem tanımın geçerlilik aralığında ve en çok 12 ay ileride olmalıdır. */
function resolveTiming(definitionShape, input, now) {
  const todayIsoDate = today(now);
  if (definitionShape.kind === 'recurring') {
    const period = input.period;
    if (period < definitionShape.startPeriod || (definitionShape.endPeriod !== null && period > definitionShape.endPeriod)) {
      throw definitionInactive();
    }
    if (period > addMonths(currentPeriod(now), MAX_FUTURE_PERIOD_MONTHS)) {
      throw invalidBody(`Dönem en fazla ${MAX_FUTURE_PERIOD_MONTHS} ay ileride olabilir.`);
    }
    return { period, entryDate: period, dueDate: addDays(period, definitionShape.dueDay - 1) };
  }
  return { period: periodOfDate(todayIsoDate), entryDate: todayIsoDate, dueDate: input.dueDate ?? todayIsoDate };
}

// ---------------------------------------------------------------------------
// Önizleme
// ---------------------------------------------------------------------------

/** POST definitions/:id/preview -> önizleme (YAZMAZ). */
export async function previewDefinition({ siteCode, rawId, body, now = new Date() }, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw definitionNotFound();
  }
  const row = await loadDefinitionRow(db, siteCode, id);
  if (!row) {
    throw definitionNotFound();
  }
  const shape = shapeOfRow(row);
  const input = parsePreviewInput(body, shape.kind, now);
  if (!shape.isActive) {
    throw definitionInactive();
  }
  // Eski m² tanımı: daire alanı yok, her daire area_missing olurdu (belirsiz tıkanma). Açık hata: 409 AREA_DISTRIBUTION_REMOVED.
  if (shape.distribution === 'area') {
    throw areaDefinitionUnusable();
  }
  const timing = resolveTiming(shape, input, now);
  const alreadyPosted = await runExists(db, id, shape.kind === 'recurring' ? timing.period : null);
  const closed = await isPeriodClosed(db, siteCode, timing.period);
  const plan = await computePlan(db, siteCode, shape, { lock: false, onDate: timing.entryDate });
  const decisionRequirement = await describeDecisionRequirement(db, siteCode, fundOfChargeParty(shape.chargeParty));
  return previewBody({
    plan,
    period: timing.period,
    definitionId: id,
    alreadyPosted,
    closed,
    dueDate: timing.dueDate,
    distribution: shape.distribution,
    decisionRequirement,
  });
}

/** POST charges/preview -> ek borç önizlemesi (YAZMAZ). `duplicate_of_run_id`: son 24 saatte aynı ek borcun çalıştırma kimliği (varsa). */
export async function previewCharge({ siteCode, body, now = new Date() }, db = pool) {
  const input = parseChargeInput(body, { requireExpected: false, now });
  await assertTargetBelongsToSite(db, siteCode, input.target);
  const todayIsoDate = today(now);
  const period = periodOfDate(todayIsoDate);
  const dueDate = input.dueDate ?? todayIsoDate;
  const plan = await computePlan(db, siteCode, input, { lock: false, onDate: todayIsoDate });
  const duplicate = await findRecentDuplicate(db, siteCode, chargeNaturalKey(input, dueDate));
  return previewBody({
    plan,
    period,
    definitionId: null,
    alreadyPosted: false,
    closed: await isPeriodClosed(db, siteCode, period),
    dueDate,
    distribution: input.distribution,
    duplicateOfRunId: duplicate ? Number(duplicate.id) : null,
    decisionRequirement: await describeDecisionRequirement(db, siteCode, fundOfChargeParty(input.chargeParty)),
  });
}

/** Tanım için çalıştırma var mı: recurring -> o dönem; tek seferlik (period null) -> herhangi bir çalıştırma. */
async function runExists(db, definitionId, periodIso) {
  const result =
    periodIso === null
      ? await db.query(`SELECT 1 FROM fee_runs WHERE definition_id = $1 LIMIT 1`, [definitionId])
      : await db.query(`SELECT 1 FROM fee_runs WHERE definition_id = $1 AND period = $2::DATE LIMIT 1`, [definitionId, periodIso]);
  return Boolean(result.rows?.[0]);
}

// ---------------------------------------------------------------------------
// Borçlandırma (post)
// ---------------------------------------------------------------------------

const RUN_RETURNING = `id, definition_id, to_char(period, 'YYYY-MM-DD') AS period, total_minor::text AS total_minor, apartment_count, skipped_count, posted_at`;

/** Aynı işlem anahtarıyla daha önce yazılmış çalıştırma (aynı site): istek parmak izi, tanım türü ve dağıtımıyla. */
async function findRunByKey(db, siteCode, key) {
  if (key === null) {
    return null;
  }
  const result = await db.query(
    `
      SELECT
        r.id, r.definition_id, to_char(r.period, 'YYYY-MM-DD') AS period, r.total_minor::text AS total_minor, r.apartment_count,
        r.skipped_count, r.posted_at, r.request_fingerprint, d.kind AS definition_kind, d.distribution AS definition_distribution,
        r.decision_id AS run_decision_id, r.decision_reason AS run_decision_reason, bd.year AS run_decision_year, bd.decision_no AS run_decision_no,
        bd.title AS run_decision_title, bd.visibility AS run_decision_visibility
      FROM fee_runs r
      INNER JOIN fee_definitions d ON d.id = r.definition_id
      LEFT JOIN board_decisions bd ON bd.site_code = r.site_code AND bd.id = r.decision_id
      WHERE r.site_code = $1 AND r.idempotency_key = $2
      LIMIT 1
    `,
    [siteCode, key],
  );
  return result.rows?.[0] ?? null;
}

/** skip_missing ile hariç tutulan daire sayısı ve payın kalanlara yeniden dağıtılıp dağıtılmadığı (fixed / category: dağıtılmaz). */
function skipSummary(skippedCount, distribution) {
  return { skipped_count: skippedCount, redistributed: skippedCount > 0 && redistributesOnSkip(distribution) };
}

/**
 * Plan -> yazma izni: eksik veri (PREVIEW_INCOMPLETE), boş plan, toplam sınırı ve önizleme güncelliği (PREVIEW_STALE: toplam, daire sayısı VE
 * önizleme özeti `preview_hash` yeniden hesaplananla aynı olmalı; daireler takas edilmiş ya da pay değişmişse eşit toplamla geçemez).
 */
function verifyPlan(plan, { skipMissing, expectedTotal, expectedCount, expectedHash }) {
  if (plan.missing.length > 0 && !skipMissing) {
    throw previewIncomplete({ missing_count: plan.missing.length });
  }
  if (plan.lines.length === 0) {
    throw nothingToPost();
  }
  if (plan.total > BigInt(MAX_RUN_TOTAL_MINOR)) {
    throw invalidBody('Toplam tutar çok büyük.');
  }
  const hash = planHash(plan);
  if (plan.total !== BigInt(expectedTotal) || plan.lines.length !== expectedCount || hash !== expectedHash) {
    throw previewStale({ total_minor: minorToNumber(plan.total), apartment_count: plan.lines.length, preview_hash: hash });
  }
}

/** Çalıştırma + defter satırları (tek INSERT ... SELECT ... FROM unnest). Çağıran kilidi ve doğrulamaları yapmış olmalıdır. */
async function writeRun(client, { siteCode, definitionId, definitionName, plan, timing, idempotencyKey, requestFingerprint, naturalKey, actorUserCode, fund, decision }) {
  // Tahakkuk dayanağı (K2): Karar Defteri kaydı ve/veya gerekçe, çalıştırma yazılırken konur (fee_runs eklemelidir; sonradan DEĞİŞMEZ)
  const inserted = await client.query(
    `
      INSERT INTO fee_runs (
        site_code, definition_id, period, total_minor, apartment_count, skipped_count, idempotency_key, request_fingerprint, natural_key, posted_by,
        decision_id, decision_reason
      )
      VALUES ($1, $2, $3::DATE, $4::BIGINT, $5, $6, $7, $8, $9, $10, $11::BIGINT, $12)
      RETURNING ${RUN_RETURNING}
    `,
    [
      siteCode,
      definitionId,
      timing.period,
      plan.total.toString(),
      plan.lines.length,
      plan.missing.length,
      idempotencyKey,
      requestFingerprint,
      naturalKey,
      actorUserCode,
      decision.decisionId === null ? null : String(decision.decisionId),
      decision.decisionReason,
    ],
  );
  const run = { ...inserted.rows[0], ...(decision.label ?? {}) };
  const lines = [...plan.lines].sort((a, b) => a.apartmentId - b.apartmentId);
  const written = await client.query(
    `
      INSERT INTO ledger_entries (
        site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_id, definition_name, run_id, payer_party, created_by, account_party, fund
      )
      SELECT $1, t.apartment_id, 'charge', t.amount, $2::DATE, $3::DATE, $4::DATE, $5, $6::TEXT, $7, t.payer, $8, t.account, $13::TEXT
      FROM unnest($9::BIGINT[], $10::BIGINT[], $11::TEXT[], $12::TEXT[]) AS t(apartment_id, amount, payer, account)
      ORDER BY t.apartment_id
    `,
    [
      siteCode,
      timing.period,
      timing.entryDate,
      timing.dueDate,
      definitionId,
      definitionName,
      Number(run.id),
      actorUserCode,
      bigintsToSqlArray(lines.map((line) => BigInt(line.apartmentId))),
      bigintsToSqlArray(lines.map((line) => line.amount)),
      lines.map((line) => line.payerParty),
      // İki hesap (İP-1A): satırın hesabı (önizlemeyle AYNI kuralla kilit altında çözüldü; planHash'e de girer)
      lines.map((line) => line.accountParty ?? (line.payerParty === 'tenant' ? 'tenant' : 'owner')),
      // Kasa (docs/PLATFORM_FINANS_KASALAR.md 2): tanimin "kim oder" degerinden (owner => capital, occupant => operating); tum satirlarda ayni
      fund,
    ],
  );
  if (written.rowCount !== lines.length) {
    throw new Error(`borçlandırma satır sayısı uyuşmuyor (${written.rowCount} / ${lines.length})`);
  }
  return mapRunRow(run);
}

/**
 * İşlem anahtarı daha önce kullanılmışsa: AYNI istek (parmak izi ve tür eşleşir) ise kayıt döner (tekrar), değilse 409 IDEMPOTENCY_CONFLICT
 * (farklı hedef / tutar / dönem, aynı toplam olsa bile sessizce "başarı" dönmez).
 */
async function replayOrConflict(client, siteCode, key, { fingerprint, kind }) {
  const existing = await findRunByKey(client, siteCode, key);
  if (!existing) {
    return null;
  }
  if (existing.request_fingerprint !== fingerprint || existing.definition_kind !== kind) {
    throw idempotencyConflict();
  }
  return {
    replayed: true,
    run: mapRunRow(existing),
    entries_count: Number(existing.apartment_count),
    ...skipSummary(Number(existing.skipped_count), existing.definition_distribution),
  };
}

/** Son 24 saatte AYNI sitede aynı doğal özetli (ad + tutar + dağıtım + hedef + vade) ek borç çalıştırması. */
async function findRecentDuplicate(db, siteCode, naturalKey) {
  const result = await db.query(
    `
      SELECT id, posted_at
      FROM fee_runs
      WHERE site_code = $1 AND natural_key = $2 AND posted_at > NOW() - INTERVAL '24 hours'
      ORDER BY posted_at DESC, id DESC
      LIMIT 1
    `,
    [siteCode, naturalKey],
  );
  return result.rows?.[0] ?? null;
}

const isoOrNull = (value) => (value === null || value === undefined ? null : new Date(value).toISOString());

/**
 * POST definitions/:id/post -> { replayed, run, entries_count, skipped_count, redistributed }.
 * Sıra: tanım (404) -> işlem anahtarı tekrarı -> pasif/süre dışı -> kapalı dönem -> aynı dönem tekrarı -> plan (yeniden hesap) -> eksik veri
 * -> boş plan -> önizleme güncelliği (toplam, sayı, özet) -> yazma. Hata olursa hiçbir şey yazılmaz.
 */
export async function postDefinition({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw definitionNotFound();
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const row = await loadDefinitionRow(client, siteCode, id);
    if (!row) {
      throw definitionNotFound();
    }
    const shape = shapeOfRow(row);
    const input = parsePostInput(body, shape.kind, now);
    const fingerprint = postRequestFingerprint({
      definitionId: id,
      period: input.period,
      dueDate: input.dueDate,
      skipMissing: input.skipMissing,
      decisionId: input.decisionId,
      decisionReason: input.decisionReason,
    });
    // İşlem anahtarı tekrarı EN BAŞTA: ilk istek yazıldıktan sonra tanım pasifleşmiş ya da dönem kapanmış olsa bile yeniden deneme aynı kaydı alır.
    const replay = await replayOrConflict(client, siteCode, input.idempotencyKey, { fingerprint, kind: shape.kind });
    if (replay) {
      return replay;
    }
    if (!shape.isActive) {
      throw definitionInactive();
    }
    if (shape.distribution === 'area') {
      throw areaDefinitionUnusable();
    }
    const resolved = resolveTiming(shape, input, now);
    if (await isPeriodClosed(client, siteCode, resolved.period)) {
      throw periodClosed();
    }
    if (await runExists(client, id, shape.kind === 'recurring' ? resolved.period : null)) {
      throw periodAlreadyPosted();
    }
    // Tahakkuk dayanağı (K2): Fon hesabı borcu için Karar Defteri kaydı (modül açık) ya da gerekçe (modül kapalı) ZORUNLU; plan hesaplanmadan önce (hızlı ret)
    const fund = fundOfChargeParty(shape.chargeParty);
    const decision = await resolveRunDecision(client, { siteCode, fund, decisionId: input.decisionId, decisionReason: input.decisionReason });
    const plan = await computePlan(client, siteCode, shape, { lock: true, onDate: resolved.entryDate });
    verifyPlan(plan, input);
    await lockActorRow(client, actorInfo);
    const run = await writeRun(client, {
      siteCode,
      definitionId: id,
      definitionName: shape.name,
      plan,
      timing: resolved,
      idempotencyKey: input.idempotencyKey,
      requestFingerprint: fingerprint,
      naturalKey: null,
      actorUserCode: actorInfo.userCode,
      fund,
      decision,
    });
    await recordFinanceAudit(client, actor, 'finance.run.posted', siteCode, run.id, {
      definition_id: id,
      period: run.period,
      total_minor: run.total_minor,
      apartment_count: run.apartment_count,
      skipped_missing_count: plan.missing.length,
      ...decisionAuditDetails(decision),
    });
    return { replayed: false, run, entries_count: run.apartment_count, ...skipSummary(plan.missing.length, shape.distribution) };
  });
}

/**
 * POST charges (ek borç) -> { replayed, run, entries_count, skipped_count, redistributed, definition }. TEK işlemde: önizleme doğrulaması + tek seferlik
 * tanım + borçlandırma. Önizleme güncel değilse tanım da OLUŞMAZ (geri alınır). İşlem anahtarı ZORUNLUDUR; aynı anahtar + farklı gövde = 409
 * IDEMPOTENCY_CONFLICT. İstemci anahtarı yeniden üretse bile son 24 saatte aynı ek borç 409 DUPLICATE_CHARGE olur (`allow_duplicate: true` ile aşılır).
 */
export async function postCharge({ siteCode, body, actor, now = new Date() }) {
  const input = parseChargeInput(body, { requireExpected: true, now });
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = chargeRequestFingerprint(input);
  return withFinanceTransaction(siteCode, async (client) => {
    const replay = await replayOrConflict(client, siteCode, input.idempotencyKey, { fingerprint, kind: 'one_time' });
    if (replay) {
      const definition = await loadDefinitionRow(client, siteCode, Number(replay.run.definition_id));
      const [mapped] = await attachTargetLabels(client, siteCode, [mapDefinitionRow(definition)]);
      return { ...replay, definition: mapped };
    }
    await assertTargetBelongsToSite(client, siteCode, input.target);
    const todayIsoDate = today(now);
    const timing = { period: periodOfDate(todayIsoDate), entryDate: todayIsoDate, dueDate: input.dueDate ?? todayIsoDate };
    if (await isPeriodClosed(client, siteCode, timing.period)) {
      throw periodClosed();
    }
    const naturalKey = chargeNaturalKey(input, timing.dueDate);
    if (!input.allowDuplicate) {
      const duplicate = await findRecentDuplicate(client, siteCode, naturalKey);
      if (duplicate) {
        throw duplicateCharge(Number(duplicate.id), isoOrNull(duplicate.posted_at));
      }
    }
    // Tahakkuk dayanağı (K2): Fon hesabı borcu için Karar Defteri kaydı (modül açık) ya da gerekçe (modül kapalı) ZORUNLU; plan hesaplanmadan önce (hızlı ret)
    const fund = fundOfChargeParty(input.chargeParty);
    const decision = await resolveRunDecision(client, { siteCode, fund, decisionId: input.decisionId, decisionReason: input.decisionReason });
    const plan = await computePlan(client, siteCode, input, { lock: true, onDate: timing.entryDate });
    verifyPlan(plan, input);
    const shape = {
      kind: 'one_time',
      name: input.name,
      distribution: input.distribution,
      areaBasis: input.areaBasis,
      amountMinor: input.amountMinor,
      categoryAmounts: input.categoryAmounts,
      dueDay: null,
      startPeriod: timing.period,
      endPeriod: null,
      isActive: true,
      target: input.target,
      chargeParty: input.chargeParty,
    };
    assertDefinitionShape(shape);
    await lockActorRow(client, actorInfo);
    const created = await client.query(
      `
        INSERT INTO fee_definitions (
          site_code, name, kind, distribution, area_basis, amount_minor, category_amounts, due_day, start_period, end_period,
          target_type, target_block_ids, target_apartment_ids, is_active, created_by, charge_party
        )
        VALUES ($1, $2, $3, $4, $5, $6::BIGINT, $7::JSONB, $8, $9::DATE, $10::DATE, $11, $12::BIGINT[], $13::BIGINT[], TRUE, $14, $15)
        RETURNING id
      `,
      [siteCode, ...sqlParamsOfShape(shape), actorInfo.userCode, shape.chargeParty],
    );
    const definitionId = Number(created.rows[0].id);
    const run = await writeRun(client, {
      siteCode,
      definitionId,
      definitionName: input.name,
      plan,
      timing,
      idempotencyKey: input.idempotencyKey,
      requestFingerprint: fingerprint,
      naturalKey,
      actorUserCode: actorInfo.userCode,
      fund,
      decision,
    });
    await recordFinanceAudit(client, actor, 'finance.charge.posted', siteCode, run.id, {
      definition_id: definitionId,
      distribution: input.distribution,
      period: run.period,
      total_minor: run.total_minor,
      apartment_count: run.apartment_count,
      skipped_missing_count: plan.missing.length,
      ...decisionAuditDetails(decision),
    });
    const [definition] = await attachTargetLabels(client, siteCode, [mapDefinitionRow(await loadDefinitionRow(client, siteCode, definitionId))]);
    return { replayed: false, run, entries_count: run.apartment_count, ...skipSummary(plan.missing.length, input.distribution), definition };
  });
}
