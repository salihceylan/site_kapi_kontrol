// Aidat ve Finans (Faz 4a): elle tahsilat, ters kayıt (düzeltme), tahsilat düzeltme ve dönem kapatma.
//
// Sözleşme: docs/PLATFORM_FINANS.md. Defter eklemelidir (append-only): kayıt SİLİNMEZ, DEĞİŞTİRİLMEZ; yanlış kayıt ters kayıtla düzeltilir.
//  - Tüm yazmalar finance_tx.js ile: sites FOR KEY SHARE -> finance_post:<site> advisory kilidi -> apartments (FOR KEY SHARE) -> finans tabloları.
//    Defter satırlarına satır kilidi KONMAZ (değişmezler; tekillik kısmi tekil indekslerle ve advisory kilitle sağlanır): kullanıcı silme
//    (apartments -> users -> ledger SET NULL) ile ters sıra oluşmaz.
//  - İdempotans: `idempotency_key` tekrarı AYNI kaydı döndürür (200); aynı anahtar FARKLI bir işlem için gelirse 409 IDEMPOTENCY_CONFLICT.
//  - Kapalı döneme kayıt eklenemez (409 PERIOD_CLOSED). Ters kayıt AÇIK dönemdedir (bugünün açık ayı; bugünün ayı kapalıysa sonraki açık ay).
//  - Audit `details` yalnız tutar / sayı / dönem / tür içerir: açıklama, neden metni ve kişi adı ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  addMonths,
  apartmentNotFound,
  computeOpenPeriod,
  currentPeriod,
  entryAlreadyReversed,
  entryNotCorrectable,
  entryNotFound,
  entryNotReversible,
  idempotencyConflict,
  mapEntryRow,
  parseCorrectInput,
  parsePaymentInput,
  parsePeriod,
  parseReverseInput,
  periodClosed,
  periodLabel,
  periodNotClosable,
  periodNotReopenable,
  periodOfDate,
  today,
} from './finance_common.js';
import { minorToNumber } from './finance_money.js';
import { recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { parsePositiveId } from './people_common.js';

// ---------------------------------------------------------------------------
// Ortak okumalar
// ---------------------------------------------------------------------------

/** Ekstre satırı (Entry) SELECT'i; çağıran WHERE ekler. */
export const ENTRY_SELECT = `
  SELECT
    l.id, l.apartment_id, l.kind, l.amount_minor::text AS amount_minor, to_char(l.period, 'YYYY-MM-DD') AS period,
    to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date,
    l.description, l.method, l.payer_party, d.name AS definition_name, l.reverses_entry_id, rv.id AS reversed_by_entry_id,
    l.reversal_reason, u.full_name AS created_by_name, l.created_at, l.definition_id, l.run_id, l.idempotency_key
  FROM ledger_entries l
  LEFT JOIN fee_definitions d ON d.id = l.definition_id
  LEFT JOIN ledger_entries rv ON rv.reverses_entry_id = l.id
  LEFT JOIN users u ON u.user_code = l.created_by
`;

async function loadEntryRow(db, siteCode, id) {
  const result = await db.query(`${ENTRY_SELECT} WHERE l.id = $1 AND l.site_code = $2 LIMIT 1`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function loadEntryByKey(db, siteCode, key) {
  const result = await db.query(`${ENTRY_SELECT} WHERE l.site_code = $1 AND l.idempotency_key = $2 LIMIT 1`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** Bir dairenin bakiyesi (kuruş, işaretli toplam; pozitif = borç). */
export async function loadApartmentBalance(db, siteCode, apartmentId) {
  const result = await db.query(
    `SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS balance FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2`,
    [siteCode, apartmentId],
  );
  return minorToNumber(result.rows?.[0]?.balance ?? '0');
}

async function lockApartment(client, siteCode, apartmentId) {
  const result = await client.query(
    `SELECT id, responsible_party FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`,
    [apartmentId, siteCode],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw apartmentNotFound();
  }
  return row;
}

/** Site kapanışları (artan sırada, 'YYYY-MM-DD'). */
async function loadClosures(db, siteCode) {
  const result = await db.query(
    `
      SELECT to_char(c.period, 'YYYY-MM-DD') AS period, c.closed_at, u.full_name AS closed_by_name
      FROM finance_period_closures c
      LEFT JOIN users u ON u.user_code = c.closed_by
      WHERE c.site_code = $1
      ORDER BY c.period
    `,
    [siteCode],
  );
  return result.rows ?? [];
}

const toIsoOrNull = (value) => (value === null || value === undefined ? null : new Date(value).toISOString());

/** GET periods gövdesi: { closed_through, items (yeni -> eski), open_period }. */
export function periodsBody(closures, now = new Date()) {
  const periods = closures.map((row) => row.period);
  const last = periods.length > 0 ? periods[periods.length - 1] : null;
  return {
    closed_through: last === null ? null : periodLabel(last),
    items: [...closures].reverse().map((row) => ({
      period: periodLabel(row.period),
      closed_at: toIsoOrNull(row.closed_at),
      closed_by_name: row.closed_by_name ?? null,
    })),
    open_period: periodLabel(computeOpenPeriod(currentPeriod(now), new Set(periods))),
  };
}

export async function listPeriods(siteCode, now = new Date(), db = pool) {
  return periodsBody(await loadClosures(db, siteCode), now);
}

async function isClosed(db, siteCode, periodIso) {
  const result = await db.query(`SELECT 1 FROM finance_period_closures WHERE site_code = $1 AND period = $2::DATE LIMIT 1`, [siteCode, periodIso]);
  return Boolean(result.rows?.[0]);
}

// ---------------------------------------------------------------------------
// Tahsilat
// ---------------------------------------------------------------------------

/**
 * POST payments -> { replayed, entry, balance_minor }. Tahsilat tutarı pozitif girilir, defterde negatif yazılır. Fazla ödeme alacak olur.
 * Dönem = tahsilat tarihinin ayı; kapalıysa 409 PERIOD_CLOSED. Aynı işlem anahtarı = aynı kayıt.
 */
export async function recordPayment({ siteCode, body, actor, now = new Date() }) {
  const input = parsePaymentInput(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const apartment = await lockApartment(client, siteCode, input.apartmentId);
    const existing = await loadEntryByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      const same =
        existing.kind === 'payment' &&
        Number(existing.apartment_id) === input.apartmentId &&
        BigInt(existing.amount_minor) === -BigInt(input.amountMinor) &&
        existing.entry_date === input.entryDate &&
        existing.method === input.method;
      if (!same) {
        throw idempotencyConflict();
      }
      return { replayed: true, entry: mapEntryRow(existing), balance_minor: await loadApartmentBalance(client, siteCode, input.apartmentId) };
    }
    const period = periodOfDate(input.entryDate);
    if (await isClosed(client, siteCode, period)) {
      throw periodClosed();
    }
    const inserted = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method, description, idempotency_key, created_by
        )
        VALUES ($1, $2, 'payment', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8, $9, $10)
        RETURNING id
      `,
      [
        siteCode,
        input.apartmentId,
        String(-input.amountMinor),
        period,
        input.entryDate,
        apartment.responsible_party,
        input.method,
        input.description,
        input.idempotencyKey,
        actorInfo.userCode,
      ],
    );
    const entryId = Number(inserted.rows[0].id);
    await recordFinanceAudit(client, actor, 'finance.payment.recorded', siteCode, entryId, {
      apartment_id: input.apartmentId,
      amount_minor: input.amountMinor,
      period: periodLabel(period),
      method: input.method,
    });
    return {
      replayed: false,
      entry: mapEntryRow(await loadEntryRow(client, siteCode, entryId)),
      balance_minor: await loadApartmentBalance(client, siteCode, input.apartmentId),
    };
  });
}

// ---------------------------------------------------------------------------
// Ters kayıt ve düzeltme
// ---------------------------------------------------------------------------

/** Bir kaydın apartment_id'sini KİLİTSİZ okur (daire kilidi önce alınsın; kilit sırası apartments -> ledger). */
async function apartmentOfEntry(client, siteCode, entryId) {
  const head = await client.query(`SELECT apartment_id FROM ledger_entries WHERE id = $1 AND site_code = $2`, [entryId, siteCode]);
  if (!head.rows?.[0]) {
    throw entryNotFound();
  }
  return Number(head.rows[0].apartment_id);
}

async function isReversed(client, entryId) {
  const result = await client.query(`SELECT 1 FROM ledger_entries WHERE reverses_entry_id = $1 LIMIT 1`, [entryId]);
  return Boolean(result.rows?.[0]);
}

const isReverseUniqueViolation = (error) => error?.code === '23505' && String(error?.constraint ?? '') === 'uq_ledger_entries_reverses';

/** Karşı işaretli ters kayıt satırını yazar; yeni kaydın kimliğini döndürür. */
async function insertReversal(client, { siteCode, original, openPeriod, todayIsoDate, reason, key, actorUserCode }) {
  try {
    const inserted = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_id, run_id, payer_party,
          reverses_entry_id, reversal_reason, idempotency_key, created_by
        )
        VALUES ($1, $2, 'reversal', $3::BIGINT, $4::DATE, $5::DATE, $6::DATE, $7, $8, $9, $10, $11, $12, $13)
        RETURNING id
      `,
      [
        siteCode,
        Number(original.apartment_id),
        String(-BigInt(original.amount_minor)),
        openPeriod,
        todayIsoDate,
        original.due_date,
        original.definition_id === null ? null : Number(original.definition_id),
        original.run_id === null ? null : Number(original.run_id),
        original.payer_party,
        Number(original.id),
        reason,
        key,
        actorUserCode,
      ],
    );
    return Number(inserted.rows[0].id);
  } catch (error) {
    if (isReverseUniqueViolation(error)) {
      throw entryAlreadyReversed();
    }
    throw error;
  }
}

/** Bugünün açık dönemi (kapalıysa sonraki açık ay). */
async function resolveOpenPeriod(client, siteCode, now) {
  const closures = await loadClosures(client, siteCode);
  return computeOpenPeriod(currentPeriod(now), new Set(closures.map((row) => row.period)));
}

/**
 * POST entries/:id/reverse -> { replayed, entry, balance_minor }. Karşı işaretli `reversal` kaydı; bir kaydın tek ters kaydı olur, ters kaydın tersi yoktur.
 */
export async function reverseEntry({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw entryNotFound();
  }
  const input = parseReverseInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const apartmentId = await apartmentOfEntry(client, siteCode, id);
    await lockApartment(client, siteCode, apartmentId);
    const original = await loadEntryRow(client, siteCode, id);
    if (!original) {
      throw entryNotFound();
    }
    if (input.idempotencyKey !== null) {
      const existing = await loadEntryByKey(client, siteCode, input.idempotencyKey);
      if (existing) {
        if (existing.kind !== 'reversal' || Number(existing.reverses_entry_id) !== id) {
          throw idempotencyConflict();
        }
        return { replayed: true, entry: mapEntryRow(existing), balance_minor: await loadApartmentBalance(client, siteCode, apartmentId) };
      }
    }
    if (original.kind === 'reversal') {
      throw entryNotReversible();
    }
    if (await isReversed(client, id)) {
      throw entryAlreadyReversed();
    }
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const newId = await insertReversal(client, {
      siteCode,
      original,
      openPeriod,
      todayIsoDate: today(now),
      reason: input.reason,
      key: input.idempotencyKey,
      actorUserCode: actorInfo.userCode,
    });
    await recordFinanceAudit(client, actor, 'finance.entry.reversed', siteCode, newId, {
      reversed_entry_id: id,
      reversed_kind: original.kind,
      amount_minor: minorToNumber(-BigInt(original.amount_minor)),
      period: periodLabel(openPeriod),
    });
    return {
      replayed: false,
      entry: mapEntryRow(await loadEntryRow(client, siteCode, newId)),
      balance_minor: await loadApartmentBalance(client, siteCode, apartmentId),
    };
  });
}

