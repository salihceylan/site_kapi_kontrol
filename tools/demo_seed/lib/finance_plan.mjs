// Finans plani (SAF hesap; DB yok): aidat tutarlari, tahsilat deseni, gider takvimi, kasa/banka benzetimi.
// Cikti: servislere (finance_service, finance_ledger_service, finance_expenses, finance_accounts) verilecek olay listesi.

import {
  addDays, clampDay, diffDays, isWeekend, monthsBetween, nextBusinessDay, weekdayOf, ymOf,
} from './util.mjs';

export const TR_MONTHS = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
export const monthLabel = (ym) => `${TR_MONTHS[Number(ym.slice(5, 7)) - 1]} ${ym.slice(0, 4)}`;

/** Yillik ortalama aylik aidat (TL, daire basina). */
export const AVG_DUES_TL = { 2023: 1500, 2024: 2400, 2025: 3500, 2026: 4800 };

export const PROFILES = ['punctual', 'slow30', 'punctual', 'chronicA', 'prepay', 'punctual', 'slow60', 'chronicB', 'punctual', 'slow30'];
export const profileOfIndex = (i) => PROFILES[i % PROFILES.length];

const CHRONIC = {
  chronicA: { stallFrom: '2026-04', partial: { date: '2026-07-14', fractionOfCharge: 0.5 } },
  chronicB: { stallFrom: '2026-08' },
};

const sortedUnique = (list) => [...new Set(list)].sort();

/**
 * Bir hesap satiri (borc) icin odeme tarihlerini ve tutarlarini planlar.
 * charge: { id, apartment_id, account_party, amount_minor, entry_date, due_date, period }
 * dondurur: [{ date, amountMinor }]  (TODAY'den sonrasi atilir)
 */
export function planChargePayments({ profile, aptSeed, charge, rng, today, start, prepayQuarterFor }) {
  const due = charge.due_date ?? charge.entry_date;
  const ym = ymOf(charge.entry_date);
  const amount = Number(charge.amount_minor);
  const cfg = CHRONIC[profile];
  const out = [];
  const push = (date, amountMinor) => {
    if (amountMinor <= 0) return;
    out.push({ date, amountMinor });
  };
  let delay;
  switch (profile) {
    case 'punctual':
      delay = rng.chance(0.07) ? rng.int(15, 35) : Math.max(-3, Math.round(rng.normal(2, 2.5)));
      break;
    case 'slow30':
      delay = Math.round(rng.normal(31, 5));
      break;
    case 'slow60':
      delay = Math.round(rng.normal(62, 7));
      break;
    case 'chronicA':
      if (ym >= cfg.stallFrom) return [];
      delay = Math.round(rng.normal(34, 6));
      break;
    case 'chronicB':
      if (ym >= cfg.stallFrom) return [];
      delay = Math.round(rng.normal(60, 8));
      break;
    case 'prepay':
      return prepayQuarterFor(charge);
    default:
      delay = 3;
  }
  let date = addDays(due, delay);
  if (date < start) date = start;
  if (rng.chance(0.08) && delay > -1) {
    const first = Math.round(amount * 0.6);
    push(date, first);
    push(addDays(date, rng.int(8, 20)), amount - first);
  } else {
    push(date, amount);
  }
  return out.filter((p) => p.date <= today);
}

/** Kismi odeme (kronik daire): dondurulen odemeyi son ekstraya ekler. */
export function chronicPartial(profile, charges, today) {
  const cfg = CHRONIC[profile];
  if (!cfg?.partial) return [];
  if (cfg.partial.date > today) return [];
  const target = charges.filter((c) => ymOf(c.entry_date) >= cfg.stallFrom)[0];
  if (!target) return [];
  return [{ chargeId: target.id, date: cfg.partial.date, amountMinor: Math.round(Number(target.amount_minor) * cfg.partial.fractionOfCharge) }];
}

/** Hafta sonu/ay sonu desenleri: havale/cek hafta icine, nakit pazar disina. */
export function adjustPaymentDate(date, method) {
  if (method === 'cash') {
    return weekdayOf(date) === 0 ? addDays(date, 1) : date;
  }
  return nextBusinessDay(date);
}

// --- Gider takvimi -------------------------------------------------------------------------------------------------------

