// Sakin "Borcum" görünümü (finance_resident_view.residentView): kapsam + mahsup kuralı. Saf hesap, DB yok.
// Bağımsız inceleme senaryoları (2026-10-19): a) önceki sakinin geç ödemesi, b) önceki döneme ait tahsilatın düzeltilmesi,
// c) taşınmadan önce peşin ödeme, d) tarihsiz toplu yükleme + geçmiş aya yazılan borç.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { residentView } from '../src/modules/finance_resident_view.js';

let nextId = 0;
const charge = (amount, period, { due = null, entryDate = null, anchor = null, id = null } = {}) => ({
  id: id ?? (nextId += 1),
  kind: 'charge',
  amount: BigInt(amount),
  anchor: anchor ?? period,
  entryDate: entryDate ?? period,
  dueDate: due ?? `${period.slice(0, 8)}15`,
  reversesId: null,
});
const payment = (amount, entryDate, { id = null } = {}) => ({
  id: id ?? (nextId += 1),
  kind: 'payment',
  amount: -BigInt(amount),
  anchor: `${entryDate.slice(0, 8)}01`,
  entryDate,
  dueDate: null,
  reversesId: null,
});
const reversal = (original, entryDate) => ({
  id: (nextId += 1),
  kind: 'reversal',
  amount: -original.amount,
  anchor: original.anchor,
  entryDate,
  dueDate: original.dueDate,
  reversesId: original.id,
});
const TODAY = '2026-10-19';
const ids = (set) => [...set].sort((a, b) => a - b);

describe('residentView: kapsamsız (since = null) sonuç dairenin defter toplamıdır', () => {
  it('bakiye = tutarların toplamı; vadesi geçmiş = bakiye - vadesi gelmemiş; ters kayıt çiftleri sıfırlanır; sıradaki vade', () => {
    const c1 = charge(1000, '2026-08-01');
    const c2 = charge(1000, '2026-09-01');
    const c3 = charge(1000, '2026-10-01', { due: '2026-10-28' });
    const p1 = payment(1500, '2026-09-20');
    const bad = charge(700, '2026-09-01');
    const all = [c1, c2, c3, p1, bad, reversal(bad, '2026-10-02')];
    const view = residentView(all, { since: null, today: TODAY });
    assert.equal(view.balance, 1500n);
    assert.equal(view.overdue, 500n, 'ödeme en eski vadeden: c1 tamamen, c2 yarısı ödendi; c3 vadesi gelmedi');
    assert.deepEqual(view.nextDue, { dueDate: '2026-10-28', amount: 1000n });
    assert.equal(view.hiddenCount, 0);
  });

  it('fazla ödeme alacak olur (negatif bakiye), vadesi geçmiş 0', () => {
    const view = residentView([charge(1000, '2026-09-01'), payment(1600, '2026-09-10')], { since: null, today: TODAY });
    assert.equal(view.balance, -600n);
    assert.equal(view.overdue, 0n);
    assert.equal(view.nextDue, null);
  });
});

