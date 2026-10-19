// F9 yonetim turu terim katmani (saf, DB'siz): terimler, onerilen moduller, ozetler ve /app/management-types gorunumu.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { MODULE_CODES } from '../src/modules/catalog.js';
import { MANAGEMENT_TYPES } from '../src/modules/management_types.js';
import {
  DEFAULT_MANAGEMENT_TERMS,
  MANAGEMENT_TERM_KEYS,
  MANAGEMENT_TYPE_RECOMMENDED_MODULES,
  MANAGEMENT_TYPE_SUMMARIES,
  MANAGEMENT_TYPE_TERMS,
  isRecommendedModule,
  listManagementTypesView,
  managementTerms,
  managementTypeSummary,
  recommendedModules,
} from '../src/modules/management_type_terms.js';

const TYPE_CODES = ['apartment_site', 'residence', 'business_center', 'cooperative', 'shopping_mall'];

describe('F9 terimler: sozlesme tablosu', () => {
  it('her tur icin 8 terim, sozlesmedeki degerlerle', () => {
    assert.deepEqual(Object.keys(MANAGEMENT_TYPE_TERMS), TYPE_CODES);
    const row = (code) => MANAGEMENT_TERM_KEYS.map((key) => MANAGEMENT_TYPE_TERMS[code][key]);
    assert.deepEqual(row('apartment_site'), ['Daire', 'Daireler', 'Sakin', 'Sakinler', 'Malik', 'Aidat', 'Blok', 'Bloklar']);
    assert.deepEqual(row('residence'), ['Daire', 'Daireler', 'Sakin', 'Sakinler', 'Malik', 'Aidat', 'Blok', 'Bloklar']);
    assert.deepEqual(row('business_center'), ['Ofis', 'Ofisler', 'Firma', 'Firmalar', 'Mal sahibi', 'Ortak gider', 'Kat', 'Katlar']);
    assert.deepEqual(row('cooperative'), ['Hisse', 'Hisseler', 'Üye', 'Üyeler', 'Üye', 'Üye aidatı', 'Blok', 'Bloklar']);
    assert.deepEqual(row('shopping_mall'), [
      'Mağaza',
      'Mağazalar',
      'Kiracı firma',
      'Kiracı firmalar',
      'Mal sahibi',
      'Ortak gider',
      'Kat',
      'Katlar',
    ]);
    for (const code of TYPE_CODES) {
      assert.deepEqual(Object.keys(MANAGEMENT_TYPE_TERMS[code]), [...MANAGEMENT_TERM_KEYS], code);
      for (const key of MANAGEMENT_TERM_KEYS) {
        const value = MANAGEMENT_TYPE_TERMS[code][key];
        assert.equal(typeof value, 'string');
        assert.ok(value.length > 0 && !value.includes('_'), `${code}.${key}`);
      }
    }
  });

  it('varsayilan terimler apartment_site ile aynidir; tablo donmus (degistirilemez)', () => {
    assert.deepEqual(DEFAULT_MANAGEMENT_TERMS, MANAGEMENT_TYPE_TERMS.apartment_site);
    assert.ok(Object.isFrozen(MANAGEMENT_TYPE_TERMS));
    assert.ok(Object.isFrozen(MANAGEMENT_TYPE_TERMS.business_center));
    assert.ok(Object.isFrozen(MANAGEMENT_TYPE_RECOMMENDED_MODULES.residence));
  });

  it('managementTerms: bilinen tur, bilinmeyen/bos tur -> varsayilan; donen nesne kopyadir', () => {
    assert.equal(managementTerms('business_center').unit, 'Ofis');
    assert.equal(managementTerms('shopping_mall').resident_plural, 'Kiracı firmalar');
    for (const raw of [undefined, null, '', 'hotel', 5]) {
      assert.deepEqual(managementTerms(raw), DEFAULT_MANAGEMENT_TERMS, String(raw));
    }
    const copy = managementTerms('cooperative');
    copy.unit = 'X';
    assert.equal(managementTerms('cooperative').unit, 'Hisse', 'kaynak tablo degismez');
  });
});

