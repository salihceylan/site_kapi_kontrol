// Kisi ve Daire Kayitlari (Faz 2a): saf dogrulayicilar ve yardimcilar (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  RELATIONS,
  apartmentLabel,
  dateToIso,
  escapeLike,
  foldSql,
  foldText,
  normalizeDateInput,
  normalizePersonEmail,
  normalizePersonName,
  normalizePersonPhone,
  normalizePlate,
  optionalQueryId,
  parsePage,
  parsePositiveId,
  parseRelationFilter,
  parseRelationInput,
  parseSearchTerm,
  parseStatusFilter,
  redactForReadOnlyRole,
  redactManagerNotes,
  todayIso,
} from '../src/modules/people_common.js';
import { mergeLandShare, parseApartmentPatch } from '../src/modules/apartment_records_service.js';
import { parsePersonCreateInput } from '../src/modules/people_service.js';

const codeOf = (fn) => {
  try {
    fn();
  } catch (error) {
    return { code: error.code, status: error.statusCode, message: error.message };
  }
  return null;
};

describe('people_common: telefon (+90 ve 10 hane)', () => {
  it('yaygin biclimler +90XXXXXXXXXX olur', () => {
    for (const raw of ['0555 123 45 67', '555 123 45 67', '+90 555 123 45 67', '905551234567', '(0555) 123-45-67', '5551234567', ' +905551234567 ']) {
      assert.equal(normalizePersonPhone(raw), '+905551234567', raw);
    }
    assert.equal(normalizePersonPhone('0212 555 12 34'), '+902125551234');
  });

  it('bos/yok -> null; gecersiz -> 400 INVALID_BODY (alan adiyla)', () => {
    for (const raw of [undefined, null, '', '   ']) {
      assert.equal(normalizePersonPhone(raw), null);
    }
    for (const raw of ['123', '055512345', '+1 555 123 4567', 'abc', '0555 123 45 678', '0000000000', 5551234567]) {
      const result = codeOf(() => normalizePersonPhone(raw));
      assert.equal(result?.code, 'INVALID_BODY', String(raw));
      assert.equal(result.status, 400);
      assert.match(result.message, /phone/);
    }
  });
});

describe('people_common: e-posta, ad, tarih, plaka', () => {
  it('e-posta kucuk harfe cevrilir; gecersiz 400', () => {
    assert.equal(normalizePersonEmail('  Ali.Veli@Example.COM '), 'ali.veli@example.com');
    assert.equal(normalizePersonEmail(''), null);
    assert.equal(normalizePersonEmail(undefined), null);
    for (const raw of ['bozuk', 'a@b', 'a b@c.com', 'a@@b.com', 'a..b@c.com', 7, `${'x'.repeat(250)}@a.com`]) {
      assert.equal(codeOf(() => normalizePersonEmail(raw))?.code, 'INVALID_BODY', String(raw));
    }
  });

  it('ad 2-100 karakter; kontrol karakterleri temizlenir; bosluklar tekleshir', () => {
    assert.equal(normalizePersonName('  Ayşe   Yılmaz '), 'Ayşe Yılmaz');
    assert.equal(normalizePersonName('Al'), 'Al');
    assert.equal(normalizePersonName('A\tB'), 'A B');
    for (const raw of ['A', '   ', '', 'x'.repeat(101), null, undefined, 5]) {
      assert.equal(codeOf(() => normalizePersonName(raw))?.code, 'INVALID_BODY', String(raw));
    }
    assert.equal(normalizePersonName('ç'.repeat(100)).length, 100);
  });

  it('tarih: YYYY-AA-GG ve GG.AA.YYYY kabul; gercek olmayan / aralik disi / bicim hatasi 400', () => {
    assert.equal(normalizeDateInput('2026-03-05', 'move_in_date'), '2026-03-05');
    assert.equal(normalizeDateInput('05.03.2026', 'move_in_date'), '2026-03-05');
    assert.equal(normalizeDateInput(undefined, 'x'), null);
    assert.equal(normalizeDateInput('', 'x'), null);
    for (const raw of ['2026-02-30', '2026-13-01', '31.04.2026', '2026/03/05', '5.3.2026', '1899-12-31', '2101-01-01', 20260305, 'dün']) {
      const result = codeOf(() => normalizeDateInput(raw, 'move_in_date'));
      assert.equal(result?.code, 'INVALID_BODY', String(raw));
      assert.match(result.message, /move_in_date/);
    }
    assert.equal(normalizeDateInput('2024-02-29', 'x'), '2024-02-29', 'artik yil');
  });

  it('plaka: buyuk harf, bosluk/tire atilir; 5-10 karakter A-Z0-9; display korunur', () => {
    assert.deepEqual(normalizePlate('34 abc 123'), { plate: '34ABC123', display: '34 ABC 123' });
    assert.deepEqual(normalizePlate('06-AB-1234'), { plate: '06AB1234', display: '06-AB-1234' });
    assert.equal(normalizePlate('  34ABC123  ').plate, '34ABC123');
    for (const raw of ['34A', '34 ŞŞŞ 123', 'x'.repeat(11), '', '   ', '34 ABC 12!', null, 5, '1234 5678 9012 3456 78']) {
      const result = codeOf(() => normalizePlate(raw));
      assert.equal(result?.code, 'PLATE_INVALID', String(raw));
      assert.equal(result.status, 400);
      assert.equal(result.message, 'Plaka biçimi geçersiz.');
    }
  });

  it('dateToIso: Date ve metin; null guvenli; todayIso Istanbul gunu', () => {
    assert.equal(dateToIso(null), null);
    assert.equal(dateToIso('2026-03-05'), '2026-03-05');
    assert.equal(dateToIso(new Date(2026, 2, 5)), '2026-03-05');
    assert.match(todayIso(), /^\d{4}-\d{2}-\d{2}$/);
    // 22:30 UTC = ertesi gun 01:30 Istanbul (UTC+3)
    assert.equal(todayIso(new Date('2026-06-14T22:30:00Z')), '2026-06-15');
  });
});

