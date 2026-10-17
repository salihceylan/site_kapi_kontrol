// Toplu yükleme (Faz 2b) değer ayrıştırıcıları (DB'siz): sayı, kat, tarih, plaka, ilişki, formül/metin kuralları, blok/daire eşleşmesi,
// özellik testi (rastgele metin hiçbir zaman özel hata fırlatmaz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  apartmentKey,
  cellToText,
  leadingChar,
  matchBlock,
  readArea,
  readDate,
  readEmail,
  readFloor,
  readLandShareInt,
  readName,
  readPhone,
  readPlates,
  readRelation,
  readResponsible,
  readText,
} from '../src/modules/bulk_import_parsers.js';

const TODAY = '2026-10-16';
const NBSP = String.fromCodePoint(0xa0);
const ZWSP = String.fromCodePoint(0x200b);
const RLO = String.fromCodePoint(0x202e);
const BOM = String.fromCodePoint(0xfeff);

describe('readText: metin kuralları', () => {
  it('NFC, görünmez/yön karakterleri silinir, NBSP ve ardışık boşluk tekile, kırpılır; boş = yok', () => {
    assert.equal(readText(`  A${ZWSP}li${NBSP}${NBSP}Veli${RLO} `).value, 'Ali Veli');
    assert.equal(readText(`${BOM}Ahmet`).value, 'Ahmet');
    assert.equal(readText('   ').value, null);
    assert.equal(readText(null).value, null);
    assert.equal(readText(undefined).value, null);
    assert.equal('Ç'.normalize('NFC'), readText('Ç').value);
  });

  it('sayı hücresi düz metne çevrilir (5 -> "5"); bool/nesne metin sayılmaz', () => {
    assert.equal(cellToText(5), '5');
    assert.equal(cellToText(5.5), '5.5');
    assert.equal(cellToText(true), null);
    assert.equal(cellToText({}), null);
    assert.equal(readText(12).value, '12');
  });

  it('formül önekleri: = @ TAB CR HER metin alanında FORMULA_LIKE; + - yalnız forbidSigned alanlarında', () => {
    for (const lead of ['=', '@', '\t', '\r']) {
      const result = readText(`${lead}SUM(A1)`);
      assert.equal(result.error, 'FORMULA_LIKE', JSON.stringify(lead));
    }
    assert.equal(readText('  =cmd|calc').error, 'FORMULA_LIKE');
    assert.equal(readText(`${ZWSP}=1+1`).error, 'FORMULA_LIKE');
    assert.equal(readText('+905551234567').error, undefined);
    assert.equal(readText('-1').error, undefined);
    assert.equal(readText('+evil', { forbidSigned: true }).error, 'FORMULA_LIKE');
    assert.equal(readText('-evil', { forbidSigned: true }).error, 'FORMULA_LIKE');
    assert.equal(readText('A+B', { forbidSigned: true }).error, undefined);
    // Unicode boşlukla gizlenmiş önek de yakalanır (kırpmadan sonra)
    assert.equal(readText(`${String.fromCodePoint(0x2003)}=1`).error, 'FORMULA_LIKE');
  });

  it('uzunluk: sütun sınırı aşılırsa TOO_LONG (kod noktası sayılır)', () => {
    assert.equal(readText('x'.repeat(41), { max: 40 }).error, 'TOO_LONG');
    assert.equal(readText('x'.repeat(40), { max: 40 }).value.length, 40);
    assert.equal(readText('😀'.repeat(40), { max: 40 }).error, undefined);
    assert.equal(readText('x'.repeat(601)).error, 'TOO_LONG');
  });

  it('çok satırlı not: satır sonları korunur, yatay boşluk sadeleşir', () => {
    assert.equal(readText('a  b\r\nc\n\n\n\nd', { multiline: true }).value, 'a b\nc\n\nd');
  });

  it('leadingChar: görünmezleri ve LF atlar, TAB/CR atlamaz', () => {
    assert.equal(leadingChar(`${ZWSP} =x`), '=');
    assert.equal(leadingChar('\n\nabc'), 'a');
    assert.equal(leadingChar('\tabc'), '\t');
    assert.equal(leadingChar(''), '');
  });
});

