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
  mapEntryRow,
  parseAccountQuery,
  parseBalancesQuery,
  periodLabel,
  redactEntryForResident,
  today,
} from './finance_common.js';
import { ENTRY_SELECT } from './finance_ledger_service.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { apartmentLabel, escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import { syncUserPeopleSafe } from './people_sync.js';
import { residentEntryOf, residentView } from './finance_resident_view.js';

const INT32_MAX = 2147483647;

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

const BALANCE_CTES = (searchSql) => `
  agg AS MATERIALIZED (
    SELECT
      l.apartment_id,
      SUM(l.amount_minor) AS balance,
      COALESCE(SUM(l.amount_minor) FILTER (WHERE l.due_date > $2::DATE), 0) AS not_due
    FROM ledger_entries l
    WHERE l.site_code = $1
    GROUP BY l.apartment_id
  ),
  totals AS (
    SELECT
      COALESCE(SUM(balance) FILTER (WHERE balance > 0), 0) AS debt,
      COALESCE(-SUM(balance) FILTER (WHERE balance < 0), 0) AS credit
    FROM agg
  ),
  base AS (
    SELECT
      a.id AS apartment_id, a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort,
      COALESCE(g.balance, 0) AS balance,
      GREATEST(COALESCE(g.balance, 0) - COALESCE(g.not_due, 0), 0) AS overdue
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

const STATUS_WHERE = { debtor: 'WHERE balance > 0', credit: 'WHERE balance < 0', all: '' };
const STATUS_ORDER = {
  debtor: 'balance DESC, block_sort, apt_sort, apartment_id',
  credit: 'balance ASC, block_sort, apt_sort, apartment_id',
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
             t.debt::TEXT AS debt, t.credit::TEXT AS credit, o.name AS owner_name, te.name AS tenant_name
      FROM paged f
      CROSS JOIN totals t
      ${OWNER_NAME_LATERAL('o', 'owner')}
      ${OWNER_NAME_LATERAL('te', 'tenant')}
      ORDER BY ${STATUS_ORDER[filters.status].replace(/\b(balance|block_sort|apt_sort|apartment_id)\b/g, 'f.$1')}
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
    })),
    total: Number(meta.total),
    totals: { debt_minor: minorToNumber(meta.debt), credit_minor: minorToNumber(meta.credit) },
  };
}

// ---------------------------------------------------------------------------
// Daire ekstresi
// ---------------------------------------------------------------------------

/** GET apartments/:apartmentId/account -> { apartment, balance_minor, overdue_minor, items, next_before_id }. Başka sitenin dairesi 404. */
export async function getApartmentAccount(siteCode, rawApartmentId, query = {}, now = new Date(), db = pool) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw apartmentNotFound();
  }
  const filters = parseAccountQuery(query);
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
  const sums = await db.query(
    `
      SELECT
        COALESCE(SUM(amount_minor), 0)::TEXT AS balance,
        COALESCE(SUM(amount_minor) FILTER (WHERE due_date > $3::DATE), 0)::TEXT AS not_due
      FROM ledger_entries
      WHERE site_code = $1 AND apartment_id = $2
    `,
    [siteCode, apartmentId, today(now)],
  );
  const params = [siteCode, apartmentId];
  const clauses = ['l.site_code = $1', 'l.apartment_id = $2'];
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
  const balance = sums.rows[0].balance;
  return {
    apartment: {
      id: Number(apartment.id),
      label: apartmentLabel(apartment.block_name, apartment.unit_label),
      block_name: apartment.block_name ?? null,
      responsible_party: apartment.responsible_party,
    },
    currency: 'TRY',
    balance_minor: minorToNumber(balance),
    overdue_minor: minorToNumber(overdueOf(balance, sums.rows[0].not_due)),
    items,
    next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null,
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
      WITH agg AS (
        SELECT apartment_id, SUM(amount_minor) AS balance FROM ledger_entries WHERE site_code = $1 GROUP BY apartment_id
      ),
      period_sums AS (
        SELECT
          COALESCE(SUM(amount_minor) FILTER (WHERE kind = 'charge' OR (kind = 'reversal' AND amount_minor < 0)), 0) AS charged,
          COALESCE(-SUM(amount_minor) FILTER (WHERE kind = 'payment' OR (kind = 'reversal' AND amount_minor > 0)), 0) AS collected
        FROM ledger_entries
        WHERE site_code = $1 AND period = $2::DATE
      )
      SELECT
        COALESCE(SUM(balance), 0)::TEXT AS balance_total,
        COALESCE(SUM(balance) FILTER (WHERE balance > 0), 0)::TEXT AS debt_total,
        COALESCE(-SUM(balance) FILTER (WHERE balance < 0), 0)::TEXT AS credit_total,
        (COUNT(*) FILTER (WHERE balance > 0))::TEXT AS debtor_count,
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

/** loadVisibleApartments satırının kapsam başlangıcı ('YYYY-MM-01') ya da null. */
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
 * Çağıranın borcu görebileceği daireler. Kural (F2.05 responsible_party): owner -> güncel malik, tenant -> güncel kiracı, both -> malik + kiracı +
 * belirsiz ilişki (resident); family_member HİÇBİR durumda görmez. Eşleşen güncel (aktif) kişi hiç yoksa güvenli yedek: dairenin güncel
 * resident/owner/tenant ilişkili kişileri görür (borç sahipsiz kalmasın). Yalnız onaylı siteler. `visible_from`: çağıranın bu dairedeki güncel
 * ilişkisinin taşınma ayı (taşınma tarihi boşsa ilişkinin kayıt günü, İstanbul takvimi; birden çok kişi kaydı varsa en erkeni). Ziyaretçi
 * kayıtlarındaki "önceki sakinin kayıtları yeni sakine görünmez" kuralıyla aynı ilke (visitor_log_resident.js).
 */
export async function loadVisibleApartments(db, userCode) {
  const result = await db.query(
    `
      SELECT
        a.id AS apartment_id, a.site_code, s.name AS site_name, a.unit_label, b.block_name, b.sort_order AS block_sort,
        a.sort_order AS apt_sort, a.responsible_party,
        to_char(date_trunc('month', MIN(LEAST(
          COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE),
          -- Aynı kişinin aynı dairedeki kesintisiz önceki ilişkisi (ör. kiracıyken daireyi satın aldı): kendi eski kayıtlarını görmeye devam eder.
          COALESCE((
            SELECT MIN(COALESCE(p.move_in_date, (p.created_at AT TIME ZONE 'Europe/Istanbul')::DATE))
            FROM apartment_residencies p
            WHERE p.person_id = r.person_id AND p.apartment_id = r.apartment_id AND p.is_current = FALSE
              -- Yalnız borcu görebileceği bir ilişki sayılır (ör. malik sorumluyken kiracılık dönemi sayılmaz: önceki malikin kayıtları sızmaz).
              AND p.relation <> 'family_member' AND p.relation = ANY(${ALLOWED_RELATIONS_SQL}) AND p.move_out_date IS NOT NULL
              AND p.move_out_date >= COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE) - 1
          ), COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE))
        ))), 'YYYY-MM-DD') AS visible_from,
        -- Sakinin bu dairedeki ilişki kaydının (kesintisiz önceki ilişki dahil) açıldığı an: bundan önce düzenlenmiş makbuzlarda ödeyen
        -- adı sakine gösterilmez (o an daireye bağlı değildi; ad başka birine ait olabilir).
        MIN(LEAST(r.created_at, COALESCE((
          SELECT MIN(p.created_at)
          FROM apartment_residencies p
          WHERE p.person_id = r.person_id AND p.apartment_id = r.apartment_id AND p.is_current = FALSE
            AND p.relation <> 'family_member' AND p.relation = ANY(${ALLOWED_RELATIONS_SQL}) AND p.move_out_date IS NOT NULL
            AND p.move_out_date >= COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE) - 1
        ), r.created_at))) AS relation_since_at
      FROM site_people sp
      INNER JOIN apartment_residencies r ON r.person_id = sp.id AND r.is_current = TRUE
      INNER JOIN apartments a ON a.id = r.apartment_id AND a.site_code = sp.site_code
      INNER JOIN site_blocks b ON b.id = a.block_id
      INNER JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      WHERE sp.user_code = $1 AND sp.is_active = TRUE
        AND r.relation <> 'family_member'
        AND (
          r.relation = ANY(${ALLOWED_RELATIONS_SQL})
          OR NOT EXISTS (
            SELECT 1
            FROM apartment_residencies r2
            INNER JOIN site_people sp2 ON sp2.id = r2.person_id AND sp2.is_active = TRUE
            WHERE r2.apartment_id = a.id AND r2.is_current = TRUE AND r2.relation = ANY(${ALLOWED_RELATIONS_SQL})
          )
        )
      GROUP BY a.id, a.site_code, s.name, a.unit_label, b.block_name, b.sort_order, a.sort_order, a.responsible_party
      ORDER BY s.name, b.sort_order, a.sort_order, a.id
    `,
    [userCode],
  );
  return result.rows ?? [];
}

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

/**
 * GET /app/my-finance -> { items: [...] } (bkz. dosya başı). Bakiye, vadesi geçmiş tutar ve sıradaki vade sakin kapsamıyla ve mahsup kuralıyla
 * (finance_resident_view.residentView) hesaplanır; `recent` yalnız görünen satırlardır. `visible_from` ('YYYY-MM') yalnız kapsam
 * dışında kalan kayıt VARSA dolar (sakine "Kayıtlar … ayından itibaren" notu gösterilir).
 */
export async function getMyFinance(authUser, now = new Date(), db = pool) {
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
  if (userCode === null) {
    return { items: [] };
  }
  await syncUserPeopleSafe(userCode);
  const visible = await loadVisibleApartments(db, userCode);
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
      const since = residentSinceOf(row, todayIsoDate);
      const view = residentView(rows.map(residentEntryOf), { since, today: todayIsoDate });
      const shown = rows.filter((entry) => view.visibleIds.has(Number(entry.id)));
      // Görünen satırların toplamı bakiyeye eşit değilse bir tahsilat ya da alacak önceki dönem kayıtlarıyla mahsup edilmiştir: istemci açıklar.
      const shownSum = shown.reduce((sum, entry) => sum + BigInt(entry.amount_minor), 0n);
      const recent = shown
        .sort((a, b) => (a.entry_date === b.entry_date ? Number(b.id) - Number(a.id) : a.entry_date < b.entry_date ? 1 : -1))
        .slice(0, RECENT_ENTRIES_LIMIT)
        .map((entry) => redactEntryForResident(mapEntryRow(entry)));
      return {
        site_code: Number(row.site_code),
        site_name: row.site_name ?? null,
        apartment_id: id,
        label: apartmentLabel(row.block_name, row.unit_label),
        block_name: row.block_name ?? null,
        currency: 'TRY',
        balance_minor: minorToNumber(view.balance),
        overdue_minor: minorToNumber(view.overdue),
        next_due_date: view.nextDue ? view.nextDue.dueDate : null,
        next_due_minor: view.nextDue ? minorToNumber(view.nextDue.amount) : null,
        payer_party: row.responsible_party,
        // Kapsam dışında kalan kayıt varsa başlangıç ayı ('YYYY-MM'); istemci bunu sakine açıkça yazar.
        visible_from: view.hiddenCount > 0 ? periodLabel(since) : null,
        offset_note: shownSum !== view.balance,
        recent,
      };
    }),
  };
}
