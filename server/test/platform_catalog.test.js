// Platform modul sistemi: katalog hesabi, yonetim turleri ve mapSiteRow (saf, DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  DOOR_CONTROL_DISABLE_WARNING,
  MODULE_CATALOG,
  MODULE_CODES,
  computeEnabledMap,
  computeModuleEnabled,
  computeSiteModuleList,
  getModuleDefinition,
  isToggleable,
  publicCatalog,
} from '../src/modules/catalog.js';
import {
  DEFAULT_MANAGEMENT_TYPE,
  MANAGEMENT_TYPES,
  isKnownManagementType,
  managementTypeLabel,
  normalizeManagementType,
  resolveManagementTypeInput,
} from '../src/modules/management_types.js';
import { mapSiteRow } from '../src/utils/helpers.js';
import { managementTerms } from '../src/modules/management_type_terms.js';

const def = (code) => getModuleDefinition(code);

describe('platform katalog: sozlesme tablosu', () => {
  it('18 modul, sozlesmedeki sirayla ve alanlarla', () => {
    assert.deepEqual(MODULE_CODES, [
      'door_control',
      'people',
      'announcements',
      'finance',
      'documents',
      'reservation',
      'work_tracking',
      'metering',
      'online_payment',
      'survey',
      'visitor_log',
      'card_access',
      'contracts',
      'decision_book',
      'directory',
      'budget',
      'drive_storage',
      'plate_recognition',
      'hgs_access',
      'cctv_link',
    ]);
    const table = Object.fromEntries(MODULE_CATALOG.map((m) => [m.code, [m.core, m.status]]));
    assert.deepEqual(table, {
      door_control: [false, 'available'],
      people: [true, 'available'], // Faz 2a: Kişi ve Daire Kayıtları çekirdek + kullanılabilir (hep açık)
      announcements: [true, 'available'], // Faz 3a: Duyuru ve Bildirim çekirdek + kullanılabilir (hep açık)
      finance: [false, 'available'], // Faz 4a: Aidat ve Finans kullanılabilir (varsayılan KAPALI; süper açar, yönetici modül talep eder)
      documents: [false, 'available'], // Faz 3b-A: Belgeler (Dosya Deposu) kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      reservation: [false, 'available'], // Rezervasyon ve Konsiyerj: kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      work_tracking: [false, 'available'], // Is Takibi: kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      metering: [false, 'available'],
      online_payment: [false, 'coming_soon'],
      survey: [false, 'available'], // Anket ve Oylama: kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      visitor_log: [false, 'available'], // Ziyaretci ve Kargo (F11.03): kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      card_access: [false, 'available'], // F10: Kartli Gecis kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      contracts: [false, 'available'], // Firma ve Sozlesme Takibi: kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      decision_book: [false, 'available'], // Karar Defteri: kullanilabilir (varsayilan KAPALI; super acar, yonetici modul talep eder)
      directory: [false, 'available'], // Rehber: kullanilabilir (varsayilan KAPALI; yonetim kadrosu ve faydali telefonlar)
      budget: [false, 'available'], // Isletme Projesi (F7): kullanilabilir (varsayilan KAPALI)
      drive_storage: [false, 'available'], // Dosya Deposu (Google Drive, D1): varsayilan KAPALI
      plate_recognition: [false, 'coming_soon'],
      hgs_access: [false, 'coming_soon'],
      cctv_link: [false, 'coming_soon'],
    });
    assert.equal(def('door_control').name, 'Geçiş Kontrol (SmartKeyPass)');
    assert.equal(def('people').name, 'Kişi ve Daire Kayıtları');
    assert.equal(def('online_payment').name, 'Online Tahsilat ve Banka Bağlantısı');
  });

  it('her modulun Turkce kisa aciklamasi var', () => {
    for (const module of MODULE_CATALOG) {
      assert.equal(typeof module.description, 'string');
      assert.ok(module.description.length >= 10 && module.description.length <= 120, module.code);
      assert.ok(module.description.endsWith('.'), module.code);
    }
  });

  it('publicCatalog yalnizca { code, name, description, core, status } alanlarini dondurur', () => {
    const catalog = publicCatalog();
    assert.equal(catalog.length, 18);
    for (const entry of catalog) {
      assert.deepEqual(Object.keys(entry), ['code', 'name', 'description', 'core', 'status']);
    }
  });

  it('katalog degistirilemez (dondurulmus) ve bilinmeyen/prototype anahtarlari tanimsizdir', () => {
    assert.ok(Object.isFrozen(MODULE_CATALOG));
    assert.ok(Object.isFrozen(MODULE_CATALOG[0]));
    for (const code of ['__proto__', 'constructor', 'toString', 'nope', '', null, undefined, 5, {}]) {
      assert.equal(getModuleDefinition(code), null, String(code));
    }
  });

  it('toggleable = !core && status === available (door_control, finance, documents, rezervasyon, is takibi, anket, ziyaretci, kartli gecis, sozlesmeler, karar defteri)', () => {
    assert.deepEqual(
      MODULE_CATALOG.filter(isToggleable).map((m) => m.code),
      ['door_control', 'finance', 'documents', 'reservation', 'work_tracking', 'survey', 'visitor_log', 'card_access', 'contracts', 'decision_book', 'directory'],
      ['door_control', 'finance', 'documents', 'reservation', 'work_tracking', 'survey', 'visitor_log', 'card_access', 'contracts', 'decision_book', 'budget'],
      ['door_control', 'finance', 'documents', 'reservation', 'work_tracking', 'survey', 'visitor_log', 'card_access', 'contracts', 'decision_book', 'drive_storage'],
      ['door_control', 'finance', 'documents', 'reservation', 'work_tracking', 'metering', 'survey', 'visitor_log', 'card_access', 'contracts', 'decision_book'],
    );
    assert.equal(isToggleable(null), false);
  });

  it('onay metni sozlesmedekiyle birebir ayni', () => {
    assert.equal(
      DOOR_CONTROL_DISABLE_WARNING,
      'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?',
    );
    assert.equal(def('door_control').confirmOnDisable, DOOR_CONTROL_DISABLE_WARNING);
    assert.equal(def('finance').confirmOnDisable, null);
  });
});

