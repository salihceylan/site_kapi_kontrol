// Finans Faz 4b: işlem içi (DB) tarih / dönem denetimleri. 4a kuralları: kapalı dönem = period <= MAX(kapalı); tarih bugünden en çok 5 yıl öncesi; gelecek yok.

import {
  addMonths,
  assertNotTooOld,
  computeOpenPeriod,
  currentPeriod,
  invalidBody,
  latestClosedPeriod,
  minEntryDate,
  periodClosed,
  periodOfDate,
  today,
} from './finance_common.js';
import { isPeriodClosed } from './finance_tx.js';

/** Site kapanışları (artan, 'YYYY-MM-DD'). */
export async function loadClosedPeriods(db, siteCode) {
  const result = await db.query(
    `SELECT to_char(period, 'YYYY-MM-DD') AS period FROM finance_period_closures WHERE site_code = $1 ORDER BY period`,
    [siteCode],
  );
  return (result.rows ?? []).map((row) => row.period);
}

/** Bugünün AÇIK dönemi (bugünün ayı kapalıysa sonraki açık ay): ters kayıtlar / iptaller bu aya yazılır. */
export async function resolveOpenPeriod(db, siteCode, now = new Date()) {
  const closed = await loadClosedPeriods(db, siteCode);
  return computeOpenPeriod(currentPeriod(now), new Set(closed));
}

/** En erken YAZILABİLİR gün: kapanış varsa closed_through + 1 ay; yoksa 5 yıllık alt sınır. */
export async function earliestWritableDate(db, siteCode, now = new Date()) {
  const closed = await loadClosedPeriods(db, siteCode);
  const latest = latestClosedPeriod(closed);
  return latest === null ? minEntryDate(now) : addMonths(latest, 1);
}

/**
 * Yazılacak kayıt tarihi: bugünden ileri olamaz (400), 5 yıldan eski olamaz (400), ayı KAPALI olamaz (409 PERIOD_CLOSED).
 * @returns {Promise<string>} dönem 'YYYY-MM-01'
 */
export async function assertWritableDate(db, siteCode, dateIso, label, now = new Date()) {
  if (dateIso > today(now)) {
    throw invalidBody(`${label} gelecek bir tarih olamaz.`);
  }
  assertNotTooOld(dateIso, label, now);
  const period = periodOfDate(dateIso);
  if (await isPeriodClosed(db, siteCode, period)) {
    throw periodClosed();
  }
  return period;
}
