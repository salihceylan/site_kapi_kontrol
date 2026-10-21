// TR IBAN yardımcıları (saf): mod-97, biçim, maske.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { formatIban, iban97, maskIban, normalizeIban, parseTrIban } from '../src/modules/finance_iban.js';

/** Test için geçerli TR IBAN üretir (mod-97 sağlama basamakları). */
export function makeTrIban(body22 = '0006100519786457841326') {
  const check = String(98 - iban97(`TR00${body22}`)).padStart(2, '0');
  return `TR${check}${body22}`;
}

describe('finance_iban', () => {
  it('üretilen geçerli IBAN kabul edilir; boşluk, tire ve küçük harf normalleşir', () => {
    const iban = makeTrIban();
    assert.equal(iban.length, 26);
    assert.equal(parseTrIban(iban), iban);
    assert.equal(parseTrIban(formatIban(iban).toLowerCase()), iban);
    assert.equal(parseTrIban(formatIban(iban).replace(/ /g, '-')), iban);
    assert.equal(normalizeIban(' tr 12-3 '), 'TR123');
  });

  it('uzunluk, ülke ve sağlama hataları reddedilir', () => {
    const iban = makeTrIban();
    assert.equal(parseTrIban(iban.slice(0, 25)), null);
    assert.equal(parseTrIban(`${iban}0`), null);
    assert.equal(parseTrIban(`DE${iban.slice(2)}`), null);
    const last = iban.at(-1) === '9' ? '0' : String(Number(iban.at(-1)) + 1);
    assert.equal(parseTrIban(iban.slice(0, 25) + last), null);
    assert.equal(parseTrIban(''), null);
    assert.equal(parseTrIban(null), null);
    assert.equal(parseTrIban(`TR${'A'.repeat(24)}`), null);
  });

  it('gruplu gösterim 4lü, maske yalnız son 4 haneyi gösterir', () => {
    const iban = makeTrIban();
    assert.equal(formatIban(iban), iban.replace(/(.{4})/g, '$1 ').trim());
    assert.equal(maskIban(iban), `TR** … ${iban.slice(-4)}`);
    assert.ok(!maskIban(iban).includes(iban.slice(2, 20)));
  });
});