describe('people_common: arama katlama ve sayfalama', () => {
  it('foldText Turkce karakter ve buyuk/kucuk harf duyarsiz', () => {
    assert.equal(foldText('ÇAĞLAR Şahin İŞÇİ'), 'caglar sahin isci');
    assert.equal(foldText('ıİöÖüÜğĞ'), 'iioouugg');
    assert.equal(foldText('Gül Sitesi'), 'gul sitesi');
  });

  it('foldSql SQL tarafinda ayni kurali uygular (translate + lower)', () => {
    const sql = foldSql('col');
    assert.match(sql, /^lower\(translate\(COALESCE\(col, ''\), 'ÇĞİÖŞÜçğıöşü', 'CGIOSUcgiosu'\)\)$/);
  });

  it('escapeLike joker karakterleri kacirir', () => {
    assert.equal(escapeLike('50%_ab\\c'), '50\\%\\_ab\\\\c');
  });

  it('parseSearchTerm kirpar ve 100 karaktere indirir', () => {
    assert.equal(parseSearchTerm('  ali  '), 'ali');
    assert.equal(parseSearchTerm(''), null);
    assert.equal(parseSearchTerm(undefined), null);
    assert.equal(parseSearchTerm(['a']), null);
    assert.equal(Array.from(parseSearchTerm('x'.repeat(300))).length, 100);
  });

  it('parsePage: limit 1-200 (varsayilan 50), offset >= 0; gecersiz offset 400 INVALID_QUERY', () => {
    assert.deepEqual(parsePage({}), { limit: 50, offset: 0 });
    assert.deepEqual(parsePage({ limit: '0', offset: '10' }), { limit: 1, offset: 10 });
    assert.deepEqual(parsePage({ limit: '999' }), { limit: 200, offset: 0 });
    assert.deepEqual(parsePage({ limit: 'abc' }), { limit: 50, offset: 0 });
    assert.equal(codeOf(() => parsePage({ offset: '-1' }))?.code, 'INVALID_QUERY');
    assert.equal(codeOf(() => parsePage({ offset: 'x' }))?.code, 'INVALID_QUERY');
  });

  it('kimlik ve filtre ayristiricilari', () => {
    assert.equal(parsePositiveId('12'), 12);
    assert.equal(parsePositiveId(0), null);
    assert.equal(parsePositiveId('1e3'), null);
    assert.equal(parsePositiveId('99999999999', 2147483647), null);
    assert.equal(optionalQueryId(undefined), null);
    assert.equal(optionalQueryId(''), null);
    assert.equal(optionalQueryId('7'), 7);
    assert.equal(codeOf(() => optionalQueryId('abc'))?.code, 'INVALID_QUERY');
    assert.equal(parseStatusFilter(undefined), 'active');
    assert.equal(parseStatusFilter('all'), 'all');
    assert.equal(codeOf(() => parseStatusFilter('zz'))?.code, 'INVALID_QUERY');
    assert.equal(parseRelationFilter(undefined), null);
    assert.equal(parseRelationFilter('tenant'), 'tenant');
    assert.equal(codeOf(() => parseRelationFilter('x'))?.code, 'INVALID_QUERY');
    assert.deepEqual([...RELATIONS], ['owner', 'tenant', 'family_member', 'resident']);
    assert.equal(parseRelationInput(undefined), 'resident');
    assert.equal(parseRelationInput('owner'), 'owner');
    assert.equal(codeOf(() => parseRelationInput('malik'))?.code, 'INVALID_BODY');
  });

  it('apartmentLabel "<blok> - <daire>" (kapi gunlugundeki apartment_label ile ayni)', () => {
    assert.equal(apartmentLabel('A Blok', 'Daire 5'), 'A Blok - Daire 5');
    assert.equal(apartmentLabel('A Blok', ''), 'A Blok');
    assert.equal(apartmentLabel(null, 'Daire 5'), 'Daire 5');
  });
});

