// Banka dosyası içe aktarma: profil, önizleme, yükleme (commit), geri alma, IBAN hafızası, dikkat sayacı. Sözleşme: docs/PLATFORM_FINANS_BANKA.md.
// Dosya İSTEMCİDE ayrıştırılır (Karar C); sunucuya yalnız satırlar + dosya adı/boyutu/sha256 gelir, ham dosya saklanmaz.
// Tahsilat YALNIZ finance_parties.postPayment ile yazılır (sourceKind 'bank_line', anahtar 'bl:<satır>'). Defter eklemelidir: geri alma ters kayıtladır.
import { createHash } from 'node:crypto';
import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { registerAttentionSource } from './attention_registry.js';
import { PlatformError } from './errors.js';
import { reverseEntry } from './finance_ledger_service.js';
import { postPayment } from './finance_parties.js';
import { periodOfDate, today } from './finance_common.js';
import { isPeriodClosed, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel } from './people_common.js';
import { computeFingerprints, matchLine, normalizeIban, outcomeOf, previewHash, summarize } from './bank_line_match.js';
import { buildUnitIndex, periodHintOf } from './bank_match_hints.js';
import {
  MAX_AUTO_POST,
  accountNotFound,
  alreadyReverted,
  fileAlreadyImported,
  hasClassified,
  importNotFound,
  invalid,
  parseProfileBody,
  parseStatementBody,
  previewStale,
} from './bank_import_common.js';

const norm = (text) => String(text ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
const num = (value) => Number(value);

// --- Hesap ve profil --------------------------------------------------------------------------------------

export async function loadBankAccount(db, siteCode, accountId) {
  const r = await db.query(`SELECT id, name, kind, is_active FROM finance_accounts WHERE id = $1 AND site_code = $2`, [accountId, siteCode]);
  const row = r.rows?.[0];
  if (!row) throw accountNotFound();
  if (row.kind !== 'bank' || row.is_active !== true) throw invalid('Etkin bir banka hesabı seçin.');
  return row;
}

export async function getProfile(siteCode, rawAccountId) {
  const id = num(rawAccountId);
  if (!Number.isSafeInteger(id) || id <= 0) throw accountNotFound();
  const acc = await pool.query(`SELECT id FROM finance_accounts WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!acc.rows?.[0]) throw accountNotFound();
  const r = await pool.query(
    `SELECT format, header_signature, mapping, options, profile_version, updated_at FROM bank_import_profiles WHERE account_id = $1 AND site_code = $2`,
    [id, siteCode],
  );
  return { profile: r.rows?.[0] ?? null };
}

export async function putProfile({ siteCode, rawAccountId, body, actor }) {
  const id = num(rawAccountId);
  if (!Number.isSafeInteger(id) || id <= 0) throw accountNotFound();
  const input = parseProfileBody(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const acc = await client.query(`SELECT id FROM finance_accounts WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    if (!acc.rows?.[0]) throw accountNotFound();
    const r = await client.query(
      `INSERT INTO bank_import_profiles (account_id, site_code, format, header_signature, mapping, options, updated_by)
       VALUES ($1, $2, $3, $4, $5::JSONB, $6::JSONB, $7)
       ON CONFLICT (account_id) DO UPDATE SET format = EXCLUDED.format, header_signature = EXCLUDED.header_signature, mapping = EXCLUDED.mapping,
         options = EXCLUDED.options, profile_version = bank_import_profiles.profile_version + 1, updated_by = EXCLUDED.updated_by, updated_at = NOW()
       RETURNING format, header_signature, mapping, options, profile_version, updated_at`,
      [id, siteCode, input.format, input.signature, JSON.stringify(input.mapping), JSON.stringify(input.options), actorInfo.userCode],
    );
    return { profile: r.rows[0] };
  });
}

// --- Çözümleme (önizleme ve commit ortak) -----------------------------------------------------------------

