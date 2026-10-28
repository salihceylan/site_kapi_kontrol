// Aidat ve Finans (Faz 4a): okuma uçları (bakiyeler, daire ekstresi, özet) ve sakin "Borcum" (/app/my-finance).
//
// Sözleşme: docs/PLATFORM_FINANS.md.
//  - Bakiye = defter satırlarının işaretli toplamı (pozitif = borç, negatif = alacak). Vadesi geçmiş tutar (overdue_minor) FIFO-örtük hesaplanır:
//    bakiye - vadesi gelmemiş borçlar (due_date > bugün; ters kayıtlar aynı vadeyi taşıdığı için net sıfırlanır), en az 0.
//  - Her sorguda site_code vardır (IDOR yok). Ekstre ve sakin sorguları (site_code, apartment_id, ...) indeksiyle okunur. Bakiye listesi ve özet ise sitenin TÜM
//    defterini her istekte toplar (O(site satırı): indeks taramasıyla, ~1 milyon satırda ~350 ms; bilinen / kabul edilen risk, bkz. rapor): ledger_entries
//    üzerinde sıralı tarama yoktur ama sitenin tüm satırları okunur. Toplamlar JSON güvenli tamsayı sınırını aşarsa 500 (sessiz bozulma yok).
//  - Sakin ucu YALNIZ çağıranın kendi dairelerini döndürür: dairenin responsible_party kuralı + family_member HİÇBİR durumda görmez +
//    eşleşen güncel kişi yoksa güvenli yedek; yönetici serbest metinleri (açıklama, ters kayıt nedeni) ve oluşturan adı sızmaz.

