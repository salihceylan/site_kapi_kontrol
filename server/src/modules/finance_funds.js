// İki kasa (İşletme `operating` / Yatırım ve Demirbaş Fon `capital`): saf kurallar, TEK dağıtım işlevi ve defter yükleyicisi.
//
// Sözleşme: docs/PLATFORM_FINANS_KASALAR.md (bağlayıcı). Kasa bir BAKİYEDİR, fiziksel hesap değildir; nakit / banka hesapları (finance_accounts) iki kasada ortaktır.
//  - Borcun kasası (§2): `ledger_entries.fund`; 080 öncesi satırda NULL'dır ve OKUMADA türetilir (effectiveFund): devir -> operating, gecikme tazminatı -> operating,
//    çalıştırma -> tanımın etkin "kim öder" değeri (owner -> capital, occupant -> operating), aksi operating. Ters kayıt asılın kasasını taşır.
//  - Tahsilatın dağıtımı (§3) OKUMADA türetilir, SAKLANMAZ: allocateFunds (aşağıda) TEK saf işlevdir; ekstre, Borcum, makbuz, kasa bakiyesi hep bunu kullanır.
//  - PARA BigInt'tir (finance_money.js); kayan nokta yok. Bu dosya diğer finans modüllerini İÇE AKTARMAZ (döngüsel içe aktarma olmasın).

import { PlatformError } from './errors.js';
import { toBigInt } from './finance_money.js';

export const FUNDS = Object.freeze(['operating', 'capital']);
// Kullanıcı kararı (2026-10-26): kasalar TAM bu adlarla anılır (ev sahibi / kiracı daire hesaplarıyla ve nakit / banka hesaplarıyla karışmasın); yer darsa kısa ad.
export const FUND_LABELS = Object.freeze({ operating: 'İşletme Projesi (Aidat) Hesabı', capital: 'Yatırım ve Demirbaş (Fon) Hesabı' });
export const FUND_SHORT_LABELS = Object.freeze({ operating: 'Aidat Hesabı', capital: 'Fon Hesabı' });
/** Her sitede bulunan sistem gider kategorisi (kasa: capital). */
export const CAPITAL_CATEGORY_NAME = 'Yatırım ve demirbaş';

export const isFund = (value) => value === 'operating' || value === 'capital';

/** "Kim öder" -> borcun kasası: owner => capital (malik öder), occupant => operating (dairede oturan öder). */
export const fundOfChargeParty = (chargeParty) => (chargeParty === 'owner' ? 'capital' : 'operating');

/** Kasa -> "kim öder": capital => owner, operating => occupant. */
export const chargePartyOfFund = (fund) => (fund === 'capital' ? 'owner' : 'occupant');

/** Tanım satırının etkin "kim öder" değeri (052 öncesi satırda NULL: aylık occupant, tek seferlik owner). */
export function effectiveChargePartyOf(chargeParty, kind) {
  if (chargeParty === 'occupant' || chargeParty === 'owner') {
    return chargeParty;
  }
  return kind === 'recurring' ? 'occupant' : 'owner';
}

const invalid = (message) => new PlatformError(400, 'INVALID_BODY', message);

// --- Hatalar -------------------------------------------------------------------------------------------------------------------------------------

export const categoryFundLocked = (message) =>
  new PlatformError(409, 'CATEGORY_FUND_LOCKED', message ?? 'Bu kategorinin hesabı (Aidat / Fon) değiştirilemez.');
export const fundTransferNotFound = () => new PlatformError(404, 'FUND_TRANSFER_NOT_FOUND', 'Hesaplar arası aktarım bulunamadı.');
export const fundTransferAlreadyReversed = () =>
  new PlatformError(409, 'FUND_TRANSFER_ALREADY_REVERSED', 'Bu aktarım zaten ters aktarımla düzeltilmiş.');
export const fundTransferNotReversible = () =>
  new PlatformError(409, 'FUND_TRANSFER_NOT_REVERSIBLE', 'Ters aktarım tekrar ters çevrilemez; gerekirse yeni bir aktarım girin.');