async function loadContext(db, siteCode) {
  const [prefixes, codes, ibans, people, apartments] = await Promise.all([
    db.query(`SELECT prefix, site_code FROM finance_site_ref_prefixes WHERE site_code = $1`, [siteCode]),
    db.query(`SELECT code, apartment_id, site_code FROM finance_apartment_ref_codes WHERE site_code = $1`, [siteCode]),
    db.query(
      `SELECT b.iban, b.apartment_id, b.account_party,
              EXISTS (SELECT 1 FROM apartment_residencies r WHERE r.apartment_id = b.apartment_id AND r.is_current AND r.created_at > b.created_at) AS stale
       FROM bank_payer_ibans b WHERE b.site_code = $1`,
      [siteCode],
    ),
    db.query(
      `SELECT r.apartment_id, r.relation, p.full_name FROM apartment_residencies r JOIN site_people p ON p.id = r.person_id
       WHERE r.site_code = $1 AND r.is_current AND r.relation IN ('owner', 'tenant') AND p.full_name IS NOT NULL`,
      [siteCode],
    ),
    db.query(`SELECT a.id AS apartment_id, a.unit_label, b.block_name FROM apartments a JOIN site_blocks b ON b.id = a.block_id WHERE a.site_code = $1 AND a.is_active`, [siteCode]),
  ]);
  const ibanMap = new Map();
  for (const row of ibans.rows ?? []) {
    if (!ibanMap.has(row.iban)) ibanMap.set(row.iban, []);
    ibanMap.get(row.iban).push({ apartment_id: num(row.apartment_id), party: row.account_party, stale: row.stale === true });
  }
  return {
    refKnown: {
      prefixes: (prefixes.rows ?? []).map((r) => ({ prefix: r.prefix, site_code: num(r.site_code) })),
      codes: (codes.rows ?? []).map((r) => ({ site_code: num(r.site_code), code: r.code, apartment_id: num(r.apartment_id) })),
    },
    codes: (codes.rows ?? []).map((r) => ({ code: r.code, apartment_id: num(r.apartment_id) })),
    ibans: ibanMap,
    people: (people.rows ?? []).map((r) => ({
      apartment_id: num(r.apartment_id),
      party: r.relation,
      tokens: new Set(norm(r.full_name).split(' ').filter((t) => t.length >= 2)),
    })),
    unitIndex: buildUnitIndex(apartments.rows ?? []),
  };
}

/** Aynı daire + hesap + tutar, valörden 5 gün önce - 2 gün sonra, ters kaydı ve başka bağı olmayan tahsilatlar. */
export async function findExistingPayments(db, siteCode, { apartmentId, accountId, amountMinor, valueDate, exclude = [] }) {
  const r = await db.query(
    `SELECT l.id FROM ledger_entries l
       JOIN account_movements m ON m.ledger_entry_id = l.id AND m.kind = 'collection' AND m.account_id = $3
      WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.kind = 'payment' AND l.amount_minor = $4::BIGINT
        AND l.entry_date BETWEEN ($5::DATE - 5) AND ($5::DATE + 2)
        AND NOT EXISTS (SELECT 1 FROM ledger_entries x WHERE x.reverses_entry_id = l.id)
        AND NOT EXISTS (SELECT 1 FROM bank_statement_lines b WHERE b.ledger_entry_id = l.id AND b.status IN ('posted', 'linked'))
        AND NOT (l.id = ANY($6::BIGINT[]))
      ORDER BY l.id`,
    [siteCode, apartmentId, accountId, String(-amountMinor), valueDate, exclude],
  );
  return (r.rows ?? []).map((x) => num(x.id));
}

