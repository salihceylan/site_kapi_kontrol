// Rezervasyon: zaman dönüşümü TEK YERDE (saf, DB bağımsız).
//
// Sözleşme: docs/PLATFORM_REZERVASYON.md "Zaman kuralları". Tüm takvim hesabı (gün, hafta, açık saatler) Europe/Istanbul yerel zamanına göredir; saklama UTC timestamptz.
// Türkiye 2016'dan beri sabit +03'tür ama dönüşüm yine Intl (IANA) kaydından yapılır: ileride kural değişirse tek yer bu dosyadır. Intl çözülemezse +03 sabitine düşer.
// Tarihler "YYYY-MM-DD" metni (takvim günü), saatler gün başından dakika sayısıdır (0-1440).

export const ISTANBUL_TZ = 'Europe/Istanbul';
const FALLBACK_OFFSET_MINUTES = 180;
const MINUTE_MS = 60_000;
const DAY_MS = 86_400_000;

let formatter;
function getFormatter() {
  if (formatter === undefined) {
    try {
      formatter = new Intl.DateTimeFormat('en-GB', {
        timeZone: ISTANBUL_TZ,
        hourCycle: 'h23',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
      });
      if (formatter.resolvedOptions().timeZone !== ISTANBUL_TZ) formatter = null;
    } catch (_error) {
      formatter = null;
    }
  }
  return formatter;
}

/** UTC anında İstanbul'un UTC'den farkı (dakika). */
export function offsetMinutesAt(ms) {
  const fmt = getFormatter();
  if (!fmt) return FALLBACK_OFFSET_MINUTES;
  const parts = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((part) => [part.type, part.value]));
  const asUtc = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour), Number(parts.minute), Number(parts.second));
  return Math.round((asUtc - Math.floor(ms / 1000) * 1000) / MINUTE_MS);
}

const pad = (value, width = 2) => String(value).padStart(width, '0');

export function formatDate(year, month, day) {
  return `${pad(year, 4)}-${pad(month)}-${pad(day)}`;
}

/** Takvim günü metni gerçek bir gün mü (2020-2100)? */
export function isValidDateStr(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d && y >= 2020 && y <= 2100;
}

/** Bir anın İstanbul yerel parçaları: { date, weekday (1=Pzt..7=Paz), minuteOfDay }. */
export function istanbulParts(input) {
  const ms = input instanceof Date ? input.getTime() : Number(input);
  const local = new Date(ms + offsetMinutesAt(ms) * MINUTE_MS);
  return {
    date: formatDate(local.getUTCFullYear(), local.getUTCMonth() + 1, local.getUTCDate()),
    weekday: ((local.getUTCDay() + 6) % 7) + 1,
    minuteOfDay: local.getUTCHours() * 60 + local.getUTCMinutes(),
  };
}

export const todayIstanbul = (now = new Date()) => istanbulParts(now).date;

/** İstanbul yerel "tarih + dakika" -> UTC Date. minuteOfDay 1440 ertesi gün 00:00'dır. */
export function istanbulToUtc(dateStr, minuteOfDay = 0) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const naive = Date.UTC(y, m - 1, d, 0, minuteOfDay);
  const guess = naive - offsetMinutesAt(naive - FALLBACK_OFFSET_MINUTES * MINUTE_MS) * MINUTE_MS;
  return new Date(naive - offsetMinutesAt(guess) * MINUTE_MS);
}

export function addDays(dateStr, days) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + days));
  return formatDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
}

export function diffDays(fromDate, toDate) {
  const a = fromDate.split('-').map(Number);
  const b = toDate.split('-').map(Number);
  return Math.round((Date.UTC(b[0], b[1] - 1, b[2]) - Date.UTC(a[0], a[1] - 1, a[2])) / DAY_MS);
}

/** 1=Pazartesi .. 7=Pazar. */
export function weekdayOf(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number);
  return ((new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7) + 1;
}

export const weekStartOf = (dateStr) => addDays(dateStr, -(weekdayOf(dateStr) - 1));

/** Takvim gününün UTC aralığı [başlangıç, ertesi gün başlangıcı). */
export function dayRangeUtc(dateStr) {
  return { start: istanbulToUtc(dateStr, 0), end: istanbulToUtc(addDays(dateStr, 1), 0) };
}

/** İstanbul haftasının (Pzt-Paz) UTC aralığı. */
export function weekRangeUtc(dateStr) {
  const monday = weekStartOf(dateStr);
  return { start: istanbulToUtc(monday, 0), end: istanbulToUtc(addDays(monday, 7), 0) };
}

/** "HH:MM" -> dakika; allow24: "24:00" geçerli (yalnız aralık bitişi). Geçersizse null. */
export function parseHhmm(value, { allow24 = false } = {}) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const minutes = Number(match[1]) * 60 + Number(match[2]);
  if (Number(match[2]) > 59 || minutes > (allow24 ? 1440 : 1439)) return null;
  return minutes;
}

export function formatHhmm(minutes) {
  return `${pad(Math.floor(minutes / 60))}:${pad(minutes % 60)}`;
}
