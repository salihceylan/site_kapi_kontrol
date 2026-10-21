// Ödeme referans kodu (saf): önek, daire kodu, biçim, findRefs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { aptCode, findRefs, foldRef, formatRef, parsePrefix, periodLabel, suggestPrefix } from '../src/modules/finance_payment_ref.js';

const known = {
  prefixes: [
    { prefix: 'GUL', site_code: 1 },
    { prefix: 'ESK', site_code: 1 },
  ],
  codes: [
    { site_code: 1, code: 'A2', apartment_id: 7 },
    { site_code: 1, code: 'A21', apartment_id: 8 },
    { site_code: 1, code: 'D5', apartment_id: 9 },
  ],
};
const idOf = (text) => {
  const r = findRefs(text, known);
  return r.status === 'unique' ? r.match.apartment_id : r.status;
};

describe('finance_payment_ref: önek', () => {
  it('katlama ve doğrulama', () => {
    assert.equal(foldRef('Gül-A2 / 10'), 'GULA210');
    assert.equal(parsePrefix(' Gül '), 'GUL');
    assert.equal(parsePrefix('G1L'), null);
    assert.equal(parsePrefix('GÜLL'), null);
    assert.equal(parsePrefix(''), null);
  });
  it('öneri ve çakışmada başka varyant', () => {
    assert.equal(suggestPrefix('Gül Sitesi'), 'GUL');
    const second = suggestPrefix('Gül Sitesi', new Set(['GUL']));
    assert.match(second, /^[A-Z]{3}$/);
    assert.notEqual(second, 'GUL');
    assert.equal(suggestPrefix('Ay'), 'AYX');
  });
});

describe('finance_payment_ref: daire kodu ve biçim', () => {
  it('tek blok D+no, çok blok jeton+no, rakamlı jetonda D, yedek K+id', () => {
    assert.equal(aptCode({ blockName: 'A Blok', unitLabel: 'Daire 5', blockCount: 1, apartmentId: 1 }), 'D5');
    assert.equal(aptCode({ blockName: 'A Blok', unitLabel: 'Daire 2', blockCount: 3, apartmentId: 1 }), 'A2');
    assert.equal(aptCode({ blockName: 'Gül', unitLabel: 'Daire 05', blockCount: 3, apartmentId: 1 }), 'GUL5');
    assert.equal(aptCode({ blockName: 'B1', unitLabel: 'Daire 5', blockCount: 2, apartmentId: 1 }), 'B1D5');
    assert.equal(aptCode({ blockName: 'A', unitLabel: 'Dükkan', blockCount: 2, apartmentId: 55 }), 'K55');
  });
  it('referans biçimi İstanbul saatine göre', () => {
    const now = new Date('2026-10-21T10:00:00Z');
    assert.equal(formatRef({ prefix: 'GUL', code: 'A2', now }), 'GUL-A2-1026');
    assert.equal(formatRef({ prefix: 'GUL', code: 'A2', now, withPeriod: false }), 'GUL-A2');
    assert.equal(formatRef({ prefix: 'GUL', code: 'A2', now: new Date('2026-12-31T22:00:00Z') }), 'GUL-A2-0127');
    assert.equal(periodLabel(now), '10/2026');
  });
});

describe('finance_payment_ref: findRefs', () => {
  it('çeşitli yazımlar tek daireye çözülür', () => {
    assert.equal(idOf('GUL-A2-1026'), 7);
    assert.equal(idOf('gul a2 1026'), 7);
    assert.equal(idOf('GUL-A2'), 7);
    assert.equal(idOf('GÜL A2'), 7);
    assert.equal(idOf('ESK A2 aidat'), 7);
    assert.equal(idOf('aidat ödemesi GUL-D5-0126 teşekkürler'), 9);
    assert.equal(idOf('GUL/D5'), 9);
  });
  it('dönem bilgisi okunur; geçersiz ay dönemsiz sayılır', () => {
    assert.deepEqual(findRefs('GUL-A2-1026', known).match.period, { month: 10, year2: 26 });
    assert.equal(findRefs('GUL A2 1326', known).match.period, null);
    assert.equal(findRefs('GUL-A2', known).match.period, null);
  });
  it('eşleşmeyenler ve belirsizlik', () => {
    assert.equal(idOf('GULSEN'), 'none');
    assert.equal(idOf('ALTIN A2'), 'none');
    assert.equal(idOf('GUL X9'), 'none');
    assert.equal(idOf('GULA21026'), 7);
    // hem A2 + "1026" hem A21 + "026"(geçersiz) -> yalnız A2; A21 ayrı yazılınca A21
    assert.equal(idOf('GUL A21'), 8);
    // iki farklı daire kodu aynı metinde -> belirsiz
    assert.equal(idOf('GUL-A2 ve GUL-D5'), 'ambiguous');
  });
});