async function analyze(db, siteCode, input, now) {
  const account = await loadBankAccount(db, siteCode, input.accountId);
  const ctx = await loadContext(db, siteCode);
  const fingerprints = computeFingerprints(input.accountId, input.lines);
  const dup = await db.query(
    `SELECT fingerprint FROM bank_statement_lines WHERE account_id = $1 AND fingerprint = ANY($2::TEXT[]) AND status <> 'reverted'`,
    [input.accountId, fingerprints],
  );
  const known = new Set((dup.rows ?? []).map((r) => r.fingerprint));
  const closed = new Map();
  const claimed = [];
  const rows = [];
  for (let i = 0; i < input.lines.length; i += 1) {
    const line = input.lines[i];
    const fingerprint = fingerprints[i];
    const duplicate = known.has(fingerprint);
    const warnings = [];
    let match = duplicate ? null : matchLine(line, ctx);
    // PDF'den okunan, güveni düşük satır otomatik işlenmez: güçlü eşleşme bile "kontrol edin"e düşer.
    if (match && match.strength === 'strong' && line.confidence === 'low') {
      match = { ...match, strength: 'weak' };
      warnings.push('LOW_CONFIDENCE');
    }
    let linkedEntryId = null;
    let ambiguousLink = false;
    if (match && match.strength === 'strong') {
      const found = await findExistingPayments(db, siteCode, {
        apartmentId: match.apartmentId,
        accountId: input.accountId,
        amountMinor: line.amount_minor,
        valueDate: line.value_date,
        exclude: claimed,
      });
      if (found.length === 1) {
        linkedEntryId = found[0];
        claimed.push(found[0]);
      } else if (found.length > 1) {
        ambiguousLink = true;
        warnings.push('LINK_AMBIGUOUS');
      }
    }
    if (match && match.strength === 'strong' && !linkedEntryId && !ambiguousLink) {
      const period = periodOfDate(line.value_date);
      if (!closed.has(period)) closed.set(period, await isPeriodClosed(db, siteCode, period));
      if (closed.get(period)) {
        warnings.push('PERIOD_CLOSED');
        ambiguousLink = true; // kontrol bölümüne düşer
      }
    }
    rows.push({ ...line, fingerprint, match, linkedEntryId, warnings, outcome: outcomeOf({ line, duplicate, match, linkedEntryId, ambiguousLink }) });
  }
  const warnings = [];
  const file = await db.query(`SELECT id FROM bank_imports WHERE account_id = $1 AND file_sha256 = $2 AND status = 'active'`, [input.accountId, input.file.sha256]);
  if (file.rows?.[0]) warnings.push('FILE_ALREADY_IMPORTED');
  if (input.statement.accountIban) {
    const det = await db.query(`SELECT iban FROM finance_account_bank_details WHERE account_id = $1 ORDER BY id DESC LIMIT 1`, [input.accountId]);
    if (det.rows?.[0] && normalizeIban(det.rows[0].iban) !== input.statement.accountIban) warnings.push('ACCOUNT_IBAN_MISMATCH');
  }
  if (input.lines.every((l) => l.balance_after_minor !== null) && input.lines.length > 1) {
    let gaps = 0;
    for (let i = 1; i < input.lines.length; i += 1) {
      const a = input.lines[i - 1];
      const b = input.lines[i];
      if (a.balance_after_minor + b.amount_minor !== b.balance_after_minor && b.balance_after_minor + a.amount_minor !== a.balance_after_minor) gaps += 1;
    }
    if (gaps > 0) warnings.push('BALANCE_GAP');
  }
  const duplicates = rows.filter((r) => r.outcome === 'duplicate').length;
  if (duplicates > 0) warnings.push('OVERLAP');
  return { account, rows, warnings, summary: summarize(rows), hash: previewHash(input.file.sha256, input.accountId, rows), now };
}

async function labelsOf(db, siteCode, ids) {
  const unique = [...new Set(ids.filter((x) => x))];
  if (unique.length === 0) return new Map();
  const r = await db.query(
    `SELECT a.id, a.unit_label, b.block_name FROM apartments a JOIN site_blocks b ON b.id = a.block_id WHERE a.site_code = $1 AND a.id = ANY($2::BIGINT[])`,
    [siteCode, unique],
  );
  return new Map((r.rows ?? []).map((x) => [num(x.id), apartmentLabel(x.block_name, x.unit_label)]));
}

