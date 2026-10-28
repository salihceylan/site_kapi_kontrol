// K5 (P1-5): dağıtım tabanı YÖNETİMİN açık seçimidir, varsayılan eşit; kişi sayısı tabanı. DB'siz (KATI sahte DB).
//  - Tanım / ek borç girdisi: 'person_count' geçerli, 'area' (m²) hâlâ reddedilir; taban verilmezse sunucu SEÇMEZ (400).
//  - Önizleme: kişi sayısı alt sorgusu YALNIZ person_count seçildiğinde okunur; satır `basis_value`; kişi kaydı olmayan daire eksik veri (eşit paya düşmez).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { previewCharge } from '../src/modules/finance_service.js';
import { DISTRIBUTIONS, parseChargeInput, parseDefinitionCreate, parseDefinitionPatch } from '../src/modules/finance_common.js';
import { PERSON_COUNT_SQL } from '../src/modules/finance_distribution_basis.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const NOW = new Date('2026-10-21T09:00:00Z');
const SITE = 1000000001;

function fakeDb(apartments) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      const sql = norm(text);
      calls.push({ sql, params });
      if (/FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.is_active = TRUE/.test(sql)) return ok(apartments);
      if (/FROM fee_runs WHERE site_code = \$1 AND natural_key = \$2/.test(sql)) return ok();
      if (/FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE/.test(sql)) return ok();
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
}

const apt = (id, personCount, extra = {}) => ({
  id: String(id), unit_label: `Daire ${id}`, block_name: 'A Blok', block_sort: 1, apt_sort: id, responsible_party: 'owner', category: null,
  gross_x100: null, net_x100: null, land_share_numerator: null, land_share_denominator: null, person_count: personCount, has_tenant: false, ...extra,
});
const body = (extra = {}) => ({ name: 'Asansör bakımı', distribution: 'person_count', amount_minor: 100000, target: { type: 'site' }, ...extra });

describe('K5 girdi: dağıtım tabanı', () => {
  it("'person_count' geçerli taban; 'area' (m²) hâlâ reddedilir; taban verilmezse sunucu bir taban SEÇMEZ (400)", () => {
    assert.ok(DISTRIBUTIONS.includes('person_count'));
    const charge = parseChargeInput(body(), { requireExpected: false, now: NOW });
    assert.equal(charge.distribution, 'person_count');
    assert.equal(charge.amountMinor, 100000);
    assert.equal(charge.categoryAmounts, null);
    assert.throws(() => parseChargeInput(body({ distribution: 'area', area_basis: 'gross' }), { requireExpected: false, now: NOW }), { code: 'AREA_DISTRIBUTION_REMOVED' });
    assert.throws(() => parseChargeInput(body({ distribution: undefined }), { requireExpected: false, now: NOW }), { code: 'INVALID_BODY' });
    assert.throws(() => parseChargeInput(body({ distribution: 'm2' }), { requireExpected: false, now: NOW }), { code: 'INVALID_BODY' });
  });

  it('kişi sayısı toplam tutar ister (kategori tutarı / alan esası kabul edilmez)', () => {
    assert.throws(() => parseChargeInput(body({ amount_minor: undefined }), { requireExpected: false, now: NOW }), { code: 'INVALID_BODY' });
    assert.throws(() => parseChargeInput(body({ category_amounts: { '3+1': 100 } }), { requireExpected: false, now: NOW }), { code: 'INVALID_BODY' });
    assert.throws(() => parseChargeInput(body({ area_basis: 'net' }), { requireExpected: false, now: NOW }), { code: 'INVALID_BODY' });
  });

  it('aylık tanım ve PATCH: person_count kabul edilir; PATCH dağıtımı değişince bağımlı alanlar sıfırlanır', () => {
    const definition = parseDefinitionCreate({
      name: 'Aylık su payı', kind: 'recurring', distribution: 'person_count', amount_minor: 500000, due_day: 5, start_period: '2026-10', target: { type: 'site' },
    });
    assert.equal(definition.distribution, 'person_count');
    assert.equal(definition.chargeParty, 'occupant');
    const patch = parseDefinitionPatch({ distribution: 'person_count', amount_minor: 250000 });
    assert.deepEqual(patch.keys.sort(), ['amount_minor', 'distribution']);
    assert.equal(patch.distribution, 'person_count');
  });
});

