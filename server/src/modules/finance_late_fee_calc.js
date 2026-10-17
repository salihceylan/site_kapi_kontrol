// Gecikme tazminatı hesabı (Faz 4b Ö2) — SAF (DB/ağ yok), BigInt. docs/PLATFORM_FINANS_4B.md "Ö2 Hesap (normatif tanım)".
//
// Daire A, hesaplanan ay P (p1 = ilk gün, p2 = son gün), aylık oran R (baz puan), ek gün G, yöntem sabiti D (daily_30 -> 30; daily_actual -> ayın gün sayısı).
// p1..p2 aralığındaki HER gün d için kalemler ve ödemeler M1 ile T = d günü itibarıyla alınır (finance_m1.js); L(d) = max(vade_i, entry_date_i) + G < d olan,
// gecikme tazminatı OLMAYAN kalemlerin rem_i(d) toplamı ("vade gününü izleyen günden başlar; ödeme günü gecikme sayılmaz; geç kaydedilen kalem kayıt gününden önce
// gecikmeye girmez"). S = Σ_d L(d) (kuruş·gün). fee = floor((2·S·R + 10000·D) / (20000·D)) (yarım yukarı). Faiz üstüne faiz yok: tazminat kalemleri tabana GİRMEZ
// (ama M1'de ödeme tüketir).
//
// Optimizasyon: durum yalnız olay günlerinde (kayıt / ters kayıt / gecikmeye girme günleri) değişir; her parça içinde L sabittir. Sonuç, gün-gün kaba kuvvet
// tanımıyla BİREBİR aynıdır (QA ve birim testi ≥ 2000 rastgele defterle doğrular).

import { dayNumber, isoOfDay } from './finance_4b_common.js';

const NEVER = Number.MAX_SAFE_INTEGER;

/**
 * Daire satırlarını hazırlar. rows: { id, kind, amount (bigint, işaretli), entryDay, dueDay|null, lateFee (bool), reversesId|null } (gün = dayNumber).
 * @returns {{ items: object[], pays: object[] }}
 */
export function prepareApartment(rows, graceDays) {
  const reversedOn = new Map();
  for (const row of rows) {
    if (row.kind === 'reversal' && row.reversesId !== null && row.reversesId !== undefined) {
      const current = reversedOn.get(row.reversesId);
      reversedOn.set(row.reversesId, current === undefined || row.entryDay < current ? row.entryDay : current);
    }
  }
  const items = rows
    .filter((row) => row.kind === 'charge')
    .map((row) => {
      const due = row.dueDay === null || row.dueDay === undefined ? row.entryDay : row.dueDay;
      return {
        id: row.id,
        amount: row.amount,
        entry: row.entryDay,
        due,
        rev: reversedOn.get(row.id) ?? NEVER,
        lateFee: row.lateFee === true,
        threshold: Math.max(due, row.entryDay) + graceDays,
      };
    })
    .sort((a, b) => (a.due === b.due ? a.id - b.id : a.due - b.due));
  const pays = rows
    .filter((row) => row.kind === 'payment')
    .map((row) => ({ day: row.entryDay, amount: -row.amount, rev: reversedOn.get(row.id) ?? NEVER }));
  return { items, pays };
}

/** d günü itibarıyla L(d) (kuruş): M1 + gecikme koşulu. */
export function overdueOnDay(prepared, day) {
  let pay = 0n;
  for (const p of prepared.pays) {
    if (p.day <= day && p.rev > day) {
      pay += p.amount;
    }
  }
  let cumulative = 0n;
  let overdue = 0n;
  for (const item of prepared.items) {
    if (item.entry > day || item.rev <= day) {
      continue;
    }
    cumulative += item.amount;
    const open = cumulative - pay;
    const clipped = open < 0n ? 0n : open < item.amount ? open : item.amount;
    if (!item.lateFee && item.threshold < day) {
      overdue += clipped;
    }
  }
  return overdue;
}

/** fee = floor((2·S·R + 10000·D) / (20000·D)); S kuruş·gün (BigInt), R baz puan, D gün sabiti. */
export function feeFromBase(base, rateBp, divisor) {
  const r = BigInt(rateBp);
  const d = BigInt(divisor);
  return (2n * base * r + 10000n * d) / (20000n * d);
}

/**
 * Bir daire için tazminat. p1 / p2 gün sayıları. Dönüş: { base (S), peak, fee, breakdown: [{ from, to, overdue }] } (from/to ISO, to dahil; yalnız L>0 parçaları).
 */
export function lateFeeForApartment(rows, { p1, p2, graceDays, rateBp, divisor }) {
  const prepared = prepareApartment(rows, graceDays);
  const points = new Set([p1]);
  const consider = (day) => {
    if (day > p1 && day <= p2) {
      points.add(day);
    }
  };
  for (const item of prepared.items) {
    consider(item.entry);
    consider(item.rev);
    consider(item.threshold + 1);
  }
  for (const pay of prepared.pays) {
    consider(pay.day);
    consider(pay.rev);
  }
  const starts = [...points].sort((a, b) => a - b);
  let base = 0n;
  let peak = 0n;
  const breakdown = [];
  for (let i = 0; i < starts.length; i += 1) {
    const from = starts[i];
    const next = i + 1 < starts.length ? starts[i + 1] : p2 + 1;
    const level = overdueOnDay(prepared, from);
    base += level * BigInt(next - from);
    if (level > peak) {
      peak = level;
    }
    if (level > 0n) {
      const last = breakdown[breakdown.length - 1];
      if (last && last.level === level && last.toDay === from - 1) {
        last.toDay = next - 1;
      } else {
        breakdown.push({ level, fromDay: from, toDay: next - 1 });
      }
    }
  }
  return {
    base,
    peak,
    fee: feeFromBase(base, rateBp, divisor),
    breakdown: breakdown.map((part) => ({ from: isoOfDay(part.fromDay), to: isoOfDay(part.toDay), overdue: part.level })),
  };
}

/** Gün-gün KABA KUVVET (tanımın doğrudan kodu; yalnız test / QA oracle'ı): optimizasyonun doğruluğunu bağımsız doğrular. */
export function lateFeeBruteForce(rows, { p1, p2, graceDays, rateBp, divisor }) {
  let base = 0n;
  for (let day = p1; day <= p2; day += 1) {
    const reversal = new Map();
    for (const row of rows) {
      if (row.kind === 'reversal' && row.entryDay <= day) {
        reversal.set(row.reversesId, true);
      }
    }
    const alive = (row) => row.entryDay <= day && !reversal.has(row.id);
    const charges = rows
      .filter((row) => row.kind === 'charge' && alive(row))
      .sort((a, b) => {
        const da = a.dueDay ?? a.entryDay;
        const db = b.dueDay ?? b.entryDay;
        return da === db ? a.id - b.id : da - db;
      });
    const paid = rows.filter((row) => row.kind === 'payment' && alive(row)).reduce((acc, row) => acc - row.amount, 0n);
    let level = 0n;
    for (let i = 0; i < charges.length; i += 1) {
      const row = charges[i];
      const cumulative = charges.slice(0, i + 1).reduce((acc, c) => acc + c.amount, 0n);
      const remaining = (() => {
        const open = cumulative - paid;
        const positive = open > 0n ? open : 0n;
        return positive < row.amount ? positive : row.amount;
      })();
      const due = row.dueDay ?? row.entryDay;
      if (row.lateFee !== true && Math.max(due, row.entryDay) + graceDays < day) {
        level += remaining;
      }
    }
    base += level;
  }
  return { base, fee: feeFromBase(base, rateBp, divisor) };
}

export { dayNumber };