import { pool } from '../db.js';
import { computeModuleEnabled, getModuleDefinition } from './catalog.js';
import {
  FINANCE_MODULE,
  RECENT_ENTRIES_LIMIT,
  apartmentNotFound,
  computeOpenPeriod,
  currentPeriod,
  entryAccountParty,
  mapEntryRow,
  parseAccountPartyQuery,
  parseAccountQuery,
  parseBalancesQuery,
  periodLabel,
  redactEntryForResident,
  today,
} from './finance_common.js';
import { ENTRY_SELECT } from './finance_ledger_service.js';
import { allocateFunds, fundSplitOf, fundsBodyOf, loadFundLedger, summarizeFunds, toAllocatorEntry } from './finance_funds.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { accountPartySql, currentTenantSql, defaultPaymentParty, partyOfRelation, responsiblePersonSql, visiblePartyOfRelation } from './finance_parties.js';
import { apartmentLabel, escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import { syncUserPeopleSafe } from './people_sync.js';
import { residentEntryOf, residentView } from './finance_resident_view.js';

const INT32_MAX = 2147483647;

// İki hesap (İP-1A): defter satırının (takma ad `l`) hesabı, dairenin (takma ad `a`) güncel kiracısı ve borç sorumlusu tarafın güncel kişisi (finance_parties.js).
const LEDGER_ACCOUNT = accountPartySql('l');
const CURRENT_TENANT = currentTenantSql('a');
const RESPONSIBLE_PERSON = responsiblePersonSql('a');

/** Vadesi geçmiş tutar: bakiye - vadesi gelmemiş borçlar, en az 0 (BigInt). */
export function overdueOf(balance, notDue) {
  const value = toBigInt(balance) - toBigInt(notDue);
  return value > 0n ? value : 0n;
}

// ---------------------------------------------------------------------------
// Bakiye listesi
// ---------------------------------------------------------------------------

const OWNER_NAME_LATERAL = (alias, relation) => `
  LEFT JOIN LATERAL (
    SELECT COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name
    FROM apartment_residencies r
    INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
    LEFT JOIN users u ON u.user_code = sp.user_code
    WHERE r.apartment_id = f.apartment_id AND r.is_current = TRUE AND r.relation = '${relation}'
    ORDER BY r.id
    LIMIT 1
  ) ${alias} ON TRUE
`;

// İki hesap (İP-1A): bakiye, vadesi geçen, borç ve alacak HESAP BAZINDA hesaplanır, sonra daireye toplanır: bir hesabın alacağı diğerinin borcunu
// kapatmaz (bakiyeler karışmaz). balance = iki hesabın toplamı (eski istemci); debt / credit = hesapların pozitif / negatif bakiyeleri.
const BALANCE_CTES = (searchSql) => `
  acc AS MATERIALIZED (
    SELECT
      l.apartment_id,
      ${LEDGER_ACCOUNT} AS account_party,
      SUM(l.amount_minor) AS balance,
      COALESCE(SUM(l.amount_minor) FILTER (WHERE l.due_date > $2::DATE), 0) AS not_due
    FROM ledger_entries l
    WHERE l.site_code = $1
    GROUP BY 1, 2
  ),
  agg AS MATERIALIZED (
    SELECT
      apartment_id,
      SUM(balance) AS balance,
      SUM(GREATEST(balance - not_due, 0)) AS overdue,
      SUM(GREATEST(balance, 0)) AS debt,
      SUM(GREATEST(-balance, 0)) AS credit,
      COALESCE(SUM(balance) FILTER (WHERE account_party = 'owner'), 0) AS owner_balance,
      COALESCE(SUM(GREATEST(balance - not_due, 0)) FILTER (WHERE account_party = 'owner'), 0) AS owner_overdue,
      COALESCE(SUM(balance) FILTER (WHERE account_party = 'tenant'), 0) AS tenant_balance,
      COALESCE(SUM(GREATEST(balance - not_due, 0)) FILTER (WHERE account_party = 'tenant'), 0) AS tenant_overdue
    FROM acc
    GROUP BY apartment_id
  ),
  totals AS (
    SELECT COALESCE(SUM(debt), 0) AS debt, COALESCE(SUM(credit), 0) AS credit FROM agg
  ),
  base AS (
    SELECT
      a.id AS apartment_id, a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort,
      COALESCE(g.balance, 0) AS balance,
      COALESCE(g.overdue, 0) AS overdue,
      COALESCE(g.debt, 0) AS debt,
      COALESCE(g.credit, 0) AS credit,
      COALESCE(g.owner_balance, 0) AS owner_balance,
      COALESCE(g.owner_overdue, 0) AS owner_overdue,
      COALESCE(g.tenant_balance, 0) AS tenant_balance,
      COALESCE(g.tenant_overdue, 0) AS tenant_overdue
    FROM apartments a
    INNER JOIN site_blocks b ON b.id = a.block_id
    LEFT JOIN agg g ON g.apartment_id = a.id
    WHERE a.site_code = $1 AND (a.is_active = TRUE OR g.apartment_id IS NOT NULL)
    ${searchSql}
  )
`;

function searchClause(term, paramIndex) {
  if (term === null) {
    return '';
  }
  const like = `$${paramIndex}`;
  return `
    AND (
      ${foldSql(`b.block_name || ' - ' || a.unit_label`)} LIKE ${like} ESCAPE '\\'
      OR EXISTS (
        SELECT 1
        FROM apartment_residencies rr
        INNER JOIN site_people ssp ON ssp.id = rr.person_id AND ssp.is_active = TRUE
        LEFT JOIN users uu ON uu.user_code = ssp.user_code
        WHERE rr.apartment_id = a.id AND rr.is_current = TRUE
          AND ${foldSql(`COALESCE(NULLIF(uu.full_name, ''), ssp.full_name)`)} LIKE ${like} ESCAPE '\\'
      )
    )
  `;
}

// İP-1A: borçlu = en az bir hesabı borçlu; alacaklı = en az bir hesabı alacaklı (iki hesaplı daire iki listede de görünebilir).
const STATUS_WHERE = { debtor: 'WHERE debt > 0', credit: 'WHERE credit > 0', all: '' };
const STATUS_ORDER = {
  debtor: 'debt DESC, block_sort, apt_sort, apartment_id',
  credit: 'credit DESC, block_sort, apt_sort, apartment_id',
  all: 'block_sort, apt_sort, apartment_id',
};

/** GET balances -> { items, total, totals: { debt_minor, credit_minor } } (totals: sitenin TÜMÜ; süzgeçler uygulanmaz). */
export async function listBalances(siteCode, query = {}, now = new Date(), db = pool) {
  const filters = parseBalancesQuery(query);
  const params = [siteCode, today(now)];
  let searchSql = '';
  if (filters.q !== null) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    searchSql = searchClause(filters.q, params.length);
  }
  const ctes = BALANCE_CTES(searchSql);
  params.push(filters.limit, filters.offset);
  const limitIndex = params.length - 1;
  const page = await db.query(
    `
      WITH ${ctes},
      filtered AS (
        SELECT base.*, COUNT(*) OVER () AS total FROM base ${STATUS_WHERE[filters.status]}
      ),
      paged AS (
        SELECT * FROM filtered ORDER BY ${STATUS_ORDER[filters.status]} LIMIT $${limitIndex} OFFSET $${limitIndex + 1}
      )
      SELECT f.apartment_id, f.unit_label, f.block_name, f.balance::TEXT AS balance, f.overdue::TEXT AS overdue, f.total::TEXT AS total,
             f.debt::TEXT AS apt_debt, f.credit::TEXT AS apt_credit, f.owner_balance::TEXT AS owner_balance, f.owner_overdue::TEXT AS owner_overdue,
             f.tenant_balance::TEXT AS tenant_balance, f.tenant_overdue::TEXT AS tenant_overdue,
             t.debt::TEXT AS debt, t.credit::TEXT AS credit, o.name AS owner_name, te.name AS tenant_name
      FROM paged f
      CROSS JOIN totals t
      ${OWNER_NAME_LATERAL('o', 'owner')}
      ${OWNER_NAME_LATERAL('te', 'tenant')}
      ORDER BY ${STATUS_ORDER[filters.status].replace(/\b(debt|credit|block_sort|apt_sort|apartment_id)\b/g, 'f.$1')}
    `,
    params,
  );
  const rows = page.rows ?? [];
  // Sayfa boşsa (süzgeçle hiç eşleşme yok ya da offset sondan sonra) toplamlar ayrı küçük sorguyla alınır.
  const meta =
    rows.length > 0
      ? rows[0]
      : (
          await db.query(
            `
              WITH ${ctes},
              filtered AS (SELECT apartment_id FROM base ${STATUS_WHERE[filters.status]})
              SELECT (SELECT COUNT(*) FROM filtered)::TEXT AS total, t.debt::TEXT AS debt, t.credit::TEXT AS credit FROM totals t
            `,
            params.slice(0, params.length - 2),
          )
        ).rows?.[0] ?? { total: '0', debt: '0', credit: '0' };
  return {
    items: rows.map((row) => ({
      apartment_id: Number(row.apartment_id),
      label: apartmentLabel(row.block_name, row.unit_label),
      block_name: row.block_name ?? null,
      balance_minor: minorToNumber(row.balance),
      overdue_minor: minorToNumber(row.overdue),
      owner_name: row.owner_name ?? null,
      tenant_name: row.tenant_name ?? null,
      // İki hesap (İP-1A): hesapların borç / alacak toplamları ve hesap başına bakiye
      debt_minor: minorToNumber(row.apt_debt),
      credit_minor: minorToNumber(row.apt_credit),
      accounts: {
        owner: { balance_minor: minorToNumber(row.owner_balance), overdue_minor: minorToNumber(row.owner_overdue) },
        tenant: { balance_minor: minorToNumber(row.tenant_balance), overdue_minor: minorToNumber(row.tenant_overdue) },
      },
    })),
    total: Number(meta.total),
    totals: { debt_minor: minorToNumber(meta.debt), credit_minor: minorToNumber(meta.credit) },
  };
}

