// Toplu yükleme (F4): DEVİR BAKİYESİ planlayıcısı. Saf: DB/ağ bağımsız.
//
// Her geçerli satır, dairenin seçilen hesabına (ev sahibi/kiracı) BİR defter kaydı olur (source_kind='opening'):
//   + tutar (borç)   -> `charge` (borç; vadeli),
//   - tutar (ALACAK) -> `payment` (alacak; vadesiz; method 'transfer' yalnız şema zorunluluğu, kaynak izi 'opening'). K16 (P2-4): alacaklı devir desteklenir; alacak,
//                       sonraki borçlara mahsup mantığıyla (M1: vadesi en eski borçtan) düşer — bilinen "fazla ödeme" ile aynı yoldur.
// Op biçimi: `{ t: 'ob', aptId, account, minor, due, desc }`; `minor` İŞARETLİDİR (borç +, alacak -); alacakta `due` null. Yazıcı işarete göre charge / payment yazar.
// Aynı daire + hesapta etkin devir (borç ya da alacak) varsa: aynı değerler "değişiklik yok", farklı değerler hata (önce yüklemeyi geri al). Defter yalnız eklemelidir.
// Sayılar: `opening_add` yazılacak kayıt (borç + alacak), `total_minor` BORÇ toplamı (>= 0; onay toplamı), `opening_credit_add` / `credit_total_minor` alacak kaydı ve alacak
// toplamı (büyüklük, >= 0).

import { readAccount, readDate, readMoney, readText } from './bulk_import_parsers.js';
import { addIssue, buildLocator, completeRow, finalizePlan, newRowResult } from './bulk_import_plan_common.js';
import { todayIso } from './people_common.js';

const KIND = 'opening_balances';
const MAX_BACK_YEARS = 5;

const minorText = (minor) => `${Math.floor(minor / 100).toLocaleString('tr-TR')},${String(minor % 100).padStart(2, '0')} TL`;

/**
 * @param {{ rows: object[], snapshot: object, options: { cutover_date: string }, today?: string }} input
 *   snapshot: blocks, apartments + opening { existing: Map('aptId:account' -> {minor, due, desc}), tenantApts: Set, inactive: Set, otherLedger: Set, cutoverClosed: boolean }
 */
export function planOpening({ rows, snapshot, options, today = todayIso() }) {
  const locator = buildLocator(snapshot);
  const info = snapshot.opening ?? { existing: new Map(), tenantApts: new Set(), inactive: new Set(), otherLedger: new Set(), cutoverClosed: false };
  const cutover = options.cutover_date;
  const oldest = `${Number(cutover.slice(0, 4)) - MAX_BACK_YEARS}${cutover.slice(4)}`;
  const seen = new Map();
  const counts = { opening_add: 0, opening_unchanged: 0, opening_zero: 0, total_minor: 0, opening_credit_add: 0, credit_total_minor: 0 };
  const results = [];

  for (const row of rows) {
    const result = newRowResult(row.n);
    const cells = row.cells;
    const issue = (code, field, ctx, severity) => addIssue(result, KIND, code, field, ctx, severity);

    const blockText = readText(cells.blok, { forbidSigned: true, max: 60 });
    const numberText = readText(cells.daire_no, { max: 30 });
    if (blockText.error) issue(blockText.error, 'blok', blockText);
    else if (blockText.value === null) issue('REQUIRED', 'blok');
    if (numberText.error) issue(numberText.error, 'daire_no', numberText);
    else if (numberText.value === null) issue('REQUIRED', 'daire_no');

    let apartment = null;
    if (blockText.value !== null && numberText.value !== null) {
      const resolved = locator.resolve(blockText.value, numberText.value);
      if (resolved.error === 'BLOCK_NOT_FOUND') issue('BLOCK_NOT_FOUND', 'blok', { value: blockText.value, blocks: locator.blockNames });
      else if (resolved.error === 'BLOCK_AMBIGUOUS') issue('BLOCK_AMBIGUOUS', 'blok', { value: blockText.value });
      else if (resolved.error === 'APARTMENT_NOT_FOUND') issue('APARTMENT_NOT_FOUND', 'daire_no', { value: `${resolved.block.name} - ${numberText.value}` });
      else apartment = resolved.apartment;
    }

    const account = readAccount(cells.hesap);
    if (account.error) issue(account.error, 'hesap', { value: cells.hesap });
    const party = account.value ?? 'owner';

    const money = readMoney(cells.tutar);
    // İşaretli tutar: borç +, ALACAK - (K16). 0 atlanır.
    let minor = 0;
    if (money.error) issue(money.error, 'tutar', { value: cells.tutar });
    else if (money.value === null) issue('REQUIRED', 'tutar');
    else {
      for (const code of money.warnings ?? []) issue(code, 'tutar', { value: cells.tutar });
      minor = money.value;
    }
    const isCredit = minor < 0;

    const dueRead = readDate(cells.vade, today);
    let due = cutover;
    if (dueRead.error) issue(dueRead.error, 'vade', { value: cells.vade });
    else if (dueRead.value !== null) {
      if (isCredit) {
        // Alacak vadesizdir (tahsilat gibi devir tarihinde yazılır); verilen vade yok sayılır.
        issue('OPENING_CREDIT_DUE_IGNORED', 'vade', {});
      } else {
        due = dueRead.value;
        if (due < oldest) issue('DATE_RANGE', 'vade', {});
        else if (due > cutover) issue('FUTURE_DATE', 'vade', { value: due });
      }
    }
    const storedDue = isCredit ? null : due;

    const note = readText(cells.aciklama, { max: 200, multiline: false });
    if (note.error) issue(note.error, 'aciklama', { ...note, value: cells.aciklama });
    const desc = note.value ?? null;

    if (info.cutoverClosed) issue('PERIOD_CLOSED', null);

    if (apartment && !result.hasError) {
      const key = `${apartment.id}:${party}`;
      if (seen.has(key)) {
        issue('DUPLICATE_IN_FILE', 'daire_no', { line: seen.get(key) }, 'error');
      } else if (info.inactive.has(apartment.id)) {
        issue('APARTMENT_INACTIVE', null);
      } else {
        seen.set(key, row.n);
        const existing = info.existing.get(key);
        if (minor === 0) {
          issue('OPENING_ZERO', 'tutar');
          counts.opening_zero += 1;
          result.action = 'skip';
        } else if (existing) {
          if (existing.minor === minor && existing.due === storedDue && (existing.desc ?? null) === desc) {
            counts.opening_unchanged += 1;
            result.action = 'unchanged';
          } else {
            issue('OPENING_EXISTS', null);
          }
        } else {
          if (party === 'tenant' && !info.tenantApts.has(apartment.id)) issue('NO_TENANT', 'hesap');
          if (info.otherLedger.has(apartment.id)) issue('OPENING_LEDGER_EXISTS', null);
          result.ops.push({ t: 'ob', aptId: apartment.id, account: party, minor, due: storedDue, desc });
          counts.opening_add += 1;
          if (isCredit) {
            counts.opening_credit_add += 1;
            counts.credit_total_minor += -minor;
          } else {
            counts.total_minor += minor;
          }
          result.action = 'add';
          result.summary = `${locator.labelOfApartment(apartment)}: ${minorText(Math.abs(minor))}${isCredit ? ' alacak' : ''} (${party === 'tenant' ? 'kiracı' : 'ev sahibi'})`;
        }
      }
    }
    results.push(completeRow(result, apartment ? `${apartment.id}:${party}` : ''));
  }

  return finalizePlan({ kind: KIND, results, counts, hashSalt: `cut=${cutover}` });
}
