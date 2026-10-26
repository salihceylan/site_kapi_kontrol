// Banka satırı eşleme (saf) ve 067 şema/migration eşitliği.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { computeFingerprints, computeLegacyFingerprints, matchLine, outcomeOf, previewHash, summarize } from '../src/modules/bank_line_match.js';
import { BANK_IMPORT_STATEMENTS } from '../src/modules/bank_import_schema.js';
import { parseStatementBody } from '../src/modules/bank_import_common.js';

const ctx = {
  refKnown: { prefixes: [{ prefix: 'GUL', site_code: 1 }], codes: [{ site_code: 1, code: 'A2', apartment_id: 7 }, { site_code: 1, code: 'B3', apartment_id: 8 }] },
  codes: [{ code: 'A2', apartment_id: 7 }, { code: 'B3', apartment_id: 8 }],
  ibans: new Map([
    ['TR330006100519786457841326', [{ apartment_id: 9, party: 'tenant', stale: false }]],
    ['TR000000000000000000000001', [{ apartment_id: 8, party: 'owner', stale: true }]],
  ]),
  people: [
    { apartment_id: 10, party: 'tenant', tokens: new Set(['AHMET', 'YILMAZ']) },
    { apartment_id: 11, party: 'owner', tokens: new Set(['AYSE', 'KAYA']) },
  ],
};
const line = (over) => ({ n: 1, value_date: '2026-10-01', amount_minor: 150000, description: '', counterparty_name: null, counterparty_iban: null, bank_reference: null, ...over });

describe('matchLine sırası', () => {
  it('referans kodu güçlü', () => {
    const m = matchLine(line({ description: 'Gül-A2-1026 aidat' }), ctx);
    assert.deepEqual([m.method, m.apartmentId, m.strength], ['ref', 7, 'strong']);
  });
  it('açıklamadaki daire kodu zayıf', () => {
    const m = matchLine(line({ description: 'B3 aidat ekim' }), ctx);
    assert.deepEqual([m.method, m.apartmentId, m.strength], ['code', 8, 'weak']);
  });
  it('IBAN hafızası güçlü; bayat kayıt sayılmaz', () => {
    assert.equal(matchLine(line({ counterparty_iban: 'TR33 0006 1005 1978 6457 8413 26' }), ctx).apartmentId, 9);
    assert.equal(matchLine(line({ counterparty_iban: 'TR000000000000000000000001' }), ctx), null);
  });
  it('gönderen adı en az 2 belirteç, zayıf', () => {
    const m = matchLine(line({ counterparty_name: 'AHMET YILMAZ' }), ctx);
    assert.deepEqual([m.method, m.apartmentId, m.party, m.strength], ['name', 10, 'tenant', 'weak']);
    assert.equal(matchLine(line({ counterparty_name: 'AHMET DEMIR' }), ctx), null);
  });
  it('çıkan para eşlenmez; hiçbiri yoksa null', () => {
    assert.equal(matchLine(line({ amount_minor: -500, description: 'GUL A2' }), ctx), null);
    assert.equal(matchLine(line({ description: 'serbest metin' }), ctx), null);
  });
  it('iki farklı daire kodu geçen açıklama eşleşmez', () => {
    assert.equal(matchLine(line({ description: 'A2 ve B3 icin' }), ctx), null);
  });
  it('açıklamadaki daire kodu ile IBAN hafızası AYNI daireyi gösteriyorsa güçlü (iban)', () => {
    const both = { ...ctx, ibans: new Map([['TR330006100519786457841326', [{ apartment_id: 8, party: 'owner', stale: false }]]]) };
    const m = matchLine(line({ description: 'B3 aidat', counterparty_iban: 'TR330006100519786457841326' }), both);
    assert.deepEqual([m.method, m.apartmentId, m.party, m.strength], ['iban', 8, 'owner', 'strong']);
  });
  it('ÇELİŞEN kanıt: açıklamadaki tekil daire kodu B (8), IBAN hafızası tek ve FARKLI daire A (9) -> eşleşme YOK (eskiden yanlış daireye strong)', () => {
    // ctx: B3 -> daire 8; TR33... IBAN'ı -> daire 9 (tenant, bayat değil)
    assert.equal(matchLine(line({ description: 'B3 aidat ekim', counterparty_iban: 'TR33 0006 1005 1978 6457 8413 26' }), ctx), null);
    // sonuç sınıfı: eşleşme yok -> unmatched (otomatik tahsilat yazılmaz)
    assert.equal(outcomeOf({ line: line({}), duplicate: false, match: null, linkedEntryId: null, ambiguousLink: false }), 'unmatched');
  });
  it('kod B + IBAN hafızası BAYAT ya da BİRDEN ÇOK daire: çelişki sayılmaz, kod zayıf eşleşir', () => {
    const stale = matchLine(line({ description: 'B3 aidat', counterparty_iban: 'TR000000000000000000000001' }), ctx);
    assert.deepEqual([stale.method, stale.apartmentId, stale.strength], ['code', 8, 'weak']);
    const many = { ...ctx, ibans: new Map([['TR330006100519786457841326', [{ apartment_id: 9, party: 'tenant', stale: false }, { apartment_id: 10, party: 'owner', stale: false }]]]) };
    const m = matchLine(line({ description: 'B3 aidat', counterparty_iban: 'TR330006100519786457841326' }), many);
    assert.deepEqual([m.method, m.apartmentId, m.strength], ['code', 8, 'weak']);
  });
});