// ---------------------------------------------------------------------------
// Daire ekstresi
// ---------------------------------------------------------------------------

/**
 * Dairenin hesap başına bakiyesi (İP-1A): { owner: { balance_minor, overdue_minor, entry_count }, tenant: { … } } (satırı olmayan hesap 0). Vadesi geçen
 * = hesap bakiyesi - hesabın vadesi gelmemiş borçları, en az 0 (4a tanımı, hesap başına).
 */
async function loadAccountSums(db, siteCode, apartmentId, todayIsoDate) {
  const result = await db.query(
    `
      SELECT ${LEDGER_ACCOUNT} AS account_party, COALESCE(SUM(l.amount_minor), 0)::TEXT AS balance,
             COALESCE(SUM(l.amount_minor) FILTER (WHERE l.due_date > $3::DATE), 0)::TEXT AS not_due, COUNT(*)::TEXT AS n
      FROM ledger_entries l
      WHERE l.site_code = $1 AND l.apartment_id = $2
      GROUP BY 1
    `,
    [siteCode, apartmentId, todayIsoDate],
  );
  const sums = { owner: { balance: 0n, overdue: 0n, count: 0 }, tenant: { balance: 0n, overdue: 0n, count: 0 } };
  for (const row of result.rows ?? []) {
    const party = row.account_party === 'tenant' ? 'tenant' : 'owner';
    sums[party] = { balance: toBigInt(row.balance), overdue: overdueOf(row.balance, row.not_due), count: Number(row.n) };
  }
  return sums;
}

const accountSumsBody = (sums) => ({
  owner: { balance_minor: minorToNumber(sums.owner.balance), overdue_minor: minorToNumber(sums.owner.overdue), entry_count: sums.owner.count },
  tenant: { balance_minor: minorToNumber(sums.tenant.balance), overdue_minor: minorToNumber(sums.tenant.overdue), entry_count: sums.tenant.count },
});

/**
 * GET apartments/:apartmentId/account -> { apartment, balance_minor, overdue_minor, items, next_before_id } (+ İP-1A: account_party, accounts,
 * show_tenant_account, has_current_tenant, default_payment_account). Başka sitenin dairesi 404. `?account_party=owner|tenant` satırları ve bakiyeyi o
 * hesapla sınırlar; verilmezse eski davranış (dairenin tüm satırları; bakiye iki hesabın toplamı, vadesi geçen hesapların vadesi geçenlerinin toplamı).
 */
