// Aidat ve Finans (Faz 4a): ortak sabitler, hata fabrikaları, doğrulayıcılar (gövde / sorgu), dönem-tarih aritmetiği ve yanıt eşleyicileri (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  METHODS,
  PATCH_KEYS,
  POSTED_PATCH_KEYS,
  addDays,
  addMonths,
  apartmentHasFinance,
  assertDefinitionShape,
  canonicalJson,
  chargeNaturalKey,
  chargeRequestFingerprint,
  closableMonths,
  computeOpenPeriod,
  duplicateCharge,
  latestClosedPeriod,
  minEntryDate,
  postRequestFingerprint,
  currentPeriod,
  definitionInactive,
  definitionLocked,
  definitionNotFound,
  entryAlreadyReversed,
  entryNotReversible,
  financeLockKey,
  idempotencyConflict,
  mapDefinitionRow,
  mapEntryRow,
  mapRunRow,
  mergeDefinitionPatch,
  moduleDisabled,
  normalizeFreeText,
  nothingToPost,
  parseAccountQuery,
  parseBalancesQuery,
  parseChargeInput,
  parseCorrectInput,
  parseDefinitionCreate,
  parseDefinitionPatch,
  parseDefinitionsQuery,
  parseIdempotencyKey,
  parseIsoDate,
  parsePaymentInput,
  parsePeriod,
  parsePostInput,
  parsePreviewInput,
  parseReverseInput,
  parseTarget,
  periodAlreadyPosted,
  periodClosed,
  periodLabel,
  periodNotClosable,
  periodNotReopenable,
  periodOfDate,
  previewIncomplete,
  previewStale,
  redactEntryForResident,
  redactFinanceForBoard,
  today,
} from '../src/modules/finance_common.js';

const NOW = new Date('2026-10-16T09:00:00.000Z'); // İstanbul 12:00, 16 Ekim 2026

const throwsCode = (fn, code, status = 400) => {
  try {
    fn();
  } catch (error) {
    assert.equal(error.code, code);
    assert.equal(error.statusCode, status);
    return;
  }
  assert.fail(`${code} hatası bekleniyordu`);
};

describe('finans: hata fabrikaları (sözleşme kodları ve durumları)', () => {
  it('durum kodları ve makine okunur kodlar', () => {
    const table = [
      [moduleDisabled(), 403, 'MODULE_DISABLED'],
      [previewStale(), 409, 'PREVIEW_STALE'],
      [previewIncomplete(), 409, 'PREVIEW_INCOMPLETE'],
      [periodAlreadyPosted(), 409, 'PERIOD_ALREADY_POSTED'],
      [periodClosed(), 409, 'PERIOD_CLOSED'],
      [periodNotClosable(), 409, 'PERIOD_NOT_CLOSABLE'],
      [periodNotReopenable(), 409, 'PERIOD_NOT_REOPENABLE'],
      [definitionInactive(), 409, 'DEFINITION_INACTIVE'],
      [definitionLocked(), 409, 'DEFINITION_LOCKED'],
      [definitionNotFound(), 404, 'DEFINITION_NOT_FOUND'],
      [entryAlreadyReversed(), 409, 'ENTRY_ALREADY_REVERSED'],
      [entryNotReversible(), 409, 'ENTRY_NOT_REVERSIBLE'],
      [apartmentHasFinance(), 409, 'APARTMENT_HAS_FINANCE'],
      [nothingToPost(), 409, 'NOTHING_TO_POST'],
      [idempotencyConflict(), 409, 'IDEMPOTENCY_CONFLICT'],
      [duplicateCharge(7, '2026-10-16T09:00:00.000Z'), 409, 'DUPLICATE_CHARGE'],
    ];
    for (const [error, status, code] of table) {
      assert.equal(error.statusCode, status, code);
      assert.equal(error.code, code);
      assert.equal(error.expose, true);
      assert.ok(error.message.length > 5);
    }
    assert.equal(apartmentHasFinance().message, 'Mali kaydı olan daire silinemez.');
    assert.deepEqual(moduleDisabled().extra, { module: 'finance' });
    assert.deepEqual(previewStale({ total_minor: 5 }).extra, { total_minor: 5 });
    assert.deepEqual(duplicateCharge(7, '2026-10-16T09:00:00.000Z').extra, { existing_run_id: 7, posted_at: '2026-10-16T09:00:00.000Z' });
    assert.equal(duplicateCharge(7, null).message, 'Aynı ek borç kısa süre önce kaydedilmiş görünüyor. Daire hesaplarını kontrol edin.');
  });

  it('kilit anahtarı finance_post:<site> (kilit sırası belgesi)', () => {
    assert.equal(financeLockKey(1000000001), 'finance_post:1000000001');
    assert.equal(financeLockKey('42'), 'finance_post:42');
  });
});

