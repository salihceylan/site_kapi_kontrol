// Ödeme referans kodu (saf; DB'siz). Biçim: <ÖNEK>-<DAİRE>-<AAYY>, örn. GUL-A2-1026 (önek: sitenin 3 harfi, daire kodu, dönem = ay + yıl, İstanbul).
// 2B (dekont) ve 2C (banka hareketi eşleme) bu modüldeki findRefs / formatRef / foldRef işlevlerini kullanır.
// Karar: önek 3 harf A-Z (Türkçe harfler katlanır), geçmişi dahil sistemde tekil; daire kodu kalıcıdır (tek blokta D5, çok blokta A2).

import { foldText } from './people_common.js';
import { apartmentKey } from './bulk_import_parsers.js';

export const PREFIX_PATTERN = /^[A-Z]{3}$/;
export const CODE_PATTERN = /^[A-Z0-9]{1,8}$/;

/** Katla + büyük harf + yalnız A-Z0-9. */
export function foldRef(value) {
  return foldText(value).toUpperCase().replace(/[^A-Z0-9]/g, '');
}

/** Girdiden geçerli 3 harfli önek ya da null (rakam / başka karakter reddedilir; boşluk kırpılır). */
export function parsePrefix(value) {
  const folded = foldText(String(value ?? '').trim()).toUpperCase();
  return PREFIX_PATTERN.test(folded) ? folded : null;
}

const GENERIC_WORDS = new Set(['SITE', 'SITESI', 'APARTMAN', 'APARTMANI', 'YONETIMI', 'KONUTLARI', 'KONUTLAR']);

/** Site adından önek önerisi; `taken` (Set) içindekileri atlar. */
export function suggestPrefix(siteName, taken = new Set()) {
  const words = foldText(siteName)
    .toUpperCase()
    .split(/[^A-Z0-9]+/)
    .map((w) => w.replace(/[0-9]/g, ''))
    .filter(Boolean);
  const meaningful = words.filter((w) => !GENERIC_WORDS.has(w));
  const list = meaningful.length > 0 ? meaningful : words;
  const letters = list.join('');
  const pad = (text) => (text + 'XXX').slice(0, 3);
  const candidates = [];
  if (list.length > 0) candidates.push(pad(list[0]));
  if (list.length > 1) candidates.push(pad(list.map((w) => w[0]).join('')));
  for (let k = 2; k < letters.length; k += 1) candidates.push(pad(letters[0] + letters[1] + letters[k]));
  for (let a = 0; a < 26; a += 1) {
    for (let b = 0; b < 26; b += 1) {
      candidates.push(pad(`${letters[0] ?? 'S'}${String.fromCharCode(65 + a)}${String.fromCharCode(65 + b)}`));
    }
  }
  return candidates.find((c) => PREFIX_PATTERN.test(c) && !taken.has(c)) ?? null;
}

function blockToken(blockName) {
  const text = foldText(blockName)
    .toUpperCase()
    .split(/[^A-Z0-9]+/)
    .filter((w) => w && w !== 'BLOK')
    .join('');
  return text.slice(0, 3) || 'B';
}

/** Daire kodu (çakışma denetimi yok). Tek blok: 'D'+no; çok blok: blok jetonu + no (jeton rakamla bitiyorsa araya 'D'). Bulunamazsa 'K'+id. */
export function aptCode({ blockName, unitLabel, blockCount, apartmentId }) {
  const fallback = () => {
    const direct = `K${apartmentId}`;
    return direct.length <= 8 ? direct : `K${Number(apartmentId).toString(36).toUpperCase()}`.slice(0, 8);
  };
  const key = apartmentKey(unitLabel ?? '');
  if (!key.startsWith('n:')) return fallback();
  const number = key.slice(2);
  let code;
  if (Number(blockCount) <= 1) {
    code = `D${number}`;
  } else {
    const token = blockToken(blockName);
    code = /[0-9]$/.test(token) ? `${token}D${number}` : `${token}${number}`;
  }
  return CODE_PATTERN.test(code) ? code : fallback();
}