export async function getApartmentAccount(siteCode, rawApartmentId, query = {}, now = new Date(), db = pool) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw apartmentNotFound();
  }
  const filters = parseAccountQuery(query);
  const accountParty = parseAccountPartyQuery(query.account_party);
  const apartmentResult = await db.query(
    `
      SELECT a.id, a.unit_label, b.block_name, a.responsible_party
      FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.id = $1 AND a.site_code = $2
      LIMIT 1
    `,
    [apartmentId, siteCode],
  );
  const apartment = apartmentResult.rows?.[0];
  if (!apartment) {
    throw apartmentNotFound();
  }
  const sums = await loadAccountSums(db, siteCode, apartmentId, today(now));
  const tenancy = await db.query(
    `
      SELECT ${CURRENT_TENANT} AS has_current_tenant,
             EXISTS (SELECT 1 FROM apartment_residencies hr WHERE hr.apartment_id = a.id AND hr.relation = 'tenant') AS had_tenant
      FROM apartments a WHERE a.id = $1 AND a.site_code = $2
    `,
    [apartmentId, siteCode],
  );
  const tenancyRow = tenancy.rows?.[0] ?? {};
  const params = [siteCode, apartmentId];
  const clauses = ['l.site_code = $1', 'l.apartment_id = $2'];
  if (accountParty !== null) {
    params.push(accountParty);
    clauses.push(`${LEDGER_ACCOUNT} = $${params.length}`);
  }
  if (filters.from !== null) {
    params.push(filters.from);
    clauses.push(`l.entry_date >= $${params.length}::DATE`);
  }
  if (filters.to !== null) {
    params.push(filters.to);
    clauses.push(`l.entry_date <= $${params.length}::DATE`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    // İmleç satırı AYNI daireye bağlıdır: başka dairenin / sitenin kaydı imleç olarak kullanılamaz (eşleşme yoksa alt sorgu NULL, sayfa boş).
    clauses.push(`(l.entry_date, l.id) < (SELECT c.entry_date, c.id FROM ledger_entries c WHERE c.id = $${params.length} AND c.site_code = $1 AND c.apartment_id = $2)`);
  }
  params.push(filters.limit + 1);
  const entries = await db.query(
    `${ENTRY_SELECT} WHERE ${clauses.join(' AND ')} ORDER BY l.entry_date DESC, l.id DESC LIMIT $${params.length}`,
    params,
  );
  const rows = entries.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map(mapEntryRow);
  // Kasa dagitimi (docs/PLATFORM_FINANS_KASALAR.md 3): hesap basina TEK saf islev; ekstre kasa bazinda acik borc / vadesi gecen / avans + her tahsilatin dagitimi
  const todayIsoDate = today(now);
  const ledgerGroups = await loadFundLedger(db, siteCode, { apartmentIds: [apartmentId] });
  const allocations = {
    owner: allocateFunds(ledgerGroups.get(`${apartmentId}:owner`) ?? [], { today: todayIsoDate }),
    tenant: allocateFunds(ledgerGroups.get(`${apartmentId}:tenant`) ?? [], { today: todayIsoDate }),
  };
  for (const item of items) {
    item.fund_split = item.kind === 'payment' ? fundSplitOf(allocations[item.account_party], item.id, minorToNumber) : null;
  }
  const fundsView = fundsBodyOf(
    summarizeFunds(accountParty === null ? [allocations.owner, allocations.tenant] : [allocations[accountParty]], { today: todayIsoDate }),
    minorToNumber,
  );
  const selected = accountParty === null
    ? { balance: sums.owner.balance + sums.tenant.balance, overdue: sums.owner.overdue + sums.tenant.overdue }
    : sums[accountParty];
  return {
    apartment: {
      id: Number(apartment.id),
      label: apartmentLabel(apartment.block_name, apartment.unit_label),
      block_name: apartment.block_name ?? null,
      responsible_party: apartment.responsible_party,
    },
    currency: 'TRY',
    balance_minor: minorToNumber(selected.balance),
    overdue_minor: minorToNumber(selected.overdue),
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
    // Kasa kirilimi (secili hesap ya da iki hesabin toplami): acik borc, vadesi gecen, kasaya kisitli avans; `advance_minor` = toplam avans (kisitsiz dahil)
    ...fundsView,
    // İki hesap (İP-1A)
    account_party: accountParty,
    accounts: accountSumsBody(sums),
    // Kiracısı hiç olmamış ve kiracı hesabında satırı olmayan dairede yönetici ekranı yalnız ev sahibi hesabını (sekmesiz) gösterir.
    show_tenant_account: tenancyRow.had_tenant === true || tenancyRow.has_current_tenant === true || sums.tenant.count > 0,
    has_current_tenant: tenancyRow.has_current_tenant === true,
    default_payment_account: await defaultPaymentParty(db, { siteCode, apartmentId, onDate: today(now) }),
  };
}

// ---------------------------------------------------------------------------
// Özet
// ---------------------------------------------------------------------------

