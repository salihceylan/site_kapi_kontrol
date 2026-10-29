// Kampanya "şimdi abone olana 2 ay ücretsiz" (115: sites.subscription_started_at + sites.free_until). Saf yardımcılar + onay anındaki tek UPDATE.
//
// Kural: site başvurusu ONAYLANIRKEN abonelik başlangıcı = bugün, ücretsiz dönem sonu = bugün + 2 ay (Europe/Istanbul takvimi; kampanya varsayılanı).
// Süper kullanıcı site düzenlemesiyle iki tarihi değiştirebilir ya da temizleyebilir. Mevcut sitelere dokunulmaz (NULL = kampanyadan önce / tanımsız).
// Bu alanlar bir İŞARETTİR: özellik kilitlemez, fiyat / ödeme tutmaz (fiyat bu depoda yoktur). Bu dosya db.js'i İÇE AKTARMAZ.

import { diffDays, todayIstanbul } from './reservation_time.js';

export const FREE_PERIOD_MONTHS = 2;

/**
 * Onay işlemi (TEK transaction) içinde çağrılır: yeni sitenin abonelik başlangıcını ve ücretsiz dönem sonunu yazar.
 * Yalnız iki alan da BOŞSA yazar (yeniden çalıştırma / elle girilmiş değer ezilmez). DB oturum saat dilimi Europe/Istanbul'dur (db.js options),
 * CURRENT_DATE İstanbul gününü verir; ay eklemesi PG kuralıyla ay sonuna kırpılır (31 Ara + 2 ay = 28/29 Şub).
 */
export async function applyApprovalFreePeriod(client, siteCode) {
  await client.query(
    `UPDATE sites SET subscription_started_at = CURRENT_DATE, free_until = (CURRENT_DATE + make_interval(months => $2))::DATE
     WHERE site_code = $1 AND subscription_started_at IS NULL AND free_until IS NULL`,
    [siteCode, FREE_PERIOD_MONTHS],
  );
}

/** "YYYY-MM-DD" gerçek bir takvim günü mü (2020-2100)? */
export function isValidIsoDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d && y >= 2020 && y <= 2100;
}

/** DB değeri (to_char metni ya da Date) -> "YYYY-MM-DD" ya da null. */
function toIsoDay(value) {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : todayIstanbul(value);
  const text = String(value).slice(0, 10);
  return isValidIsoDate(text) ? text : null;
}

/**
 * PATCH gövdesinden iki tarih alanı. Her alan: undefined (gönderilmedi) | null (temizle) | "YYYY-MM-DD".
 * @returns {{ value?: { subscriptionStartedAt: string|null|undefined, freeUntil: string|null|undefined }, error?: string }}
 */
export function parseFreePeriodBody(body) {
  const source = body && typeof body === 'object' ? body : {};
  const read = (key, label) => {
    const raw = source[key];
    if (raw === undefined) return { ok: true, value: undefined };
    if (raw === null) return { ok: true, value: null };
    if (!isValidIsoDate(raw)) return { ok: false, error: `${label} YYYY-AA-GG biçiminde geçerli bir tarih olmalı (ya da null).` };
    return { ok: true, value: raw };
  };
  const started = read('subscription_started_at', 'Abonelik başlangıcı');
  if (!started.ok) return { error: started.error };
  const freeUntil = read('free_until', 'Ücretsiz dönem sonu');
  if (!freeUntil.ok) return { error: freeUntil.error };
  return { value: { subscriptionStartedAt: started.value, freeUntil: freeUntil.value } };
}

/** Birleşik (yeni değer, yoksa mevcut) çifti için sıra denetimi: ücretsiz dönem sonu abonelik başlangıcından önce olamaz. Hata metni ya da null. */
export function freePeriodOrderError(startedAt, freeUntil) {
  const a = toIsoDay(startedAt);
  const b = toIsoDay(freeUntil);
  if (a && b && b < a) return 'Ücretsiz dönem sonu abonelik başlangıcından önce olamaz.';
  return null;
}

/**
 * API alanları (mapSiteRow'a eklenir; eski istemciler yok sayar). free_period_state:
 *  - 'none'   : ücretsiz dönem tanımsız (free_until boş; kampanyadan önceki siteler),
 *  - 'active' : free_until bugün ya da gelecekte (son gün DAHİL ücretsiz); free_period_days_left = bugünden o güne gün sayısı (bugün = 0),
 *  - 'ended'  : free_until geçmişte.
 */
export function freePeriodFields(row, now = new Date()) {
  const startedAt = toIsoDay(row?.subscription_started_at);
  const freeUntil = toIsoDay(row?.free_until);
  if (!freeUntil) {
    return { subscription_started_at: startedAt, free_until: null, free_period_state: 'none', free_period_days_left: null };
  }
  const left = diffDays(todayIstanbul(now), freeUntil);
  return {
    subscription_started_at: startedAt,
    free_until: freeUntil,
    free_period_state: left >= 0 ? 'active' : 'ended',
    free_period_days_left: left >= 0 ? left : null,
  };
}
