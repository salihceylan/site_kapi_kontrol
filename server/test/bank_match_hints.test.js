// Banka satırı ipuçları: açıklamadaki daire numarası + kişi adı eşlemesi, ay/dönem ipucu, PDF güven alanının gövdeden geçmesi.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { buildUnitIndex, periodHintOf, unitCandidates } from '../src/modules/bank_match_hints.js';
import { matchLine } from '../src/modules/bank_line_match.js';
import { parseStatementBody } from '../src/modules/bank_import_common.js';

const apartments = [
  { apartment_id: 21, block_name: 'A Blok', unit_label: '5' },
  { apartment_id: 22, block_name: 'A Blok', unit_label: '12' },
  { apartment_id: 31, block_name: 'B Blok', unit_label: '5' },
  { apartment_id: 32, block_name: 'B Blok', unit_label: '12' },
  { apartment_id: 41, block_name: 'C Blok', unit_label: '1A' }, // harfli etiket: numara kuralı dışında
];
const unitIndex = buildUnitIndex(apartments);
const ctx = {
  refKnown: { prefixes: [], codes: [] },
  codes: [],
  ibans: new Map(),
  people: [
    { apartment_id: 21, party: 'owner', tokens: new Set(['AHMET', 'YILMAZ']) },
    { apartment_id: 31, party: 'tenant', tokens: new Set(['AYSE', 'KAYA']) },
    { apartment_id: 32, party: 'owner', tokens: new Set(['MEHMET', 'DEMIR']) },
  ],
  unitIndex,
};
const line = (description, over = {}) => ({ n: 1, value_date: '2026-10-21', amount_minor: 150000, description, counterparty_name: null, counterparty_iban: null, bank_reference: null, ...over });
const m = (description, over) => matchLine(line(description, over), ctx);
const ids = (text) => [...unitCandidates(text, unitIndex)].sort();

describe('unitCandidates: daire numarası biçimleri', () => {
  it('blok + numara çeşitleri', () => {
    for (const t of ['A blok 5', 'A Blok Daire 5', 'blok A no 5', 'A5', 'A-5', 'A/5', 'a 5 nolu', 'Daire A5']) assert.deepEqual(ids(t), [21], t);
    assert.deepEqual(ids('B Blok 12 aidat'), [32]);
  });
  it('bloksuz numara ancak daire/no/nolu/d işaretliyse sayılır; birden çok blokta aday çoğalır', () => {
    assert.deepEqual(ids('5 nolu daire aidat'), [21, 31]);
    assert.deepEqual(ids('daire 12'), [22, 32]);
    assert.deepEqual(ids('D12 kasim'), [22, 32]);
    assert.deepEqual(ids('no: 5'), [21, 31]);
  });
  it('çıplak sayı, tarih, dekont numarası, harfli etiket sayılmaz', () => {
    for (const t of ['aidat 5', '15.10.2026 havale', '10/2026 aidat', 'dekont no 5', 'ref no 12', 'ekim 12 taksit', '1A']) assert.deepEqual(ids(t), [], t);
  });
});

describe('matchLine: daire numarası + kişi adı', () => {
  it('numara VE ad birlikte -> güçlü (otomatik işlenir)', () => {
    for (const t of ['A blok 5 Ahmet Yilmaz ekim aidati', 'AHMET YILMAZ A5 aidat', '5 nolu daire Ahmet Yılmaz', 'Ayşe Kaya B blok 5 kasım']) {
      const r = m(t);
      assert.equal(r.strength, 'strong', t);
      assert.equal(r.method, 'unit_name', t);
    }
    assert.deepEqual([m('A blok 5 Ahmet Yilmaz').apartmentId, m('A blok 5 Ahmet Yilmaz').party], [21, 'owner']);
    assert.equal(m('5 nolu daire Ayse Kaya').apartmentId, 31); // iki bloktaki 5 numaradan adı eşleşen
  });
  it('ad gönderen alanında, numara açıklamada olabilir', () => {
    const r = m('A blok 5 aidat', { counterparty_name: 'AHMET YILMAZ' });
    assert.deepEqual([r.method, r.strength, r.apartmentId], ['unit_name', 'strong', 21]);
  });
  it('yalnız numara -> zayıf (önizlemede önerili, onayla)', () => {
    const r = m('B blok 12 kasim aidat');
    assert.deepEqual([r.method, r.strength, r.apartmentId], ['unit', 'weak', 32]);
    assert.equal(m('A5 aidat').strength, 'weak');
  });
  it('yalnız ad -> zayıf (eski kural değişmedi)', () => {
    const r = m('Ahmet Yilmaz ekim aidati');
    assert.deepEqual([r.method, r.strength, r.apartmentId], ['name', 'weak', 21]);
  });
  it('belirsiz ya da çelişen kanıt -> eşleşme yok', () => {
    assert.equal(m('5 nolu daire aidat'), null); // iki aday
    assert.equal(m('A blok 5 Ayse Kaya'), null); // numara A5'i, ad B5'i gösteriyor
    assert.equal(m('D12 kasim'), null);
  });
  it('unitIndex yoksa eski davranış (numara kuralı çalışmaz)', () => {
    const { unitIndex: _omit, ...legacy } = ctx;
    assert.equal(matchLine(line('A blok 5 aidat'), legacy), null);
    assert.equal(matchLine(line('A blok 5 Ahmet Yilmaz'), legacy).method, 'name');
  });
  it('çıkan para (negatif) eşlenmez', () => {
    assert.equal(matchLine(line('A blok 5 Ahmet Yilmaz', { amount_minor: -100 }), ctx), null);
  });
});

describe('periodHintOf', () => {
  it('ay adı, ay/yıl, yıl-ay; yıl çıkarımı', () => {
    assert.equal(periodHintOf('Ahmet Yilmaz ekim aidati', '2026-10-21'), '2026-10');
    assert.equal(periodHintOf('KASIM AYI AIDAT', '2026-11-03'), '2026-11');
    assert.equal(periodHintOf('aralık aidatı', '2026-01-05'), '2025-12'); // Ocak'ta ödenen aralık
    assert.equal(periodHintOf('aidat 10/2026', '2026-10-21'), '2026-10');
    assert.equal(periodHintOf('aidat 2026-11', '2026-10-21'), '2026-11');
    assert.equal(periodHintOf('Kasım 2026 aidatı', '2026-10-21'), '2026-11');
    assert.equal(periodHintOf('NİSAN AİDATI', '2026-04-30'), '2026-04');
  });
  it('ay yoksa, birden çok ay varsa ya da yalnız tarih varsa null', () => {
    assert.equal(periodHintOf('aidat odemesi', '2026-10-21'), null);
    assert.equal(periodHintOf('ekim kasim aidati', '2026-11-21'), null);
    assert.equal(periodHintOf('15.10.2026 havale', '2026-10-21'), null);
    assert.equal(periodHintOf('', null), null);
  });
});

describe('parseStatementBody: PDF güven alanı', () => {
  const base = { account_id: 1, format: 'csv', file: { name: 'e.pdf', size: 10, sha256: 'a'.repeat(64) }, lines: [{ value_date: '2026-10-05', amount_minor: 100, description: 'x', confidence: 'low' }] };
  it('geçerli güven geçer, geçersiz değer null olur', () => {
    assert.equal(parseStatementBody(base, { todayIso: '2026-10-21' }).lines[0].confidence, 'low');
    const odd = { ...base, lines: [{ ...base.lines[0], confidence: 'zzz' }] };
    assert.equal(parseStatementBody(odd, { todayIso: '2026-10-21' }).lines[0].confidence, null);
  });
});
