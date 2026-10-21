// Banka satırları: liste, özet, daireye atama, toplu onay, mevcut tahsilata bağlama, daire dışı sınıflama ve geri alma.
// Tahsilat YALNIZ postPayment ile yazılır; gider/düzeltme/aktarım mevcut işlevlerle ve 'bl:<satır>:*' anahtarlarıyla (tekrar güvenli).
import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { createExpense, voidExpense } from './finance_expenses.js';
import { createAdjustment, createTransfer, voidTransfer } from './finance_accounts.js';
import { postPayment } from './finance_parties.js';
import { recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel } from './people_common.js';
import { findExistingPayments } from './bank_import_service.js';
import { CLASSIFY_KINDS, LINE_STATUSES, invalid, lineNotFound, lineNotOpen } from './bank_import_common.js';
import { normalizeIban } from './bank_line_match.js';

const num = (v) => Number(v);
const idOf = (raw, make = lineNotFound) => {
  const id = num(raw);
  if (!Number.isSafeInteger(id) || id <= 0) throw make();
  return id;
};

const SELECT_LINE = `
  SELECT l.id, l.import_id, l.account_id, l.line_no, to_char(l.value_date, 'YYYY-MM-DD') AS value_date, l.amount_minor::TEXT AS amount_minor, l.description,
         l.counterparty_name, l.counterparty_iban, l.bank_reference, l.status, l.match_method, l.suggested_apartment_id, l.suggested_party, l.ledger_entry_id,
         l.expense_id, l.movement_id, l.transfer_id, l.classification, l.note, a.unit_label, b.block_name
    FROM bank_statement_lines l
    LEFT JOIN apartments a ON a.id = l.suggested_apartment_id
    LEFT JOIN site_blocks b ON b.id = a.block_id`;

const lineDto = (r) => ({
  id: num(r.id),
  import_id: num(r.import_id),
  account_id: num(r.account_id),
  line_no: r.line_no,
  value_date: r.value_date,
  amount_minor: num(r.amount_minor),
  description: r.description,
  counterparty_name: r.counterparty_name,
  counterparty_iban: r.counterparty_iban,
  bank_reference: r.bank_reference,
  status: r.status,
  match_method: r.match_method,
  apartment_id: r.suggested_apartment_id === null ? null : num(r.suggested_apartment_id),
  apartment_label: r.suggested_apartment_id === null ? null : apartmentLabel(r.block_name, r.unit_label),
  party: r.suggested_party,
  ledger_entry_id: r.ledger_entry_id === null ? null : num(r.ledger_entry_id),
  classification: r.classification,
  note: r.note,
});

async function loadLine(db, siteCode, id, { lock = false } = {}) {
  const r = await db.query(`${SELECT_LINE} WHERE l.id = $1 AND l.site_code = $2${lock ? ' FOR UPDATE OF l' : ''}`, [id, siteCode]);
  if (!r.rows?.[0]) throw lineNotFound();
  return r.rows[0];
}

export async function listLines(siteCode, query = {}) {
  const status = query.status === undefined || query.status === '' ? null : String(query.status);
  const wanted = status === 'attention' ? ['unmatched', 'suggested'] : status === 'done' ? ['classified', 'ignored'] : status ? [status] : null;
  if (wanted && !wanted.every((s) => LINE_STATUSES.includes(s))) throw invalid('Durum geçersiz.');
  const importId = query.import_id === undefined ? null : idOf(query.import_id, () => invalid('Yükleme geçersiz.'));
  const limit = Math.min(Math.max(num(query.limit) || 100, 1), 200);
  const offset = Math.min(Math.max(num(query.offset) || 0, 0), 100000);
  const r = await pool.query(
    `${SELECT_LINE}
      JOIN bank_imports i ON i.id = l.import_id
     WHERE l.site_code = $1 AND ($2::TEXT[] IS NULL OR l.status = ANY($2::TEXT[])) AND ($3::BIGINT IS NULL OR l.import_id = $3::BIGINT) AND i.status = 'active'
     ORDER BY l.value_date, l.id LIMIT $4 OFFSET $5`,
    [siteCode, wanted, importId, limit, offset],
  );
  return { lines: (r.rows ?? []).map(lineDto) };
}