describe('residentView: sakin kapsamı', () => {
  it('a) önceki sakinin geç ödemesi eski borca mahsup edilir: yeni sakinin borcu açık kalır, ödeme satırı görünür (kapsam içi tarih)', () => {
    const old = charge(1000, '2026-08-01');
    const mine = charge(1000, '2026-09-01');
    const late = payment(1000, '2026-09-25');
    const view = residentView([old, mine, late], { since: '2026-09-01', today: TODAY });
    assert.equal(view.balance, 1000n, 'yeni sakine "borcunuz yok" denmez');
    assert.equal(view.overdue, 1000n);
    assert.deepEqual(ids(view.visibleIds), [mine.id, late.id]);
  });

  it('b) önceki döneme ait tahsilatın düzeltilmesi (ters kayıt + yeni tahsilat): yeni sakinin bakiyesi bozulmaz', () => {
    const old = charge(1000, '2026-08-01');
    const oldPay = payment(1000, '2026-08-20');
    const mine = charge(1000, '2026-09-01');
    const corrected = payment(900, '2026-10-05');
    const view = residentView([old, oldPay, reversal(oldPay, '2026-10-05'), mine, corrected], { since: '2026-09-01', today: TODAY });
    assert.equal(view.balance, 1000n, 'düzeltilen 900, kapsam dışındaki eski borca mahsup edilir; yeni sakinin borcu 1000 kalır');
    assert.equal(view.visibleIds.has(oldPay.id), false, 'önceki dönemin tahsilatı ve ters kaydı görünmez');
  });

  it('c) taşınmadan önce peşin ödeme kapsam içi borca mahsup edilir: borç kapanır, ödeme görünür', () => {
    const prepay = payment(1000, '2026-08-28');
    const mine = charge(1000, '2026-09-01');
    const view = residentView([prepay, mine], { since: '2026-09-01', today: TODAY });
    assert.equal(view.balance, 0n);
    assert.equal(view.visibleIds.has(prepay.id), true);
  });

  it('d) tarihsiz toplu yükleme (kapsam Ekim) + Eylül ve Ekim aidatı + 2000 ödeme: sahte alacak YOK', () => {
    const sep = charge(1000, '2026-09-01', { entryDate: '2026-10-19' });
    const oct = charge(1000, '2026-10-01', { entryDate: '2026-10-19' });
    const pay = payment(2000, '2026-10-19');
    const view = residentView([sep, oct, pay], { since: '2026-10-01', today: TODAY });
    assert.equal(view.balance, 0n);
    assert.deepEqual(ids(view.visibleIds), [oct.id, pay.id]);
    assert.equal(view.hiddenCount, 1);
  });

  it('kapsam dışı fazla ödeme (önceki sakinin alacağı) yeni sakine alacak olarak yazılmaz ama borcunu kapatır', () => {
    const oldPay = payment(1500, '2026-08-10');
    const old = charge(1000, '2026-08-01');
    const mine = charge(1000, '2026-09-01');
    const view = residentView([old, oldPay, mine], { since: '2026-09-01', today: TODAY });
    assert.equal(view.balance, 500n, 'önceki fazla ödeme (500) sıradaki borca mahsup edilir; sakinin kalanı 500');
    assert.equal(view.visibleIds.has(oldPay.id), false, 'kısmen önceki döneme giden tahsilat görünmez (etkisi bakiyede)');
  });

  it('gecikme tazminatı kalemi dayanak ayına (hesaplanan ay) göre: önceki aya ait kalem ve ters kaydı görünmez', () => {
    const fee = charge(50, '2026-10-01', { anchor: '2026-08-01', entryDate: '2026-10-05', due: '2026-10-05' });
    const view = residentView([fee, reversal(fee, '2026-10-06')], { since: '2026-09-01', today: TODAY });
    assert.equal(view.visibleIds.size, 0);
    assert.equal(view.balance, 0n);
  });

  it('sakinin taşınmadan önceki KISMİ peşin ödemesi (hiçbir kısmı önceki döneme gitmedi): görünür, artanı alacak sayılır', () => {
    const prepay = payment(1500, '2026-09-28');
    const mine = charge(1000, '2026-10-01');
    const view = residentView([prepay, mine], { since: '2026-10-01', today: TODAY });
    assert.equal(view.balance, -500n);
    assert.equal(view.visibleIds.has(prepay.id), true);
  });

  it('ileri tarihli borcun asıl kayıttan ÖNCE yazılan ters kaydı: kesitte kendi tutarıyla sayılır (yönetici ekstresiyle aynı)', () => {
    const nov = charge(1000, '2026-11-01', { entryDate: '2026-11-01', due: '2026-11-15' });
    const rev = reversal(nov, '2026-10-19');
    const entries = [nov, rev];
    const asOfRev = residentView(entries, { since: null, today: TODAY, upTo: { date: '2026-10-19', id: rev.id } });
    assert.equal(asOfRev.balance, -1000n, 'asıl kayıt henüz deftere girmedi: ters kayıt alacak gibi');
    assert.equal(residentView(entries, { since: null, today: TODAY }).balance, 0n, 'ikisi birlikte sıfır');
    assert.equal(residentView(entries, { since: '2026-10-01', today: TODAY, upTo: { date: '2026-10-19', id: rev.id } }).visibleIds.has(rev.id), true);
  });

  it('vadesi boş borç: vade yerine kayıt tarihi (M1 ile aynı); ileri tarihli kayıt vadesi gelmemiş sayılır', () => {
    const future = { ...charge(1000, '2026-11-01', { entryDate: '2026-11-01' }), dueDate: null };
    const view = residentView([future], { since: null, today: TODAY });
    assert.equal(view.overdue, 0n);
    assert.deepEqual(view.nextDue, { dueDate: '2026-11-01', amount: 1000n });
  });

  it('ekstre kesitleri: before (açılış) ve upTo (kayan bakiye)', () => {
    const mine = charge(1000, '2026-09-01');
    const pay = payment(400, '2026-09-10');
    const entries = [mine, pay];
    assert.equal(residentView(entries, { since: '2026-09-01', today: TODAY, before: '2026-09-05' }).balance, 1000n);
    assert.equal(residentView(entries, { since: '2026-09-01', today: TODAY, upTo: { date: '2026-09-10', id: pay.id } }).balance, 600n);
    assert.equal(residentView(entries, { since: '2026-09-01', today: TODAY, upTo: { date: '2026-09-10', id: pay.id - 1 } }).balance, 1000n);
  });
});