describe('parmak izi, özet, hash', () => {
  it('eş satırlar farklı parmak izi alır; kararlıdır', () => {
    const l = line({ description: 'Aidat' });
    const a = computeFingerprints(5, [l, { ...l, n: 2 }, line({ description: 'Başka' })]);
    assert.equal(new Set(a).size, 3);
    assert.deepEqual(a, computeFingerprints(5, [l, { ...l, n: 2 }, line({ description: 'Başka' })]));
    assert.notEqual(a[0], computeFingerprints(6, [l])[0]);
  });
  it('banka referansı DOLUysa parmak izi açıklamadan BAĞIMSIZ: aynı ekstre PDF ve XLSX ta (farklı açıklama metni) aynı parmak izi', () => {
    const pdf = line({ description: 'EFT GELEN GÜL-A2 AİDAT', bank_reference: 'REF 2026/10/0042' });
    const xlsx = line({ description: 'Gelen EFT - Gul-A2 aidat ekim (ahmet yilmaz)', bank_reference: 'ref-2026-10-0042' });
    assert.deepEqual(computeFingerprints(5, [pdf]), computeFingerprints(5, [xlsx]));
    // valör / tutar / hesap / referans farkı yine ayırır
    assert.notEqual(computeFingerprints(5, [pdf])[0], computeFingerprints(5, [{ ...pdf, bank_reference: 'REF 2026/10/0043' }])[0]);
    assert.notEqual(computeFingerprints(5, [pdf])[0], computeFingerprints(5, [{ ...pdf, amount_minor: 150001 }])[0]);
    assert.notEqual(computeFingerprints(5, [pdf])[0], computeFingerprints(5, [{ ...pdf, value_date: '2026-10-02' }])[0]);
    assert.notEqual(computeFingerprints(5, [pdf])[0], computeFingerprints(6, [pdf])[0]);
    // aynı referans + aynı tutar + aynı gün iki satır dosya içinde sıra numarası ile ayrılır
    const twin = computeFingerprints(5, [pdf, { ...pdf, n: 2 }]);
    assert.equal(new Set(twin).size, 2);
  });
  it('referans YOKSA parmak izi açıklamaya bağlı kalır (eski davranış); eski formül referanslı satırda açıklamayı da içerir', () => {
    const a = line({ description: 'Aidat ekim' });
    const b = line({ description: 'Başka açıklama' });
    assert.notEqual(computeFingerprints(5, [a])[0], computeFingerprints(5, [b])[0]);
    assert.deepEqual(computeFingerprints(5, [a]), computeLegacyFingerprints(5, [a]), 'referanssız satırda yeni = eski');
    const withRef = line({ description: 'Aidat', bank_reference: 'R1' });
    assert.notEqual(computeFingerprints(5, [withRef])[0], computeLegacyFingerprints(5, [withRef])[0]);
    const withRefOtherText = { ...withRef, description: 'Aidat (PDF)' };
    assert.notEqual(computeLegacyFingerprints(5, [withRef])[0], computeLegacyFingerprints(5, [withRefOtherText])[0], 'eski formül açıklamaya bağlıydı');
  });
  it('sonuç sınıfları ve özet', () => {
    const strong = { strength: 'strong' };
    const rows = [
      { outcome: outcomeOf({ line: line(), duplicate: true }) },
      { outcome: outcomeOf({ line: line({ amount_minor: -5 }) }), amount_minor: -5 },
      { outcome: outcomeOf({ line: line(), match: null }) },
      { outcome: outcomeOf({ line: line(), match: strong }), amount_minor: 100 },
      { outcome: outcomeOf({ line: line(), match: strong, linkedEntryId: 4 }) },
      { outcome: outcomeOf({ line: line(), match: { strength: 'weak' } }) },
      { outcome: outcomeOf({ line: line(), match: strong, ambiguousLink: true }) },
    ];
    assert.deepEqual(rows.map((r) => r.outcome), ['duplicate', 'outgoing', 'unmatched', 'recognized', 'linked', 'check', 'check']);
    const s = summarize(rows);
    assert.deepEqual([s.recognized, s.check, s.unmatched, s.linked_existing, s.duplicates, s.outgoing, s.recognized_minor], [1, 2, 1, 1, 1, 1, 100]);
    const base = [{ n: 1, outcome: 'recognized', match: { apartmentId: 1, party: null } }];
    assert.notEqual(previewHash('a', 1, base), previewHash('a', 1, [{ ...base[0], outcome: 'check' }]));
  });
});

