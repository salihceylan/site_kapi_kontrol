// K3 (sahip kararı, 2026-10-28; karşılaştırma raporu P1-3): "Yazılım ödemeyi kendiliğinden bir hesaba (İşletme / Fon) atamaz."
//  - Bir daire hesabında (daire + ev sahibi / kiracı hesabı) YALNIZ bir türün açık borcu varsa önerilen hesap odur: formda seçili gelir, yönetici değiştirebilir.
//  - İKİ türün de açık borcu varsa hesap seçimi ZORUNLUDUR: seçimsiz kayıt 400 FUND_CHOICE_REQUIRED ile reddedilir (hiçbir satır yazılmaz).
//  - Açık borç yoksa seçim zorunlu değildir (tutar genel avans olur; eski davranış). Yönetici isterse yine de bir hesap seçebilir.
// Tüm tahsilat yolları (elle tahsilat, tahsilat düzeltmesi, dekont onayı, banka satırı eşleme / onay, banka dosyası otomatik işleme) tek giriş noktası olan
// finance_parties.postPayment içinde bu denetimden geçer. Dağıtım burada YENİDEN hesaplanmaz: açık borçlar allocateFunds sonucundan okunur (AGENTS.md Kural 26);
// "önerilen dağılım" da aynı işlevin, hesaba eklenen varsayımsal bir tahsilatla çalıştırılmasıdır (yalnız bilgi; hiçbir şey yazılmaz).
// Bu dosya finance_parties.js'i İÇE AKTARMAZ (postPayment bu dosyayı kullanır; döngüsel içe aktarma olmasın). PARA BigInt'tir; kayan nokta yok.

import { PlatformError } from './errors.js';
import { FUND_LABELS, allocateFunds, loadFundLedger } from './finance_funds.js';
import { minorToNumber } from './finance_money.js';

export const FUND_CHOICE_REQUIRED = 'FUND_CHOICE_REQUIRED';

// Önerilen dağılım için varsayımsal tahsilatın kimliği: gerçek kimliklerden büyüktür, aynı tarihte en sona sıralanır.
const PROPOSAL_ID = Number.MAX_SAFE_INTEGER;

const partyKey = (accountParty) => (accountParty === 'tenant' ? 'tenant' : 'owner');

/**
 * SAF: allocateFunds sonucu -> hesap seçim durumu (BigInt). `required` = iki türün de açık borcu var (seçim zorunlu); `suggested` = yalnız bir türün açık borcu
 * varsa o hesap ('operating' | 'capital'), aksi null (iki tür: öneri yok, yönetici seçer; hiç borç yok: genel avans).
 * @param {ReturnType<typeof allocateFunds>} allocation
 */
export function fundChoiceOf(allocation) {
  const openOperating = allocation.funds.operating.open;
  const openCapital = allocation.funds.capital.open;
  const required = openOperating > 0n && openCapital > 0n;
  let suggested = null;
  if (!required) {
    if (openOperating > 0n) suggested = 'operating';
    else if (openCapital > 0n) suggested = 'capital';
  }
  return { openOperating, openCapital, advanceTotal: allocation.advanceTotal, required, suggested };
}

/**
 * SAF: `amount` (BigInt, pozitif) tutarında KISITSIZ bir tahsilat `paidOn` tarihinde yapılsaydı allocateFunds'ın nasıl dağıtacağı (yalnız bilgi).
 * Dağıtım ikinci yerde hesaplanmaz: aynı işlev, hesabın satırlarına varsayımsal bir tahsilat eklenerek çalıştırılır. Tutar yoksa null.
 */
export function proposalOf(entries, amount, paidOn) {
  if (typeof amount !== 'bigint' || amount <= 0n) {
    return null;
  }
  const hypothetical = { id: PROPOSAL_ID, kind: 'payment', amount: -amount, fund: null, entryDate: paidOn, dueDate: null, reversesId: null };
  const paid = allocateFunds([...entries, hypothetical]).payments.get(PROPOSAL_ID);
  return paid ? { operating: paid.operating, capital: paid.capital, advance: paid.advance } : null;
}

/** API gövdesi (tamsayı kuruş): uç yanıtı ve 400 FUND_CHOICE_REQUIRED ek alanı aynı biçimi kullanır. */
export function fundChoiceBody(choice, { apartmentId = null, accountParty, proposal = null } = {}) {
  return {
    apartment_id: apartmentId,
    account_party: partyKey(accountParty),
    open: { operating_minor: minorToNumber(choice.openOperating), capital_minor: minorToNumber(choice.openCapital) },
    advance_minor: minorToNumber(choice.advanceTotal),
    choice_required: choice.required,
    suggested_fund: choice.suggested,
    proposal: proposal ? { operating_minor: minorToNumber(proposal.operating), capital_minor: minorToNumber(proposal.capital), advance_minor: minorToNumber(proposal.advance) } : null,
  };
}

export const FUND_CHOICE_MESSAGE = `Bu hesapta hem ${FUND_LABELS.operating} hem de ${FUND_LABELS.capital} için açık borç var. Ödemenin hangisine işleneceğini siz seçin; yazılım kendiliğinden atamaz.`;

/** 400 FUND_CHOICE_REQUIRED: seçimsiz kayıt reddedilir; ek alan `fund_choice` açık borçları ve (varsa) önerilen dağılımı taşır. */
export function fundChoiceRequired(choice, { apartmentId = null, accountParty, proposal = null } = {}) {
  return new PlatformError(400, FUND_CHOICE_REQUIRED, FUND_CHOICE_MESSAGE, { fund_choice: fundChoiceBody(choice, { apartmentId, accountParty, proposal }) });
}

/**
 * Bir daire hesabının (daire + ev sahibi / kiracı) hesap seçim durumu. `db` havuz ya da işlem bağlantısı olabilir. `amountMinor` (pozitif tamsayı) verilirse
 * `proposal` (otomatik dağıtım ne yapardı) da hesaplanır; `paidOn` ('YYYY-MM-DD') verilmezse `todayIso`.
 * @returns {Promise<{ choice: ReturnType<typeof fundChoiceOf>, proposal: object|null }>}
 */
export async function loadFundChoice(db, { siteCode, apartmentId, accountParty, amountMinor = null, paidOn = null, todayIso = null }) {
  const groups = await loadFundLedger(db, siteCode, { apartmentIds: [apartmentId] });
  const entries = groups.get(`${apartmentId}:${partyKey(accountParty)}`) ?? [];
  const choice = fundChoiceOf(allocateFunds(entries));
  const amount = amountMinor === null || amountMinor === undefined ? null : BigInt(amountMinor);
  const proposalDate = paidOn ?? todayIso ?? new Date().toISOString().slice(0, 10);
  return { choice, proposal: amount === null ? null : proposalOf(entries, amount, proposalDate) };
}

/**
 * Tahsilat hesap (kasa) kısıtı OLMADAN yazılırken çağrılır (finance_parties.postPayment): iki türün de açık borcu varsa 400 FUND_CHOICE_REQUIRED fırlatır.
 * Kısıt verilmişse çağrılmaz (yönetici seçimini yapmıştır). Okuma, çağıranın finans işlemi içindedir: tüm finans yazmaları `finance_post` kilidiyle sıralıdır.
 */
export async function assertFundChoice(db, { siteCode, apartmentId, accountParty }) {
  const { choice } = await loadFundChoice(db, { siteCode, apartmentId, accountParty });
  if (choice.required) {
    throw fundChoiceRequired(choice, { apartmentId, accountParty });
  }
  return choice;
}