describe('finans: tarih ve dönem aritmetiği', () => {
  it('parseIsoDate: gerçek tarih, 2000-2100; aksi INVALID_BODY', () => {
    assert.equal(parseIsoDate('2026-10-16', 'Tarih'), '2026-10-16');
    assert.equal(parseIsoDate(' 2026-02-28 ', 'Tarih'), '2026-02-28');
    for (const bad of ['2026-02-30', '2026-13-01', '2026-1-1', '1999-12-31', '2101-01-01', '16.10.2026', '', null, undefined, 20261016, '2026-10-16T00:00:00Z']) {
      throwsCode(() => parseIsoDate(bad, 'Tarih'), 'INVALID_BODY');
    }
    assert.equal(parseIsoDate('2024-02-29', 'Tarih'), '2024-02-29');
    throwsCode(() => parseIsoDate('2025-02-29', 'Tarih'), 'INVALID_BODY');
  });

  it('parsePeriod: YYYY-MM ve YYYY-MM-01 kabul edilir; başka gün / aralık dışı reddedilir', () => {
    assert.equal(parsePeriod('2026-10'), '2026-10-01');
    assert.equal(parsePeriod('2026-10-01'), '2026-10-01');
    for (const bad of ['2026-10-02', '2026-13', '2026-00', '1999-12', '2101-01', 'abc', '', null, undefined, 202610]) {
      throwsCode(() => parsePeriod(bad), 'INVALID_BODY');
    }
  });

  it('addMonths: yıl sınırı ve negatif; addDays: ay sonu / artık yıl', () => {
    assert.equal(addMonths('2026-10-01', 1), '2026-11-01');
    assert.equal(addMonths('2026-12-01', 1), '2027-01-01');
    assert.equal(addMonths('2026-01-01', -1), '2025-12-01');
    assert.equal(addMonths('2026-10-01', 12), '2027-10-01');
    assert.equal(addMonths('2026-10-01', -22), '2024-12-01');
    assert.equal(addDays('2026-10-01', 4), '2026-10-05');
    assert.equal(addDays('2026-10-01', 27), '2026-10-28');
    assert.equal(addDays('2024-02-28', 1), '2024-02-29');
    assert.equal(addDays('2025-12-31', 1), '2026-01-01');
  });

  it('periodOfDate / periodLabel / today / currentPeriod (İstanbul takvimi)', () => {
    assert.equal(periodOfDate('2026-10-16'), '2026-10-01');
    assert.equal(periodLabel('2026-10-01'), '2026-10');
    assert.equal(periodLabel('2026-10'), '2026-10');
    assert.equal(today(NOW), '2026-10-16');
    assert.equal(currentPeriod(NOW), '2026-10-01');
    // UTC 31 Ekim 22:00 = İstanbul 1 Kasım 01:00 -> yeni ay
    assert.equal(currentPeriod(new Date('2026-10-31T22:00:00.000Z')), '2026-11-01');
    assert.equal(today(new Date('2026-12-31T21:30:00.000Z')), '2027-01-01');
  });

  it('computeOpenPeriod = closed_through sonrası ilk ay, ancak bu aydan küçükse bu ay (boşluklu kapanışlarda da MAX esas)', () => {
    assert.equal(computeOpenPeriod('2026-10-01', []), '2026-10-01');
    assert.equal(computeOpenPeriod('2026-10-01', ['2026-08-01', '2026-09-01']), '2026-10-01');
    assert.equal(computeOpenPeriod('2026-10-01', ['2026-09-01', '2026-10-01']), '2026-11-01');
    assert.equal(computeOpenPeriod('2026-12-01', new Set(['2026-12-01', '2027-01-01'])), '2027-02-01');
    assert.equal(computeOpenPeriod('2026-10-01', ['2026-03-01', '2026-10-01']), '2026-11-01', 'arada boşluk olsa da MAX esas');
    assert.equal(computeOpenPeriod('2026-10-01', ['2027-02-01']), '2027-03-01');
    assert.equal(latestClosedPeriod([]), null);
    assert.equal(latestClosedPeriod(new Set(['2026-03-01', '2026-09-01', '2026-05-01'])), '2026-09-01');
  });

  it('closableMonths: kapalı ay yoksa bu ay ve önceki 11 ay (yeni -> eski); varsa yalnız closed_through + 1 (bu ay ya da öncesiyse), aksi boş', () => {
    const none = closableMonths('2026-10-01', []);
    assert.equal(none.length, 12);
    assert.equal(none[0], '2026-10-01');
    assert.equal(none[11], '2025-11-01');
    assert.deepEqual(closableMonths('2026-10-01', ['2026-08-01']), ['2026-10-01', '2026-09-01']);
    assert.equal(closableMonths('2026-10-01', ['2025-01-01']).length, 12);
    assert.deepEqual(closableMonths('2026-10-01', ['2026-08-01', '2026-09-01']), ['2026-10-01']);
    assert.deepEqual(closableMonths('2026-10-01', ['2026-10-01']), [], 'bu ay kapalıysa sonraki ay gelecek: kapatılamaz');
    assert.deepEqual(closableMonths('2026-01-01', ['2025-12-01']), ['2026-01-01']);
  });

  it('minEntryDate: bugünden 5 yıl önce (İstanbul takvimi, 29 Şubat -> 28 Şubat); alt sınırın ötesi 400', () => {
    assert.equal(minEntryDate(NOW), '2021-10-16');
    assert.equal(minEntryDate(new Date('2028-02-29T09:00:00.000Z')), '2023-02-28');
    assert.equal(minEntryDate(new Date('2026-10-31T22:00:00.000Z')), '2021-11-01');
  });
});

describe('finans: serbest metin ve işlem anahtarı', () => {
  it('normalizeFreeText: kontrol / görünmez karakterler atılır, boşluklar tekilleşir; sınır code point ile', () => {
    const rlo = String.fromCodePoint(0x202e);
    const zws = String.fromCodePoint(0x200b);
    const ls = String.fromCodePoint(0x2028);
    assert.equal(normalizeFreeText(`  A${zws}li\t  Veli${rlo} \n x${ls}y `, { label: 'Ad', max: 80 }), 'Ali Veli x y');
    assert.equal(normalizeFreeText('   ', { label: 'Ad', max: 80 }), null);
    assert.equal(normalizeFreeText(undefined, { label: 'Ad', max: 80 }), null);
    assert.equal(normalizeFreeText('😀'.repeat(80), { label: 'Ad', max: 80 }).length, 160); // 80 code point
    throwsCode(() => normalizeFreeText('😀'.repeat(81), { label: 'Ad', max: 80 }), 'INVALID_BODY');
    throwsCode(() => normalizeFreeText(5, { label: 'Ad', max: 80 }), 'INVALID_BODY');
    throwsCode(() => normalizeFreeText('', { label: 'Ad', max: 80, required: true }), 'INVALID_BODY');
    throwsCode(() => normalizeFreeText(null, { label: 'Ad', max: 80, required: true }), 'INVALID_BODY');
  });

  it('parseIdempotencyKey: 1-64 görünür ASCII; yoksa null (zorunluysa 400)', () => {
    assert.equal(parseIdempotencyKey('abc-123_X:9.z'), 'abc-123_X:9.z');
    assert.equal(parseIdempotencyKey(undefined), null);
    assert.equal(parseIdempotencyKey(null), null);
    assert.equal(parseIdempotencyKey(''), null);
    assert.equal(parseIdempotencyKey('k'.repeat(64)), 'k'.repeat(64));
    for (const bad of ['k'.repeat(65), 'a b', 'ü', 'a\nb', 5, {}]) {
      throwsCode(() => parseIdempotencyKey(bad), 'INVALID_BODY');
    }
    throwsCode(() => parseIdempotencyKey(undefined, { required: true }), 'INVALID_BODY');
    throwsCode(() => parseIdempotencyKey('', { required: true }), 'INVALID_BODY');
  });
});