/** GET summary. this_period: AÇIK dönemde kaydedilen net borçlandırma ve tahsilat (ters kayıtlar net düşer). */
export async function getSummary(siteCode, now = new Date(), db = pool) {
  const closures = await db.query(`SELECT to_char(period, 'YYYY-MM-DD') AS period FROM finance_period_closures WHERE site_code = $1`, [siteCode]);
  const openPeriod = computeOpenPeriod(currentPeriod(now), new Set((closures.rows ?? []).map((row) => row.period)));
  const result = await db.query(
    `
      WITH acc AS (
        SELECT l.apartment_id, ${LEDGER_ACCOUNT} AS account_party, SUM(l.amount_minor) AS balance FROM ledger_entries l WHERE l.site_code = $1 GROUP BY 1, 2
      ),
      agg AS (
        SELECT apartment_id, SUM(balance) AS balance, SUM(GREATEST(balance, 0)) AS debt, SUM(GREATEST(-balance, 0)) AS credit FROM acc GROUP BY apartment_id
      ),
      period_sums AS (
        SELECT
          COALESCE(SUM(amount_minor) FILTER (WHERE COALESCE(source_kind, '') NOT IN ('refund', 'liability_transfer') AND (kind = 'charge' OR (kind = 'reversal' AND amount_minor < 0))), 0) AS charged,
          COALESCE(-SUM(amount_minor) FILTER (WHERE kind = 'payment' OR (kind = 'reversal' AND amount_minor > 0)), 0) - COALESCE(SUM(amount_minor) FILTER (WHERE source_kind = 'refund'), 0) AS collected
        FROM ledger_entries
        WHERE site_code = $1 AND period = $2::DATE
      )
      SELECT
        COALESCE(SUM(balance), 0)::TEXT AS balance_total,
        COALESCE(SUM(debt), 0)::TEXT AS debt_total,
        COALESCE(SUM(credit), 0)::TEXT AS credit_total,
        (COUNT(*) FILTER (WHERE debt > 0))::TEXT AS debtor_count,
        (SELECT charged FROM period_sums)::TEXT AS charged,
        (SELECT collected FROM period_sums)::TEXT AS collected
      FROM agg
    `,
    [siteCode, openPeriod],
  );
  const row = result.rows[0];
  return {
    currency: 'TRY',
    open_period: periodLabel(openPeriod),
    balance_total_minor: minorToNumber(row.balance_total),
    debt_total_minor: minorToNumber(row.debt_total),
    credit_total_minor: minorToNumber(row.credit_total),
    debtor_count: Number(row.debtor_count),
    this_period: { charged_minor: minorToNumber(row.charged), collected_minor: minorToNumber(row.collected) },
  };
}

// ---------------------------------------------------------------------------
// Sakin: Borcum
// ---------------------------------------------------------------------------

/**
 * ESKİ (İP-1A öncesi) "borç sorumlusu taraf görür" kuralının ilişki listesi. İP-1A'dan beri sakin görünümü hesap sahipliğiyle
 * belirlenir (loadVisibleAccounts / finance_parties.partyOfRelation); bu sabit hiçbir sorguda KULLANILMAZ, dışa açık adı geriye uyum
 * için korunur.
 */
export const ALLOWED_RELATIONS_SQL = `(
  CASE a.responsible_party
    WHEN 'owner' THEN ARRAY['owner']::TEXT[]
    WHEN 'tenant' THEN ARRAY['tenant']::TEXT[]
    ELSE ARRAY['owner', 'tenant', 'resident']::TEXT[]
  END
)`;

/**
 * Sakin kapsamı (KVKK ölçülülük): sakin dairenin defterini yalnız kendi taşınma ayından (`visible_from`, ayın 1'i) itibaren görür; önceki
 * malikin / kiracının kayıtları yeni sakine görünmez. Bir satırın DAYANAK AYI: gecikme tazminatı kalemi (ve ters kaydı) için HESAPLANAN ay
 * (late_fee_runs.period), ters kayıt için asıl kaydın ayı, diğerlerinde kaydın ayı (period); böylece önceki döneme ait bir kayıt sonradan
 * ters çevrilse ya da tazminatı sonradan yazılsa da yeni sakine görünmez. Bakiye ve tahsilat görünürlüğü mahsup kuralıyla
 * finance_resident_view.js'te hesaplanır. Yönetici ve kurul uçları kapsamsızdır (dairenin tüm defteri).
 */
export function residentAnchorSql(alias) {
  return `COALESCE(
    (SELECT lfr.period FROM late_fee_runs lfr WHERE lfr.id = ${alias}.late_fee_run_id),
    (SELECT orig.period FROM ledger_entries orig WHERE orig.id = ${alias}.reverses_entry_id),
    ${alias}.period
  )`;
}

/** Satır (takma ad `alias`) kapsam içinde mi: dayanak ayı >= `since` ($n ya da sütun; NULL = sınırsız, yalnız yönetici yolları). */
export function residentScopeSql(alias, since) {
  return `(${since}::DATE IS NULL OR ${residentAnchorSql(alias)} >= ${since}::DATE)`;
}

/** Görünümün (loadVisibleAccounts `views[]`) ya da satırın kapsam başlangıcı ('YYYY-MM-01') ya da null. */
export function visibleFromOf(row) {
  const value = row?.visible_from;
  return typeof value === 'string' && /^\d{4}-\d{2}-01$/.test(value) ? value : null;
}

/**
 * Sakin yolunda kapsam başlangıcı. Güvenli taraf: değer okunamazsa (beklenmez) sınır KALKMAZ, bu ay esas alınır.
 * `todayIso`: 'YYYY-MM-DD' (İstanbul).
 */
export function residentSinceOf(row, todayIso) {
  return visibleFromOf(row) ?? `${todayIso.slice(0, 7)}-01`;
}