describe('POST people girdi ayristirma', () => {
  it('tam girdi normalize edilir', () => {
    const input = parsePersonCreateInput({
      full_name: ' Ali  Veli ',
      phone: '0555 111 22 33',
      email: 'ALI@Example.com',
      note: ' not ',
      apartment_id: '12',
      relation: 'tenant',
      move_in_date: '01.02.2026',
    });
    assert.deepEqual(input, {
      fullName: 'Ali Veli',
      phone: '+905551112233',
      email: 'ali@example.com',
      note: 'not',
      apartmentId: 12,
      relation: 'tenant',
      moveInDate: '2026-02-01',
    });
  });

  it('yalniz ad zorunlu; digerleri bos/yok -> null, relation varsayilan resident', () => {
    assert.deepEqual(parsePersonCreateInput({ full_name: 'Ayşe Kaya' }), {
      fullName: 'Ayşe Kaya',
      phone: null,
      email: null,
      note: null,
      apartmentId: null,
      relation: 'resident',
      moveInDate: null,
    });
  });

  it('hatalar alan adiyla 400 INVALID_BODY', () => {
    const cases = [
      [{}, /full_name/],
      [{ full_name: 'Ali', phone: '123' }, /phone/],
      [{ full_name: 'Ali', email: 'bozuk' }, /email/],
      [{ full_name: 'Ali', apartment_id: 'abc' }, /apartment_id/],
      [{ full_name: 'Ali', relation: 'malik' }, /relation/],
      [{ full_name: 'Ali', move_in_date: '2026-02-30' }, /move_in_date/],
      [{ full_name: 'Ali', note: 'x'.repeat(501) }, /note/],
    ];
    for (const [body, pattern] of cases) {
      const result = codeOf(() => parsePersonCreateInput(body));
      assert.equal(result?.code, 'INVALID_BODY', JSON.stringify(body));
      assert.match(result.message, pattern);
    }
  });
});

describe('PATCH apartments girdi ayristirma ve arsa payi', () => {
  it('gecerli degerler; null alani temizler; yalniz gonderilen anahtarlar doner', () => {
    assert.deepEqual(parseApartmentPatch({}), {});
    assert.deepEqual(
      parseApartmentPatch({ floor: 3, gross_area_m2: 120.456, net_area_m2: null, category: '  3+1  ', responsible_party: 'tenant' }),
      { floor: 3, gross_area_m2: 120.46, net_area_m2: null, category: '3+1', responsible_party: 'tenant' },
    );
    assert.deepEqual(parseApartmentPatch({ category: '   ' }), { category: null });
    assert.deepEqual(parseApartmentPatch({ category: null }), { category: null });
    assert.deepEqual(parseApartmentPatch({ floor: -1, unknown_field: 5 }), { floor: -1 });
  });

  it('gecersiz deger 400 INVALID_BODY ve ALAN ADI mesajda', () => {
    const cases = [
      [{ floor: 1.5 }, /floor/],
      [{ floor: '3' }, /floor/],
      [{ floor: 501 }, /floor/],
      [{ gross_area_m2: 0 }, /gross_area_m2/],
      [{ gross_area_m2: -5 }, /gross_area_m2/],
      [{ net_area_m2: '90' }, /net_area_m2/],
      [{ land_share_numerator: -1 }, /land_share_numerator/],
      [{ land_share_denominator: 0 }, /land_share_denominator/],
      [{ category: 'x'.repeat(41) }, /category/],
      [{ category: 5 }, /category/],
      [{ responsible_party: 'kimse' }, /responsible_party/],
    ];
    for (const [body, pattern] of cases) {
      const result = codeOf(() => parseApartmentPatch(body));
      assert.equal(result?.code, 'INVALID_BODY', JSON.stringify(body));
      assert.match(result.message, pattern);
    }
    assert.equal(parseApartmentPatch({ category: 'x'.repeat(40) }).category.length, 40);
  });

  it('mergeLandShare: pay+payda birlikte dolu ya da birlikte bos; payda>0; pay<=payda; tek alan mevcutla birlesir', () => {
    assert.deepEqual(mergeLandShare({ numerator: null, denominator: null }, { land_share_numerator: 35, land_share_denominator: 1000 }), {
      numerator: 35,
      denominator: 1000,
    });
    assert.deepEqual(mergeLandShare({ numerator: 35, denominator: 1000 }, { land_share_numerator: 40 }), { numerator: 40, denominator: 1000 });
    assert.deepEqual(mergeLandShare({ numerator: 35, denominator: 1000 }, { land_share_numerator: null, land_share_denominator: null }), {
      numerator: null,
      denominator: null,
    });
    assert.deepEqual(mergeLandShare({ numerator: null, denominator: null }, { land_share_numerator: 0, land_share_denominator: 5 }), {
      numerator: 0,
      denominator: 5,
    });
    const bad = [
      [{ numerator: null, denominator: null }, { land_share_numerator: 5 }], // yalniz pay
      [{ numerator: null, denominator: null }, { land_share_denominator: 5 }], // yalniz payda
      [{ numerator: 35, denominator: 1000 }, { land_share_denominator: null }], // payda silinip pay kalir
      [{ numerator: 35, denominator: 1000 }, { land_share_numerator: 2000 }], // pay > payda
      [{ numerator: null, denominator: null }, { land_share_numerator: 5, land_share_denominator: 4 }],
    ];
    for (const [current, patch] of bad) {
      const result = codeOf(() => mergeLandShare(current, patch));
      assert.equal(result?.code, 'INVALID_BODY', JSON.stringify(patch));
      assert.match(result.message, /land_share/);
    }
  });
});