const GAS_WEIGHTS = [1.9, 1.7, 1.2, 0.5, 0.2, 0.1, 0.1, 0.1, 0.2, 0.6, 1.3, 1.8];
const ELEC_SEASON = [1.3, 1.25, 1.1, 0.95, 0.85, 0.8, 0.85, 0.85, 0.9, 1.0, 1.15, 1.3];
const WATER_SEASON = [0.9, 0.9, 0.95, 1.0, 1.1, 1.2, 1.3, 1.3, 1.1, 1.0, 0.95, 0.9];

export const SUPPLIERS = [
  { key: 'elec', name: 'Örnek Elektrik Dağıtım A.Ş. (Demo)' },
  { key: 'water', name: 'Örnek Su ve Kanalizasyon İdaresi (Demo)' },
  { key: 'gas', name: 'Örnek Doğalgaz Dağıtım A.Ş. (Demo)' },
  { key: 'lift', name: 'Mavi Asansör Bakım Ltd. Şti. (Demo)' },
  { key: 'clean', name: 'Berrak Temizlik Hizmetleri (Demo)' },
  { key: 'garden', name: 'Yeşil Vadi Peyzaj (Demo)' },
  { key: 'insure', name: 'Güven Sigorta Aracılık (Demo)' },
  { key: 'stationery', name: 'Köşe Kırtasiye (Demo)' },
  { key: 'tech', name: 'Çözüm Teknik Servis (Demo)' },
  { key: 'boiler', name: 'Isıtek Kazan Servisi (Demo)' },
  { key: 'paint', name: 'Pınar Boya ve Yapı (Demo)' },
  { key: 'lock', name: 'Hızlı Çilingir (Demo)' },
  { key: 'cleansup', name: 'Beyaz Temizlik Malzemeleri (Demo)' },
];

/** Beklenmedik giderler (ay, kategori, aciklama, carpan x aylik toplam aidat, tedarikci, ekipman anahtari). */
export const UNEXPECTED = [
  { ym: '2023-07', cat: 'Asansör bakım', text: 'Asansör kumanda kartı ve motor arızası onarımı', mult: 2.4, supplier: 'lift', equip: 'lift1' },
  { ym: '2023-11', cat: 'Bakım-onarım', text: 'Hidrofor pompası değişimi', mult: 1.6, supplier: 'tech', equip: 'hydro' },
  { ym: '2024-02', cat: 'Bakım-onarım', text: 'Çatı su yalıtımı onarımı', mult: 3.0, supplier: 'paint' },
  { ym: '2024-04', cat: 'Asansör bakım', text: 'Asansör modernizasyonu (kumanda ve kabin yenileme)', mult: 5.2, supplier: 'lift', equip: 'lift2', funded: 'lift' },
  { ym: '2024-09', cat: 'Bakım-onarım', text: 'Kazan brülörü arıza onarımı', mult: 2.0, supplier: 'boiler', equip: 'boiler' },
  { ym: '2025-01', cat: 'Bakım-onarım', text: 'Jeneratör aküsü ve genel bakım', mult: 0.8, supplier: 'tech', equip: 'genset' },
  { ym: '2025-06', cat: 'Bakım-onarım', text: 'Dış cephe boya ve onarım işi (ilk hakediş)', mult: 6.5, supplier: 'paint', funded: 'paint' },
  { ym: '2025-07', cat: 'Bakım-onarım', text: 'Dış cephe boya ve onarım işi (ikinci hakediş)', mult: 5.0, supplier: 'paint', funded: 'paint' },
  { ym: '2025-12', cat: 'Bakım-onarım', text: 'Otopark bariyeri motor değişimi', mult: 1.1, supplier: 'tech', equip: 'barrier' },
  { ym: '2026-03', cat: 'Bakım-onarım', text: 'Yangın algılama sistemi revizyonu', mult: 1.5, supplier: 'tech', equip: 'fire' },
  { ym: '2026-08', cat: 'Bakım-onarım', text: 'Su deposu temizliği ve kaçak onarımı', mult: 1.2, supplier: 'clean' },
];

/**
 * Ham gider listesi (olcek uygulanmadan): her ogenin raw = carpan x o yilin aylik toplam aidati (D).
 * dues: yil -> aylik toplam aidat (kurus). today: 'YYYY-MM-DD'. dondurur: [{date, cat, text, raw, supplier, nature, doc, key, equip}]
 */
