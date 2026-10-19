// Sakin "Borcum" görünümü (KVKK ölçülülük + doğru bakiye). Saf hesap: veritabanına dokunmaz.
//
// Kapsam: sakin dairenin defterini kendi taşınma ayından (`since`, ayın 1'i) itibaren görür. Satırın dayanak ayı (`anchor`):
// gecikme tazminatı kalemi ve ters kaydı için hesaplanan ay, ters kayıt için asıl kaydın ayı, diğerlerinde kaydın ayı
// (finance_read_service.residentAnchorSql).
//
// Bakiye M1 mahsup kuralıyla (makbuzdaki "vadesi en eski borçtan başlayarak mahsup edilir"; docs/PLATFORM_FINANS_4B.md, finance_m1.js)
// hesaplanır: ters kaydı olmayan borçlar (gecikme tazminatı dahil) (vade, kimlik) sırasıyla dizilir; ters kaydı olmayan tahsilatlar ve
// asıl kaydı henüz deftere girmemiş (ileri tarihli) borçların ters kayıtları "alacak" olarak (tarih, kimlik) sırasıyla bu borçlara
// dökülür. Sakinin bakiyesi = kapsam içi borçların ödenmemiş kalanı − GÖRÜNEN alacakların artan kısmı. Böylece önceki sakinin geç
// ödemesi yeni sakinin borcunu ödenmiş göstermez; geçmiş aya yazılan borç ödendiğinde sahte alacak doğmaz.
// since = null: kapsam yok; sonuç dairenin defter toplamıyla AYNIDIR (4a bakiye / vadesi geçmiş / sıradaki vade tanımları).
//
// Görünen satırlar: kapsam içi borç ve ters kayıtlar; tahsilat kapsam içiyse ya da hiçbir kısmı kapsam DIŞI bir borca mahsup edilmediyse
// (ör. sakinin taşınmadan önce yaptığı peşin ödeme; ters kaydı olan tahsilat yalnız kapsam içiyse). Bilinen sınır: kapsam içi tarihli her
// tahsilat görünür; kimin ödediği defterde tutulmadığından önceki sakinin taşınmadan SONRA yaptığı ödeme de yeni sakine görünür (bakiyesini
// etkilemez; makbuzdaki ödeyen adı, sakinin ilişki kaydından önce düzenlenmişse gizlenir: finance_receipts.js).

const byDue = (a, b) => {
  const ka = a.dueDate ?? a.entryDate;
  const kb = b.dueDate ?? b.entryDate;
  return ka < kb ? -1 : ka > kb ? 1 : a.id - b.id;
};
const byEntry = (a, b) => (a.entryDate < b.entryDate ? -1 : a.entryDate > b.entryDate ? 1 : a.id - b.id);

/**
 * Bir kez sıralanmış girdi (ekstre gibi çok kesitli hesaplarda sıralama her kesitte tekrarlanmaz).
 * @param {Array<{id:number, kind:string, amount:bigint, anchor:string, entryDate:string, dueDate:string|null, reversesId:number|null}>} entries
 */
export function prepareResidentLedger(entries) {
  return {
    entries,
    charges: entries.filter((e) => e.kind === 'charge').sort(byDue),
    payments: entries.filter((e) => e.kind === 'payment').sort(byEntry),
    reversals: entries.filter((e) => e.kind === 'reversal').sort(byEntry),
  };
}

/**
 * @param {ReturnType<typeof prepareResidentLedger> | Array} input  prepareResidentLedger çıktısı ya da düz girdi dizisi
 * @param {{ since: string|null, today: string, upTo?: { date: string, id: number } | null, before?: string | null }} options
 *   upTo: yalnız (entryDate, id) <= (date, id) satırlar; before: yalnız entryDate < before satırlar (ekstre açılışı).
 * @returns {{ balance: bigint, overdue: bigint, nextDue: { dueDate: string, amount: bigint } | null, visibleIds: Set<number>, hiddenCount: number }}
 */