const baseDef = () => ({ name: ' Aidat ', kind: 'recurring', distribution: 'fixed', amount_minor: 150000, due_day: 5, start_period: '2026-01', target: { type: 'site' } });

describe('finans: tanım gövdeleri', () => {
  it('geçerli tanım: normalize edilir (ad kırpılır, dönem ayın ilk günü, hedef sıralı)', () => {
    const parsed = parseDefinitionCreate({ ...baseDef(), target: { type: 'apartments', apartment_ids: ['9', 3, 3, 7] } });
    assert.deepEqual(parsed, {
      name: 'Aidat',
      distribution: 'fixed',
      areaBasis: null,
      amountMinor: 150000,
      categoryAmounts: null,
      kind: 'recurring',
      dueDay: 5,
      startPeriod: '2026-01-01',
      endPeriod: null,
      target: { type: 'apartments', blockIds: [], apartmentIds: [3, 7, 9] },
      // İP-1A: "kim öder" verilmedi -> aylık aidat dairede oturanın hesabına
      chargeParty: 'occupant',
    });
  });

  it('İP-1A: charge_party (occupant | owner); verilmezse aylık -> occupant, tek seferlik -> owner; geçersiz 400', () => {
    assert.equal(parseDefinitionCreate({ ...baseDef(), charge_party: 'owner' }).chargeParty, 'owner');
    assert.equal(parseDefinitionCreate({ ...baseDef(), kind: 'one_time', due_day: undefined }).chargeParty, 'owner');
    assert.equal(parseDefinitionCreate({ ...baseDef(), kind: 'one_time', due_day: undefined, charge_party: 'occupant' }).chargeParty, 'occupant');
    for (const bad of ['tenant', 'both', 5, '']) {
      throwsCode(() => parseDefinitionCreate({ ...baseDef(), charge_party: bad }), 'INVALID_BODY');
    }
  });

  it('amount takma adı (kuruş) kabul edilir; ikisi farklıysa 400; kategori ve m² varyantları', () => {
    assert.equal(parseDefinitionCreate({ ...baseDef(), amount_minor: undefined, amount: 777 }).amountMinor, 777);
    assert.equal(parseDefinitionCreate({ ...baseDef(), amount: 150000 }).amountMinor, 150000);
    throwsCode(() => parseDefinitionCreate({ ...baseDef(), amount: 1 }), 'INVALID_BODY');
    const category = parseDefinitionCreate({ ...baseDef(), distribution: 'category', amount_minor: undefined, category_amounts: { ' 2+1 ': 100, 'Dükkan': 250 } });
    assert.deepEqual(category.categoryAmounts, { '2+1': 100, 'Dükkan': 250 });
    assert.equal(category.amountMinor, null);
    const area = parseDefinitionCreate({ ...baseDef(), distribution: 'area', area_basis: 'net' });
    assert.equal(area.areaBasis, 'net');
    const oneTime = parseDefinitionCreate({ ...baseDef(), kind: 'one_time', due_day: undefined });
    assert.equal(oneTime.dueDay, null);
    assert.equal(parseDefinitionCreate({ ...baseDef(), kind: 'one_time', due_day: 9 }).dueDay, null, 'tek seferlikte vade günü yok sayılır');
  });

  it('geçersiz tanım gövdeleri 400 INVALID_BODY / INVALID_TARGET', () => {
    const cases = [
      [{ name: undefined }, 'INVALID_BODY'], [{ name: '  ' }, 'INVALID_BODY'], [{ name: 'x'.repeat(81) }, 'INVALID_BODY'], [{ kind: 'x' }, 'INVALID_BODY'], [{ distribution: 'x' }, 'INVALID_BODY'],
      [{ amount_minor: 1500.5 }, 'INVALID_BODY'], [{ amount_minor: '150000' }, 'INVALID_BODY'], [{ amount_minor: 0 }, 'INVALID_BODY'], [{ amount_minor: -1 }, 'INVALID_BODY'], [{ amount_minor: 1e12 + 1 }, 'INVALID_BODY'],
      [{ amount_minor: undefined }, 'INVALID_BODY'], [{ due_day: undefined }, 'INVALID_BODY'], [{ due_day: 29 }, 'INVALID_BODY'], [{ due_day: 0 }, 'INVALID_BODY'], [{ due_day: '5' }, 'INVALID_BODY'], [{ due_day: 2.5 }, 'INVALID_BODY'],
      [{ start_period: undefined }, 'INVALID_BODY'], [{ start_period: '2026-13' }, 'INVALID_BODY'], [{ end_period: '2025-12' }, 'INVALID_BODY'],
      [{ distribution: 'area' }, 'INVALID_BODY'], [{ distribution: 'area', area_basis: 'x' }, 'INVALID_BODY'], [{ area_basis: 'gross' }, 'INVALID_BODY'],
      [{ category_amounts: { a: 1 } }, 'INVALID_BODY'], [{ distribution: 'category', category_amounts: { a: 1 } }, 'INVALID_BODY'], [{ distribution: 'category', amount_minor: undefined }, 'INVALID_BODY'],
      [{ distribution: 'category', amount_minor: undefined, category_amounts: {} }, 'INVALID_BODY'], [{ distribution: 'category', amount_minor: undefined, category_amounts: { a: 1.5 } }, 'INVALID_BODY'],
      [{ distribution: 'category', amount_minor: undefined, category_amounts: { Dukkan: 1, DUKKAN: 2 } }, 'INVALID_BODY'], [{ distribution: 'category', amount_minor: undefined, category_amounts: { ['x'.repeat(41)]: 1 } }, 'INVALID_BODY'],
      [{ target: undefined }, 'INVALID_BODY'], [{ target: { type: 'kat' } }, 'INVALID_BODY'], [{ target: [] }, 'INVALID_BODY'],
      [{ target: { type: 'blocks' } }, 'INVALID_TARGET'], [{ target: { type: 'blocks', block_ids: [] } }, 'INVALID_TARGET'], [{ target: { type: 'apartments', apartment_ids: ['abc'] } }, 'INVALID_TARGET'],
      [{ target: { type: 'apartments', apartment_ids: Array.from({ length: 5001 }, (_, i) => i + 1) } }, 'INVALID_TARGET'],
    ];
    for (const [override, code] of cases) {
      throwsCode(() => parseDefinitionCreate({ ...baseDef(), ...override }), code);
    }
    throwsCode(() => parseDefinitionCreate(null), 'INVALID_BODY');
    throwsCode(() => parseDefinitionCreate([1, 2]), 'INVALID_BODY');
  });

  it('parseTarget: site / blocks / apartments; yinelenenler tekilleşir', () => {
    assert.deepEqual(parseTarget({ type: 'site', block_ids: [1] }), { type: 'site', blockIds: [], apartmentIds: [] });
    assert.deepEqual(parseTarget({ type: 'blocks', block_ids: [5, '2', 5] }), { type: 'blocks', blockIds: [2, 5], apartmentIds: [] });
    throwsCode(() => parseTarget(undefined), 'INVALID_BODY');
  });

  it('PATCH: yalnız gönderilen alanlar; amount -> amount_minor; boş gövde 400; mergeDefinitionPatch bağımlı alanları sıfırlar', () => {
    throwsCode(() => parseDefinitionPatch({}), 'INVALID_BODY');
    throwsCode(() => parseDefinitionPatch({ kind: 'one_time' }), 'INVALID_BODY');
    const patch = parseDefinitionPatch({ amount: 5000, due_day: 3, is_active: false, end_period: null });
    assert.deepEqual(patch.keys.sort(), ['amount_minor', 'due_day', 'end_period', 'is_active']);
    assert.equal(patch.amountMinor, 5000);
    assert.equal(patch.endPeriod, null);
    assert.equal(patch.isActive, false);
    throwsCode(() => parseDefinitionPatch({ is_active: 'evet' }), 'INVALID_BODY');
    throwsCode(() => parseDefinitionPatch({ amount_minor: 1.5 }), 'INVALID_BODY');

    const existing = { ...parseDefinitionCreate(baseDef()), isActive: true };
    const toEqual = mergeDefinitionPatch(existing, parseDefinitionPatch({ distribution: 'equal', amount_minor: 900 }));
    assert.equal(toEqual.distribution, 'equal');
    assert.equal(toEqual.amountMinor, 900);
    assert.doesNotThrow(() => assertDefinitionShape(toEqual));
    const toCategoryNoAmounts = mergeDefinitionPatch(existing, parseDefinitionPatch({ distribution: 'category' }));
    assert.equal(toCategoryNoAmounts.amountMinor, null);
    assert.throws(() => assertDefinitionShape(toCategoryNoAmounts), (error) => error.code === 'INVALID_BODY');
    const toArea = mergeDefinitionPatch(existing, parseDefinitionPatch({ distribution: 'area' }));
    assert.throws(() => assertDefinitionShape(toArea), (error) => error.code === 'INVALID_BODY');
    const cleared = mergeDefinitionPatch({ ...existing, distribution: 'area', areaBasis: 'gross' }, parseDefinitionPatch({ distribution: 'equal' }));
    assert.equal(cleared.areaBasis, null, 'm²den çıkınca alan esası sıfırlanır');
    const badEnd = mergeDefinitionPatch(existing, parseDefinitionPatch({ end_period: '2025-01' }));
    assert.throws(() => assertDefinitionShape(badEnd), (error) => error.code === 'INVALID_BODY');
  });

  it('İP-1A: PATCH charge_party borçlandırılmış tanımda da değişebilir (yalnız SONRAKİ borçlandırmaları etkiler); geçersiz 400', () => {
    const patch = parseDefinitionPatch({ charge_party: 'owner' });
    assert.deepEqual(patch.keys, ['charge_party']);
    assert.equal(patch.chargeParty, 'owner');
    assert.ok(POSTED_PATCH_KEYS.includes('charge_party'));
    assert.ok(PATCH_KEYS.includes('charge_party'));
    const merged = mergeDefinitionPatch({ ...parseDefinitionCreate(baseDef()), isActive: true }, patch);
    assert.equal(merged.chargeParty, 'owner');
    throwsCode(() => parseDefinitionPatch({ charge_party: 'tenant' }), 'INVALID_BODY');
    throwsCode(() => parseDefinitionPatch({ charge_party: null }), 'INVALID_BODY');
  });
});

