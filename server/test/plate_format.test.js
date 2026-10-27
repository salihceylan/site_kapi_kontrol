// Türk plakası biçim kuralı (plate_format.js): sunucudaki TEK kural; istemci lib/ui/helpers/plate_input.dart aynısını uygular.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import * as common from '../src/modules/plate_recognition_common.js';
import {
  TR_PLATE_RE,
  canonicalPlate,
  formatPlate,
  normalizeTrPlate,
  parseTrPlate,
  plateInvalid,
  requireTrPlate,
  requireTrPlateEntry,
} from '../src/modules/plate_format.js';

const MESSAGE = 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).';
const code = (c, status) => (e) => e.code === c && e.statusCode === status && e.message === MESSAGE;

describe('plate_format: Türk plakası kuralı', () => {
  it('geçerli biçimler: il kodu 01-81 + 1-3 harf + 2-4 rakam', () => {
    for (const plate of ['01A12', '34ABC123', '06XY789', '81Z1234', '34AB12', '07ABC1234', '10A99', '80ABC12', '81AB123']) {
      assert.ok(TR_PLATE_RE.test(plate), plate);
      assert.equal(normalizeTrPlate(plate), plate, plate);
    }
  });

  it('il kodu 00 ve 82+ , harf / rakam sayısı dışı ve fazlası geçersiz', () => {
    for (const bad of [
      '00ABC123', '82ABC123', '99ABC123', '34ABC1', '34ABC12345', '34ABCD123', '34123', '34ABC', 'ABC123', '3ABC123', '34 12 ABC',
      'ABC12345', '12345', '34A', '34ABC12A', '3412ABC', '340ABC12', '34-',
    ]) {
      assert.equal(normalizeTrPlate(bad), null, bad);
    }
  });

  it('boşluk / tire / nokta / alt çizgi atılır, büyük harf, Türkçe harfler ASCII olur', () => {
    assert.equal(normalizeTrPlate('34 abc 123'), '34ABC123');
    assert.equal(normalizeTrPlate('34-ABC-123'), '34ABC123');
    assert.equal(normalizeTrPlate(' 06 a 1234 '), '06A1234');
    assert.equal(normalizeTrPlate('34.abc.123'), '34ABC123');
    assert.equal(canonicalPlate('34 şç 123'), '34SC123');
    assert.equal(canonicalPlate('34 ĞÜÖ 12'), '34GUO12');
    assert.equal(canonicalPlate('34 ıİ 12'), '34II12');
  });

  it('metin olmayan ya da 24 karakterden uzun girdi geçersiz', () => {
    for (const bad of [null, undefined, 34123, {}, [], '', '   ', 'x'.repeat(25), '34 ABC 123'.repeat(3)]) {
      assert.equal(normalizeTrPlate(bad), null, String(bad));
    }
  });

  it('formatPlate: "34ABC123" -> "34 ABC 123"; geçersiz olduğu gibi döner', () => {
    assert.equal(formatPlate('34ABC123'), '34 ABC 123');
    assert.equal(formatPlate('06A1234'), '06 A 1234');
    assert.equal(formatPlate('ABC12345'), 'ABC12345');
    assert.equal(formatPlate(null), '');
  });

  it('requireTrPlate: geçersizse 400 PLATE_INVALID ve sabit ileti', () => {
    assert.equal(requireTrPlate('34 abc 123'), '34ABC123');
    assert.throws(() => requireTrPlate('ABC12345'), code('PLATE_INVALID', 400));
    assert.throws(() => requireTrPlate(undefined), code('PLATE_INVALID', 400));
    assert.equal(plateInvalid().message, MESSAGE);
  });

  it('parseTrPlate / requireTrPlateEntry: { plate, display } çifti (plate = boşluksuz, display = 34 ABC 123)', () => {
    assert.deepEqual(parseTrPlate('34-abc-123'), { plate: '34ABC123', display: '34 ABC 123' });
    assert.deepEqual(requireTrPlateEntry('06 xy 12'), { plate: '06XY12', display: '06 XY 12' });
    assert.equal(parseTrPlate('ABC12345'), null);
    assert.throws(() => requireTrPlateEntry('ABC12345'), code('PLATE_INVALID', 400));
  });

  it('plate_recognition_common aynı işlevleri dışa vermeye devam eder (eski içe aktarmalar bozulmaz)', () => {
    assert.equal(common.TR_PLATE_RE, TR_PLATE_RE);
    assert.equal(common.canonicalPlate, canonicalPlate);
    assert.equal(common.normalizeTrPlate, normalizeTrPlate);
    assert.equal(common.requireTrPlate, requireTrPlate);
    assert.equal(common.formatPlate, formatPlate);
    assert.equal(common.plateInvalid, plateInvalid);
  });
});
