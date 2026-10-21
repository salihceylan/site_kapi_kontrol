// İcra dökümü (F8): hesap (ev sahibi / kiracı) bazında vadesi geçmiş ödenmemiş kalemler. PDF'i ve avukat Excel'ini İSTEMCİ üretir; sunucu ham veriyi verir.
// Hesaplama M1 mahsup CTE'leriyle (finance_m1.js) AYNIDIR: ekran, yaşlandırma raporu ve döküm sapmaz. Yalnız okur; defter satırı yazmaz.
// Hukuki not: içerik İİK m.68 açısından avukat tarafından doğrulanmalıdır (ENFORCEMENT_NOTE).

import { invalidQuery } from './finance_common.js';
import { parseAgingQuery, loadResidentNames, withReportSnapshot } from './finance_reports.js';
import { m1Ctes } from './finance_m1.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { apartmentLabel } from './people_common.js';

export const ENFORCEMENT_NOTE = 'Bu döküm bilgi amaçlıdır; icra takibine esas olmadan önce avukat kontrolünden geçirilmelidir.';
export const ENFORCEMENT_ACCOUNT_LIMIT = 200;
const PARTIES = ['owner', 'tenant'];

/** `accounts=12:owner,15:tenant` -> [{apartmentId, party}] (en çok 200, tekrarsız); boş / yok -> null (= tüm borçlu hesaplar). */
export function parseEnforcementAccounts(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const seen = new Set();
  const out = [];
  for (const part of String(value).split(',')) {
    const match = /^(\d{1,12}):(owner|tenant)$/.exec(part.trim());
    if (!match) {
      throw invalidQuery();
    }
    const key = `${match[1]}:${match[2]}`;
    if (!seen.has(key)) {
      seen.add(key);
      out.push({ apartmentId: Number(match[1]), party: match[2] });
    }
  }
  if (out.length > ENFORCEMENT_ACCOUNT_LIMIT) {
    throw invalidQuery();
  }
  return out;
}

const dayDiff = (asOf, due) => Number((BigInt(Date.parse(`${asOf}T00:00:00Z`)) - BigInt(Date.parse(`${due}T00:00:00Z`))) / 86400000n);

/** Vadesi geçmiş ödenmemiş kalemler, hesap başına gruplu. `selection` null ise tüm borçlu hesaplar (en çok 200). */
export async function computeEnforcement(db, siteCode, asOf, selection = null) {
  const ids = selection === null ? null : [...new Set(selection.map((s) => s.apartmentId))];
  const clause = ids === null ? '' : ' AND l.apartment_id = ANY($3::BIGINT[])';
  const params = ids === null ? [siteCode, asOf] : [siteCode, asOf, ids];
  const result = await db.query(
    `
      WITH ${m1Ctes('$1', '$2', clause)},
      open_items AS (
        SELECT i.id, i.apartment_id, i.account_party, i.due, i.is_lf, i.a,
               LEAST(i.a, GREATEST(0, i.c - COALESCE(p.p, 0))) AS r
        FROM items i LEFT JOIN pay p ON p.apartment_id = i.apartment_id AND p.account_party = i.account_party
      )
      SELECT o.id AS entry_id, o.apartment_id, o.account_party, to_char(o.due, 'YYYY-MM-DD') AS due, o.is_lf, o.a::TEXT AS amount, o.r::TEXT AS remaining,
             to_char(l.period, 'YYYY-MM-DD') AS period, l.definition_name, l.description,
             a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort
      FROM open_items o
      INNER JOIN ledger_entries l ON l.id = o.id
      INNER JOIN apartments a ON a.id = o.apartment_id AND a.site_code = $1
      INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE o.r > 0 AND o.due <= $2::DATE
      ORDER BY b.sort_order, a.sort_order, o.apartment_id, o.account_party, o.due, o.id
    `,
    params,
  );
  const wanted = selection === null ? null : new Set(selection.map((s) => `${s.apartmentId}:${s.party}`));
  const byAccount = new Map();
  for (const row of result.rows ?? []) {
    if (!PARTIES.includes(row.account_party)) continue;
    const key = `${Number(row.apartment_id)}:${row.account_party}`;
    if (wanted !== null && !wanted.has(key)) continue;
    let acc = byAccount.get(key);
    if (!acc) {
      acc = {
        apartmentId: Number(row.apartment_id),
        accountParty: row.account_party,
        label: apartmentLabel(row.block_name, row.unit_label),
        blockName: row.block_name ?? null,
        items: [],
        principal: 0n,
        lateFee: 0n,
      };
      byAccount.set(key, acc);
    }
    const remaining = toBigInt(row.remaining);
    acc.items.push({
      entry_id: Number(row.entry_id),
      due_date: row.due,
      period: row.period,
      name: row.definition_name ?? (row.is_lf ? 'Gecikme tazminatı' : 'Borç'),
      description: row.description ?? '',
      is_late_fee: row.is_lf === true,
      amount_minor: minorToNumber(toBigInt(row.amount)),
      remaining_minor: minorToNumber(remaining),
      days_overdue: dayDiff(asOf, row.due),
    });
    if (row.is_lf === true) acc.lateFee += remaining;
    else acc.principal += remaining;
  }
  const list = [...byAccount.values()];
  return selection === null ? list.slice(0, ENFORCEMENT_ACCOUNT_LIMIT) : list;
}

/** GET reports/enforcement (yalnız yönetici). */
export async function enforcementReport(siteCode, query = {}, now = new Date()) {
  const { asOf } = parseAgingQuery({ as_of: query.as_of }, now);
  const selection = parseEnforcementAccounts(query.accounts);
  return withReportSnapshot(siteCode, async (client) => {
    const site = await client.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
    const accounts = await computeEnforcement(client, siteCode, asOf, selection);
    const names = await loadResidentNames(client, [...new Set(accounts.map((a) => a.apartmentId))]);
    let principal = 0n;
    let lateFee = 0n;
    const out = accounts.map((a) => {
      principal += a.principal;
      lateFee += a.lateFee;
      return {
        apartment_id: a.apartmentId,
        label: a.label,
        block_name: a.blockName,
        account_party: a.accountParty,
        person_name: names.get(a.apartmentId)?.[a.accountParty] ?? null,
        items: a.items,
        principal_minor: minorToNumber(a.principal),
        late_fee_minor: minorToNumber(a.lateFee),
        total_minor: minorToNumber(a.principal + a.lateFee),
        oldest_due_date: a.items[0]?.due_date ?? null,
      };
    });
    return {
      site: { name: site.rows?.[0]?.name ?? '' },
      generated_at: now.toISOString(),
      as_of: asOf,
      currency: 'TRY',
      note: ENFORCEMENT_NOTE,
      accounts: out,
      totals: { principal_minor: minorToNumber(principal), late_fee_minor: minorToNumber(lateFee), total_minor: minorToNumber(principal + lateFee), account_count: out.length },
    };
  });
}