export function residentView(input, { since, today, upTo = null, before = null }) {
  const prepared = Array.isArray(input) ? prepareResidentLedger(input) : input;
  const inPool = (e) => {
    if (before !== null && !(e.entryDate < before)) return false;
    if (upTo !== null && (e.entryDate > upTo.date || (e.entryDate === upTo.date && e.id > upTo.id))) return false;
    return true;
  };
  const inScope = (e) => since === null || e.anchor >= since;
  const poolIds = new Set();
  for (const e of prepared.entries) {
    if (inPool(e)) poolIds.add(e.id);
  }
  const reversed = new Set();
  const orphanReversals = [];
  for (const r of prepared.reversals) {
    if (!poolIds.has(r.id)) continue;
    if (r.reversesId !== null && poolIds.has(r.reversesId)) reversed.add(r.reversesId);
    else orphanReversals.push(r); // asıl kayıt henüz deftere girmedi (ileri tarihli borç): tutarı kendi işaretiyle sayılır
  }
  const charges = prepared.charges.filter((e) => poolIds.has(e.id) && !reversed.has(e.id));
  const orphanCharges = orphanReversals.filter((r) => r.amount > 0n);
  const allCharges = orphanCharges.length > 0 ? [...charges, ...orphanCharges].sort(byDue) : charges;
  const credits = [
    ...prepared.payments.filter((e) => poolIds.has(e.id) && !reversed.has(e.id)),
    ...orphanReversals.filter((r) => r.amount < 0n),
  ].sort(byEntry);

  const remaining = allCharges.map((c) => c.amount);
  const appliedToHidden = new Map();
  const leftover = new Map();
  let ci = 0;
  for (const p of credits) {
    let left = -p.amount;
    let hidden = 0n;
    while (left > 0n && ci < allCharges.length) {
      const take = remaining[ci] < left ? remaining[ci] : left;
      remaining[ci] -= take;
      left -= take;
      if (!inScope(allCharges[ci])) hidden += take;
      if (remaining[ci] === 0n) ci += 1;
    }
    appliedToHidden.set(p.id, hidden);
    leftover.set(p.id, left > 0n ? left : 0n);
  }

  const visibleIds = new Set();
  for (const e of prepared.entries) {
    if (!poolIds.has(e.id)) continue;
    if (e.kind === 'payment' && !reversed.has(e.id)) {
      if (inScope(e) || (appliedToHidden.get(e.id) ?? 0n) === 0n) visibleIds.add(e.id);
    } else if (inScope(e)) {
      visibleIds.add(e.id);
    }
  }

  let balance = 0n;
  let overdue = 0n;
  const upcoming = new Map();
  allCharges.forEach((c, index) => {
    if (!inScope(c)) return;
    const rem = remaining[index];
    balance += rem;
    if (rem === 0n) return;
    const due = c.dueDate ?? c.entryDate;
    if (due <= today) {
      overdue += rem;
    } else {
      upcoming.set(due, (upcoming.get(due) ?? 0n) + rem);
    }
  });
  for (const p of credits) {
    if (visibleIds.has(p.id)) balance -= leftover.get(p.id);
  }
  let nextDue = null;
  for (const [dueDate, amount] of upcoming) {
    if (nextDue === null || dueDate < nextDue.dueDate) nextDue = { dueDate, amount };
  }
  return { balance, overdue, nextDue, visibleIds, hiddenCount: poolIds.size - visibleIds.size };
}

/** ENTRY_SELECT satırı + `anchor` sütunu -> residentView girdisi. */
export function residentEntryOf(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    amount: BigInt(row.amount_minor),
    anchor: row.anchor,
    entryDate: row.entry_date,
    dueDate: row.due_date ?? null,
    reversesId: row.reverses_entry_id === null || row.reverses_entry_id === undefined ? null : Number(row.reverses_entry_id),
  };
}
