// Aidat ve Finans (Faz 4a): para yardımcıları ve dağıtım matematiği (saf, DB'siz). Para = tamsayı kuruş; kayan nokta YOK.
// "En büyük kalan" yöntemi: pay toplamı tutara BİREBİR eşit, deterministik (eşitlikte apartment_id küçük olan önce), rastgele özellik testi.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_AMOUNT_MINOR,
  MAX_RUN_TOTAL_MINOR,
  bigintsToSqlArray,
  isMinorInteger,
  minorToNumber,
  minorToNumberOrNull,
  parseMinor,
  sumBig,
  toBigInt,
} from '../src/modules/finance_money.js';
import {
  LAND_SHARE_LCM_MAX_BITS,
  buildDistributionPlan,
  categoryKey,
  distributeLargestRemainder,
  gcdBig,
  landShareWeights,
  lcmBig,
} from '../src/modules/finance_distribution.js';

// Deterministik rastgele sayı üretici (hata yeniden üretilebilsin)
function mulberry32(seed) {
  let a = seed;
  return () => {
    a += 0x6d2b79f5;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

describe('finans para yardımcıları', () => {
  it('sınırlar: tek tutar 10^12 kuruş, tek borçlandırma toplamı 10^14 kuruş (JSON güvenli aralığının çok altında)', () => {
    assert.equal(MAX_AMOUNT_MINOR, 1_000_000_000_000);
    assert.equal(MAX_RUN_TOTAL_MINOR, 100_000_000_000_000);
    assert.ok(MAX_RUN_TOTAL_MINOR < Number.MAX_SAFE_INTEGER);
  });

  it('parseMinor yalnızca JSON TAMSAYI kabul eder (ondalık, metin, NaN, sonsuz, negatif, sıfır, taşan, null, nesne reddedilir)', () => {
    for (const bad of [1.5, 0.1, '100', '1e3', NaN, Infinity, -Infinity, -1, 0, 1e21, 2 ** 53, MAX_AMOUNT_MINOR + 1, null, undefined, true, {}, [5], 5n]) {
      assert.equal(parseMinor(bad), null, String(bad));
    }
    assert.equal(parseMinor(1), 1);
    assert.equal(parseMinor(MAX_AMOUNT_MINOR), MAX_AMOUNT_MINOR);
    assert.equal(parseMinor(0, { min: 0 }), 0);
    assert.equal(parseMinor(50, { min: 0, max: 50 }), 50);
    assert.equal(parseMinor(51, { min: 0, max: 50 }), null);
    assert.equal(isMinorInteger(12), true);
    assert.equal(isMinorInteger(12.5), false);
    assert.equal(isMinorInteger('12'), false);
  });

  it('toBigInt: number (güvenli tamsayı), bigint ve rakam metni; başka her şey hata', () => {
    assert.equal(toBigInt(5), 5n);
    assert.equal(toBigInt(-7), -7n);
    assert.equal(toBigInt('123456789012345678'), 123456789012345678n);
    assert.equal(toBigInt(' -42 '), -42n);
    assert.equal(toBigInt(9n), 9n);
    for (const bad of [1.5, NaN, 2 ** 53, '1.5', '1e3', '', 'abc', null, undefined, {}]) {
      assert.throws(() => toBigInt(bad), undefined, String(bad));
    }
  });

  it('minorToNumber: güvenli aralıkta tamsayı; aralığın dışında HATA (sessizce bozulmaz); null -> 0, minorToNumberOrNull null korur', () => {
    assert.equal(minorToNumber('150000'), 150000);
    assert.equal(minorToNumber(-3n), -3);
    assert.equal(minorToNumber(null), 0);
    assert.equal(minorToNumber('9007199254740991'), Number.MAX_SAFE_INTEGER);
    assert.throws(() => minorToNumber('9007199254740993'), RangeError);
    assert.throws(() => minorToNumber(10n ** 20n), RangeError);
    assert.equal(minorToNumberOrNull(null), null);
    assert.equal(minorToNumberOrNull('5'), 5);
  });

  it('sumBig ve bigintsToSqlArray', () => {
    assert.equal(sumBig([]), 0n);
    assert.equal(sumBig([1n, 2n, -5n]), -2n);
    assert.deepEqual(bigintsToSqlArray([1n, 20n]), ['1', '20']);
  });
});

describe('dağıtım: en büyük kalan yöntemi', () => {
  it('eşitlikte apartment_id KÜÇÜK olan kalan kuruşu önce alır: 7 kuruş / 5 daire', () => {
    const result = distributeLargestRemainder(7n, [30, 10, 50, 20, 40].map((id) => ({ id, weight: 1n })));
    assert.deepEqual([...result.entries()].sort((a, b) => a[0] - b[0]), [[10, 2n], [20, 2n], [30, 1n], [40, 1n], [50, 1n]]);
  });

  it('toplam 0 -> herkese 0; tek daire -> tüm tutar; sıfır ağırlıklı daire pay almaz', () => {
    assert.deepEqual([...distributeLargestRemainder(0n, [{ id: 1, weight: 3n }, { id: 2, weight: 4n }]).values()], [0n, 0n]);
    assert.equal(distributeLargestRemainder(123456789n, [{ id: 9, weight: 5n }]).get(9), 123456789n);
    const withZero = distributeLargestRemainder(100n, [{ id: 1, weight: 0n }, { id: 2, weight: 1n }, { id: 3, weight: 1n }]);
    assert.equal(withZero.get(1), 0n);
    assert.equal(withZero.get(2) + withZero.get(3), 100n);
  });

  it('geçersiz girdi: negatif toplam / ağırlık, tüm ağırlıklar sıfır, boş liste ve pozitif toplam hata', () => {
    assert.throws(() => distributeLargestRemainder(-1n, [{ id: 1, weight: 1n }]), RangeError);
    assert.throws(() => distributeLargestRemainder(5n, [{ id: 1, weight: -1n }]), RangeError);
    assert.throws(() => distributeLargestRemainder(5n, [{ id: 1, weight: 0n }]), RangeError);
    assert.throws(() => distributeLargestRemainder(5n, []), RangeError);
    assert.throws(() => distributeLargestRemainder(5, [{ id: 1, weight: 1n }]), RangeError);
    assert.equal(distributeLargestRemainder(0n, []).size, 0);
  });

  it('10^12 kuruş / 3000 daire: toplam birebir, paylar yalnız iki değer', () => {
    const result = distributeLargestRemainder(1_000_000_000_000n, Array.from({ length: 3000 }, (_, i) => ({ id: i + 1, weight: 1n })));
    assert.equal(sumBig([...result.values()]), 1_000_000_000_000n);
    assert.equal(new Set(result.values()).size, 2);
  });

  it('ÖZELLİK TESTİ (3000 rastgele girdi): pay toplamı tutara BİREBİR eşit; her pay tabana veya tabana+1; sıfır ağırlık 0; girdi sırasından bağımsız', () => {
    const rnd = mulberry32(20261016);
    const randInt = (max) => Math.floor(rnd() * (max + 1));
    const randBig = (digits) => {
      let text = '';
      for (let i = 0; i < digits; i += 1) text += String(randInt(9));
      return BigInt(text);
    };
    const shuffle = (list) => {
      const copy = [...list];
      for (let i = copy.length - 1; i > 0; i -= 1) {
        const j = randInt(i);
        [copy[i], copy[j]] = [copy[j], copy[i]];
      }
      return copy;
    };
    const failures = [];
    for (let trial = 0; trial < 3000; trial += 1) {
      const n = 1 + randInt(trial % 10 === 0 ? 300 : 40);
      const total = trial % 7 === 0 ? BigInt(randInt(50)) : randBig(1 + randInt(12));
      const ids = [...new Set(Array.from({ length: n }, (_, i) => 1000 + i * 3 + randInt(2)))];
      const weights = ids.map(() => (rnd() < 0.15 ? 0n : BigInt(1 + randInt(trial % 3 === 0 ? 5 : 1_000_000))));
      if (weights.every((w) => w === 0n)) weights[0] = 1n;
      const items = shuffle(ids.map((id, i) => ({ id, weight: weights[i] })));
      const result = distributeLargestRemainder(total, items);
      const weightSum = weights.reduce((a, b) => a + b, 0n);
      let sum = 0n;
      let bad = null;
      for (const item of items) {
        const share = result.get(item.id);
        sum += share;
        const floor = (total * item.weight) / weightSum;
        if (share !== floor && share !== floor + 1n) bad = `pay ${share} sınır dışı (taban ${floor})`;
        if (item.weight === 0n && share !== 0n) bad = 'sıfır ağırlık pay aldı';
      }
      if (sum !== total) bad = `toplam ${sum} != ${total}`;
      const again = distributeLargestRemainder(total, shuffle(items));
      if (items.some((item) => again.get(item.id) !== result.get(item.id))) bad = 'girdi sırasına bağımlı';
      if (bad) failures.push({ trial, n, total: String(total), bad });
    }
    assert.deepEqual(failures.slice(0, 3), []);
  });
});

describe('arsa payı: ortak payda ile tamsayı ağırlık', () => {
  it('gcd / lcm', () => {
    assert.equal(gcdBig(12n, 18n), 6n);
    assert.equal(gcdBig(0n, 7n), 7n);
    assert.equal(lcmBig(4n, 6n), 12n);
    assert.equal(lcmBig(0n, 6n), 0n);
  });

  it('1/4 ve 1/2 -> ağırlık 1:2; 35/1000 ve 12/2000 aynı paydaya getirilir', () => {
    assert.deepEqual(landShareWeights([{ id: 1, numerator: 1n, denominator: 4n }, { id: 2, numerator: 1n, denominator: 2n }]).map((w) => w.weight), [1n, 2n]);
    assert.deepEqual(landShareWeights([{ id: 1, numerator: 35n, denominator: 1000n }, { id: 2, numerator: 12n, denominator: 2000n }]).map((w) => w.weight), [70n, 12n]);
  });

  it('600 rastgele girdi: ağırlıklar kesirlerle ORANTILI (çapraz çarpım) ve pay toplamı tutara eşit', () => {
    const rnd = mulberry32(777);
    const denominators = [100, 360, 1000, 7000, 10000, 2000];
    for (let trial = 0; trial < 600; trial += 1) {
      const n = 2 + Math.floor(rnd() * 30);
      const shares = Array.from({ length: n }, (_, i) => {
        const denominator = denominators[Math.floor(rnd() * denominators.length)];
        return { id: i + 1, numerator: BigInt(1 + Math.floor(rnd() * (denominator - 1))), denominator: BigInt(denominator) };
      });
      const weights = landShareWeights(shares);
      for (let i = 0; i + 1 < n; i += 1) {
        assert.equal(weights[i].weight * shares[i + 1].numerator * shares[i].denominator, weights[i + 1].weight * shares[i].numerator * shares[i + 1].denominator);
      }
      const total = BigInt(1 + Math.floor(rnd() * 1e9));
      assert.equal(sumBig([...distributeLargestRemainder(total, weights).values()]), total);
    }
  });

  it('ortak payda sınırsız büyüyemez: 24 ayrı büyük asal payda -> LAND_SHARE_UNSUPPORTED (409)', () => {
    const primes = [];
    for (let candidate = 2147483647; primes.length < 24; candidate -= 2) {
      let isPrime = true;
      for (let d = 3; d * d <= candidate; d += 2) {
        if (candidate % d === 0) {
          isPrime = false;
          break;
        }
      }
      if (isPrime) primes.push(candidate);
    }
    try {
      landShareWeights(primes.map((p, i) => ({ id: i + 1, numerator: 1n, denominator: BigInt(p) })));
      assert.fail('hata bekleniyordu');
    } catch (error) {
      assert.equal(error.code, 'LAND_SHARE_UNSUPPORTED');
      assert.equal(error.statusCode, 409);
    }
    assert.equal(LAND_SHARE_LCM_MAX_BITS, 512);
    assert.throws(() => landShareWeights([{ id: 1, numerator: 1n, denominator: 0n }]), RangeError);
  });
});

const apt = (id, extra = {}) => ({
  id,
  label: `D${id}`,
  blockName: 'A',
  blockSort: 1,
  aptSort: id,
  payerParty: 'both',
  category: null,
  grossX100: null,
  netX100: null,
  landNumerator: null,
  landDenominator: null,
  ...extra,
});
const flat = (plan) => plan.lines.map((l) => `${l.apartmentId}:${l.amount}`).join(',');

describe('dağıtım planı (buildDistributionPlan)', () => {
  it('fixed: her daireye amount_minor; ödeyen taraf dairenin değeri; sıra blok/daire sırası', () => {
    const plan = buildDistributionPlan({ distribution: 'fixed', amountMinor: 123456 }, [apt(2, { payerParty: 'owner' }), apt(1, { payerParty: 'tenant', aptSort: 5 })]);
    assert.equal(plan.total, 246912n);
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.payerParty]), [[2, 'owner'], [1, 'tenant']]);
    assert.equal(plan.missing.length, 0);
  });

  it('equal: toplam bölünür; 2 kuruş / 5 daire -> yalnız 2 daire 1 kuruş alır (defter satırı sıfır olamaz), sıfır paylar sayılır', () => {
    const plan = buildDistributionPlan({ distribution: 'equal', amountMinor: 2 }, [1, 2, 3, 4, 5].map((id) => apt(id)));
    assert.equal(flat(plan), '1:1,2:1');
    assert.equal(plan.total, 2n);
    assert.equal(plan.zeroAmountCount, 3);
    assert.equal(plan.includedCount, 5);
  });

  it('category: Türkçe karakter ve harf duyarsız eşleşme; kategorisiz ve haritada olmayan daire eksik veri (iki neden)', () => {
    const plan = buildDistributionPlan(
      { distribution: 'category', categoryAmounts: { 'DÜKKAN': 20000, '2+1': 10000, 'iş yeri': 30000 } },
      [apt(1, { category: 'dükkan' }), apt(2, { category: '2+1' }), apt(3, { category: 'İŞ YERİ' }), apt(4), apt(5, { category: '9+9' })],
    );
    assert.equal(flat(plan), '1:20000,2:10000,3:30000');
    assert.deepEqual(plan.missing.map((m) => [m.apartmentId, m.reasonCode, m.reason]), [[4, 'category_missing', 'Kategori tanımsız'], [5, 'category_amount_missing', 'Kategori için tutar tanımlı değil']]);
    assert.equal(categoryKey('  İŞ   YERİ '), 'is yeri');
  });

  it('area: seçili esas (net/brüt) x100 tamsayı ağırlık; tanımsız veya 0 m² eksik veri', () => {
    const plan = buildDistributionPlan({ distribution: 'area', areaBasis: 'net', amountMinor: 100000 }, [apt(1, { netX100: '10000', grossX100: '99999' }), apt(2, { netX100: '30000' }), apt(3, { grossX100: '5000' }), apt(4, { netX100: '0' })]);
    assert.equal(flat(plan), '1:25000,2:75000');
    assert.deepEqual(plan.missing.map((m) => [m.apartmentId, m.reasonCode]), [[3, 'area_missing'], [4, 'area_missing']]);
    const gross = buildDistributionPlan({ distribution: 'area', areaBasis: 'gross', amountMinor: 100 }, [apt(1, { grossX100: '100' }), apt(2, { grossX100: '100' })]);
    assert.equal(flat(gross), '1:50,2:50');
  });

  it('land_share: 1/4 : 1/2 -> 333 / 667 (kalan kuruş büyük kalana); tanımsız ve sıfır pay eksik veri', () => {
    const plan = buildDistributionPlan({ distribution: 'land_share', amountMinor: 1000 }, [apt(1, { landNumerator: 1, landDenominator: 4 }), apt(2, { landNumerator: 1, landDenominator: 2 }), apt(3), apt(4, { landNumerator: 0, landDenominator: 10 })]);
    assert.equal(flat(plan), '1:333,2:667');
    assert.equal(plan.total, 1000n);
    assert.deepEqual(plan.missing.map((m) => [m.apartmentId, m.reasonCode]), [[3, 'land_share_missing'], [4, 'land_share_missing']]);
  });

  it('eksik veri varsa kalan daireler tutarın TAMAMINI paylaşır (toplam değişmez)', () => {
    const plan = buildDistributionPlan({ distribution: 'equal', amountMinor: 1000 }, [apt(1), apt(2), apt(3)]);
    assert.equal(plan.total, 1000n);
    const land = buildDistributionPlan({ distribution: 'land_share', amountMinor: 999 }, [apt(1, { landNumerator: 1, landDenominator: 10 }), apt(2), apt(3, { landNumerator: 3, landDenominator: 10 })]);
    assert.equal(land.total, 999n);
    assert.equal(land.lines.length, 2);
  });

  it('hiç dahil daire yoksa plan boş (toplam 0); bilinmeyen dağıtım hata; para birimi kayan nokta içermez', () => {
    const empty = buildDistributionPlan({ distribution: 'land_share', amountMinor: 500 }, [apt(1), apt(2)]);
    assert.equal(empty.lines.length, 0);
    assert.equal(empty.total, 0n);
    assert.equal(empty.missing.length, 2);
    assert.throws(() => buildDistributionPlan({ distribution: 'rastgele', amountMinor: 1 }, [apt(1)]), RangeError);
    const plan = buildDistributionPlan({ distribution: 'equal', amountMinor: 1000001 }, Array.from({ length: 20 }, (_, i) => apt(i + 1)));
    assert.ok(plan.lines.every((l) => typeof l.amount === 'bigint'));
    assert.equal(plan.lines[0].amount, 50001n);
    assert.equal(sumBig(plan.lines.map((l) => l.amount)), 1000001n);
  });
});