/** İstanbul saatine göre dönem: { month: 1-12, year2: 0-99 }. */
export function istanbulPeriod(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Istanbul', year: 'numeric', month: '2-digit' }).formatToParts(now);
  const get = (type) => Number(parts.find((p) => p.type === type)?.value);
  return { month: get('month'), year2: get('year') % 100 };
}

const two = (n) => String(n).padStart(2, '0');

/** 'GUL-A2-1026' (dönemli) ya da 'GUL-A2' (kısa; withPeriod=false). */
export function formatRef({ prefix, code, now = new Date(), withPeriod = true }) {
  if (!withPeriod) return `${prefix}-${code}`;
  const period = istanbulPeriod(now);
  return `${prefix}-${code}-${two(period.month)}${two(period.year2)}`;
}

/** Sayısal dönem etiketi: '10/2026'. */
export function periodLabel(now = new Date()) {
  const period = istanbulPeriod(now);
  return `${two(period.month)}/20${two(period.year2)}`;
}

const normalizeFree = (text) => foldText(text).toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();

function validPeriod(text) {
  const m = /^(\d{2})(\d{2})$/.exec(text);
  return m && Number(m[1]) >= 1 && Number(m[1]) <= 12 ? { month: Number(m[1]), year2: Number(m[2]) } : null;
}

/**
 * Serbest metinde (havale açıklaması) referans arar. `known`: { prefixes: [{ prefix, site_code }] (güncel + eski), codes: [{ site_code, code, apartment_id }] }.
 * Önek kelime başında aranır; ardındaki boşluk/tire/alt çizgi/nokta/eğik çizgi atılır; daire kodunu metin sonu, ayırıcı ya da geçerli AAYY izlemelidir
 * (bitişik yazımda yalnız geçerli AAYY kabul edilir). Dönem yoksa ya da geçersizse (13. ay) kod dönemsiz sayılır.
 * Dönüş: { status: 'none' | 'unique' | 'ambiguous', match?: { site_code, apartment_id, code, period }, candidates }.
 * Birden çok farklı daire adayı varsa 'ambiguous' (eşleme YAPILMAZ).
 */
export function findRefs(text, known) {
  const s = normalizeFree(text);
  const prefixMap = new Map();
  for (const row of known?.prefixes ?? []) prefixMap.set(String(row.prefix).toUpperCase(), Number(row.site_code));
  const codesBySite = new Map();
  for (const row of known?.codes ?? []) {
    const site = Number(row.site_code);
    if (!codesBySite.has(site)) codesBySite.set(site, []);
    codesBySite.get(site).push({ code: String(row.code).toUpperCase(), apartmentId: Number(row.apartment_id) });
  }
  const found = new Map();
  for (const [prefix, siteCode] of prefixMap) {
    const codes = (codesBySite.get(siteCode) ?? []).sort((a, b) => b.code.length - a.code.length);
    let from = 0;
    for (;;) {
      const at = s.indexOf(prefix, from);
      if (at < 0) break;
      from = at + 1;
      if (at > 0 && s[at - 1] !== ' ') continue;
      const rest = s.slice(at + prefix.length).replace(/^ +/, '');
      for (const { code, apartmentId } of codes) {
        if (!rest.startsWith(code)) continue;
        const tail = rest.slice(code.length);
        let period = null;
        if (tail === '') {
          // dönemsiz, metin sonu
        } else if (tail[0] === ' ') {
          period = validPeriod(tail.trim().split(' ')[0]);
        } else {
          period = validPeriod(tail.split(' ')[0]);
          if (!period) continue; // bitişik yazımda yalnız geçerli AAYY
        }
        found.set(`${siteCode}:${apartmentId}`, { site_code: siteCode, apartment_id: apartmentId, code, period });
      }
    }
  }
  const candidates = [...found.values()];
  if (candidates.length === 0) return { status: 'none', candidates };
  if (candidates.length > 1) return { status: 'ambiguous', candidates };
  return { status: 'unique', match: candidates[0], candidates };
}