describe('gövde doğrulama', () => {
  const ok = () => ({
    account_id: 3,
    format: 'csv',
    file: { name: 'e.csv', size: 10, sha256: 'a'.repeat(64) },
    lines: [{ value_date: '2026-10-01', amount_minor: 1000, description: '=cmd', counterparty_iban: 'tr33 0006 1005 1978 6457 8413 26' }],
    idempotency_key: 'abcdefgh12',
    expected_hash: 'b'.repeat(64),
  });
  it('geçerli gövde', () => {
    const p = parseStatementBody(ok(), { commit: true, todayIso: '2026-10-21' });
    assert.equal(p.lines[0].counterparty_iban, 'TR330006100519786457841326');
  });
  it('geçersizler', () => {
    const bad = (mut) => assert.throws(() => parseStatementBody(mut(ok()), { commit: true, todayIso: '2026-10-21' }), { code: 'INVALID_BODY' });
    bad((b) => ({ ...b, lines: [] }));
    bad((b) => ({ ...b, lines: [{ ...b.lines[0], amount_minor: 10.5 }] }));
    bad((b) => ({ ...b, lines: [{ ...b.lines[0], value_date: '2026-12-01' }] }));
    bad((b) => ({ ...b, lines: [{ ...b.lines[0], amount_minor: 0 }] }));
    bad((b) => ({ ...b, file: { ...b.file, sha256: 'x' } }));
    bad((b) => ({ ...b, lines: Array.from({ length: 1501 }, () => b.lines[0]) }));
    bad((b) => ({ ...b, expected_hash: '' }));
  });
});

describe('067 şema = migration', () => {
  it('ifadeler migration dosyasında aynen bulunur', () => {
    const sql = readFileSync(new URL('../migrations/067_bank_imports.sql', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
    for (const statement of BANK_IMPORT_STATEMENTS) assert.ok(sql.includes(statement.replace(/\r\n/g, '\n')), statement.slice(0, 60));
    assert.ok(/IF NOT EXISTS/.test(sql) && !/DROP /.test(sql));
  });
});
