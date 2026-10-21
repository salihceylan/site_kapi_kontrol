// Ortak yardimcilar: deterministik rastgele (tohumlu), tarih, para. Hicbir DB/ag bagimliligi yok.

/** mulberry32: kucuk, hizli, tohumlu rastgele uretec. */
export function makeRng(seed = 20261022) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const rng = {
    next,
    float: (min = 0, max = 1) => min + next() * (max - min),
    int: (min, max) => Math.floor(min + next() * (max - min + 1)),
    chance: (p) => next() < p,
    pick: (list) => list[Math.floor(next() * list.length)],
    /** Ortalama mean, sapma sd (Box-Muller). */
    normal: (mean = 0, sd = 1) => {
      let u = 0;
      let v = 0;
      while (u === 0) u = next();
      while (v === 0) v = next();
      return mean + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
    },
    shuffle: (list) => {
      const out = [...list];
      for (let i = out.length - 1; i > 0; i -= 1) {
        const j = Math.floor(next() * (i + 1));
        [out[i], out[j]] = [out[j], out[i]];
      }
      return out;
    },
    /** Agirlikli secim: [[deger, agirlik], ...] */
    weighted: (pairs) => {
      const total = pairs.reduce((s, p) => s + p[1], 0);
      let r = next() * total;
      for (const [value, weight] of pairs) {
        r -= weight;
        if (r <= 0) return value;
      }
      return pairs[pairs.length - 1][0];
    },
  };
  return rng;
}

// --- tarih (UTC gun numarasi uzerinden; Istanbul takvimi icin yalnizca 'YYYY-MM-DD' metni kullanilir) ---------------

export const dayNo = (iso) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10))) / 86400000;
export const isoOf = (n) => new Date(n * 86400000).toISOString().slice(0, 10);
export const addDays = (iso, days) => isoOf(dayNo(iso) + days);
export const diffDays = (a, b) => dayNo(a) - dayNo(b);
export const periodOf = (iso) => `${iso.slice(0, 7)}-01`;
export const ymOf = (iso) => iso.slice(0, 7);

export function addMonths(iso, months) {
  const y = Number(iso.slice(0, 4));
  const m = Number(iso.slice(5, 7)) - 1 + months;
  const yy = y + Math.floor(m / 12);
  const mm = ((m % 12) + 12) % 12;
  return `${String(yy).padStart(4, '0')}-${String(mm + 1).padStart(2, '0')}-${iso.slice(8, 10)}`;
}

export function daysInMonth(ym) {
  const y = Number(ym.slice(0, 4));
  const m = Number(ym.slice(5, 7));
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

export const clampDay = (ym, day) => `${ym}-${String(Math.min(day, daysInMonth(ym))).padStart(2, '0')}`;

/** 'YYYY-MM' listesi (iki uc dahil). */
export function monthsBetween(fromYm, toYm) {
  const out = [];
  let cur = `${fromYm}-01`;
  const end = `${toYm}-01`;
  while (cur <= end) {
    out.push(cur.slice(0, 7));
    cur = addMonths(cur, 1);
  }
  return out;
}

/** 0=Pazar ... 6=Cumartesi */
export const weekdayOf = (iso) => new Date(`${iso}T00:00:00Z`).getUTCDay();
export const isWeekend = (iso) => [0, 6].includes(weekdayOf(iso));

/** Hafta sonuna denk gelirse sonraki is gunune kaydirir. */
export function nextBusinessDay(iso) {
  let d = iso;
  while (isWeekend(d)) d = addDays(d, 1);
  return d;
}

/** Istanbul 12:00 yerel an (UTC+3, sabit) -> Date. */
export const noonIstanbul = (iso) => new Date(`${iso}T09:00:00.000Z`);

/** Istanbul yerel saat metni ('YYYY-MM-DD', 'HH:MM') -> ISO zaman damgasi (UTC+03:00). */
export const tsIstanbul = (iso, hhmm = '12:00') => `${iso}T${hhmm}:00+03:00`;

// --- para (kurus tamsayi) ----------------------------------------------------------------------------------------

export const tl = (liras) => Math.round(liras * 100);
/** Kurusu 'YYYY.NN TL' bicimine cevirir (rapor ozeti icin). */
export const fmtTl = (minor) => `${(Number(minor) / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} TL`;

/** En yakin 50 kurusa yuvarla (gercekci fatura tutari icin degil, aidat icin 10 TL'ye). */
export const roundTo = (minor, step) => Math.round(minor / step) * step;

export function sum(list) {
  return list.reduce((s, v) => s + v, 0);
}

export function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}