describe('ad, telefon, e-posta', () => {
  it('ad: 2-100 karakter; kısa/uzun NAME_INVALID; +/- ile başlayan FORMULA_LIKE', () => {
    assert.equal(readName('Ahmet Yılmaz').value, 'Ahmet Yılmaz');
    assert.equal(readName('A').error, 'NAME_INVALID');
    assert.equal(readName('x'.repeat(101)).error, 'NAME_INVALID');
    assert.equal(readName('=HYPERLINK("http://x")').error, 'FORMULA_LIKE');
    assert.equal(readName('-Ali').error, 'FORMULA_LIKE');
    assert.equal(readName('').value, null);
  });

  it('telefon: biçimler +90... olur; Excel baştaki sıfırı attıysa da kabul; sayı hücresi kabul; geçersiz PHONE_INVALID', () => {
    assert.equal(readPhone('0 (555) 123 45 67').value, '+905551234567');
    assert.equal(readPhone('555 123 45 67').value, '+905551234567');
    assert.equal(readPhone(5551234567).value, '+905551234567');
    assert.equal(readPhone('+90 555 123 45 67').value, '+905551234567');
    assert.equal(readPhone('12345').error, 'PHONE_INVALID');
    assert.equal(readPhone('abc').error, 'PHONE_INVALID');
    assert.equal(readPhone('=1+1').error, 'FORMULA_LIKE');
    assert.equal(readPhone('').value, null);
  });

  it('e-posta: küçük harf; geçersiz EMAIL_INVALID; @ahbu.local EMAIL_INTERNAL; =x@y.com FORMULA_LIKE', () => {
    assert.equal(readEmail('Ali@Example.COM').value, 'ali@example.com');
    assert.equal(readEmail('ali@').error, 'EMAIL_INVALID');
    assert.equal(readEmail('a b@c.com').error, 'EMAIL_INVALID');
    assert.equal(readEmail('daire5@ahbu.local').error, 'EMAIL_INTERNAL');
    assert.equal(readEmail('=x@y.com').error, 'FORMULA_LIKE');
    assert.equal(readEmail('+x@y.com').error, 'FORMULA_LIKE');
    assert.equal(readEmail(null).value, null);
  });
});

describe('readArea (m²)', () => {
  const v = (input) => readArea(input).value;
  it('JSON sayı olduğu gibi; metinde virgül ondalık; nokta ondalık; binlik gruplar', () => {
    assert.equal(v(125.5), 125.5);
    assert.equal(v('125,5'), 125.5);
    assert.equal(v('125.5'), 125.5);
    assert.equal(v('1.250'), 1250);
    assert.equal(v('1.250,5'), 1250.5);
    assert.equal(v('1,250.5'), 1250.5);
    assert.equal(readArea('1.250.000').error, 'NUMBER_RANGE'); // 1.250.000 m2 > 999999.99
    assert.equal(v('110 m2'), 110);
    assert.equal(v('110 m²'), 110);
    assert.equal(v('110㎡'), 110);
    assert.equal(v(`1${NBSP}250,5 M2`), 1250.5);
    assert.equal(v('0,5'), 0.5);
  });

  it('hatalar: NUMBER_INVALID (harf, çoklu ayırıcı, bozuk binlik), NUMBER_RANGE (0, negatif, > 999999.99)', () => {
    for (const bad of ['abc', '12a', '1.2.3', '1,2,3', '1.25,0.5', '', 'e5', '..', ',', 'm2']) {
      const result = readArea(bad);
      if (bad === '') {
        assert.equal(result.value, null);
      } else {
        assert.equal(result.error, 'NUMBER_INVALID', bad);
      }
    }
    for (const bad of ['0', '-5', '1000000', 0, -1]) {
      assert.equal(readArea(bad).error, 'NUMBER_RANGE', String(bad));
    }
    assert.equal(readArea('=1').error, 'FORMULA_LIKE');
  });

  it('ROUNDED (2 ondalıktan fazla yuvarlanır), AREA_UNUSUAL (< 10 ya da > 2000)', () => {
    assert.deepEqual(readArea('125,456'), { value: 125.46, warnings: ['ROUNDED'] });
    assert.deepEqual(readArea(125.456).warnings, ['ROUNDED']);
    assert.deepEqual(readArea('125,50').warnings, []);
    assert.deepEqual(readArea('5').warnings, ['AREA_UNUSUAL']);
    assert.deepEqual(readArea('2500').warnings, ['AREA_UNUSUAL']);
    assert.deepEqual(readArea('125').warnings, []);
  });
});