export function buildRawExpenses({ dues, start, today, rng, receptionFrom = '2024-04' }) {
  const items = [];
  const months = monthsBetween(ymOf(start), ymOf(today));
  const add = (item) => {
    if (item.date > today || item.date < start) return;
    items.push({ nature: 'routine', doc: 'invoice', supplier: null, equip: null, key: null, ...item });
  };
  for (const ym of months) {
    const y = Number(ym.slice(0, 4));
    const mi = Number(ym.slice(5, 7)) - 1;
    const D = dues[y];
    const salaryDay = (day) => {
      let d = clampDay(ym, day);
      while (isWeekend(d)) d = addDays(d, -1);
      return d;
    };
    add({ date: salaryDay(27), cat: 'Personel', text: `${monthLabel(ym)} kapıcı maaşı`, raw: 0.285 * D, doc: 'none', key: 'salary' });
    if (ym >= receptionFrom) add({ date: salaryDay(27), cat: 'Personel', text: `${monthLabel(ym)} danışma görevlisi maaşı`, raw: 0.1 * D, doc: 'none', key: 'salary2' });
    add({ date: salaryDay(28), cat: 'Yönetici aylığı', text: `${monthLabel(ym)} yönetici aylığı`, raw: 0.035 * D, doc: 'none', key: 'manager' });
    add({ date: clampDay(ym, rng.int(14, 19)), cat: 'Elektrik', text: `${monthLabel(ym)} ortak alan elektrik faturası`, raw: 0.055 * D * ELEC_SEASON[mi] * rng.float(0.93, 1.07), supplier: 'elec', key: 'elec' });
    add({ date: clampDay(ym, rng.int(15, 21)), cat: 'Su', text: `${monthLabel(ym)} ortak alan su faturası`, raw: 0.065 * D * WATER_SEASON[mi] * rng.float(0.92, 1.08), supplier: 'water', key: 'water' });
    add({ date: clampDay(ym, rng.int(16, 22)), cat: 'Doğalgaz/Yakıt', text: `${monthLabel(ym)} merkezi ısıtma doğalgaz faturası`, raw: 0.075 * D * GAS_WEIGHTS[mi] * rng.float(0.94, 1.06), supplier: 'gas', key: 'gas' });
    add({ date: clampDay(ym, 10), cat: 'Asansör bakım', text: `${monthLabel(ym)} asansör aylık bakım bedeli`, raw: 0.05 * D, supplier: 'lift', key: 'lift', equip: 'liftMaint' });
    add({ date: clampDay(ym, 8), cat: 'Temizlik hizmeti', text: `${monthLabel(ym)} merdiven ve ortak alan temizliği`, raw: 0.06 * D, supplier: 'clean', key: 'clean' });
    add({ date: clampDay(ym, rng.int(3, 12)), cat: 'Temizlik malzemesi', text: `${monthLabel(ym)} temizlik malzemesi alımı`, raw: 0.012 * D * rng.float(0.7, 1.3), supplier: 'cleansup', key: 'supplies' });
    const garden = mi >= 3 && mi <= 9 ? 0.03 : 0.008;
    add({ date: clampDay(ym, 12), cat: 'Peyzaj ve Bahçe', text: `${monthLabel(ym)} bahçe bakım hizmeti`, raw: garden * D, supplier: 'garden', key: 'garden' });
    if (rng.chance(0.55)) add({ date: clampDay(ym, rng.int(4, 24)), cat: 'Kırtasiye ve Ofis', text: 'Kırtasiye ve ofis malzemesi', raw: 0.007 * D * rng.float(0.6, 1.4), supplier: 'stationery', key: 'stationery' });
    add({ date: clampDay(ym, 26), cat: 'Banka/noter masrafı', text: `${monthLabel(ym)} banka hesap işletim ve EFT masrafı`, raw: 0.004 * D, doc: 'none', key: 'bank' });
    if (rng.chance(0.7)) add({ date: clampDay(ym, rng.int(5, 25)), cat: 'Bakım-onarım', text: rng.pick(['Ampul ve aydınlatma armatürü değişimi', 'Kapı kilidi ve menteşe onarımı', 'Ortak alan küçük boya-badana', 'Boru tıkanıklığı açma', 'İnterkom ve zil onarımı']), raw: 0.04 * D * rng.float(0.5, 1.5), supplier: rng.pick(['tech', 'lock', 'paint']), key: 'repair' });
    if (mi === 2) add({ date: clampDay(ym, 12), cat: 'Sigorta', text: `${y} yılı DASK ve bina yangın sigortası`, raw: 0.9 * D, supplier: 'insure', key: 'insurance' });
    if (mi === 4) add({ date: clampDay(ym, 20), cat: 'Asansör bakım', text: `${y} yılı asansör periyodik kontrol ve etiket bedeli`, raw: 0.3 * D, supplier: 'lift', key: 'liftcheck', equip: 'liftCheck' });
    if (mi === 9) add({ date: clampDay(ym, 14), cat: 'Bakım-onarım', text: 'Kazan dairesi yıllık bakımı ve baca temizliği', raw: 0.25 * D, supplier: 'boiler', key: 'boilerservice', equip: 'boilerMaint' });
    if (mi === 5 || mi === 11) add({ date: clampDay(ym, 18), cat: 'Vergi/harç', text: 'Yönetim planı gereği noter ve harç gideri', raw: 0.03 * D, doc: 'receipt', key: 'tax' });
  }
  for (const u of UNEXPECTED) {
    const y = Number(u.ym.slice(0, 4));
    add({ date: clampDay(u.ym, rng.int(8, 24)), cat: u.cat, text: u.text, raw: u.mult * dues[y], supplier: u.supplier, nature: 'unexpected', key: `unexpected:${u.ym}`, equip: u.equip ?? null, funded: u.funded ?? null });
  }
  return items.sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Kasa/banka benzetimi. Olaylar: tahsilatlar (kasa|banka), giderler (kasa|banka), aktarimlar.
 * collections: [{date, amountMinor, to:'cash'|'bank'}], expenses: [{date, amountMinor, from:'cash'|'bank', small:boolean}]
 * Donus: { transfers:[{date, from, to, amountMinor, description}], minBank, minCash, balances: {cash, bank}, series }
 * Hesap bakiyeleri acilis=0 varsayimiyla gider; cagiran minimum degerlere gore acilis bakiyesini belirler.
 */
export function simulateAccounts({ collections, expenses, monthlyTotalOf, start, today }) {
  const days = new Map();
  const slot = (d) => {
    if (!days.has(d)) days.set(d, { col: [], exp: [] });
    return days.get(d);
  };
  for (const c of collections) slot(c.date).col.push(c);
  for (const e of expenses) slot(e.date).exp.push(e);
  const dates = [...days.keys(), ...monthsBetween(ymOf(start), ymOf(today)).map((ym) => clampDay(ym, 26))].filter((d) => d >= start && d <= today);
  const ordered = sortedUnique(dates);
  let cash = 0;
  let bank = 0;
  let minCash = 0;
  let minBank = 0;
  const transfers = [];
  const series = [];
  for (const d of ordered) {
    const D = monthlyTotalOf(d);
    const level = Math.round(0.22 * D);
    const slotDay = days.get(d);
    if (slotDay) {
      for (const c of slotDay.col) {
        if (c.to === 'cash') cash += c.amountMinor;
        else bank += c.amountMinor;
      }
      for (const e of slotDay.exp) {
        if (e.from === 'cash') {
          if (cash - e.amountMinor < 0) {
            const need = e.amountMinor - cash + level;
            transfers.push({ date: d, phase: 'pre', from: 'bank', to: 'cash', amountMinor: need, description: 'Kasa için bankadan nakit çekimi' });
            bank -= need;
            cash += need;
          }
          cash -= e.amountMinor;
        } else {
          bank -= e.amountMinor;
        }
      }
    }
    if (d.slice(8, 10) === '26') {
      if (cash > 2.2 * level) {
        const amount = cash - level;
        transfers.push({ date: d, phase: 'post', from: 'cash', to: 'bank', amountMinor: amount, description: 'Kasadaki tahsilatın bankaya yatırılması' });
        cash -= amount;
        bank += amount;
      } else if (cash < 0.3 * level) {
        const amount = level;
        transfers.push({ date: d, phase: 'post', from: 'bank', to: 'cash', amountMinor: amount, description: 'Kasa için bankadan nakit çekimi' });
        bank -= amount;
        cash += amount;
      }
    }
    minCash = Math.min(minCash, cash);
    minBank = Math.min(minBank, bank);
    series.push({ date: d, cash, bank });
  }
  return { transfers, minBank, minCash, balances: { cash, bank }, series };
}

export { diffDays };