describe('redactManagerNotes (H14: kurul uyesine yonetici ic notu verilmez)', () => {
  it('kisi ve arac note alanlari null olur; anahtar ve diger alanlar korunur; girdi degismez', () => {
    const body = {
      id: 5,
      full_name: 'Ali Veli',
      note: 'ic not',
      vehicles: [{ id: 4, plate: '34ABC123', note: 'arac ic notu' }],
      items: [{ id: 1, note: 'x', details: { changes: [{ field: 'note', changed: true }] } }],
    };
    const redacted = redactManagerNotes(body);
    assert.equal(redacted.note, null);
    assert.equal(redacted.vehicles[0].note, null);
    assert.equal(redacted.items[0].note, null);
    assert.equal(redacted.full_name, 'Ali Veli');
    assert.equal(redacted.vehicles[0].plate, '34ABC123');
    assert.deepEqual(redacted.items[0].details.changes, [{ field: 'note', changed: true }], 'field:note alan ADI kalir (deger yok)');
    assert.equal(body.note, 'ic not', 'girdi degismez');
    assert.equal(JSON.stringify(redacted).includes('ic not'), false);
    assert.equal(JSON.stringify(redacted).includes('arac ic notu'), false);
  });

  it('ilkel degerler, null ve tarih nesneleri aynen doner', () => {
    const date = new Date('2026-10-14T08:00:00.000Z');
    assert.equal(redactManagerNotes(null), null);
    assert.equal(redactManagerNotes('x'), 'x');
    assert.equal(redactManagerNotes(date), date);
    assert.deepEqual(redactManagerNotes([1, { note: 2 }]), [1, { note: null }]);
  });
});

describe('redactForReadOnlyRole (S9: kurul uyesi icin not + kullanici kodu temizligi)', () => {
  it('note null olur; actor_user_code / user_code / created_by alanlari yanittan CIKARILIR; diger alanlar korunur; girdi degismez', () => {
    const body = {
      user_code: 30001,
      note: 'ic not',
      items: [{ id: 1, actor_user_code: 20001, actor_name: 'Ayse', note: null, details: { changes: [{ field: 'note', changed: true }], created_by: 7 } }],
    };
    const redacted = redactForReadOnlyRole(body);
    assert.equal('user_code' in redacted, false);
    assert.equal(redacted.note, null);
    assert.equal('actor_user_code' in redacted.items[0], false);
    assert.equal('created_by' in redacted.items[0].details, false);
    assert.equal(redacted.items[0].actor_name, 'Ayse');
    assert.deepEqual(redacted.items[0].details.changes, [{ field: 'note', changed: true }]);
    assert.equal(body.user_code, 30001, 'girdi degismez');
    assert.equal(body.items[0].actor_user_code, 20001);
  });
});