export async function linesSummary(siteCode) {
  const r = await pool.query(
    `SELECT l.status, COUNT(*)::INT AS count FROM bank_statement_lines l JOIN bank_imports i ON i.id = l.import_id
      WHERE l.site_code = $1 AND i.status = 'active' GROUP BY l.status`,
    [siteCode],
  );
  const by = Object.fromEntries((r.rows ?? []).map((x) => [x.status, x.count]));
  return { by_status: by, attention: (by.unmatched ?? 0) + (by.suggested ?? 0) };
}

async function assertApartment(db, siteCode, apartmentId) {
  const r = await db.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2`, [apartmentId, siteCode]);
  if (!r.rows?.[0]) throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
}

const partyOf = (value) => {
  if (value === undefined || value === null || value === '') return null;
  if (value !== 'owner' && value !== 'tenant') throw invalid('Hesap (malik veya kiracı) geçersiz.');
  return value;
};

/** Tek satırı daireye işler (mevcut tahsilat varsa ona bağlar). Çağıran finans işlemi içindedir; satır kilitlidir. */
async function settleToApartment(client, { siteCode, line, apartmentId, party, saveIban, actor, now }) {
  if (!['unmatched', 'suggested'].includes(line.status) || num(line.amount_minor) <= 0) throw lineNotOpen();
  await assertApartment(client, siteCode, apartmentId);
  const amount = num(line.amount_minor);
  const found = await findExistingPayments(client, siteCode, { apartmentId, accountId: num(line.account_id), amountMinor: amount, valueDate: line.value_date });
  let status = 'linked';
  let entryId = found.length === 1 ? found[0] : null;
  if (found.length > 1) throw new PlatformError(409, 'LINK_AMBIGUOUS', 'Birden çok benzer tahsilat var; "Mevcut tahsilata bağla" ile birini seçin.');
  if (entryId === null) {
    const res = await postPayment(client, {
      siteCode,
      apartmentId,
      accountParty: party,
      amountMinor: amount,
      paidOn: line.value_date,
      method: 'transfer',
      description: `Banka: ${line.description}`.slice(0, 200),
      sourceKind: 'bank_line',
      sourceId: num(line.id),
      idempotencyKey: `bl:${line.id}`,
      actor,
      cashAccountId: num(line.account_id),
      now,
    });
    entryId = res.entryId;
    status = 'posted';
  }
  const actorInfo = actorFromAuthUser(actor);
  await client.query(
    `UPDATE bank_statement_lines SET status = $2, ledger_entry_id = $3, suggested_apartment_id = $4, suggested_party = $5, note = NULL, decided_by = $6, decided_at = NOW() WHERE id = $1`,
    [line.id, status, entryId, apartmentId, party, actorInfo.userCode],
  );
  const iban = normalizeIban(line.counterparty_iban);
  if (saveIban && iban) {
    await client.query(
      `INSERT INTO bank_payer_ibans (site_code, iban, apartment_id, account_party, created_import_id, use_count, last_used_at) VALUES ($1,$2,$3,$4,$5,1,NOW())
       ON CONFLICT (site_code, iban, apartment_id) DO UPDATE SET account_party = EXCLUDED.account_party, use_count = bank_payer_ibans.use_count + 1, last_used_at = NOW()`,
      [siteCode, iban, apartmentId, party, num(line.import_id)],
    );
  }
  await recordFinanceAudit(client, actor, 'finance.bank_line.assigned', siteCode, line.id, { apartment_id: apartmentId, status, save_iban: Boolean(saveIban && iban) });
  return status;
}

export async function assignLine({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = idOf(rawId);
  const apartmentId = idOf(body?.apartment_id, () => invalid('Daire seçimi geçersiz.'));
  const party = partyOf(body?.account_party);
  return withFinanceTransaction(siteCode, async (client) => {
    const line = await loadLine(client, siteCode, id, { lock: true });
    const status = await settleToApartment(client, { siteCode, line, apartmentId, party, saveIban: body?.save_iban === true, actor, now });
    return { line: lineDto(await loadLine(client, siteCode, id)), status };
  });
}

/** Önerilen daireyi onaylar (tek ya da toplu; en çok 200). Her satır kendi savepoint'inde: biri hata verirse diğerleri işlenir. */
export async function confirmLines({ siteCode, body, actor, now = new Date() }) {
  const ids = Array.isArray(body?.line_ids) ? [...new Set(body.line_ids.map(num))] : [];
  if (ids.length === 0 || ids.length > 200 || ids.some((x) => !Number.isSafeInteger(x) || x <= 0)) throw invalid('Satır listesi geçersiz (en çok 200).');
  ids.sort((a, b) => a - b);
  return withFinanceTransaction(siteCode, async (client) => {
    const done = [];
    const failed = [];
    for (const id of ids) {
      await client.query('SAVEPOINT bl_confirm');
      try {
        const line = await loadLine(client, siteCode, id, { lock: true });
        if (line.status !== 'suggested' || line.suggested_apartment_id === null) throw lineNotOpen();
        await settleToApartment(client, { siteCode, line, apartmentId: num(line.suggested_apartment_id), party: line.suggested_party, saveIban: false, actor, now });
        await client.query('RELEASE SAVEPOINT bl_confirm');
        done.push(id);
      } catch (error) {
        await client.query('ROLLBACK TO SAVEPOINT bl_confirm');
        if (!(error instanceof PlatformError)) throw error;
        failed.push({ id, code: error.code });
      }
    }
    return { done, failed };
  });
}

export async function linkLine({ siteCode, rawId, body, actor }) {
  const id = idOf(rawId);
  const entryId = idOf(body?.ledger_entry_id, () => invalid('Tahsilat seçimi geçersiz.'));
  return withFinanceTransaction(siteCode, async (client) => {
    const line = await loadLine(client, siteCode, id, { lock: true });
    if (!['unmatched', 'suggested'].includes(line.status) || num(line.amount_minor) <= 0) throw lineNotOpen();
    const e = await client.query(
      `SELECT l.id, l.apartment_id FROM ledger_entries l
        WHERE l.id = $1 AND l.site_code = $2 AND l.kind = 'payment' AND l.amount_minor = $3::BIGINT
          AND NOT EXISTS (SELECT 1 FROM ledger_entries x WHERE x.reverses_entry_id = l.id)
          AND NOT EXISTS (SELECT 1 FROM bank_statement_lines b WHERE b.ledger_entry_id = l.id AND b.status IN ('posted', 'linked'))`,
      [entryId, siteCode, String(-num(line.amount_minor))],
    );
    if (!e.rows?.[0]) throw new PlatformError(409, 'LINK_NOT_POSSIBLE', 'Bu tahsilat bağlanamaz (tutar uyuşmuyor, iptal edilmiş ya da başka satıra bağlı).');
    const actorInfo = actorFromAuthUser(actor);
    await client.query(
      `UPDATE bank_statement_lines SET status = 'linked', ledger_entry_id = $2, suggested_apartment_id = $3, decided_by = $4, decided_at = NOW() WHERE id = $1`,
      [id, entryId, num(e.rows[0].apartment_id), actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.bank_line.linked', siteCode, id, { ledger_entry_id: entryId });
    return { line: lineDto(await loadLine(client, siteCode, id)) };
  });
}

// --- Daire dışı satırlar ------------------------------------------------------------------------------------

export async function classifyLine({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = idOf(rawId);
  const kind = body?.kind;
  if (!CLASSIFY_KINDS.includes(kind)) throw invalid('Sınıf geçersiz.');
  const line = await loadLine(pool, siteCode, id);
  if (!['unmatched', 'suggested'].includes(line.status)) throw lineNotOpen();
  const amount = num(line.amount_minor);
  const abs = Math.abs(amount);
  const incoming = amount > 0;
  const accountId = num(line.account_id);
  const note = body?.note ? String(body.note).slice(0, 200) : null;
  const text = (line.description || 'Banka satırı').slice(0, 200);
  const set = { classification: kind, expense_id: null, movement_id: null, transfer_id: null, status: kind === 'ignore' ? 'ignored' : 'classified' };
  if (kind === 'expense') {
    if (incoming) throw invalid('Gider yalnız çıkan para için seçilebilir.');
    const res = await createExpense({
      siteCode,
      actor,
      now,
      body: {
        category_id: body?.category_id,
        supplier_id: body?.supplier_id ?? null,
        description: note || text,
        amount_minor: abs,
        expense_date: line.value_date,
        account_id: accountId,
        document_kind: 'none',
        idempotency_key: `bl:${id}:exp`,
      },
    });
    set.expense_id = res.expense.id;
  } else if (kind === 'bank_fee' || kind === 'interest' || kind === 'other_income') {
    if ((kind === 'bank_fee') === incoming) throw invalid(kind === 'bank_fee' ? 'Banka masrafı yalnız çıkan para için seçilebilir.' : 'Bu sınıf yalnız giren para için seçilebilir.');
    const reason = { bank_fee: 'bank_fee', interest: 'bank_interest', other_income: 'other' }[kind];
    const res = await createAdjustment({
      siteCode,
      rawId: accountId,
      actor,
      now,
      body: { amount_minor: amount, reason_code: reason, movement_date: line.value_date, note: note || (kind === 'other_income' ? text : null), idempotency_key: `bl:${id}:adj` },
    });
    set.movement_id = res.movement.id;
  } else if (kind === 'transfer') {
    const other = idOf(body?.transfer_account_id, () => invalid('Diğer hesap seçimi geçersiz.'));
    const res = await createTransfer({
      siteCode,
      actor,
      now,
      body: {
        from_account_id: incoming ? other : accountId,
        to_account_id: incoming ? accountId : other,
        transfer_date: line.value_date,
        amount_minor: abs,
        description: note || text,
        idempotency_key: `bl:${id}:tr`,
      },
    });
    set.transfer_id = res.transfer.id;
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const r = await client.query(
      `UPDATE bank_statement_lines SET status = $2, classification = $3, expense_id = $4, movement_id = $5, transfer_id = $6, note = $7, decided_by = $8, decided_at = NOW()
        WHERE id = $1 AND site_code = $9 AND status IN ('unmatched', 'suggested')`,
      [id, set.status, set.classification, set.expense_id, set.movement_id, set.transfer_id, note, actorInfo.userCode, siteCode],
    );
    if (!r.rowCount) {
      // eşzamanlı aynı istek: anahtarlar aynı kaydı döndürdü; güncel durumu ver
      return { line: lineDto(await loadLine(client, siteCode, id)) };
    }
    await recordFinanceAudit(client, actor, 'finance.bank_line.classified', siteCode, id, { kind });
    return { line: lineDto(await loadLine(client, siteCode, id)) };
  });
}

export async function unclassifyLine({ siteCode, rawId, actor, now = new Date() }) {
  const id = idOf(rawId);
  const line = await loadLine(pool, siteCode, id);
  if (!['classified', 'ignored'].includes(line.status)) throw lineNotOpen();
  const reason = 'Banka satırı sınıflaması geri alındı';
  if (line.classification === 'expense') {
    await voidExpense({ siteCode, rawId: line.expense_id, actor, now, body: { reason, idempotency_key: `bl:${id}:unexp` } });
  } else if (line.classification === 'transfer') {
    await voidTransfer({ siteCode, rawId: line.transfer_id, actor, now, body: { reason, idempotency_key: `bl:${id}:untr` } });
  } else if (['bank_fee', 'interest', 'other_income'].includes(line.classification)) {
    const reasonCode = { bank_fee: 'bank_fee', interest: 'bank_interest', other_income: 'other' }[line.classification];
    // Düzeltme hareketinin silinmesi yok: aynı nedenle TERS işaretli yeni hareket (bugünün tarihiyle).
    await createAdjustment({
      siteCode,
      rawId: num(line.account_id),
      actor,
      now,
      body: { amount_minor: -num(line.amount_minor), reason_code: reasonCode, movement_date: now.toISOString().slice(0, 10), note: reasonCode === 'other' ? 'Banka satırı geri alındı' : null, idempotency_key: `bl:${id}:undo` },
    });
  }
  return withFinanceTransaction(siteCode, async (client) => {
    await client.query(
      `UPDATE bank_statement_lines SET status = 'unmatched', classification = NULL, expense_id = NULL, movement_id = NULL, transfer_id = NULL, decided_at = NOW() WHERE id = $1 AND site_code = $2`,
      [id, siteCode],
    );
    await recordFinanceAudit(client, actor, 'finance.bank_line.unclassified', siteCode, id, { was: line.classification });
    return { line: lineDto(await loadLine(client, siteCode, id)) };
  });
}