describe('K5 önizleme: kişi sayısı tabanı', () => {
  it('kişi sayısı alt sorgusu YALNIZ person_count seçildiğinde sorguya girer (eşit / sabit / arsa payında NULL)', async () => {
    const db = fakeDb([apt(1, 2), apt(2, 3)]);
    await previewCharge({ siteCode: SITE, body: body(), now: NOW }, db);
    const withPeople = db.calls.find((c) => /FROM apartments a INNER JOIN site_blocks/.test(c.sql)).sql;
    assert.ok(withPeople.includes(norm(PERSON_COUNT_SQL)), 'person_count: alt sorgu var');
    for (const distribution of ['equal', 'land_share']) {
      const other = fakeDb([apt(1, null, { land_share_numerator: 1, land_share_denominator: 4 }), apt(2, null, { land_share_numerator: 3, land_share_denominator: 4 })]);
      await previewCharge({ siteCode: SITE, body: body({ distribution }), now: NOW }, other);
      const sql = other.calls.find((c) => /FROM apartments a INNER JOIN site_blocks/.test(c.sql)).sql;
      assert.equal(sql.includes('apartment_residencies r'), false, `${distribution}: kişi sayısı alt sorgusu YOK`);
      assert.match(sql, /NULL::INTEGER AS person_count/);
    }
  });

  it('1.000,00 TL, kişi sayıları 2 : 3 : 1 -> 333,33 / 500,00 / 166,67; satır taban değeri kişi sayısı; toplam birebir', async () => {
    const preview = await previewCharge({ siteCode: SITE, body: body(), now: NOW }, fakeDb([apt(1, 2), apt(2, 3), apt(3, 1)]));
    // T = 100.000 kuruş, W = 6: 33.333,33 / 50.000 / 16.666,67 -> taban 33.333 + 50.000 + 16.666 = 99.999; artan 1 kuruş en büyük kalanlı (4/6) 3. daireye
    assert.deepEqual(preview.lines.map((l) => [l.apartment_id, l.amount_minor, l.basis_value]), [[1, 33333, 2], [2, 50000, 3], [3, 16667, 1]]);
    assert.equal(preview.total_minor, 100000);
    assert.equal(preview.apartment_count, 3);
    assert.deepEqual(preview.missing_data, []);
  });

  it('kişi kaydı olmayan daire EŞİT paya düşürülmez: eksik veri (reason_code person_count_missing); atlanırsa pay kalanlara yeniden dağıtılır (redistributed)', async () => {
    const preview = await previewCharge({ siteCode: SITE, body: body(), now: NOW }, fakeDb([apt(1, 2), apt(2, 0), apt(3, 3), apt(4, null)]));
    assert.deepEqual(preview.missing_data.map((m) => [m.apartment_id, m.reason_code]), [[2, 'person_count_missing'], [4, 'person_count_missing']]);
    assert.deepEqual(preview.lines.map((l) => [l.apartment_id, l.amount_minor]), [[1, 40000], [3, 60000]]);
    assert.equal(preview.total_minor, 100000, 'toplam tutarın tamamı kişi kaydı olan dairelere dağılır');
    assert.equal(preview.skipped_count, 2);
    assert.equal(preview.redistributed, true);
  });

  it('eşit seçildiğinde kişi sayısı / arsa payı verisi yok sayılır (kod taban seçmez): herkese eşit', async () => {
    const apartments = [apt(1, 5, { land_share_numerator: 9, land_share_denominator: 10 }), apt(2, 1, { land_share_numerator: 1, land_share_denominator: 10 })];
    const preview = await previewCharge({ siteCode: SITE, body: body({ distribution: 'equal' }), now: NOW }, fakeDb(apartments));
    assert.deepEqual(preview.lines.map((l) => l.amount_minor), [50000, 50000]);
    assert.deepEqual(preview.lines.map((l) => l.basis_value), [null, null]);
  });

  it('önizleme özeti taban değişince değişir (taban takas edilmiş plan eski önizlemeyle kaydedilemez)', async () => {
    const apartments = [apt(1, 2, { land_share_numerator: 1, land_share_denominator: 4 }), apt(2, 2, { land_share_numerator: 3, land_share_denominator: 4 })];
    const byPeople = await previewCharge({ siteCode: SITE, body: body(), now: NOW }, fakeDb(apartments));
    const byShare = await previewCharge({ siteCode: SITE, body: body({ distribution: 'land_share' }), now: NOW }, fakeDb(apartments));
    assert.notEqual(byPeople.preview_hash, byShare.preview_hash);
    const moved = await previewCharge({ siteCode: SITE, body: body(), now: NOW }, fakeDb([apt(1, 3), apt(2, 1)]));
    assert.notEqual(byPeople.preview_hash, moved.preview_hash, 'kişi sayısı değişince özet değişir (PREVIEW_STALE)');
  });
});