/**
 * POST entries/:id/correct (yalnız payment) -> { replayed, reversal, entry, balance_minor }. TEK işlemde ters kayıt + yeni tahsilat; yarım kalmaz.
 */
export async function correctPayment({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw entryNotFound();
  }
  const input = parseCorrectInput(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const apartmentId = await apartmentOfEntry(client, siteCode, id);
    const apartment = await lockApartment(client, siteCode, apartmentId);
    const original = await loadEntryRow(client, siteCode, id);
    if (!original) {
      throw entryNotFound();
    }
    const existing = await loadEntryByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      const reversal = await client.query(`${ENTRY_SELECT} WHERE l.reverses_entry_id = $1 AND l.site_code = $2 LIMIT 1`, [id, siteCode]);
      const same =
        existing.kind === 'payment' &&
        Number(existing.apartment_id) === apartmentId &&
        BigInt(existing.amount_minor) === -BigInt(input.amountMinor) &&
        existing.entry_date === input.entryDate &&
        existing.method === input.method &&
        Boolean(reversal.rows?.[0]);
      if (!same) {
        throw idempotencyConflict();
      }
      return {
        replayed: true,
        reversal: mapEntryRow(reversal.rows[0]),
        entry: mapEntryRow(existing),
        balance_minor: await loadApartmentBalance(client, siteCode, apartmentId),
      };
    }
    if (original.kind === 'reversal') {
      throw entryNotReversible();
    }
    if (original.kind !== 'payment') {
      throw entryNotCorrectable();
    }
    if (await isReversed(client, id)) {
      throw entryAlreadyReversed();
    }
    const newPeriod = periodOfDate(input.entryDate);
    if (await isClosed(client, siteCode, newPeriod)) {
      throw periodClosed();
    }
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const reversalId = await insertReversal(client, {
      siteCode,
      original,
      openPeriod,
      todayIsoDate: today(now),
      reason: 'Tahsilat düzeltmesi',
      key: null,
      actorUserCode: actorInfo.userCode,
    });
    const inserted = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method, description, idempotency_key, created_by
        )
        VALUES ($1, $2, 'payment', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8, $9, $10)
        RETURNING id
      `,
      [
        siteCode,
        apartmentId,
        String(-input.amountMinor),
        newPeriod,
        input.entryDate,
        apartment.responsible_party,
        input.method,
        input.description,
        input.idempotencyKey,
        actorInfo.userCode,
      ],
    );
    const newId = Number(inserted.rows[0].id);
    await recordFinanceAudit(client, actor, 'finance.entry.corrected', siteCode, newId, {
      reversed_entry_id: id,
      reversal_entry_id: reversalId,
      old_amount_minor: minorToNumber(-BigInt(original.amount_minor)),
      new_amount_minor: input.amountMinor,
      period: periodLabel(newPeriod),
    });
    return {
      replayed: false,
      reversal: mapEntryRow(await loadEntryRow(client, siteCode, reversalId)),
      entry: mapEntryRow(await loadEntryRow(client, siteCode, newId)),
      balance_minor: await loadApartmentBalance(client, siteCode, apartmentId),
    };
  });
}

// ---------------------------------------------------------------------------
// Dönem kapatma / yeniden açma
// ---------------------------------------------------------------------------

/**
 * POST periods/:period/close. Dönemler SIRAYLA kapanır: önceki ay kapalı olmalı (siteye ilk kapatmada serbest); gelecek ay kapatılamaz.
 * Hata: 409 PERIOD_NOT_CLOSABLE. Dönüş: GET periods gövdesi.
 */
export async function closePeriod({ siteCode, rawPeriod, actor, now = new Date() }) {
  const period = parsePeriod(rawPeriod);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    if (period > currentPeriod(now)) {
      throw periodNotClosable('Gelecek dönem kapatılamaz.');
    }
    const closures = await loadClosures(client, siteCode);
    const closed = new Set(closures.map((row) => row.period));
    if (closed.has(period)) {
      throw periodNotClosable('Bu dönem zaten kapalı.');
    }
    if (closures.length > 0 && !closed.has(addMonths(period, -1))) {
      throw periodNotClosable('Önce önceki dönemi kapatmalısınız; dönemler sırayla kapanır.');
    }
    await client.query(`INSERT INTO finance_period_closures (site_code, period, closed_by) VALUES ($1, $2::DATE, $3)`, [
      siteCode,
      period,
      actorInfo.userCode,
    ]);
    await recordFinanceAudit(client, actor, 'finance.period.closed', siteCode, periodLabel(period), { period: periodLabel(period) });
    return periodsBody(await loadClosures(client, siteCode), now);
  });
}

/** POST periods/:period/reopen (yalnız süper kullanıcı; rota denetler). Yalnız EN SON kapatılan ay açılır. */
export async function reopenPeriod({ siteCode, rawPeriod, actor, now = new Date() }) {
  const period = parsePeriod(rawPeriod);
  return withFinanceTransaction(siteCode, async (client) => {
    const closures = await loadClosures(client, siteCode);
    if (closures.length === 0) {
      throw periodNotReopenable('Kapalı dönem yok.');
    }
    const latest = closures[closures.length - 1].period;
    if (period !== latest) {
      throw periodNotReopenable('Yalnızca en son kapatılan dönem yeniden açılabilir.');
    }
    await client.query(`DELETE FROM finance_period_closures WHERE site_code = $1 AND period = $2::DATE`, [siteCode, period]);
    await recordFinanceAudit(client, actor, 'finance.period.reopened', siteCode, periodLabel(period), { period: periodLabel(period) });
    return periodsBody(await loadClosures(client, siteCode), now);
  });
}