/** Gövde alanı `fund`: yoksa null; geçersizse 400 INVALID_BODY. */
export function parseFundField(value, label = 'Hesap seçimi') {
  if (value === undefined || value === null) {
    return null;
  }
  if (!isFund(value)) {
    throw invalid(`${label} geçersiz (İşletme Projesi (Aidat) Hesabı veya Yatırım ve Demirbaş (Fon) Hesabı olmalıdır).`);
  }
  return value;
}

/**
 * Tanım / ek borç: `fund` ve `charge_party` birlikte çözülür. İkisi de verilirse tutarlı olmalıdır (çelişki 400 INVALID_BODY); yalnız `fund` verilirse
 * "kim öder" ondan türetilir; hiçbiri yoksa `fallback`.
 * @param {{ chargeParty: string|null, fund: string|null, fallback: string }} input chargeParty / fund ayrıştırılmış değerlerdir
 */
export function resolveChargePartyAndFund({ chargeParty, fund, fallback }) {
  if (chargeParty !== null && fund !== null && fundOfChargeParty(chargeParty) !== fund) {
    throw invalid('Hesap seçimi ile "kim öder" seçimi çelişiyor (İşletme Projesi (Aidat) Hesabı: dairede oturan öder; Yatırım ve Demirbaş (Fon) Hesabı: malik öder).');
  }
  if (chargeParty !== null) {
    return chargeParty;
  }
  return fund !== null ? chargePartyOfFund(fund) : fallback;
}

const amountSign = (row) => {
  try {
    const value = toBigInt(row.amount_minor ?? row.amount ?? 0);
    return value > 0n ? 1 : value < 0n ? -1 : 0;
  } catch (_error) {
    return 0;
  }
};

/** Tahsilat benzeri satır: payment ya da bir tahsilatın ters kaydı (işareti borç yönlü, kasa = tahsilatın kısıtı). */
const isPaymentLike = (row) => row.kind === 'payment' || (row.kind === 'reversal' && amountSign(row) > 0);

/**
 * Defter satırının ETKİN kasası. Girdi: ledger_entries sütunları (`fund`, `kind`, `amount_minor`, `source_kind`, `late_fee_run_id` ya da `late_fee`, `definition_id`) ve
 * tanım birleşimi (`def_charge_party`, `def_kind`). Tahsilat (ve tahsilatın ters kaydı) için sonuç KISITTIR: null = otomatik (kısıt yok).
 * Borç (ve borcun ters kaydı) için sonuç her zaman 'operating' | 'capital'.
 */
export function effectiveFund(row) {
  const raw = isFund(row.fund) ? row.fund : null;
  if (isPaymentLike(row)) {
    return raw;
  }
  if (raw !== null) {
    return raw;
  }
  if (row.source_kind === 'opening') {
    return 'operating';
  }
  if ((row.late_fee_run_id !== null && row.late_fee_run_id !== undefined) || row.late_fee === true) {
    return 'operating';
  }
  if (row.definition_id !== null && row.definition_id !== undefined && (row.def_kind !== undefined || row.def_charge_party !== undefined)) {
    return fundOfChargeParty(effectiveChargePartyOf(row.def_charge_party, row.def_kind));
  }
  return 'operating';
}

/** Defter satırı (ENTRY_SELECT / yükleyici) -> allocateFunds girdisi. */
export function toAllocatorEntry(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    amount: toBigInt(row.amount_minor),
    fund: effectiveFund(row),
    entryDate: row.entry_date,
    dueDate: row.due_date ?? null,
    reversesId: row.reverses_entry_id === null || row.reverses_entry_id === undefined ? null : Number(row.reverses_entry_id),
  };
}

// --- Dağıtım (§3) ---------------------------------------------------------------------------------------------------------------------------------

const compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const byDue = (a, b) => compare(a.due, b.due) || a.id - b.id;
const emptyFund = () => ({ open: 0n, overdue: 0n, advance: 0n });

