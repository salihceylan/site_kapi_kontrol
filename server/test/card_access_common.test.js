// Kartlı Geçiş ortak mantık (DB'siz): UID normalizasyonu, etiket, maske, girdi ayrıştırıcıları, yanıt eşleyicileri (sakin görünümünde UID maskeli / kişi kimliği yok).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  CARD_ACCESS_MODULE,
  cardExists,
  invalidState,
  mapManagerCard,
  mapResidentCard,
  maskCardUid,
  moduleDisabled,
  normalizeCardUid,
  normalizeLabel,
  parseCardUid,
  parseCreateInput,
  parseListQuery,
  parseResidentListQuery,
  personNotFound,
} from '../src/modules/card_access_common.js';

const fails = (fn, status, code) => assert.throws(fn, (error) => error.statusCode === status && error.code === code);

describe('kart UID normalizasyonu', () => {
  it('ayraçlar atılır, büyük harfe çevrilir; 4-32 harf/rakam dışı null', () => {
    assert.equal(normalizeCardUid('04:a3 b2-c1'), '04A3B2C1');
    assert.equal(normalizeCardUid('  zz.99  '), 'ZZ99');
    assert.equal(normalizeCardUid('A'.repeat(32)), 'A'.repeat(32));
    assert.equal(normalizeCardUid('abc'), null, '3 karakter kısa');
    assert.equal(normalizeCardUid('A'.repeat(33)), null, '33 karakter uzun');
    assert.equal(normalizeCardUid('04A3_B2'), null, 'alt çizgi yasak');
    assert.equal(normalizeCardUid('ÇAĞ1'), null, 'ASCII dışı harf yasak');
    for (const value of [null, undefined, 12345, {}, []]) assert.equal(normalizeCardUid(value), null);
  });

  it('parseCardUid: geçersiz 400 CARD_UID_INVALID; geçerli kanonik döner', () => {
    fails(() => parseCardUid('ab'), 400, 'CARD_UID_INVALID');
    fails(() => parseCardUid(undefined), 400, 'CARD_UID_INVALID');
    assert.equal(parseCardUid('04:a3:b2:c1'), '04A3B2C1');
  });

  it('maske: yalnız son 4 karakter açık; kısa UID de tamamen açılmaz', () => {
    assert.equal(maskCardUid('04A3B2C1D5'), '******C1D5');
    assert.equal(maskCardUid('ABCDE'), '****BCDE');
    assert.equal(maskCardUid('ABCD'), '****ABCD');
    assert.ok(!maskCardUid('04A3B2C1D5').includes('04A3'));
  });
});

describe('etiket ve gövde', () => {
  it('etiket isteğe bağlı: boş / null -> null; boşluklar sıkıştırılır; 60 üstü 400 INVALID_BODY; metin dışı 400', () => {
    assert.equal(normalizeLabel(undefined), null);
    assert.equal(normalizeLabel(''), null);
    assert.equal(normalizeLabel('  Ana   kapı  '), 'Ana kapı');
    assert.equal(normalizeLabel('x'.repeat(60)), 'x'.repeat(60));
    fails(() => normalizeLabel('x'.repeat(61)), 400, 'INVALID_BODY');
    fails(() => normalizeLabel(5), 400, 'INVALID_BODY');
  });

  it('parseCreateInput: person_id zorunlu pozitif tamsayı; card_uid normalize; label isteğe bağlı', () => {
    assert.deepEqual(parseCreateInput({ person_id: 7, card_uid: '04:a3:b2:c1', label: ' Kart 1 ' }), { personId: 7, cardUid: '04A3B2C1', label: 'Kart 1' });
    assert.deepEqual(parseCreateInput({ person_id: '12', card_uid: 'abcd' }), { personId: 12, cardUid: 'ABCD', label: null });
    fails(() => parseCreateInput({ card_uid: 'ABCD' }), 400, 'INVALID_BODY');
    fails(() => parseCreateInput({ person_id: 0, card_uid: 'ABCD' }), 400, 'INVALID_BODY');
    fails(() => parseCreateInput({ person_id: 1, card_uid: 'ab' }), 400, 'CARD_UID_INVALID');
    fails(() => parseCreateInput(null), 400, 'INVALID_BODY');
    fails(() => parseCreateInput([]), 400, 'INVALID_BODY');
  });
});