describe('readFloor, readLandShareInt', () => {
  it('kat: zemin/giriş = 0, bodrum = -1, "3. kat" = 3, sayılar; aralık -20..500', () => {
    const v = (x) => readFloor(x).value;
    assert.equal(v('zemin'), 0);
    assert.equal(v('Zemin Kat'), 0);
    assert.equal(v('Giriş'), 0);
    assert.equal(v('Bodrum'), -1);
    assert.equal(v('2. bodrum'), -2);
    assert.equal(v('3. kat'), 3);
    assert.equal(v('3.kat'), 3);
    assert.equal(v('kat 4'), 4);
    assert.equal(v('7'), 7);
    assert.equal(v('-1'), -1);
    assert.equal(v(5), 5);
    assert.equal(v(''), null);
    for (const bad of ['abc', '3,5', 3.5, 501, -21, '600', '1.5']) {
      assert.equal(readFloor(bad).error, 'FLOOR_INVALID', String(bad));
    }
  });

  it('arsa payı parçaları: tam sayı, 3\'lü binlik noktası kabul; aralık LAND_SHARE_INVALID', () => {
    assert.equal(readLandShareInt('35', { min: 0 }).value, 35);
    assert.equal(readLandShareInt(1000, { min: 1 }).value, 1000);
    assert.equal(readLandShareInt('1.000', { min: 1 }).value, 1000);
    assert.equal(readLandShareInt('0', { min: 0 }).value, 0);
    assert.equal(readLandShareInt('0', { min: 1 }).error, 'LAND_SHARE_INVALID');
    assert.equal(readLandShareInt(1.5, { min: 0 }).error, 'LAND_SHARE_INVALID');
    assert.equal(readLandShareInt('abc', { min: 0 }).error, 'LAND_SHARE_INVALID');
    assert.equal(readLandShareInt('2000000000', { min: 0 }).error, 'LAND_SHARE_INVALID');
    assert.equal(readLandShareInt('', { min: 0 }).value, null);
  });
});

describe('readDate', () => {
  it('biçimler: GG.AA.YYYY, G.A.YYYY, GG/AA/YYYY, GG-AA-YYYY, YYYY-AA-GG (saat eki yok sayılır)', () => {
    for (const input of ['15.03.2021', '15/03/2021', '15-03-2021', '2021-03-15', '2021-03-15T00:00:00', '2021-03-15T00:00:00.000Z']) {
      assert.equal(readDate(input, TODAY).value, '2021-03-15', input);
    }
    assert.equal(readDate('5.3.2021', TODAY).value, '2021-03-05');
  });

  it('hatalar: 2 haneli yıl, gerçek olmayan tarih, sayı, metin -> DATE_INVALID; < 1900 ve bugün+366 gün ötesi DATE_RANGE', () => {
    for (const bad of ['15.03.21', '31.02.2021', '2021-13-01', 'dün', '15.3', 44000, '00.01.2021']) {
      assert.equal(readDate(bad, TODAY).error, 'DATE_INVALID', String(bad));
    }
    assert.equal(readDate('31.12.1899', TODAY).error, 'DATE_RANGE');
    assert.equal(readDate('01.01.1900', TODAY).value, '1900-01-01');
    assert.equal(readDate('2028-01-01', TODAY).error, 'DATE_RANGE');
  });

  it('gelecek tarih (<= bugün+366 gün) FUTURE_DATE uyarısıyla kabul; sınır gün', () => {
    assert.deepEqual(readDate('2026-12-01', TODAY), { value: '2026-12-01', warnings: ['FUTURE_DATE'] });
    assert.deepEqual(readDate('2026-10-16', TODAY).warnings, []);
    assert.equal(readDate('2027-10-17', TODAY).value, '2027-10-17'); // bugün + 366 gün
    assert.equal(readDate('2027-10-18', TODAY).error, 'DATE_RANGE');
  });
});