export async function previewImport({ siteCode, body, now = new Date() }) {
  const input = parseStatementBody(body, { todayIso: today(now) });
  const result = await analyze(pool, siteCode, input, now);
  const labels = await labelsOf(pool, siteCode, result.rows.map((r) => r.match?.apartmentId));
  return {
    preview_hash: result.hash,
    summary: result.summary,
    warnings: result.warnings,
    lines: result.rows.map((r) => ({
      n: r.n,
      outcome: r.outcome,
      match: r.match ? { method: r.match.method, apartment_id: r.match.apartmentId, apartment_label: labels.get(r.match.apartmentId) ?? null, party: r.match.party } : null,
      linked_entry_id: r.linkedEntryId,
      warnings: r.warnings,
      period_hint: periodHintOf(r.description, r.value_date),
    })),
  };
}

// --- Yükleme ----------------------------------------------------------------------------------------------

const requestFingerprint = (input) => createHash('sha256').update(JSON.stringify([input.accountId, input.file.sha256, input.expectedHash])).digest('hex');

function importDto(row) {
  return {
    id: num(row.id),
    account_id: num(row.account_id),
    account_name: row.account_name ?? undefined,
    format: row.format,
    file_name: row.file_name,
    line_count: row.line_count,
    duplicate_count: row.duplicate_count,
    status: row.status,
    statement_from: row.statement_from ? String(row.statement_from).slice(0, 10) : null,
    statement_to: row.statement_to ? String(row.statement_to).slice(0, 10) : null,
    created_at: row.created_at,
    reverted_at: row.reverted_at ?? null,
  };
}