describe('finans: borçlandırma / ek borç / tahsilat gövdeleri', () => {
  it('önizleme: aylıkta period zorunlu, tek seferlikte due_date isteğe bağlı; 5 yıldan eski dönem / vade (yazım hatası: 2002) 400', () => {
    assert.deepEqual(parsePreviewInput({ period: '2026-10' }, 'recurring', NOW), { period: '2026-10-01', dueDate: null });
    throwsCode(() => parsePreviewInput({}, 'recurring', NOW), 'INVALID_BODY');
    throwsCode(() => parsePreviewInput({ period: '2026-10-15' }, 'recurring', NOW), 'INVALID_BODY');
    throwsCode(() => parsePreviewInput({ period: '2002-10' }, 'recurring', NOW), 'INVALID_BODY');
    assert.deepEqual(parsePreviewInput({ period: '2021-10' }, 'recurring', NOW), { period: '2021-10-01', dueDate: null });
    throwsCode(() => parsePreviewInput({ period: '2021-09' }, 'recurring', NOW), 'INVALID_BODY');
    assert.deepEqual(parsePreviewInput({ due_date: '2026-11-05' }, 'one_time', NOW), { period: null, dueDate: '2026-11-05' });
    assert.deepEqual(parsePreviewInput({}, 'one_time', NOW), { period: null, dueDate: null });
    throwsCode(() => parsePreviewInput({ due_date: 'yarın' }, 'one_time', NOW), 'INVALID_BODY');
    throwsCode(() => parsePreviewInput({ due_date: '2002-11-05' }, 'one_time', NOW), 'INVALID_BODY');
  });

  it('post: beklenen toplam / daire sayısı / önizleme özeti (expected_hash) ZORUNLU; skip_missing boolean; anahtar isteğe bağlı', () => {
    const hash = 'a'.repeat(64);
    const ok = parsePostInput({ period: '2026-10', expected_total_minor: 3000000, expected_apartment_count: 20, expected_hash: hash, skip_missing: true, idempotency_key: 'k-1' }, 'recurring', NOW);
    assert.deepEqual(ok, { period: '2026-10-01', dueDate: null, expectedTotal: 3000000, expectedCount: 20, expectedHash: hash, skipMissing: true, idempotencyKey: 'k-1' });
    assert.equal(parsePostInput({ period: '2026-10', expected_total_minor: 0, expected_apartment_count: 0, expected_hash: hash }, 'recurring', NOW).skipMissing, false);
    const base = { period: '2026-10', expected_total_minor: 100, expected_apartment_count: 1, expected_hash: hash };
    for (const bad of [
      { ...base, expected_hash: undefined }, { ...base, expected_hash: 'abc' }, { ...base, expected_hash: 'A'.repeat(64) }, { ...base, expected_hash: 5 }, { ...base, expected_hash: 'g'.repeat(64) },
      { ...base, expected_total_minor: undefined }, { ...base, expected_total_minor: 1.5 }, { ...base, expected_total_minor: '100' },
      { ...base, expected_apartment_count: undefined }, { ...base, expected_apartment_count: 2.5 }, { ...base, expected_apartment_count: -1 },
      { ...base, skip_missing: 'evet' }, { ...base, idempotency_key: 'a b' }, { ...base, expected_total_minor: 1e14 + 1 }, { ...base, period: undefined }, { ...base, period: '2002-10' },
    ]) {
      throwsCode(() => parsePostInput(bad, 'recurring', NOW), 'INVALID_BODY');
    }
  });

  it('ek borç: önizlemede beklenen değerler / anahtar isteğe bağlı; onayda beklenen toplam, sayı, expected_hash VE idempotency_key ZORUNLU; allow_duplicate boolean', () => {
    const hash = 'a'.repeat(64);
    const body = { name: 'Asansör', distribution: 'equal', amount_minor: 1000001, target: { type: 'site' }, due_date: '2026-11-15' };
    const preview = parseChargeInput(body, { requireExpected: false, now: NOW });
    assert.equal(preview.expectedTotal, null);
    assert.equal(preview.expectedHash, null);
    assert.equal(preview.idempotencyKey, null);
    assert.equal(preview.allowDuplicate, false);
    assert.equal(preview.dueDate, '2026-11-15');
    const confirmBody = { ...body, expected_total_minor: 1000001, expected_apartment_count: 20, expected_hash: hash, idempotency_key: 'ek-1' };
    throwsCode(() => parseChargeInput(body, { requireExpected: true, now: NOW }), 'INVALID_BODY');
    throwsCode(() => parseChargeInput({ ...confirmBody, idempotency_key: undefined }, { requireExpected: true, now: NOW }), 'INVALID_BODY');
    throwsCode(() => parseChargeInput({ ...confirmBody, expected_hash: undefined }, { requireExpected: true, now: NOW }), 'INVALID_BODY');
    throwsCode(() => parseChargeInput({ ...confirmBody, expected_hash: 'xyz' }, { requireExpected: true, now: NOW }), 'INVALID_BODY');
    const confirmed = parseChargeInput({ ...confirmBody, allow_duplicate: true, skip_missing: true }, { requireExpected: true, now: NOW });
    assert.equal(confirmed.expectedTotal, 1000001);
    assert.equal(confirmed.expectedCount, 20);
    assert.equal(confirmed.expectedHash, hash);
    assert.equal(confirmed.idempotencyKey, 'ek-1');
    assert.equal(confirmed.allowDuplicate, true);
    assert.equal(confirmed.skipMissing, true);
    throwsCode(() => parseChargeInput({ ...confirmBody, allow_duplicate: 'evet' }, { requireExpected: true, now: NOW }), 'INVALID_BODY');
    const category = parseChargeInput({ name: 'K', distribution: 'category', category_amounts: { a: 5 }, target: { type: 'site' } }, { requireExpected: false, now: NOW });
    assert.deepEqual(category.categoryAmounts, { a: 5 });
    throwsCode(() => parseChargeInput({ ...body, amount_minor: 100.5 }, { requireExpected: false, now: NOW }), 'INVALID_BODY');
    throwsCode(() => parseChargeInput({ ...body, name: undefined }, { requireExpected: false, now: NOW }), 'INVALID_BODY');
    throwsCode(() => parseChargeInput({ ...body, due_date: '2026-02-30' }, { requireExpected: false, now: NOW }), 'INVALID_BODY');
    throwsCode(() => parseChargeInput({ ...body, due_date: '2002-11-15' }, { requireExpected: false, now: NOW }), 'INVALID_BODY');
    // İP-1A: ek borç varsayılanı ev sahibi hesabı; "dairede oturan" seçilebilir
    assert.equal(preview.chargeParty, 'owner');
    assert.equal(parseChargeInput({ ...body, charge_party: 'occupant' }, { requireExpected: false, now: NOW }).chargeParty, 'occupant');
    throwsCode(() => parseChargeInput({ ...body, charge_party: 'tenant' }, { requireExpected: false, now: NOW }), 'INVALID_BODY');
  });

  it('parmak izleri: kararlı (anahtar sırasından bağımsız); gövde değişince değişir; doğal özet vade ve kategori harf farkından etkilenmez/etkilenir', () => {
    assert.equal(canonicalJson({ b: 1, a: [2, { d: 4, c: 3 }], e: undefined }), '{"a":[2,{"c":3,"d":4}],"b":1,"e":null}');
    const base = { name: 'Asansör', amountMinor: 1000, distribution: 'equal', areaBasis: null, categoryAmounts: null, target: { type: 'blocks', blockIds: [2, 1], apartmentIds: [] }, dueDate: null, skipMissing: false };
    const a = chargeRequestFingerprint(base);
    assert.match(a, /^[0-9a-f]{64}$/);
    assert.equal(chargeRequestFingerprint({ ...base }), a);
    for (const change of [{ name: 'Asansör 2' }, { amountMinor: 1001 }, { distribution: 'fixed' }, { target: { type: 'blocks', blockIds: [3], apartmentIds: [] } }, { dueDate: '2026-11-01' }, { skipMissing: true }, { chargeParty: 'occupant' }]) {
      assert.notEqual(chargeRequestFingerprint({ ...base, ...change }), a, JSON.stringify(change));
    }
    // İP-1A: varsayılan (ev sahibi) "kim öder" parmak izini DEĞİŞTİRMEZ (dağıtımdan önce başlayan tekrarlar 409 almasın)
    assert.equal(chargeRequestFingerprint({ ...base, chargeParty: 'owner' }), a);
    const natural = chargeNaturalKey(base, '2026-11-01');
    assert.match(natural, /^[0-9a-f]{64}$/);
    assert.equal(chargeNaturalKey({ ...base, skipMissing: true }, '2026-11-01'), natural, 'skip_missing doğal özete girmez');
    assert.equal(chargeNaturalKey({ ...base, name: '  ASANSÖR ' }, '2026-11-01'), natural, 'ad Türkçe harf / büyük-küçük harf duyarsız ve boşluk tekil');
    assert.notEqual(chargeNaturalKey(base, '2026-11-02'), natural, 'vade değişince farklı');
    assert.notEqual(chargeNaturalKey({ ...base, amountMinor: 1001 }, '2026-11-01'), natural);
    const post = postRequestFingerprint({ definitionId: 5, period: '2026-10-01', dueDate: null, skipMissing: false });
    assert.notEqual(postRequestFingerprint({ definitionId: 6, period: '2026-10-01', dueDate: null, skipMissing: false }), post);
    assert.notEqual(postRequestFingerprint({ definitionId: 5, period: '2026-11-01', dueDate: null, skipMissing: false }), post);
    assert.notEqual(postRequestFingerprint({ definitionId: 5, period: '2026-10-01', dueDate: null, skipMissing: true }), post);
  });

  it('tahsilat: kuruş tamsayı, yöntem, GELECEK TARİH 400, anahtar zorunlu; açıklama temizlenir', () => {
    const body = { apartment_id: 9, amount_minor: 50000, entry_date: '2026-10-16', method: 'cash', description: '  Nakit  tahsilat ', idempotency_key: 'k-1' };
    assert.deepEqual(parsePaymentInput(body, NOW), { apartmentId: 9, amountMinor: 50000, entryDate: '2026-10-16', method: 'cash', description: 'Nakit tahsilat', idempotencyKey: 'k-1', accountId: null, accountParty: null });
    assert.equal(parsePaymentInput({ ...body, apartment_id: '9', description: undefined }, NOW).description, null);
    // İki hesap (İP-1A): isteğe bağlı daire hesabı (owner | tenant); yoksa null (sunucu varsayılanı)
    assert.equal(parsePaymentInput({ ...body, account_party: 'tenant' }, NOW).accountParty, 'tenant');
    assert.equal(parsePaymentInput({ ...body, account_party: 'owner' }, NOW).accountParty, 'owner');
    throwsCode(() => parsePaymentInput({ ...body, account_party: 'both' }, NOW), 'INVALID_BODY');
    throwsCode(() => parsePaymentInput({ ...body, account_party: 1 }, NOW), 'INVALID_BODY');
    // Faz 4b: isteğe bağlı kasa / banka hesabı kimliği
    assert.equal(parsePaymentInput({ ...body, account_id: 4 }, NOW).accountId, 4);
    throwsCode(() => parsePaymentInput({ ...body, account_id: 'abc' }, NOW), 'INVALID_BODY');
    throwsCode(() => parsePaymentInput({ ...body, account_id: -2 }, NOW), 'INVALID_BODY');
    for (const method of METHODS) assert.equal(parsePaymentInput({ ...body, method }, NOW).method, method);
    for (const bad of [
      { entry_date: '2026-10-17' }, { entry_date: '2027-01-01' }, { entry_date: '2026-02-30' }, { entry_date: undefined }, { amount_minor: 0 }, { amount_minor: -5 }, { amount_minor: 50.5 }, { amount_minor: '500' },
      { amount_minor: 1e12 + 1 }, { method: 'kart' }, { method: undefined }, { idempotency_key: undefined }, { description: 'x'.repeat(201) }, { apartment_id: undefined }, { apartment_id: 'abc' }, { apartment_id: 0 },
    ]) {
      throwsCode(() => parsePaymentInput({ ...body, ...bad }, NOW), 'INVALID_BODY');
    }
    // 5 yıldan eski tarih (yazım hatası: 2002) reddedilir; tam sınır günü serbest
    throwsCode(() => parsePaymentInput({ ...body, entry_date: '2002-10-16' }, NOW), 'INVALID_BODY');
    throwsCode(() => parsePaymentInput({ ...body, entry_date: '2021-10-15' }, NOW), 'INVALID_BODY');
    assert.doesNotThrow(() => parsePaymentInput({ ...body, entry_date: '2021-10-16' }, NOW));
    // bugünün tarihi serbest; İstanbul'da yarın (UTC'de hâlâ bugün) kabul edilmez
    assert.doesNotThrow(() => parsePaymentInput({ ...body, entry_date: '2026-10-16' }, NOW));
    throwsCode(() => parsePaymentInput({ ...body, entry_date: '2026-11-01' }, new Date('2026-10-31T20:00:00.000Z')), 'INVALID_BODY');
    assert.doesNotThrow(() => parsePaymentInput({ ...body, entry_date: '2026-11-01' }, new Date('2026-10-31T21:30:00.000Z')));
  });

  it('düzeltme ve ters kayıt gövdeleri', () => {
    const correct = parseCorrectInput({ amount_minor: 100, entry_date: '2026-10-16', method: 'transfer', idempotency_key: 'k' }, NOW);
    assert.equal(correct.amountMinor, 100);
    assert.equal(correct.method, 'transfer');
    assert.equal('apartmentId' in correct, false);
    throwsCode(() => parseCorrectInput({ amount_minor: 100, entry_date: '2026-10-16', method: 'cash' }, NOW), 'INVALID_BODY');
    assert.deepEqual(parseReverseInput({}), { reason: null, idempotencyKey: null });
    assert.deepEqual(parseReverseInput({ reason: '  Hatalı  giriş ', idempotency_key: 'r1' }), { reason: 'Hatalı giriş', idempotencyKey: 'r1' });
    throwsCode(() => parseReverseInput({ reason: 'x'.repeat(201) }), 'INVALID_BODY');
    throwsCode(() => parseReverseInput({ reason: 5 }), 'INVALID_BODY');
  });
});