describe('platform katalog: enabled hesabi', () => {
  it('satiri olmayan site katalog varsayilanina gore davranir: door_control ACIK', () => {
    assert.equal(computeModuleEnabled(def('door_control'), undefined), true);
    assert.equal(computeModuleEnabled(def('door_control'), null), true);
    assert.equal(computeModuleEnabled(def('door_control'), {}), true);
  });

  it('door_control satiri varsa satirin enabled degeri gecerlidir', () => {
    assert.equal(computeModuleEnabled(def('door_control'), { enabled: false }), false);
    assert.equal(computeModuleEnabled(def('door_control'), { enabled: true }), true);
  });

  it('status !== available ise HER ZAMAN false (satir ne derse desin)', () => {
    for (const code of ['online_payment', 'plate_recognition', 'hgs_access', 'cctv_link']) {
      assert.equal(computeModuleEnabled(def(code), undefined), false, code);
      assert.equal(computeModuleEnabled(def(code), { enabled: true }), false, code);
    }
  });

  it('finance (Faz 4a): available + toggleable, varsayilan KAPALI; satir yoksa kapali, satir true ise acik, satir false ise kapali', () => {
    assert.equal(def('finance').status, 'available');
    assert.equal(def('finance').core, false);
    assert.equal(def('finance').defaultEnabled, false);
    assert.equal(isToggleable(def('finance')), true);
    assert.equal(computeModuleEnabled(def('finance'), undefined), false);
    assert.equal(computeModuleEnabled(def('finance'), null), false);
    assert.equal(computeModuleEnabled(def('finance'), {}), false);
    assert.equal(computeModuleEnabled(def('finance'), { enabled: true }), true);
    assert.equal(computeModuleEnabled(def('finance'), { enabled: false }), false);
  });

  it('people (Faz 2a): core + available -> HEP acik (satir olmasa da, satir false dese de) ve kapatilamaz', () => {
    assert.equal(def('people').core, true);
    assert.equal(def('people').status, 'available');
    assert.equal(computeModuleEnabled(def('people'), undefined), true);
    assert.equal(computeModuleEnabled(def('people'), { enabled: false }), true);
    assert.equal(isToggleable(def('people')), false);
    assert.equal(computeEnabledMap([]).people, true);
    assert.equal(computeEnabledMap([{ module_code: 'people', enabled: false }]).people, true);
  });

  it('announcements (Faz 3a): core + available -> HEP acik (satir olmasa da, satir false dese de) ve kapatilamaz', () => {
    assert.equal(def('announcements').core, true);
    assert.equal(def('announcements').status, 'available');
    assert.equal(computeModuleEnabled(def('announcements'), undefined), true);
    assert.equal(computeModuleEnabled(def('announcements'), { enabled: false }), true);
    assert.equal(isToggleable(def('announcements')), false);
    assert.equal(computeEnabledMap([]).announcements, true);
    assert.equal(computeEnabledMap([{ module_code: 'announcements', enabled: false }]).announcements, true);
  });

  it('core + available ise her zaman true (sozlesme kurali sirasi: once status, sonra core)', () => {
    const futureCore = { code: 'x', core: true, status: 'available', defaultEnabled: true };
    assert.equal(computeModuleEnabled(futureCore, { enabled: false }), true);
    const comingCore = { code: 'y', core: true, status: 'coming_soon', defaultEnabled: true };
    assert.equal(computeModuleEnabled(comingCore, undefined), false);
  });

  it('bilinmeyen tanim false', () => {
    assert.equal(computeModuleEnabled(null, { enabled: true }), false);
    assert.equal(computeModuleEnabled(undefined, undefined), false);
  });

  it('computeEnabledMap katalogdaki TUM kodlari icerir; satir dizisi veya Map kabul eder', () => {
    const empty = computeEnabledMap([]);
    assert.deepEqual(Object.keys(empty), MODULE_CODES);
    assert.equal(empty.door_control, true);
    assert.equal(empty.finance, false);

    const closed = computeEnabledMap([{ module_code: 'door_control', enabled: false }]);
    assert.equal(closed.door_control, false);

    const fromMap = computeEnabledMap(new Map([['door_control', { enabled: false }]]));
    assert.equal(fromMap.door_control, false);

    // katalogda olmayan kod yok sayilir
    const unknown = computeEnabledMap([{ module_code: 'baska', enabled: true }]);
    assert.deepEqual(Object.keys(unknown), MODULE_CODES);
  });

  it('computeSiteModuleList: alanlar, toggleable, updated_at ISO ve updated_by', () => {
    const when = new Date('2026-10-14T09:30:00.000Z');
    const list = computeSiteModuleList([
      { module_code: 'door_control', enabled: false, updated_at: when, updated_by_name: 'Ali Veli' },
    ]);
    assert.equal(list.length, 18);
    const door = list.find((m) => m.code === 'door_control');
    assert.deepEqual(door, {
      code: 'door_control',
      name: 'Geçiş Kontrol (SmartKeyPass)',
      description: def('door_control').description,
      core: false,
      status: 'available',
      enabled: false,
      toggleable: true,
      updated_at: '2026-10-14T09:30:00.000Z',
      updated_by: 'Ali Veli',
    });
    const people = list.find((m) => m.code === 'people');
    assert.equal(people.enabled, true, 'people çekirdek + available: her sitede açık');
    assert.equal(people.status, 'available');
    assert.equal(people.toggleable, false);
    assert.equal(people.updated_at, null);
    assert.equal(people.updated_by, null);
    const finance = list.find((m) => m.code === 'finance');
    assert.equal(finance.toggleable, true, 'Faz 4a: finance artık kullanılabilir ve açılıp kapatılabilir');
    assert.equal(finance.status, 'available');
    assert.equal(finance.enabled, false, 'varsayılan KAPALI');
    const reservation = list.find((m) => m.code === 'reservation');
    assert.equal(reservation.toggleable, true, 'Rezervasyon ve Konsiyerj kullanilabilir ve acilip kapatilabilir');
    assert.equal(reservation.status, 'available');
    assert.equal(reservation.enabled, false, 'varsayilan KAPALI');
    const metering = list.find((m) => m.code === 'metering');
    assert.equal(metering.toggleable, true);
    assert.equal(metering.status, 'available');
  });
});

