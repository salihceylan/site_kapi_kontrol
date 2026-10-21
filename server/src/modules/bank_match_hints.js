// Banka satırı ipuçları (saf; DB'siz): açıklamadaki daire numarası ve ay/dönem bilgisi. bank_line_match.js ve PDF ayrıştırıcı kullanır.
// Havale açıklamaları serbest metindir ("A blok 5 Ahmet Yılmaz ekim aidatı", "D12 kasım", "5 nolu daire aidat"); burada yalnız
// ölçülü kurallar var: numara ancak daire/no/nolu sözcüğüyle ya da bilinen blok adıyla birlikte sayılır, çıplak sayı sayılmaz.
import { foldText } from './people_common.js';

const MONTHS = Object.freeze(['ocak', 'subat', 'mart', 'nisan', 'mayis', 'haziran', 'temmuz', 'agustos', 'eylul', 'ekim', 'kasim', 'aralik']);
const MONTH_RE = new RegExp(`^(${MONTHS.join('|')})(i|in|e|a|u|un|ayi|ayinin|ayina)?$`);
const UNIT_WORDS = new Set(['daire', 'no', 'nolu', 'numara', 'numarali', 'nr', 'd', 'kapi']);
const BLOCK_SKIP = new Set(['daire', 'no', 'nolu', 'numara', 'numarali', 'nr', 'kapi', 'blok']);
const NOT_UNIT_CONTEXT = new Set(['dekont', 'ref', 'referans', 'islem', 'fatura', 'sira', 'seri', 'hesap', 'musteri', 'tc', 'vkn']);

const tokensOf = (text) => foldText(String(text ?? '')).match(/[a-z]+|\d+/g) ?? [];
const stripZeros = (digits) => digits.replace(/^0+(?=\d)/, '');

/**
 * Ay/dönem ipucu: "ekim", "Kasım aidatı", "10/2026", "2026-10". Tek bir ay varsa 'YYYY-MM', yoksa ya da birden çok ay varsa null.
 * Yıl yoksa valör yılı; ay valör ayından sonraysa önceki yıl (Ocak'ta ödenen "aralık"). Yalnız bilgi: mahsup yine en eski vadeden yapılır.
 */
export function periodHintOf(description, valueDate) {
  const text = foldText(String(description ?? ''));
  const found = new Map(); // 'YYYY-MM' veya 'M' (yılsız) -> {month, year|null}
  const add = (month, year) => found.set(`${year ?? '?'}-${month}`, { month, year });
  for (const m of text.matchAll(/(?<!\d|\d[./-])(0?[1-9]|1[0-2])\s*[./-]\s*(20\d{2})(?!\d)/g)) add(Number(m[1]), Number(m[2]));
  for (const m of text.matchAll(/(?<!\d|\d[./-])(20\d{2})\s*[./-]\s*(0?[1-9]|1[0-2])(?!\d)/g)) add(Number(m[2]), Number(m[1]));
  const year = (text.match(/(?<!\d)(20\d{2})(?!\d)/) ?? [])[1];
  for (const token of text.match(/[a-z]+/g) ?? []) {
    const hit = MONTH_RE.exec(token);
    if (hit) add(MONTHS.indexOf(hit[1]) + 1, year ? Number(year) : null);
  }
  if (found.size !== 1) return null;
  const { month, year: explicit } = [...found.values()][0];
  let y = explicit;
  if (y === null) {
    const vd = /^(\d{4})-(\d{2})-\d{2}$/.exec(String(valueDate ?? ''));
    if (!vd) return null;
    y = Number(vd[1]);
    if (month > Number(vd[2])) y -= 1;
  }
  return `${String(y).padStart(4, '0')}-${String(month).padStart(2, '0')}`;
}

/** apartments: [{ apartment_id, block_name, unit_label }] -> arama dizini (yalnız sayısal daire numaraları; harfli etiketler atlanır). */
export function buildUnitIndex(apartments) {
  const blockKey = (name) => foldText(String(name ?? '')).replace(/[^a-z0-9]+/g, ' ').split(' ').filter((t) => t && t !== 'blok').join(' ');
  const entries = [];
  for (const a of apartments ?? []) {
    const unit = foldText(String(a.unit_label ?? '')).trim();
    if (!/^\d{1,4}$/.test(unit)) continue;
    entries.push({ id: Number(a.apartment_id), block: blockKey(a.block_name), unit: stripZeros(unit) });
  }
  const blocks = new Set(entries.map((e) => e.block).filter(Boolean));
  return { entries, blocks, blockKey };
}

/** Açıklama/gönderen metnindeki daire numarası ifadelerinden aday daire kimlikleri (Set). */
export function unitCandidates(text, index) {
  const out = new Set();
  if (!index || index.entries.length === 0) return out;
  const tokens = tokensOf(text);
  for (let i = 0; i < tokens.length; i += 1) {
    if (!/^\d{1,4}$/.test(tokens[i])) continue;
    const unit = stripZeros(tokens[i]);
    // 1. blok + numara: [blok]? BLOK_ADI [blok|daire|no]* NUMARA  (A blok 5, A5, A-5, blok A daire 5, D12)
    let found = false;
    let p = i - 1;
    let sawBlok = false;
    for (let step = 0; step < 4 && p >= 0; step += 1, p -= 1) {
      if (BLOCK_SKIP.has(tokens[p])) {
        if (tokens[p] === 'blok') sawBlok = true;
        continue;
      }
      let key = null;
      for (let len = 1; len <= 2 && p - len + 1 >= 0; len += 1) {
        const k = tokens.slice(p - len + 1, p + 1).join(' ');
        if (index.blocks.has(k)) {
          key = k;
          break;
        }
      }
      if (key !== null) {
        const numericBlock = /^\d+$/.test(key);
        if (!numericBlock || sawBlok || tokens[p + 1] === 'blok') {
          for (const e of index.entries) if (e.block === key && e.unit === unit) {
            out.add(e.id);
            found = true;
          }
        }
      }
      break;
    }
    if (found) continue;
    // 2. yalnız numara, ama "daire/no/nolu/d" sözcüğüyle işaretli (5 nolu daire, daire 5, D12, no 5)
    const marked = UNIT_WORDS.has(tokens[i - 1] ?? '') || ['nolu', 'numarali', 'daire'].includes(tokens[i + 1] ?? '');
    if (!marked || NOT_UNIT_CONTEXT.has(tokens[i - 2] ?? '') || NOT_UNIT_CONTEXT.has(tokens[i - 1] ?? '')) continue;
    for (const e of index.entries) if (e.unit === unit) out.add(e.id);
  }
  return out;
}