describe('finans: sorgu parametreleri', () => {
  it('bakiyeler: durum, arama, limit (1-200, üstü 200\'e iner), offset', () => {
    assert.deepEqual(parseBalancesQuery({}), { status: 'all', q: null, limit: 50, offset: 0 });
    assert.deepEqual(parseBalancesQuery({ status: 'debtor', q: '  Ayşe  ', limit: '10', offset: '20' }), { status: 'debtor', q: 'Ayşe', limit: 10, offset: 20 });
    assert.equal(parseBalancesQuery({ limit: '100000' }).limit, 200);
    for (const bad of [{ status: 'x' }, { limit: '0' }, { limit: 'abc' }, { limit: '1.5' }, { offset: '-1' }, { offset: 'x' }, { limit: '-3' }]) {
      throwsCode(() => parseBalancesQuery(bad), 'INVALID_QUERY');
    }
    assert.equal(parseBalancesQuery({ q: 'x'.repeat(300) }).q.length, 100);
    assert.equal(parseBalancesQuery({ q: '   ' }).q, null);
  });

  it('ekstre: from/to/before_id/limit; ters aralık ve geçersiz değerler 400 INVALID_QUERY', () => {
    assert.deepEqual(parseAccountQuery({}), { from: null, to: null, beforeId: null, limit: 50 });
    assert.deepEqual(parseAccountQuery({ from: '2026-01-01', to: '2026-01-31', before_id: '55', limit: '5' }), { from: '2026-01-01', to: '2026-01-31', beforeId: 55, limit: 5 });
    for (const bad of [{ from: 'abc' }, { to: '2026-13-01' }, { before_id: 'x' }, { before_id: '0' }, { limit: '0' }, { from: '2026-02-01', to: '2026-01-01' }]) {
      throwsCode(() => parseAccountQuery(bad), 'INVALID_QUERY');
    }
  });

  it('tanım listesi süzgeçleri', () => {
    assert.deepEqual(parseDefinitionsQuery({}), { kind: null, active: null, limit: 500, offset: 0 });
    assert.deepEqual(parseDefinitionsQuery({ kind: 'one_time', active: 'false' }), { kind: 'one_time', active: false, limit: 500, offset: 0 });
    assert.deepEqual(parseDefinitionsQuery({ active: 'true', limit: '20', offset: '40' }), { kind: null, active: true, limit: 20, offset: 40 });
    assert.equal(parseDefinitionsQuery({ limit: '100000' }).limit, 500);
    for (const bad of [{ kind: 'x' }, { active: 'maybe' }, { active: '1' }, { limit: '0' }, { limit: 'abc' }, { offset: '-1' }]) {
      throwsCode(() => parseDefinitionsQuery(bad), 'INVALID_QUERY');
    }
  });
});