describe('enum ve plaka', () => {
  it('ilişki sözcükleri (Türkçe katlama): malik/mal sahibi/ev sahibi, kiracı/kiraci, aile/eş/çocuk, sakin/oturan; boş -> null', () => {
    const v = (x) => readRelation(x).value;
    for (const word of ['Malik', 'MALİK', 'mal sahibi', 'Ev Sahibi', ' malik ']) assert.equal(v(word), 'owner', word);
    for (const word of ['Kiracı', 'KİRACI', 'kiraci']) assert.equal(v(word), 'tenant', word);
    for (const word of ['Aile', 'Aile Üyesi', 'aile uyesi', 'Eş', 'es', 'Çocuk']) assert.equal(v(word), 'family_member', word);
    for (const word of ['Sakin', 'Oturan']) assert.equal(v(word), 'resident', word);
    assert.equal(v(''), null);
    assert.equal(v(null), null);
    assert.equal(readRelation('patron').error, 'RELATION_INVALID');
    assert.equal(readRelation('=cmd').error, 'FORMULA_LIKE');
  });

  it('borç sorumlusu: Malik / Kiracı / İkisi', () => {
    assert.equal(readResponsible('Malik').value, 'owner');
    assert.equal(readResponsible('kiracı').value, 'tenant');
    assert.equal(readResponsible('İkisi').value, 'both');
    assert.equal(readResponsible('ikisi de').value, 'both');
    assert.equal(readResponsible('komşu').error, 'RESPONSIBLE_INVALID');
  });

  it('plaka: ayırıcılar , ; / | satır sonu; normalize; yinelenen atılır; geçersizler ayrı döner', () => {
    assert.deepEqual(readPlates('34 ABC 123, 06 xy 789').plates.map((p) => p.plate), ['34ABC123', '06XY789']);
    assert.deepEqual(readPlates('34 ABC 123;06 XY 789/35 DE 45|16 AB 111').plates.map((p) => p.plate), ['34ABC123', '06XY789', '35DE45', '16AB111']);
    assert.deepEqual(readPlates('34 ABC 123\n06 XY 789').plates.map((p) => p.plate), ['34ABC123', '06XY789']);
    assert.deepEqual(readPlates('34 ABC 123, 34abc123').plates.length, 1);
    const mixed = readPlates('34 ABC 123, XX');
    assert.equal(mixed.plates.length, 1);
    assert.deepEqual(mixed.invalid, ['XX']);
    assert.equal(readPlates('1,2,3,4,5,6').error, 'TOO_MANY_PLATES');
    assert.equal(readPlates('34 ABC 123,34 ABC 124,34 ABC 125,34 ABC 126,34 ABC 127').plates.length, 5);
    assert.equal(readPlates('=cmd').error, 'FORMULA_LIKE');
    assert.equal(readPlates('-34 ABC 123').error, 'FORMULA_LIKE');
    assert.deepEqual(readPlates('').plates, []);
    assert.deepEqual(readPlates(null).plates, []);
    assert.deepEqual(readPlates(', ;').plates, []);
  });
});

