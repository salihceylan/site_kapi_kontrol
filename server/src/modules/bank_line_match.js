// Banka satırı eşleme (saf; DB'siz). Sıra (F3 kararı): referans kodu -> açıklamadaki daire kodu -> IBAN hafızası -> gönderen adı -> bekliyor.
// Güçlü (otomatik işlenir): ref, iban. Zayıf ('kontrol edin', onayla işlenir): code, name. Birden çok aday = eşleşme YAPILMAZ.
import { createHash } from 'node:crypto';
import { findRefs } from './finance_payment_ref.js';
import { foldText } from './people_common.js';

export const STRONG_METHODS = Object.freeze(['ref', 'iban']);
export const WEAK_METHODS = Object.freeze(['code', 'name']);

const norm = (text) => foldText(String(text ?? '')).toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
export const normalizeIban = (value) => {
  const v = String(value ?? '').replace(/\s+/g, '').toUpperCase();
  return /^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(v) ? v : null;
};

/** Dosyadaki satırlara kararlı parmak izi: (hesap, valör, tutar, katlanmış açıklama, banka ref, dosyadaki eş satır sırası). */
export function computeFingerprints(accountId, lines) {
  const seen = new Map();
  return lines.map((line) => {
    const base = [accountId, line.value_date, line.amount_minor, norm(line.description), norm(line.bank_reference)].join('|');
    const nth = seen.get(base) ?? 0;
    seen.set(base, nth + 1);
    return createHash('sha256').update(`${base}|${nth}`).digest('hex');
  });
}

/**
 * ctx: { refKnown (findRefs 'known'), codes: [{ code, apartment_id }], ibans: Map<iban, [{ apartment_id, party, stale }]>,
 *        people: [{ apartment_id, party: 'owner'|'tenant', tokens: Set<string> }] }
 * Dönüş: { method, apartmentId, party, strength: 'strong'|'weak', warning? } | null. Yalnız giriş (tutar > 0) satırları eşlenir.
 */
export function matchLine(line, ctx) {
  if (!(line.amount_minor > 0)) return null;
  const partyOf = (apartmentId) => {
    const parties = new Set((ctx.people ?? []).filter((p) => p.apartment_id === apartmentId).map((p) => p.party));
    return parties.size === 1 ? [...parties][0] : null;
  };
  // 1. referans kodu
  const ref = findRefs(`${line.description ?? ''} ${line.bank_reference ?? ''}`, ctx.refKnown);
  if (ref.status === 'unique') {
    return { method: 'ref', apartmentId: ref.match.apartment_id, party: partyOf(ref.match.apartment_id), strength: 'strong' };
  }
  // 2. açıklamadaki daire kodu (tam sözcük)
  const words = new Set(norm(`${line.description ?? ''} ${line.counterparty_name ?? ''}`).split(' '));
  const byCode = [...new Set((ctx.codes ?? []).filter((c) => words.has(String(c.code).toUpperCase())).map((c) => c.apartment_id))];
  // 3. IBAN hafızası (bayat kayıt sayılmaz)
  const iban = normalizeIban(line.counterparty_iban);
  const mem = iban ? (ctx.ibans?.get(iban) ?? []).filter((m) => !m.stale) : [];
  const memIds = [...new Set(mem.map((m) => m.apartment_id))];
  if (byCode.length === 1) {
    const hit = { method: 'code', apartmentId: byCode[0], party: partyOf(byCode[0]), strength: 'weak' };
    // ref yoksa IBAN daha güçlü kanıttır; ikisi aynı daireyi gösteriyorsa güçlü say.
    if (memIds.length === 1 && memIds[0] === byCode[0]) return { ...hit, method: 'iban', party: mem[0].party ?? hit.party, strength: 'strong' };
    if (memIds.length !== 1) return hit;
  }
  if (memIds.length === 1) {
    return { method: 'iban', apartmentId: memIds[0], party: mem.find((m) => m.apartment_id === memIds[0])?.party ?? partyOf(memIds[0]), strength: 'strong' };
  }
  // 4. gönderen adı: güncel kişilerle en az 2 ortak belirteç, tekil sonuç
  const senderTokens = new Set(norm(line.counterparty_name || line.description).split(' ').filter((t) => t.length >= 2));
  const scores = new Map();
  for (const p of ctx.people ?? []) {
    let n = 0;
    for (const t of p.tokens) if (senderTokens.has(t)) n += 1;
    if (n >= 2) {
      const cur = scores.get(p.apartment_id);
      if (!cur || n > cur.n) scores.set(p.apartment_id, { n, party: p.party });
    }
  }
  if (scores.size === 1) {
    const [[apartmentId, { party }]] = [...scores];
    return { method: 'name', apartmentId, party, strength: 'weak' };
  }
  return null;
}

/** Önizleme özeti için sonuç sınıflandırması. */
export function outcomeOf({ line, duplicate, match, linkedEntryId, ambiguousLink }) {
  if (duplicate) return 'duplicate';
  if (!(line.amount_minor > 0)) return 'outgoing';
  if (!match) return 'unmatched';
  if (ambiguousLink) return 'check';
  if (match.strength === 'strong') return linkedEntryId ? 'linked' : 'recognized';
  return 'check';
}

/** Önizleme özeti: sayılar ve tanınan tutar toplamı (kuruş). */
export function summarize(rows) {
  const s = { recognized: 0, check: 0, unmatched: 0, linked_existing: 0, duplicates: 0, outgoing: 0, recognized_minor: 0 };
  for (const r of rows) {
    if (r.outcome === 'recognized') {
      s.recognized += 1;
      s.recognized_minor += r.amount_minor;
    } else if (r.outcome === 'check') s.check += 1;
    else if (r.outcome === 'unmatched') s.unmatched += 1;
    else if (r.outcome === 'linked') s.linked_existing += 1;
    else if (r.outcome === 'duplicate') s.duplicates += 1;
    else if (r.outcome === 'outgoing') s.outgoing += 1;
  }
  return s;
}

export function previewHash(fileSha, accountId, rows) {
  const body = JSON.stringify([fileSha, accountId, rows.map((r) => [r.n, r.outcome, r.match?.apartmentId ?? null, r.match?.party ?? null, r.linkedEntryId ?? null])]);
  return createHash('sha256').update(body).digest('hex');
}