function insertSorted(list, debt) {
  let low = 0;
  let high = list.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (byDue(list[mid], debt) <= 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  list.splice(low, 0, debt);
}

/**
 * Bir daire HESABININ (apartment_id + account_party) satırlarından kasa dağıtımı. TEK saf işlev (BigInt, DB yok).
 *
 * Girdi: `entries` = [{ id, kind: 'charge'|'payment'|'reversal', amount: bigint (defter işareti: borç +, tahsilat -), fund, entryDate, dueDate|null, reversesId|null }]
 *   fund: borç için 'operating' | 'capital' (yoksa operating); tahsilat için KISIT ('operating' | 'capital' | null = otomatik).
 *
 * Kurallar:
 *  1. Ters kayıtlar asıllarını NÖTRLER: asıl ve ters kaydı birlikte yok sayılır (asılı bulunmayan "öksüz" ters kayıt kendi işaretiyle borç / alacak sayılır).
 *  2. Olaylar (tarih, borç önce, id) sırasıyla işlenir. Borç: kasasına kısıtlı avans, sonra genel avans (FIFO) uygulanır; kalan "açık borç" olur.
 *     Tahsilat: o ana kadar oluşmuş AÇIK borçlara, vadesi en eski olandan (eşitlikte id) başlayarak uygulanır; kısıt varsa yalnız o kasanın borçlarına. Artan = avans
 *     (kısıtlıysa o kasanın avansı, değilse genel avans); sonradan oluşan borçlara vade sırasıyla uygulanır.
 *  3. Bir dağıtımın tarihi = max(tahsilat tarihi, borcun tarihi) (olayın işlendiği tarih).
 *
 * Çıktı: {
 *   funds: { operating: { open, overdue, advance }, capital: { … } }   open: açık borç; overdue: vadesi `today` ve öncesi olan açık borç; advance: o kasaya kısıtlı avans
 *   generalAdvance, advanceTotal                                         kısıtsız avans ve toplam avans (kısıtlı + genel)
 *   payments: Map<id, { id, date, amount, restriction, operating, capital, advance }>   her tahsilatın şu anki dağıtımı (operating + capital + advance = amount)
 *   debts: Map<id, { id, fund, amount, remaining, due, date }>
 *   events: [{ date, paymentId, debtId, fund, amount }]                 tarihli dağıtım olayları (kasa hareket dökümü)
 * }
 * Değişmez: funds.operating.open + funds.capital.open - advanceTotal = Σ amount (hesabın bakiyesi).
 * @param {Array} entries
 * @param {{ today?: string|null }} [options] today ('YYYY-MM-DD') verilmezse overdue 0'dır
 */
export function allocateFunds(entries, { today = null } = {}) {
  const present = new Map();
  for (const entry of entries) {
    present.set(entry.id, entry);
  }
  const neutralized = new Set();
  for (const entry of entries) {
    if (entry.kind === 'reversal' && entry.reversesId !== null && entry.reversesId !== undefined && present.has(entry.reversesId)) {
      neutralized.add(entry.reversesId);
      neutralized.add(entry.id);
    }
  }

  const timeline = [];
  for (const entry of entries) {
    if (neutralized.has(entry.id)) {
      continue;
    }
    const fund = isFund(entry.fund) ? entry.fund : null;
    const debt = (amount) => ({ type: 'debt', id: entry.id, date: entry.entryDate, due: entry.dueDate ?? entry.entryDate, amount, fund: fund ?? 'operating' });
    const credit = (amount, restriction) => ({ type: 'credit', id: entry.id, date: entry.entryDate, amount, restriction });
    if (entry.kind === 'charge') {
      if (entry.amount > 0n) timeline.push(debt(entry.amount));
    } else if (entry.kind === 'payment') {
      if (entry.amount < 0n) timeline.push(credit(-entry.amount, fund));
    } else if (entry.kind === 'reversal') {
      // öksüz ters kayıt (asılı bu girdide yok): kendi işaretiyle sayılır
      if (entry.amount > 0n) timeline.push(debt(entry.amount));
      else if (entry.amount < 0n) timeline.push(credit(-entry.amount, null));
    }
  }
  timeline.sort((a, b) => compare(a.date, b.date) || (a.type === b.type ? 0 : a.type === 'debt' ? -1 : 1) || a.id - b.id);

  const open = [];
  const debts = new Map();
  const payments = new Map();
  const events = [];
  const queues = { general: [], operating: [], capital: [] };

  const apply = (date, paymentId, debt, take) => {
    debt.remaining -= take;
    const paid = payments.get(paymentId);
    paid[debt.fund] += take;
    events.push({ date, paymentId, debtId: debt.id, fund: debt.fund, amount: take });
  };

  for (const event of timeline) {
    if (event.type === 'debt') {
      const debt = { id: event.id, fund: event.fund, amount: event.amount, remaining: event.amount, due: event.due, date: event.date };
      debts.set(debt.id, debt);
      for (const queue of [queues[debt.fund], queues.general]) {
        while (debt.remaining > 0n && queue.length > 0) {
          const chunk = queue[0];
          const take = chunk.remaining < debt.remaining ? chunk.remaining : debt.remaining;
          chunk.remaining -= take;
          apply(event.date, chunk.paymentId, debt, take);
          if (chunk.remaining === 0n) queue.shift();
        }
      }
      if (debt.remaining > 0n) insertSorted(open, debt);
    } else {
      payments.set(event.id, { id: event.id, date: event.date, amount: event.amount, restriction: event.restriction, operating: 0n, capital: 0n, advance: 0n });
      let left = event.amount;
      let index = 0;
      while (left > 0n && index < open.length) {
        const debt = open[index];
        if (event.restriction !== null && debt.fund !== event.restriction) {
          index += 1;
          continue;
        }
        const take = debt.remaining < left ? debt.remaining : left;
        left -= take;
        apply(event.date, event.id, debt, take);
        if (debt.remaining === 0n) open.splice(index, 1);
        else index += 1;
      }
      if (left > 0n) {
        queues[event.restriction ?? 'general'].push({ paymentId: event.id, remaining: left });
      }
    }
  }

  const funds = { operating: emptyFund(), capital: emptyFund() };
  for (const debt of debts.values()) {
    if (debt.remaining > 0n) {
      funds[debt.fund].open += debt.remaining;
      if (today !== null && debt.due <= today) funds[debt.fund].overdue += debt.remaining;
    }
  }
  let generalAdvance = 0n;
  for (const [name, queue] of Object.entries(queues)) {
    for (const chunk of queue) {
      payments.get(chunk.paymentId).advance += chunk.remaining;
      if (name === 'general') generalAdvance += chunk.remaining;
      else funds[name].advance += chunk.remaining;
    }
  }
  return { funds, generalAdvance, advanceTotal: funds.operating.advance + funds.capital.advance + generalAdvance, payments, debts, events };
}

/**
 * Bir ya da birkaç hesabın dağıtımı -> kasa kırılımı (BigInt). `inScope(debtId)` verilirse (sakin kapsamı) yalnız kapsam içi borçlar sayılır; avans her durumda dağıtımdan gelir.
 * @param {Array<ReturnType<typeof allocateFunds>>} allocations
 * @param {{ today?: string|null, inScope?: ((debtId: number) => boolean)|null }} [options]
 */
export function summarizeFunds(allocations, { today = null, inScope = null } = {}) {
  const funds = { operating: emptyFund(), capital: emptyFund() };
  let advanceTotal = 0n;
  for (const allocation of allocations) {
    advanceTotal += allocation.advanceTotal;
    for (const fund of FUNDS) {
      funds[fund].advance += allocation.funds[fund].advance;
    }
    if (inScope === null) {
      for (const fund of FUNDS) {
        funds[fund].open += allocation.funds[fund].open;
        funds[fund].overdue += allocation.funds[fund].overdue;
      }
      continue;
    }
    for (const debt of allocation.debts.values()) {
      if (debt.remaining > 0n && inScope(debt.id)) {
        funds[debt.fund].open += debt.remaining;
        if (today !== null && debt.due <= today) funds[debt.fund].overdue += debt.remaining;
      }
    }
  }
  return { funds, advanceTotal };
}

/** summarizeFunds çıktısı -> API biçimi: `funds: { operating: { balance_minor, overdue_minor, advance_minor }, capital: {…} }` ve `advance_minor` (toplam avans). */
export function fundsBodyOf(summary, toNumber) {
  const one = (entry) => ({ balance_minor: toNumber(entry.open), overdue_minor: toNumber(entry.overdue), advance_minor: toNumber(entry.advance) });
  return { funds: { operating: one(summary.funds.operating), capital: one(summary.funds.capital) }, advance_minor: toNumber(summary.advanceTotal) };
}

/** Bir tahsilatın dağıtımı -> API biçimi { operating_minor, capital_minor, advance_minor } (kuruş tamsayı). Tahsilat yoksa null. */
export function fundSplitOf(allocation, paymentId, toNumber) {
  const paid = allocation.payments.get(paymentId);
  if (!paid) {
    return null;
  }
  return { operating_minor: toNumber(paid.operating), capital_minor: toNumber(paid.capital), advance_minor: toNumber(paid.advance) };
}

/**
 * Bir tahsilatın `to` tarihi itibarıyla dağıtımı (olay tarihi <= to olanlar): operating + capital + advance = tahsilat tutarı. Kasa dökümü ve kasa bakiyesi
 * tarihli (as-of) okur: ileri tarihli bir borca sonradan uygulanacak avans `to` tarihinde hâlâ avanstır.
 */
export function paymentSplitAsOf(allocation, paymentId, to) {
  const paid = allocation.payments.get(paymentId);
  if (!paid) {
    return null;
  }
  let operating = 0n;
  let capital = 0n;
  for (const event of allocation.events) {
    if (event.paymentId === paymentId && event.date <= to) {
      if (event.fund === 'capital') capital += event.amount;
      else operating += event.amount;
    }
  }
  return { operating, capital, advance: paid.amount - operating - capital };
}

// --- Defter yükleyicisi (DB; çağıran `db.query` verir) -------------------------------------------------------------------------------------------------

const ACCOUNT_SQL = `COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)`;

const LEDGER_FUND_SELECT = `
  SELECT
    l.id, l.apartment_id, l.kind, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date,
    to_char(l.due_date, 'YYYY-MM-DD') AS due_date, l.reverses_entry_id, l.fund, l.source_kind, l.late_fee_run_id, l.definition_id,
    fd.charge_party AS def_charge_party, fd.kind AS def_kind, ${ACCOUNT_SQL} AS account_party
  FROM ledger_entries l
  LEFT JOIN fee_definitions fd ON fd.id = l.definition_id
`;

/**
 * Sitenin (ya da verilen dairelerin) defter satırları, HESAP başına gruplanmış: Map<"daireId:hesap", allocateFunds girdisi[]>. 052 öncesi satırın hesabı payer_party'den
 * türetilir. Satırlar id sırasıyla gelir.
 */
export async function loadFundLedger(db, siteCode, { apartmentIds = null } = {}) {
  const result = await db.query(
    `${LEDGER_FUND_SELECT} WHERE l.site_code = $1 AND ($2::BIGINT[] IS NULL OR l.apartment_id = ANY($2::BIGINT[])) ORDER BY l.apartment_id, l.id`,
    [siteCode, apartmentIds],
  );
  const groups = new Map();
  for (const row of result.rows ?? []) {
    const key = `${Number(row.apartment_id)}:${row.account_party === 'tenant' ? 'tenant' : 'owner'}`;
    let list = groups.get(key);
    if (!list) {
      list = [];
      groups.set(key, list);
    }
    list.push(toAllocatorEntry(row));
  }
  return groups;
}

/** Tek hesabın dağıtımı (tahsilat yanıtı / makbuz için). */
export async function allocateAccount(db, { siteCode, apartmentId, accountParty, today = null }) {
  const groups = await loadFundLedger(db, siteCode, { apartmentIds: [apartmentId] });
  return allocateFunds(groups.get(`${apartmentId}:${accountParty === 'tenant' ? 'tenant' : 'owner'}`) ?? [], { today });
}

/** Bir tahsilatın şu anki dağıtımı { operating_minor, capital_minor, advance_minor } (ya da null). `toNumber` = minorToNumber. */
export async function loadPaymentFundSplit(db, { siteCode, apartmentId, accountParty, paymentId, toNumber }) {
  const allocation = await allocateAccount(db, { siteCode, apartmentId, accountParty });
  return fundSplitOf(allocation, Number(paymentId), toNumber);
}