describe('platform yonetim turleri', () => {
  it('5 tur ve etiketler; hepsi secilebilir', () => {
    assert.deepEqual(
      MANAGEMENT_TYPES.map((t) => [t.code, t.label, t.selectable]),
      [
        ['apartment_site', 'Apartman ve Site', true],
        ['residence', 'Rezidans', true],
        ['business_center', 'İş Merkezi', true],
        ['cooperative', 'Kooperatif', true],
        ['shopping_mall', 'Alışveriş Merkezi', true],
      ],
    );
    assert.equal(DEFAULT_MANAGEMENT_TYPE, 'apartment_site');
  });

  it('resolveManagementTypeInput: yok/bos -> apartment_site', () => {
    for (const raw of [undefined, null, '', '   ']) {
      assert.deepEqual(resolveManagementTypeInput(raw), { ok: true, value: 'apartment_site' });
    }
    assert.deepEqual(resolveManagementTypeInput('apartment_site'), { ok: true, value: 'apartment_site' });
    assert.deepEqual(resolveManagementTypeInput(' apartment_site '), { ok: true, value: 'apartment_site' });
  });

  it('tum turler secilebilir: gonderilen deger aynen kabul edilir', () => {
    for (const raw of ['apartment_site', 'residence', 'business_center', 'cooperative', 'shopping_mall']) {
      assert.deepEqual(resolveManagementTypeInput(raw), { ok: true, value: raw });
    }
  });

  it('bilinmeyen / metin olmayan deger 400 MANAGEMENT_TYPE_INVALID ("Geçersiz yönetim türü.")', () => {
    for (const raw of ['hotel', 'APARTMENT_SITE', 'apartment site', 5, true, {}, []]) {
      const result = resolveManagementTypeInput(raw);
      assert.equal(result.ok, false, String(raw));
      assert.equal(result.statusCode, 400);
      assert.equal(result.code, 'MANAGEMENT_TYPE_INVALID');
      assert.equal(result.error, 'Geçersiz yönetim türü.');
    }
  });

  it('normalizeManagementType / managementTypeLabel bilinmeyende apartment_site\'a duser', () => {
    assert.equal(normalizeManagementType(undefined), 'apartment_site');
    assert.equal(normalizeManagementType('hotel'), 'apartment_site');
    assert.equal(normalizeManagementType('residence'), 'residence');
    assert.equal(managementTypeLabel('shopping_mall'), 'Alışveriş Merkezi');
    assert.equal(managementTypeLabel(null), 'Apartman ve Site');
    assert.equal(isKnownManagementType('cooperative'), true);
    assert.equal(isKnownManagementType('x'), false);
  });
});

