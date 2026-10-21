// M1 mahsup kuralı (TBK m.102; docs/PLATFORM_FINANS_4B.md "4b ilkeleri" madde 3) — yaşlandırma, gecikme tazminatı ve borç hatırlatmanın ORTAK tanımı.
//
// Tarih T itibarıyla (tarihli model): kalemler = entry_date <= T olan ve ters kaydı (entry_date <= T) OLMAYAN `charge` kayıtları (aidat, ek borç, gecikme tazminatı
// kalemleri dahil), sıra (vade, id) artan; ödemeler = entry_date <= T olan ve ters kaydı (<= T) olmayan `payment` toplamı Pay(T). Kalem i'nin kalanı
//   rem_i = min(a_i, max(0, C_i - Pay))   (C_i = sıradaki ilk i kalemin toplamı); artık ödeme = alacak.
// Bu kural 4a `overdue_minor` ile TOPLAMDA uyumludur: Σ rem_i (vade <= T) = max(0, bakiye - vadesi gelmemiş) (T = bugün).
//
// Bu dosya hem SQL parçalarını (DB hesabı) hem saf BigInt referans uygulamasını içerir; ikisi QA'da birbiriyle ve kaba kuvvet simülatörüyle karşılaştırılır.
// PARA BigInt'tir; kayan nokta yok.
// İki hesap (İP-1A): mahsup HESAP BAZINDADIR (ev sahibi hesabının ödemesi kiracı hesabının borcunu kapatmaz): CTE'ler (daire, hesap) bölümlüdür ve
// `account_party` sütunu taşır (052 öncesi satırın hesabı payer_party'den türetilir: finance_parties.accountPartySql).

import { accountPartySql } from './finance_parties.js';

const M1_ACCOUNT = accountPartySql('l');

export const AGING_BUCKETS = Object.freeze(['not_due', 'd0_30', 'd31_60', 'd61_90', 'd91_180', 'd181_365', 'd366_plus']);

/** Gecikme günü (T - vade) -> kova adı; vade > T (gün < 0) = not_due. */
export function bucketOfDaysLate(days) {
  if (days < 0) return 'not_due';
  if (days <= 30) return 'd0_30';
  if (days <= 60) return 'd31_60';
  if (days <= 90) return 'd61_90';
  if (days <= 180) return 'd91_180';
  if (days <= 365) return 'd181_365';
  return 'd366_plus';
}

/**
 * Saf M1: items sıralı (vade artan, id artan) [{ amount: bigint }] ve toplam ödeme (bigint) -> kalan dizisi (bigint[]).
 * Artık ödeme (alacak) `credit` olarak ayrıca döner.
 */
export function m1Remainders(items, pay) {
  const rem = [];
  let cumulative = 0n;
  for (const item of items) {
    cumulative += item.amount;
    const open = cumulative - pay;
    const clipped = open < 0n ? 0n : open;
    rem.push(clipped < item.amount ? clipped : item.amount);
  }
  const credit = pay > cumulative ? pay - cumulative : 0n;
  return { rem, credit };
}

/**
 * SQL: T tarihi itibarıyla her kalemin kalanı. `siteParam` / `dateParam`: '$1' / '$2' gibi parametre yer tutucuları. `apartmentClause`: isteğe bağlı
 * ek süzgeç (ör. ' AND l.apartment_id = ANY($3::BIGINT[])'). Çıktı CTE'leri: items(id, apartment_id, account_party, a, due, is_lf, c),
 * pay(apartment_id, account_party, p), rem(apartment_id, account_party, due, is_lf, r, a). Mahsup (daire, hesap) bölümlüdür (İP-1A).
 * Ters kayıt aramaları `uq_ledger_entries_reverses` indeksini, kalemler (site_code, ...) indekslerini kullanır; yalnız site satırları okunur.
 */
export function m1Ctes(siteParam, dateParam, apartmentClause = '') {
  return `
    items AS (
      SELECT
        l.id, l.apartment_id, ${M1_ACCOUNT} AS account_party, l.amount_minor AS a, COALESCE(l.due_date, l.entry_date) AS due, (l.late_fee_run_id IS NOT NULL) AS is_lf,
        SUM(l.amount_minor) OVER (PARTITION BY l.apartment_id, ${M1_ACCOUNT} ORDER BY COALESCE(l.due_date, l.entry_date), l.id) AS c
      FROM ledger_entries l
      WHERE l.site_code = ${siteParam} AND l.kind = 'charge' AND l.entry_date <= ${dateParam}::DATE${apartmentClause}
        AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id AND rv.entry_date <= ${dateParam}::DATE)
    ),
    pay AS (
      SELECT l.apartment_id, ${M1_ACCOUNT} AS account_party, -SUM(l.amount_minor) AS p
      FROM ledger_entries l
      WHERE l.site_code = ${siteParam} AND l.kind = 'payment' AND l.entry_date <= ${dateParam}::DATE${apartmentClause}
        AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id AND rv.entry_date <= ${dateParam}::DATE)
      GROUP BY 1, 2
    ),
    rem AS (
      SELECT i.apartment_id, i.account_party, i.due, i.is_lf, i.a, LEAST(i.a, GREATEST(0, i.c - COALESCE(p.p, 0))) AS r
      FROM items i LEFT JOIN pay p ON p.apartment_id = i.apartment_id AND p.account_party = i.account_party
    )
  `;
}

/** Kova toplamları için SQL FILTER ifadeleri (rem CTE'si; `dateParam` T). Sütun adları `<kova>`. */
export function bucketSumSql(dateParam) {
  const days = `(${dateParam}::DATE - rem.due)`;
  return `
    COALESCE(SUM(rem.r) FILTER (WHERE rem.due > ${dateParam}::DATE), 0) AS not_due,
    COALESCE(SUM(rem.r) FILTER (WHERE rem.due <= ${dateParam}::DATE AND ${days} <= 30), 0) AS d0_30,
    COALESCE(SUM(rem.r) FILTER (WHERE ${days} BETWEEN 31 AND 60), 0) AS d31_60,
    COALESCE(SUM(rem.r) FILTER (WHERE ${days} BETWEEN 61 AND 90), 0) AS d61_90,
    COALESCE(SUM(rem.r) FILTER (WHERE ${days} BETWEEN 91 AND 180), 0) AS d91_180,
    COALESCE(SUM(rem.r) FILTER (WHERE ${days} BETWEEN 181 AND 365), 0) AS d181_365,
    COALESCE(SUM(rem.r) FILTER (WHERE ${days} >= 366), 0) AS d366_plus,
    COALESCE(SUM(rem.r) FILTER (WHERE rem.due <= ${dateParam}::DATE AND rem.is_lf), 0) AS late_fee_outstanding
  `;
}