describe('blok ve daire eşleşmesi', () => {
  const blocks = [
    { id: 1, name: 'A Blok' },
    { id: 2, name: 'B Blok' },
    { id: 3, name: 'Çınar Sitesi' },
  ];
  it('"A", "A Blok", "Blok A", "a blok", "A-Blok" aynı bloğa gider; Türkçe katlama', () => {
    for (const input of ['A', 'a', 'A Blok', 'Blok A', 'a blok', 'A-Blok', ' A  Blok ', 'BLOK A']) {
      assert.equal(matchBlock(input, blocks).block?.id, 1, input);
    }
    assert.equal(matchBlock('cinar sitesi', blocks).block?.id, 3);
    assert.equal(matchBlock('C', blocks).error, 'BLOCK_NOT_FOUND');
    assert.equal(matchBlock('', blocks).error, 'BLOCK_NOT_FOUND');
  });

  it('birden çok blok eşleşirse BLOCK_AMBIGUOUS; tam ad önceliklidir', () => {
    const dup = [{ id: 1, name: 'A' }, { id: 2, name: 'A Blok' }];
    assert.equal(matchBlock('A', dup).block?.id, 1); // tam ad
    assert.equal(matchBlock('A Blok', dup).block?.id, 2);
    assert.equal(matchBlock('Blok A', dup).error, 'BLOCK_AMBIGUOUS');
  });

  it('daire anahtarı: 5, 05, Daire 5, D5, No: 5, Daire No: 5 -> n:5; farklı etiket l:...', () => {
    for (const input of ['5', '05', 'Daire 5', 'daire5', 'D5', 'No: 5', 'Daire No: 5', 'Kapı 5', 5, 'DAİRE 005']) {
      assert.equal(apartmentKey(String(input)), 'n:5', String(input));
    }
    assert.equal(apartmentKey('Dükkan 1'), 'l:dukkan 1');
    assert.equal(apartmentKey('Daire 5'), apartmentKey('5'));
    assert.notEqual(apartmentKey('Daire 15'), apartmentKey('Daire 5'));
  });
});

describe('özellik testi: hiçbir okuyucu için rastgele girdi özel hata fırlatmaz', () => {
  const alphabet = ['=', '+', '-', '@', '\t', '\r', '\n', ' ', ZWSP, RLO, NBSP, '.', ',', '/', ';', '|', '0', '1', '5', '9', 'a', 'Z', 'ı', 'İ', 'ş', 'm', '²', '㎡', '😀', 'é', 'e', 'E', ':', '(', ')', '"', "'", '\\', '\u0000', '́'];
  function random(rng) {
    const length = Math.floor(rng() * 24);
    let out = '';
    for (let i = 0; i < length; i += 1) out += alphabet[Math.floor(rng() * alphabet.length)];
    return out;
  }
  function mulberry(seed) {
    let a = seed;
    return () => {
      a |= 0;
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  it('20.000 rastgele metin x tüm okuyucular: fırlatmaz, sonuç şekli sabit', () => {
    const rng = mulberry(20261016);
    const readers = [
      (x) => readText(x),
      (x) => readName(x),
      (x) => readPhone(x),
      (x) => readEmail(x),
      (x) => readArea(x),
      (x) => readFloor(x),
      (x) => readLandShareInt(x, { min: 0 }),
      (x) => readDate(x, TODAY),
      (x) => readRelation(x),
      (x) => readResponsible(x),
      (x) => readPlates(x),
      (x) => matchBlock(x, [{ id: 1, name: 'A Blok' }]),
      (x) => apartmentKey(x),
    ];
    for (let i = 0; i < 20000; i += 1) {
      const input = random(rng);
      for (const reader of readers) {
        const result = reader(input);
        assert.ok(typeof result === 'string' || (result !== null && typeof result === 'object'));
      }
    }
    // sayılar da güvenli
    for (const n of [0, -0, 1e308, -1e308, 1e-9, 0.1 + 0.2, 123456789.12345679, Number.MAX_SAFE_INTEGER]) {
      assert.doesNotThrow(() => readArea(n));
      assert.doesNotThrow(() => readFloor(n));
      assert.doesNotThrow(() => readText(n));
      assert.doesNotThrow(() => readPhone(n));
    }
  });

  it('ikinci okuma sonucu değiştirmez (idempotent): temizlenmiş metin yeniden okununca aynı', () => {
    const rng = mulberry(7);
    for (let i = 0; i < 5000; i += 1) {
      const first = readText(random(rng));
      if (first.value !== null && first.value !== undefined) {
        assert.equal(readText(first.value).value, first.value);
      }
    }
  });
});