/**
 * Sakin görünümü için dairelerin TÜM defter satırları (ENTRY_SELECT alanları + `anchor` = dayanak ayı 'YYYY-MM-DD'), daire ve
 * (tarih, kimlik) sırasıyla. Hesap ve süzme finance_resident_view.residentView ile yapılır.
 */
export async function loadResidentLedger(db, siteCodes, apartmentIds, { limit = null } = {}) {
  if (apartmentIds.length === 0) {
    return [];
  }
  const result = await db.query(
    `
      SELECT e.*, to_char(${residentAnchorSql('a')}, 'YYYY-MM-DD') AS anchor
      FROM (${ENTRY_SELECT} WHERE l.site_code = ANY($1::BIGINT[]) AND l.apartment_id = ANY($2::BIGINT[])) e
      INNER JOIN ledger_entries a ON a.id = e.id
      ORDER BY e.apartment_id, e.entry_date, e.id
      LIMIT $3
    `,
    [siteCodes, apartmentIds, limit],
  );
  return result.rows ?? [];
}

/**
 * İki hesap (İP-1A): çağıranın borç görünümleri. Kişinin bu dairedeki GÜNCEL ilişkisinden kendi hesabı (finance_parties.visiblePartyOfRelation: owner ->
 * ev sahibi, tenant -> kiracı, resident -> dairede güncel kiracı varsa kiracı, yoksa ev sahibi, ANCAK yalnız sorumlu both iken ya da sorumlu tarafın güncel
 * kişisi yokken; family_member HİÇBİR hesabı görmez) ve dairenin `responsible_party` değeri `both` ise MALİK kiracı hesabını SALT OKUNUR da görür. Yalnız
 * onaylı siteler, etkin kişi kaydı.
 * Kapsam (`visible_from`, ayın 1'i) HER görünüm için kişinin ilişki başlangıcıdır (taşınma günü; boşsa ilişki kaydının günü, İstanbul); aynı kişinin
 * aynı dairedeki kesintisiz önceki ilişkisi zincirin başını YALNIZ aynı hesaba düşüyorsa öne çeker (kiracıyken satın alan kişi eski kiracı kayıtlarını
 * salt okunur kiracı hesabında görür; önceki malikin ev sahibi hesabı kayıtları yeni malike görünmez). Zincir tek adımdır (güvenli taraf).
 * `relation_since_at`: o görünüm için ilişki kaydının açıldığı an (öncesinde düzenlenmiş makbuzda ödeyen adı gösterilmez).
 * Dönüş: daire satırları + `views: [{ account_party, role: 'own'|'read_only', visible_from, relation_since_at }]` (ilki kendi hesabı).
 */
export async function loadVisibleAccounts(db, userCode) {
  const result = await db.query(
    `
      SELECT
        a.id AS apartment_id, a.site_code, s.name AS site_name, a.unit_label, b.block_name, b.sort_order AS block_sort,
        a.sort_order AS apt_sort, a.responsible_party, r.relation,
        to_char(COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE), 'YYYY-MM-DD') AS start_date,
        r.created_at AS relation_created_at,
        ${CURRENT_TENANT} AS has_current_tenant,
        ${RESPONSIBLE_PERSON} AS has_responsible_person,
        COALESCE((
          SELECT json_agg(json_build_object(
            'relation', p.relation,
            'start_date', to_char(COALESCE(p.move_in_date, (p.created_at AT TIME ZONE 'Europe/Istanbul')::DATE), 'YYYY-MM-DD'),
            'created_at', p.created_at
          ) ORDER BY p.id)
          FROM apartment_residencies p
          WHERE p.person_id = r.person_id AND p.apartment_id = r.apartment_id AND p.is_current = FALSE
            AND p.relation <> 'family_member' AND p.move_out_date IS NOT NULL
            AND p.move_out_date >= COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE) - 1
        ), '[]'::json) AS previous
      FROM site_people sp
      INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
      INNER JOIN apartments a ON a.id = r.apartment_id AND a.site_code = sp.site_code
      INNER JOIN site_blocks b ON b.id = a.block_id
      INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      WHERE sp.user_code = $1 AND sp.is_active = TRUE
        AND r.relation <> 'family_member'
      ORDER BY s.name, b.sort_order, a.sort_order, a.id
    `,
    [userCode],
  );
  const out = [];
  for (const row of result.rows ?? []) {
    const views = residentViewsOf(row);
    if (views.length > 0) {
      out.push({ ...row, views });
    }
  }
  return out;
}

const instantOf = (value) => (value instanceof Date ? value.getTime() : new Date(value).getTime());

/**
 * Daire satırının görünümleri (saf; loadVisibleAccounts). Kendi hesabı visiblePartyOfRelation ile: ilişkisi belirtilmemiş sakin yalnız sorumlu both
 * iken ya da sorumlu tarafın güncel kişisi yokken görür (bağımsız inceleme: eski F2.05 kuralı korunur).
 */
