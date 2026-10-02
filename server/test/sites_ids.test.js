import test from 'node:test';
import assert from 'node:assert/strict';
import { INT32_MAX, parseId, parseOptionalId } from '../src/utils/ids.js';

test('parseId: gecerli pozitif tamsayilari kabul eder', () => {
  assert.equal(parseId(1), 1);
  assert.equal(parseId('7'), 7);
  assert.equal(parseId(' 42 '), 42);
  assert.equal(parseId('000123'), 123);
  assert.equal(parseId(Number.MAX_SAFE_INTEGER), Number.MAX_SAFE_INTEGER);
});

test('parseId: gecersiz degerlerde null doner', () => {
  const invalid = [
    0, -1, '0', '-5', 1.5, '1.5', '1e3', '0x10', '', '   ', 'abc', '12abc', '1 2',
    NaN, Infinity, -Infinity, null, undefined, true, false, {}, [], [1], () => 1,
    '9007199254740993', // guvenli tamsayi disi
    Number.MAX_SAFE_INTEGER + 2,
    '12345678901234567', // 17 hane
  ];
  for (const value of invalid) {
    assert.equal(parseId(value), null, `parseId(${String(value)}) null olmali`);
  }
});

test('parseId: max siniri (INTEGER kolonlari icin)', () => {
  assert.equal(parseId(INT32_MAX, { max: INT32_MAX }), INT32_MAX);
  assert.equal(parseId(INT32_MAX + 1, { max: INT32_MAX }), null);
  assert.equal(parseId('2147483648', { max: INT32_MAX }), null);
});

test('parseOptionalId: gonderilmeyen alan undefined, gecersiz null', () => {
  assert.equal(parseOptionalId(undefined), undefined);
  assert.equal(parseOptionalId(null), undefined);
  assert.equal(parseOptionalId(''), undefined);
  assert.equal(parseOptionalId('5'), 5);
  assert.equal(parseOptionalId('abc'), null);
  assert.equal(parseOptionalId(0), null);
  assert.equal(parseOptionalId(-3), null);
});