describe('finans: yanıt eşleyicileri ve gizlilik', () => {
  it('mapDefinitionRow: kuruş tamsayı, dönemler YYYY-MM, düz + iç içe hedef, kategori tutarları sayı', () => {
    const mapped = mapDefinitionRow({
      id: '7', name: 'Aidat', kind: 'recurring', distribution: 'category', area_basis: null, amount_minor: null, category_amounts: { '2+1': 100000, 'Dükkan': 250000 }, due_day: 5,
      start_period: '2026-01-01', end_period: null, target_type: 'blocks', target_block_ids: ['3', '4'], target_apartment_ids: [], is_active: true, has_runs: true, last_posted_period: '2026-09-01',
      created_by_name: 'Ali', created_at: new Date('2026-10-01T09:00:00Z'), updated_at: new Date('2026-10-02T09:00:00Z'),
    });
    assert.equal(mapped.id, 7);
    assert.equal(mapped.amount_minor, null);
    assert.deepEqual(mapped.category_amounts, { '2+1': 100000, 'Dükkan': 250000 });
    assert.equal(mapped.start_period, '2026-01');
    assert.equal(mapped.end_period, null);
    assert.equal(mapped.last_posted_period, '2026-09');
    assert.deepEqual(mapped.target_block_ids, [3, 4]);
    assert.deepEqual(mapped.target, { type: 'blocks', block_ids: [3, 4], apartment_ids: [], blocks: [], apartments: [] });
    assert.equal(mapped.has_runs, true);
    assert.equal(mapped.currency, 'TRY');
    assert.equal(mapped.created_at, '2026-10-01T09:00:00.000Z');
    const fixed = mapDefinitionRow({ id: 1, name: 'x', kind: 'one_time', distribution: 'fixed', amount_minor: '150000', start_period: '2026-10-01', target_type: 'site', is_active: false, created_at: null, updated_at: null });
    assert.equal(fixed.amount_minor, 150000);
    assert.equal(fixed.category_amounts, null);
    assert.equal(fixed.has_runs, false);
    assert.equal(fixed.created_at, null);
    // İP-1A: 052 öncesi tanım (charge_party yok) türüne göre: aylık -> occupant, tek seferlik -> owner; dolu değer aynen
    assert.equal(mapped.charge_party, 'occupant');
    assert.equal(fixed.charge_party, 'owner');
    assert.equal(mapDefinitionRow({ id: 1, name: 'x', kind: 'recurring', distribution: 'fixed', amount_minor: '1', start_period: '2026-10-01', target_type: 'site', charge_party: 'owner' }).charge_party, 'owner');
  });

  it('mapEntryRow / mapRunRow: tamsayı kuruş, dönem YYYY-MM, kimlikler sayı, boşlar null', () => {
    const entry = mapEntryRow({
      id: '12', kind: 'payment', amount_minor: '-50000', period: '2026-10-01', entry_date: '2026-10-16', due_date: null, description: 'Nakit', method: 'cash', payer_party: 'both', definition_name: null,
      reverses_entry_id: null, reversed_by_entry_id: '13', reversal_reason: null, created_by_name: 'Ali', created_at: new Date('2026-10-16T09:00:00Z'),
    });
    assert.deepEqual(entry, {
      id: 12, kind: 'payment', amount_minor: -50000, period: '2026-10', entry_date: '2026-10-16', due_date: null, description: 'Nakit', method: 'cash', payer_party: 'both', definition_name: null,
      reverses_entry_id: null, reversed_by_entry_id: 13, reversal_reason: null, created_by_name: 'Ali', created_at: '2026-10-16T09:00:00.000Z',
      late_fee_run_id: null, receipt: null,
      // İki hesap (İP-1A): 052 öncesi satır (account_party yok) payer_party'den türetilir: both -> ev sahibi; kaynak izi yok
      account_party: 'owner', source_kind: null, source_id: null,
    });
    assert.equal(mapEntryRow({ id: 1, kind: 'charge', amount_minor: '5', period: '2026-10-01', payer_party: 'tenant' }).account_party, 'tenant');
    assert.equal(mapEntryRow({ id: 1, kind: 'charge', amount_minor: '5', period: '2026-10-01', payer_party: 'owner', account_party: 'tenant' }).account_party, 'tenant');
    const sourced = mapEntryRow({ id: 1, kind: 'payment', amount_minor: '-5', period: '2026-10-01', payer_party: 'both', account_party: 'owner', source_kind: 'bank_line', source_id: '44' });
    assert.deepEqual([sourced.source_kind, sourced.source_id], ['bank_line', 44]);
    // Faz 4b: makbuz özeti (eklemeli alanlar)
    const withReceipt = mapEntryRow({ id: '12', kind: 'payment', amount_minor: '-50000', period: '2026-10-01', entry_date: '2026-10-16', payer_party: 'both', late_fee_run_id: '5', receipt_id: '8', receipt_year: 2026, receipt_no: 12, receipt_cancel_year: 2026, receipt_cancel_no: 13 });
    assert.equal(withReceipt.late_fee_run_id, 5);
    assert.deepEqual(withReceipt.receipt, { id: 8, number: 'MK-2026-000012', status: 'cancelled', cancelled_by_number: 'MK-2026-000013' });
    const run = mapRunRow({ id: '3', definition_id: '7', period: '2026-10-01', total_minor: '3000000', apartment_count: '20', posted_at: new Date('2026-10-16T09:00:00Z') });
    assert.deepEqual(run, { id: 3, definition_id: 7, period: '2026-10', total_minor: 3000000, apartment_count: 20, posted_at: '2026-10-16T09:00:00.000Z' });
  });

  it('redactEntryForResident: açıklama, ters kayıt nedeni ve oluşturan adı çıkarılır; kuruş ve tür kalır. Girdi değişmez', () => {
    const entry = { id: 1, kind: 'reversal', amount_minor: 100, description: 'GİZLİ', reversal_reason: 'GİZLİ NEDEN', created_by_name: 'Yönetici', method: null };
    const redacted = redactEntryForResident(entry);
    // İP-1A: kaynak kimliği (dekont / banka satırı iç kimliği) sakine verilmez
    assert.deepEqual(redacted, { id: 1, kind: 'reversal', amount_minor: 100, description: null, reversal_reason: null, created_by_name: null, method: null, source_id: null });
    assert.equal(entry.description, 'GİZLİ');
  });

  it('redactFinanceForBoard: created_by_name / closed_by_name / posted_by_name her derinlikte null; diğer alanlar aynen', () => {
    const body = { items: [{ id: 1, created_by_name: 'Ali', nested: { closed_by_name: 'Veli', posted_by_name: 'Can' } }], created_by_name: 'Ayşe', total: 3 };
    const redacted = redactFinanceForBoard(body);
    assert.deepEqual(redacted, { items: [{ id: 1, created_by_name: null, nested: { closed_by_name: null, posted_by_name: null } }], created_by_name: null, total: 3 });
    assert.equal(body.items[0].created_by_name, 'Ali');
  });

  it('apartmentLabel yeniden dışa aktarılır (blok - daire)', async () => {
    const module = await import('../src/modules/finance_common.js');
    assert.equal(module.apartmentLabel('A Blok', 'Daire 3'), 'A Blok - Daire 3');
  });
});