export function residentViewsOf(row) {
  const hasTenant = row.has_current_tenant === true;
  const own = visiblePartyOfRelation(row.relation, {
    hasCurrentTenant: hasTenant,
    responsibleParty: row.responsible_party,
    hasResponsiblePerson: row.has_responsible_person === true,
  });
  if (own === null) {
    return [];
  }
  const parties = [{ party: own, role: 'own' }];
  if (row.relation === 'owner' && row.responsible_party === 'both' && own === 'owner') {
    parties.push({ party: 'tenant', role: 'read_only' });
  }
  const previous = Array.isArray(row.previous) ? row.previous : [];
  return parties.map(({ party, role }) => {
    let start = typeof row.start_date === 'string' ? row.start_date : null;
    let sinceAt = row.relation_created_at ?? null;
    for (const prev of previous) {
      if (partyOfRelation(prev.relation, hasTenant) !== party) continue;
      if (typeof prev.start_date === 'string' && (start === null || prev.start_date < start)) start = prev.start_date;
      if (prev.created_at && (sinceAt === null || instantOf(prev.created_at) < instantOf(sinceAt))) sinceAt = prev.created_at;
    }
    return {
      account_party: party,
      role,
      visible_from: start === null ? null : `${start.slice(0, 7)}-01`,
      relation_since_at: sinceAt,
    };
  });
}

/** Sakin görünümünün kapsam başlangıcı ('YYYY-MM-01'): okunamazsa (beklenmez) sınır KALKMAZ, bu ay esas alınır. */
export function viewSinceOf(view, todayIso) {
  return visibleFromOf(view) ?? `${todayIso.slice(0, 7)}-01`;
}

/** Görünümün hesabına ait defter satırları (052 öncesi satır payer_party'den türetilir). */
export const rowsOfView = (rows, view) => rows.filter((entry) => entryAccountParty(entry) === view.account_party);

/** Modülü AÇIK siteler (katalog varsayılanı + site_modules satırı). */
export async function enabledFinanceSites(db, siteCodes) {
  if (siteCodes.length === 0) {
    return new Set();
  }
  const definition = getModuleDefinition(FINANCE_MODULE);
  const rows = await db.query(
    `SELECT site_code, enabled FROM site_modules WHERE module_code = $1 AND site_code = ANY($2::BIGINT[])`,
    [FINANCE_MODULE, siteCodes],
  );
  const byCode = new Map((rows.rows ?? []).map((row) => [Number(row.site_code), row]));
  return new Set(siteCodes.filter((code) => computeModuleEnabled(definition, byCode.get(code))));
}

/** Sıradaki vade: FIFO-örtük; ödenmiş kısım en eski vadelerden düşülür. groups: [{ dueDate, amount(bigint) }] vade artan. */
export function nextDueOf(balance, groups) {
  const upcoming = groups.filter((group) => group.amount > 0n);
  let notDue = 0n;
  for (const group of upcoming) {
    notDue += group.amount;
  }
  const positive = balance > 0n ? balance : 0n;
  let covered = notDue > positive ? notDue - positive : 0n;
  for (const group of upcoming) {
    const take = covered < group.amount ? covered : group.amount;
    covered -= take;
    const remaining = group.amount - take;
    if (remaining > 0n) {
      return { dueDate: group.dueDate, amount: remaining };
    }
  }
  return null;
}

/** Bir görünümün Borcum gövdesi (kendi hesabı ya da salt okunur kiracı hesabı). */
function myFinanceViewBody(rows, view, todayIsoDate) {
  const since = viewSinceOf(view, todayIsoDate);
  const own = rowsOfView(rows, view);
  const result = residentView(own.map(residentEntryOf), { since, today: todayIsoDate });
  const shown = own.filter((entry) => result.visibleIds.has(Number(entry.id)));
  // Görünen satırların toplamı bakiyeye eşit değilse bir tahsilat ya da alacak önceki dönem kayıtlarıyla mahsup edilmiştir: istemci açıklar.
  const shownSum = shown.reduce((sum, entry) => sum + BigInt(entry.amount_minor), 0n);
  // Kasa kirilimi: dagitim hesabin TUM satirlariyla yapilir (kapsam disi eski borclar once odenir), yalniz kapsam ici (dayanak ayi >= since) borclar gosterilir
  const anchorOf = new Map(own.map((entry) => [Number(entry.id), entry.anchor]));
  const fundsView = fundsBodyOf(
    summarizeFunds([allocateFunds(own.map(toAllocatorEntry), { today: todayIsoDate })], {
      today: todayIsoDate,
      inScope: since === null ? null : (debtId) => (anchorOf.get(debtId) ?? since) >= since,
    }),
    minorToNumber,
  );
  const recent = shown
    .sort((a, b) => (a.entry_date === b.entry_date ? Number(b.id) - Number(a.id) : a.entry_date < b.entry_date ? 1 : -1))
    .slice(0, RECENT_ENTRIES_LIMIT)
    .map((entry) => redactEntryForResident(mapEntryRow(entry)));
  return {
    account_party: view.account_party,
    role: view.role,
    balance_minor: minorToNumber(result.balance),
    overdue_minor: minorToNumber(result.overdue),
    next_due_date: result.nextDue ? result.nextDue.dueDate : null,
    next_due_minor: result.nextDue ? minorToNumber(result.nextDue.amount) : null,
    // Kapsam dışında kalan kayıt varsa başlangıç ayı ('YYYY-MM'); istemci bunu sakine açıkça yazar.
    visible_from: result.hiddenCount > 0 ? periodLabel(since) : null,
    offset_note: shownSum !== result.balance,
    recent,
    // Kasa kirilimi: { operating: { balance_minor, overdue_minor, advance_minor }, capital: {…} } + toplam avans
    ...fundsView,
  };
}