export async function commitImport({ siteCode, body, actor, now = new Date() }) {
  const input = parseStatementBody(body, { commit: true, todayIso: today(now) });
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = requestFingerprint(input);
  return withFinanceTransaction(siteCode, async (client) => {
    const existing = await client.query(`SELECT * FROM bank_imports WHERE site_code = $1 AND idempotency_key = $2`, [siteCode, input.idempotencyKey]);
    if (existing.rows?.[0]) {
      if (existing.rows[0].request_fingerprint !== fingerprint) throw new PlatformError(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı başka bir yükleme için kullanılmış.');
      return { status: 200, body: { replayed: true, import: importDto(existing.rows[0]) } };
    }
    const result = await analyze(client, siteCode, input, now);
    if (result.warnings.includes('FILE_ALREADY_IMPORTED')) throw fileAlreadyImported();
    if (result.hash !== input.expectedHash) throw previewStale();
    const rows = result.rows.filter((r) => r.outcome !== 'duplicate');
    if (rows.length === 0) throw invalid('Yüklenecek yeni satır yok; tüm satırlar daha önce işlenmiş.');
    const idRes = await client.query(`SELECT nextval(pg_get_serial_sequence('bank_statement_lines', 'id')) AS id FROM generate_series(1, $1::INT)`, [rows.length]);
    rows.forEach((r, i) => {
      r.id = num(idRes.rows[i].id);
      r.status = r.outcome === 'check' ? 'suggested' : 'unmatched';
      r.note = r.warnings.includes('PERIOD_CLOSED') ? 'PERIOD_CLOSED' : null;
      r.entryId = null;
    });
    // tanınanlar daire sırasıyla işlenir; kayıt başına en çok MAX_AUTO_POST
    const toPost = rows.filter((r) => r.outcome === 'recognized').sort((a, b) => a.match.apartmentId - b.match.apartmentId || a.n - b.n);
    let posted = 0;
    for (const r of toPost) {
      if (posted >= MAX_AUTO_POST) {
        r.status = 'suggested';
        r.note = 'LIMIT';
        continue;
      }
      await client.query('SAVEPOINT bl_post');
      try {
        const res = await postPayment(client, {
          siteCode,
          apartmentId: r.match.apartmentId,
          accountParty: r.match.party ?? null,
          amountMinor: r.amount_minor,
          paidOn: r.value_date,
          method: 'transfer',
          description: `Banka: ${r.description}`.slice(0, 200),
          sourceKind: 'bank_line',
          sourceId: r.id,
          idempotencyKey: `bl:${r.id}`,
          actor,
          cashAccountId: input.accountId,
          now,
        });
        await client.query('RELEASE SAVEPOINT bl_post');
        r.status = 'posted';
        r.entryId = res.entryId;
        posted += 1;
      } catch (error) {
        await client.query('ROLLBACK TO SAVEPOINT bl_post');
        if (!(error instanceof PlatformError)) throw error;
        r.status = 'suggested';
        r.note = error.code;
      }
    }
    for (const r of rows) {
      if (r.outcome === 'linked') {
        r.status = 'linked';
        r.entryId = r.linkedEntryId;
      }
    }
    const imp = await client.query(
      `INSERT INTO bank_imports (site_code, account_id, format, file_name, file_size, file_sha256, statement_from, statement_to, file_account_iban,
                                 line_count, duplicate_count, idempotency_key, request_fingerprint, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING *`,
      [siteCode, input.accountId, input.format, input.file.name, input.file.size, input.file.sha256, input.statement.from, input.statement.to, input.statement.accountIban,
       rows.length, result.rows.length - rows.length, input.idempotencyKey, fingerprint, actorInfo.userCode],
    );
    const importId = num(imp.rows[0].id);
    for (const r of rows) {
      await client.query(
        `INSERT INTO bank_statement_lines (id, import_id, site_code, account_id, line_no, value_date, amount_minor, description, counterparty_name, counterparty_iban,
                                           bank_reference, balance_after_minor, fingerprint, status, match_method, suggested_apartment_id, suggested_party, ledger_entry_id, note)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)`,
        [r.id, importId, siteCode, input.accountId, r.n, r.value_date, String(r.amount_minor), r.description, r.counterparty_name, r.counterparty_iban, r.bank_reference,
         r.balance_after_minor === null ? null : String(r.balance_after_minor), r.fingerprint, r.status, r.match?.method ?? null, r.match?.apartmentId ?? null,
         r.match?.party ?? null, r.entryId, r.note],
      );
    }
    await recordFinanceAudit(client, actor, 'finance.bank_import.created', siteCode, importId, { account_id: input.accountId, lines: rows.length, posted, format: input.format });
    const counts = { posted, linked: rows.filter((r) => r.status === 'linked').length, attention: rows.filter((r) => r.status === 'suggested' || r.status === 'unmatched').length };
    return { status: 201, body: { replayed: false, import: importDto(imp.rows[0]), counts } };
  });
}

export async function listImports(siteCode) {
  const r = await pool.query(
    `SELECT i.*, a.name AS account_name FROM bank_imports i JOIN finance_accounts a ON a.id = i.account_id WHERE i.site_code = $1 ORDER BY i.id DESC LIMIT 100`,
    [siteCode],
  );
  return { imports: (r.rows ?? []).map(importDto) };
}

/**
 * Geri alma: işlenmiş satırlar ters kayıtla (makbuz iptali ve hareket aynası reverseEntry içinde), bağlar çözülür, bu yüklemenin IBAN kayıtları silinir.
 * Her ters kayıt kendi finans işleminde ve anahtarlıdır ('blrev:<satır>'); yarıda kalırsa AYNI çağrı kaldığı yerden sürer.
 */
export async function revertImport({ siteCode, rawId, body, actor }) {
  const id = num(rawId);
  if (!Number.isSafeInteger(id) || id <= 0) throw importNotFound();
  const imp = await pool.query(`SELECT id, status FROM bank_imports WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!imp.rows?.[0]) throw importNotFound();
  if (imp.rows[0].status === 'reverted') throw alreadyReverted();
  const classified = await pool.query(`SELECT 1 FROM bank_statement_lines WHERE import_id = $1 AND status = 'classified' LIMIT 1`, [id]);
  if (classified.rows?.[0]) throw hasClassified();
  const reason = String(body?.reason ?? 'Banka yüklemesi geri alındı').slice(0, 150);
  const lines = await pool.query(`SELECT id, status, ledger_entry_id FROM bank_statement_lines WHERE import_id = $1 AND status <> 'reverted' ORDER BY id`, [id]);
  for (const line of lines.rows ?? []) {
    if (line.status === 'posted') {
      try {
        await reverseEntry({ siteCode, rawId: line.ledger_entry_id, body: { reason, idempotency_key: `blrev:${line.id}` }, actor });
      } catch (error) {
        if (!(error instanceof PlatformError) || error.code !== 'ENTRY_ALREADY_REVERSED') throw error;
      }
    }
    await pool.query(`UPDATE bank_statement_lines SET status = 'reverted', decided_at = NOW() WHERE id = $1`, [line.id]);
  }
  const actorInfo = actorFromAuthUser(actor);
  await withFinanceTransaction(siteCode, async (client) => {
    await client.query(`DELETE FROM bank_payer_ibans WHERE site_code = $1 AND created_import_id = $2`, [siteCode, id]);
    await client.query(`UPDATE bank_imports SET status = 'reverted', reverted_by = $2, reverted_at = NOW(), revert_reason = $3 WHERE id = $1`, [id, actorInfo.userCode, reason]);
    await recordFinanceAudit(client, actor, 'finance.bank_import.reverted', siteCode, id, { lines: lines.rows?.length ?? 0 });
  });
  return { import: { id, status: 'reverted' } };
}

// --- IBAN hafızası -----------------------------------------------------------------------------------------

export async function listIbans(siteCode) {
  const r = await pool.query(
    `SELECT b.iban, b.apartment_id, b.account_party, b.use_count, b.last_used_at, a.unit_label, bl.block_name
       FROM bank_payer_ibans b JOIN apartments a ON a.id = b.apartment_id JOIN site_blocks bl ON bl.id = a.block_id
      WHERE b.site_code = $1 ORDER BY b.iban, b.apartment_id LIMIT 500`,
    [siteCode],
  );
  return {
    ibans: (r.rows ?? []).map((x) => ({
      iban: x.iban,
      apartment_id: num(x.apartment_id),
      apartment_label: apartmentLabel(x.block_name, x.unit_label),
      account_party: x.account_party,
      use_count: x.use_count,
      last_used_at: x.last_used_at,
    })),
  };
}

export async function deleteIban({ siteCode, rawIban, query }) {
  const iban = normalizeIban(rawIban);
  if (!iban) throw invalid('IBAN geçersiz.');
  const apartmentId = query?.apartment_id === undefined ? null : num(query.apartment_id);
  const r = await pool.query(
    `DELETE FROM bank_payer_ibans WHERE site_code = $1 AND iban = $2 AND ($3::BIGINT IS NULL OR apartment_id = $3::BIGINT)`,
    [siteCode, iban, apartmentId],
  );
  return { deleted: r.rowCount ?? 0 };
}

// --- Dikkat sayacı (2F toplu ucu) ---------------------------------------------------------------------------

export async function bankLineAttention(db, siteCode) {
  const r = await db.query(
    `SELECT COUNT(*)::INT AS count FROM bank_statement_lines l JOIN bank_imports i ON i.id = l.import_id
      WHERE l.site_code = $1 AND i.status = 'active' AND l.status IN ('unmatched', 'suggested')`,
    [siteCode],
  );
  return { count: r.rows?.[0]?.count ?? 0 };
}

registerAttentionSource({ key: 'bank_lines', module: 'finance', run: (db, siteCode) => bankLineAttention(db, siteCode) });