describe('platform: mapSiteRow management_type', () => {
  it('satirda yoksa apartment_site + etiket (eski sorgular bozulmaz)', () => {
    const mapped = mapSiteRow({ id: 1, name: 'S', created_at: new Date() });
    assert.equal(mapped.management_type, 'apartment_site');
    assert.equal(mapped.management_type_label, 'Apartman ve Site');
  });

  it('satirdaki tur ve etiketi dondurur; bilinmeyen deger apartment_site olur', () => {
    const mapped = mapSiteRow({ id: 1, name: 'S', management_type: 'residence', created_at: new Date() });
    assert.equal(mapped.management_type, 'residence');
    assert.equal(mapped.management_type_label, 'Rezidans');
    assert.equal(mapSiteRow({ id: 1, name: 'S', management_type: 'garip' }).management_type, 'apartment_site');
  });
});

describe('F9: mapSiteRow management_terms (ekleyici alan)', () => {
  it('satirda tur yoksa varsayilan Daire/Sakin/Malik/Aidat/Blok terimleri; mevcut alanlar degismez', () => {
    const mapped = mapSiteRow({ id: 1, name: 'S', created_at: new Date() });
    assert.deepEqual(mapped.management_terms, managementTerms('apartment_site'));
    assert.deepEqual(mapped.management_terms, {
      unit: 'Daire',
      unit_plural: 'Daireler',
      resident: 'Sakin',
      resident_plural: 'Sakinler',
      owner: 'Malik',
      fee: 'Aidat',
      block: 'Blok',
      block_plural: 'Bloklar',
    });
    assert.equal(mapped.management_type, 'apartment_site');
    assert.equal(mapped.management_type_label, 'Apartman ve Site');
  });

  it('business_center satiri Ofis/Firma terimlerini tasir; bilinmeyen tur varsayilana duser', () => {
    const mapped = mapSiteRow({ id: 1, name: 'S', management_type: 'business_center' });
    assert.equal(mapped.management_terms.unit, 'Ofis');
    assert.equal(mapped.management_terms.resident_plural, 'Firmalar');
    assert.equal(mapped.management_terms.owner, 'Mal sahibi');
    assert.equal(mapped.management_terms.fee, 'Ortak gider');
    assert.equal(mapped.management_terms.block_plural, 'Katlar');
    assert.equal(mapSiteRow({ id: 1, name: 'S', management_type: 'garip' }).management_terms.unit, 'Daire');
  });
});