/**
 * GET /app/my-finance -> { items: [...] } (bkz. dosya başı). İki hesap (İP-1A): ESKİ alanlar (balance_minor, overdue_minor, next_due_*, visible_from,
 * offset_note, recent) kişinin KENDİ hesabıdır (eski istemci kendi hesabının bakiyesini görmeye devam eder); `account_party` kendi hesabı, `accounts`
 * görünümlerin listesi (ilki kendi hesabı; `both` dairede malik için salt okunur kiracı hesabı ikinci). Bakiye, vadesi geçmiş tutar ve sıradaki vade
 * her görünümde sakin kapsamı ve mahsup kuralıyla (finance_resident_view.residentView) YALNIZ o hesabın satırlarından hesaplanır.
 * `ownOnly`: yalnız kendi hesabı (kişisel veri dışa aktarması: salt okunur kiracı hesabı başkasının verisidir).
 */
export async function getMyFinance(authUser, now = new Date(), db = pool, { ownOnly = false, sync = true } = {}) {
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
  if (userCode === null) {
    return { items: [] };
  }
  if (sync) {
    await syncUserPeopleSafe(userCode);
  }
  const visible = await loadVisibleAccounts(db, userCode);
  const enabled = await enabledFinanceSites(db, [...new Set(visible.map((row) => Number(row.site_code)))]);
  const apartments = visible.filter((row) => enabled.has(Number(row.site_code)));
  if (apartments.length === 0) {
    return { items: [] };
  }
  const siteCodes = [...new Set(apartments.map((row) => Number(row.site_code)))];
  const apartmentIds = apartments.map((row) => Number(row.apartment_id));
  const todayIsoDate = today(now);
  const ledger = await loadResidentLedger(db, siteCodes, apartmentIds);
  const rowsByApartment = new Map();
  for (const row of ledger) {
    const key = Number(row.apartment_id);
    if (!rowsByApartment.has(key)) rowsByApartment.set(key, []);
    rowsByApartment.get(key).push(row);
  }
  return {
    items: apartments.map((row) => {
      const id = Number(row.apartment_id);
      const rows = rowsByApartment.get(id) ?? [];
      const views = (ownOnly ? row.views.slice(0, 1) : row.views).map((view) => myFinanceViewBody(rows, view, todayIsoDate));
      const own = views[0];
      return {
        site_code: Number(row.site_code),
        site_name: row.site_name ?? null,
        apartment_id: id,
        label: apartmentLabel(row.block_name, row.unit_label),
        block_name: row.block_name ?? null,
        currency: 'TRY',
        balance_minor: own.balance_minor,
        overdue_minor: own.overdue_minor,
        next_due_date: own.next_due_date,
        next_due_minor: own.next_due_minor,
        payer_party: row.responsible_party,
        visible_from: own.visible_from,
        offset_note: own.offset_note,
        recent: own.recent,
        account_party: own.account_party,
        funds: own.funds,
        advance_minor: own.advance_minor,
        accounts: views,
      };
    }),
  };
}

/**
 * Hesap silme engeli: çağıranın KENDİ hesabında ödenmemiş borç (Borcum'daki sakin kapsamlı bakiye > 0), Finans modülü AÇIK sitelerde.
 * getMyFinance ile aynı iç yol; eşitleme ÇAĞIRMAZ (silme işlemi bağlantısında da çalışır). Aile üyesi, salt okunur karşı hesap ve alacak sayılmaz.
 * Finans tabloları yoksa boş döner. @returns {Promise<Array<{site_code:number,site_name:string|null,apartment_id:number,label:string,balance_minor:number,account_party:string}>>}
 */
export async function ownOpenDebts(db, userCode, now = new Date()) {
  const has = await db.query("SELECT (to_regclass('public.ledger_entries') IS NOT NULL) AS ok");
  if (has.rows?.[0]?.ok !== true) {
    return [];
  }
  const finance = await getMyFinance({ user_code: userCode }, now, db, { ownOnly: true, sync: false });
  return finance.items
    .filter((item) => Number(item.balance_minor) > 0)
    .map((item) => ({
      site_code: item.site_code,
      site_name: item.site_name,
      apartment_id: item.apartment_id,
      label: item.label,
      balance_minor: Number(item.balance_minor),
      account_party: item.account_party,
    }));
}
