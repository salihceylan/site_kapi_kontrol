// Rezervasyon: dilim üretimi, istenen aralığın çözümü ve eşzamanlılık sayımı (saf, DB bağımsız).
//
// Sözleşme: docs/PLATFORM_REZERVASYON.md "Rezervasyon kuralları". Alan: { slot_minutes, weekly_hours: [{ weekday, start, end }] } (saatler "HH:MM", bitiş "24:00" olabilir).
// Dilim ızgarası her açık aralığın BAŞLANGICINDAN slot_minutes adımlıdır; aralığa sığmayan son parça dilim sayılmaz.

import { formatHhmm, istanbulToUtc, parseHhmm, weekdayOf } from './reservation_time.js';

/** Bir haftanın gününün açık aralıkları (dakika), başlangıca göre sıralı. */
export function windowsOn(weeklyHours, weekday) {
  return (Array.isArray(weeklyHours) ? weeklyHours : [])
    .filter((entry) => Number(entry?.weekday) === weekday)
    .map((entry) => ({ startMin: parseHhmm(entry.start), endMin: parseHhmm(entry.end, { allow24: true }) }))
    .filter((entry) => entry.startMin !== null && entry.endMin !== null && entry.endMin > entry.startMin)
    .sort((a, b) => a.startMin - b.startMin);
}

/**
 * Bir takvim gününün tüm dilimleri: [{ windowIndex, startMin, endMin, startsAt: Date, endsAt: Date }].
 * Yalnız zaman damgaları gün için hesaplanır (DST güvenli: her uç noktası İstanbul yerel -> UTC çevrilir).
 */
export function slotsForDate(area, dateStr) {
  const slots = [];
  const step = Number(area.slot_minutes);
  windowsOn(area.weekly_hours, weekdayOf(dateStr)).forEach((window, windowIndex) => {
    for (let start = window.startMin; start + step <= window.endMin; start += step) {
      slots.push({ windowIndex, startMin: start, endMin: start + step, startsAt: istanbulToUtc(dateStr, start), endsAt: istanbulToUtc(dateStr, start + step) });
    }
  });
  return slots;
}

/**
 * İstenen (gün, başlangıç dakikası, dilim sayısı) açık saatlere ve ızgaraya uyuyor mu? Uyuyorsa { startsAt, endsAt, slots }, uymuyorsa null.
 * Rezervasyon TEK açık aralıkta ardışık dilimlerden oluşur.
 */
export function resolveRange(area, dateStr, startMin, count) {
  const slots = slotsForDate(area, dateStr);
  const index = slots.findIndex((slot) => slot.startMin === startMin);
  if (index < 0 || index + count > slots.length) return null;
  const picked = slots.slice(index, index + count);
  if (picked.some((slot) => slot.windowIndex !== picked[0].windowIndex)) return null;
  return { startsAt: picked[0].startsAt, endsAt: picked[picked.length - 1].endsAt, slots: picked };
}

/**
 * [from, to) içinde herhangi bir anda çakışan aralık sayısının en büyüğü. intervals: [{ start, end }] (ms ya da Date).
 * Bitiş dışlayıcıdır: biri 10:00'da biterken öteki 10:00'da başlıyorsa çakışmaz.
 */
export function maxConcurrent(intervals, from, to) {
  const lo = Number(from);
  const hi = Number(to);
  const events = [];
  for (const interval of intervals) {
    const start = Math.max(Number(interval.start), lo);
    const end = Math.min(Number(interval.end), hi);
    if (end > start) events.push([start, 1], [end, -1]);
  }
  // aynı anda önce bitişler (-1), sonra başlangıçlar (+1)
  events.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let current = 0;
  let peak = 0;
  for (const [, delta] of events) {
    current += delta;
    if (current > peak) peak = current;
  }
  return peak;
}

/** Açık saat girdisini (zaten doğrulanmış) sıralı, normalize listeye çevirir. */
export function normalizeHoursList(entries) {
  return entries
    .map((entry) => ({ weekday: entry.weekday, start: formatHhmm(entry.startMin), end: formatHhmm(entry.endMin) }))
    .sort((a, b) => a.weekday - b.weekday || (a.start < b.start ? -1 : a.start > b.start ? 1 : 0));
}