describe('F9 onerilen moduller', () => {
  it('sozlesmedeki listeler ve sira', () => {
    assert.deepEqual(recommendedModules('apartment_site'), ['door_control', 'finance', 'documents', 'announcements']);
    assert.deepEqual(recommendedModules('residence'), ['reservation', 'visitor_log', 'work_tracking', 'door_control', 'finance']);
    assert.deepEqual(recommendedModules('business_center'), ['work_tracking', 'visitor_log', 'finance', 'documents']);
    assert.deepEqual(recommendedModules('cooperative'), ['finance', 'documents', 'announcements', 'survey']);
    assert.deepEqual(recommendedModules('shopping_mall'), ['finance', 'work_tracking', 'visitor_log', 'documents']);
  });

  it('onerilen kodlarin hepsi katalogda vardir (survey, visitor_log katalogda; bilinmeyen kod olsaydi oldugu gibi donerdi)', () => {
    const unknown = new Set();
    for (const code of TYPE_CODES) {
      for (const moduleCode of recommendedModules(code)) {
        if (!MODULE_CODES.includes(moduleCode)) unknown.add(moduleCode);
      }
    }
    assert.deepEqual([...unknown].sort(), []);
  });

  it('bilinmeyen tur -> apartment_site onerileri; donen dizi kopyadir', () => {
    assert.deepEqual(recommendedModules('garip'), recommendedModules('apartment_site'));
    const copy = recommendedModules('residence');
    copy.push('x');
    assert.equal(recommendedModules('residence').length, 5);
  });

  it('isRecommendedModule: tur+modul; bilinmeyen modul/tur guvenli', () => {
    assert.equal(isRecommendedModule('business_center', 'work_tracking'), true);
    assert.equal(isRecommendedModule('business_center', 'door_control'), false);
    assert.equal(isRecommendedModule('cooperative', 'survey'), true);
    assert.equal(isRecommendedModule('garip', 'door_control'), true, 'bilinmeyen tur apartment_site gibi');
    assert.equal(isRecommendedModule('apartment_site', undefined), false);
    assert.equal(isRecommendedModule('apartment_site', 'yok'), false);
  });
});

describe('F9 tur aciklamalari ve /app/management-types gorunumu', () => {
  it('her tur icin Turkce tek cumle; "Yakinda" gecmez', () => {
    assert.deepEqual(Object.keys(MANAGEMENT_TYPE_SUMMARIES), TYPE_CODES);
    for (const code of TYPE_CODES) {
      const summary = managementTypeSummary(code);
      assert.equal(typeof summary, 'string');
      assert.ok(summary.length >= 20 && summary.length <= 200, code);
      assert.ok(!/yak[ıi]nda/i.test(summary), `${code}: "Yakında" dememeli`);
      assert.ok(!summary.includes('_'), code);
    }
    assert.equal(managementTypeSummary('garip'), managementTypeSummary('apartment_site'));
  });

  it('listManagementTypesView: MANAGEMENT_TYPES sirasiyla 5 oge, sozlesme alanlari', () => {
    const items = listManagementTypesView();
    assert.deepEqual(items.map((i) => i.code), MANAGEMENT_TYPES.map((t) => t.code));
    for (const item of items) {
      assert.deepEqual(Object.keys(item), ['code', 'label', 'selectable', 'terms', 'recommended_modules', 'summary']);
      assert.equal(item.selectable, true);
      assert.deepEqual(item.terms, managementTerms(item.code));
      assert.deepEqual(item.recommended_modules, recommendedModules(item.code));
      assert.equal(item.summary, managementTypeSummary(item.code));
    }
    const mall = items.find((i) => i.code === 'shopping_mall');
    assert.equal(mall.label, 'Alışveriş Merkezi');
    assert.equal(mall.terms.unit, 'Mağaza');
    // JSON'a cevrilebilir (route dogrudan json'lar)
    assert.equal(JSON.parse(JSON.stringify({ items })).items.length, 5);
  });
});