describe('sorgu ayrıştırıcıları', () => {
  it('liste: varsayılan status=active, limit 50, offset 0; status değerleri; geçersiz 400 INVALID_QUERY', () => {
    assert.deepEqual(parseListQuery({}), { personId: null, q: null, status: 'active', limit: 50, offset: 0 });
    assert.deepEqual(parseListQuery({ status: 'revoked', person_id: '9', q: ' ali ', limit: '10', offset: '20' }), { personId: 9, q: 'ali', status: 'revoked', limit: 10, offset: 20 });
    assert.equal(parseListQuery({ status: 'all' }).status, 'all');
    assert.equal(parseListQuery({ limit: '999' }).limit, 200);
    fails(() => parseListQuery({ status: 'bogus' }), 400, 'INVALID_QUERY');
    fails(() => parseListQuery({ person_id: 'x' }), 400, 'INVALID_QUERY');
    fails(() => parseListQuery({ offset: '-1' }), 400, 'INVALID_QUERY');
  });

  it('sakin listesi: site_code isteğe bağlı; geçersiz 400', () => {
    assert.deepEqual(parseResidentListQuery({}), { siteCode: null });
    assert.deepEqual(parseResidentListQuery({ site_code: '1000000001' }), { siteCode: 1000000001 });
    fails(() => parseResidentListQuery({ site_code: 'abc' }), 400, 'INVALID_QUERY');
  });
});

describe('yanıt eşleyicileri ve hatalar', () => {
  const row = {
    id: '5', site_code: '1000000001', person_id: '42', person_name: 'Ali Veli', card_uid: '04A3B2C1D5', label: 'Kart 1', is_active: true, revoked_at: null,
    created_at: new Date('2026-10-19T10:00:00.000Z'), apartments: [{ b: 'A Blok', u: 'Daire 3' }, { b: null, u: 'Daire 9' }], site_name: 'Site',
  };

  it('yönetim görünümü: UID açık, kişi adı ve daire etiketleri, sayısal kimlikler', () => {
    assert.deepEqual(mapManagerCard(row), {
      id: 5, person_id: 42, person_name: 'Ali Veli', apartment_labels: ['A Blok - Daire 3', 'Daire 9'], card_uid: '04A3B2C1D5', label: 'Kart 1', is_active: true,
      revoked_at: null, created_at: '2026-10-19T10:00:00.000Z',
    });
    assert.deepEqual(mapManagerCard({ ...row, apartments: null, person_name: null, label: null }).apartment_labels, []);
  });

  it('sakin görünümü: UID MASKELİ, kişi kimliği / adı YOK', () => {
    const mapped = mapResidentCard({ ...row, is_active: false, revoked_at: new Date('2026-10-19T11:00:00.000Z') });
    assert.deepEqual(mapped, { id: 5, site_code: 1000000001, site_name: 'Site', masked_uid: '******C1D5', label: 'Kart 1', is_active: false, revoked_at: '2026-10-19T11:00:00.000Z', created_at: '2026-10-19T10:00:00.000Z' });
    assert.ok(!('card_uid' in mapped) && !('person_id' in mapped) && !('person_name' in mapped));
  });

  it('hata sözleşmesi: MODULE_DISABLED { module: card_access }, CARD_EXISTS 409, INVALID_STATE 409, PERSON_NOT_FOUND 404; mesajlar Türkçe ve alt çizgisiz', () => {
    assert.equal(CARD_ACCESS_MODULE, 'card_access');
    const disabled = moduleDisabled();
    assert.deepEqual([disabled.statusCode, disabled.code, disabled.extra], [403, 'MODULE_DISABLED', { module: 'card_access' }]);
    assert.deepEqual([cardExists().statusCode, cardExists().code], [409, 'CARD_EXISTS']);
    assert.deepEqual([invalidState().statusCode, invalidState().code], [409, 'INVALID_STATE']);
    assert.deepEqual([personNotFound().statusCode, personNotFound().code], [404, 'PERSON_NOT_FOUND']);
    for (const error of [disabled, cardExists(), invalidState(), personNotFound()]) {
      assert.ok(!error.message.includes('_') && error.message.length < 140, error.message);
    }
  });
});
