// Site başvurusu ortak kuralları (DB'siz): serbest metin, sorgu parametreleri, saklanan yapının yeniden doğrulanması, yanıt eşleyicileri.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSetupSiteInput } from '../src/services/membership_rules.js';
import { SITE_LIMITS } from '../src/utils/validators.js';
import { isPlatformError } from '../src/modules/errors.js';
import {
  APPLICATION_DAILY_LIMIT,
  likePattern,
  mapApplicationRow,
  mapApprovedSite,
  normalizeDeviceUid,
  normalizeFreeText,
  onboardingModeOf,
  parseListLimit,
  parseOffset,
  parseSearch,
  parseStatusFilter,
  revalidateStoredStructure,
  toIso,
} from '../src/modules/site_application_common.js';

const chr = (...codes) => String.fromCodePoint(...codes);

function rejects(fn, status, code) {
  assert.throws(fn, (error) => isPlatformError(error) && error.statusCode === status && error.code === code, `${status} ${code}`);
}

describe('normalizeFreeText (not / gerekçe)', () => {
  it('yok / null -> null; boş ve yalnız boşluk -> null; metin kırpılır', () => {
    assert.equal(normalizeFreeText(undefined, 'Not', 500), null);
    assert.equal(normalizeFreeText(null, 'Not', 500), null);
    assert.equal(normalizeFreeText('   ', 'Not', 500), null);
    assert.equal(normalizeFreeText('  Merhaba  ', 'Not', 500), 'Merhaba');
  });

  it('metin olmayan -> 400 INVALID_BODY (Türkçe etiketle)', () => {
    for (const bad of [5, true, {}, [], ['a']]) {
      assert.throws(
        () => normalizeFreeText(bad, 'Gerekçe', 300),
        (error) => error.statusCode === 400 && error.code === 'INVALID_BODY' && error.message === 'Gerekçe metin olmalıdır.',
      );
    }
  });

  it('en çok N karakter (kod noktası): sınırda kabul, aşınca 400; emoji tek karakter sayılır', () => {
    assert.equal(normalizeFreeText('a'.repeat(500), 'Not', 500).length, 500);
    rejects(() => normalizeFreeText('a'.repeat(501), 'Not', 500), 400, 'INVALID_BODY');
    const emoji = chr(0x1f600);
    assert.equal(Array.from(normalizeFreeText(emoji.repeat(300), 'Gerekçe', 300)).length, 300);
    rejects(() => normalizeFreeText(emoji.repeat(301), 'Gerekçe', 300), 400, 'INVALID_BODY');
  });

  it('kontrol, yön ve görünmez karakterler atılır; satır sonu LF olur; sekme korunur', () => {
    const dirty = `a${chr(0)}b${chr(7)}c${chr(0x202e)}d${chr(0x200b)}e${chr(0xfeff)}f${chr(0x2028)}g${chr(0x2066)}h${chr(127)}i`;
    assert.equal(normalizeFreeText(dirty, 'Not', 500), 'abcdefghi');
    assert.equal(normalizeFreeText('x\r\ny\rz\tw', 'Not', 500), 'x\ny\nz\tw');
    // emoji bağlayıcısı (ZWJ) korunur: aile emojisi bozulmaz
    const family = `${chr(0x1f468)}${chr(0x200d)}${chr(0x1f469)}`;
    assert.equal(normalizeFreeText(family, 'Not', 500), family);
  });

  it('başlık enjeksiyonu: CRLF + "Bcc:" LF\'ye çevrilir (e-posta konusu zaten sabittir)', () => {
    assert.equal(normalizeFreeText('Selam\r\nBcc: x@y.com', 'Not', 500), 'Selam\nBcc: x@y.com');
  });
});

describe('normalizeDeviceUid', () => {
  it('yok / boş -> null; kırpılır ve BÜYÜK harfe çevrilir', () => {
    assert.equal(normalizeDeviceUid(undefined), null);
    assert.equal(normalizeDeviceUid(null), null);
    assert.equal(normalizeDeviceUid('  '), null);
    assert.equal(normalizeDeviceUid(' a0b1c2d3e4f5 '), 'A0B1C2D3E4F5');
  });

  it('metin olmayan ve 64 karakterden uzun -> 400 INVALID_BODY', () => {
    rejects(() => normalizeDeviceUid(12), 400, 'INVALID_BODY');
    rejects(() => normalizeDeviceUid({}), 400, 'INVALID_BODY');
    assert.equal(normalizeDeviceUid('a'.repeat(64)).length, 64);
    rejects(() => normalizeDeviceUid('a'.repeat(65)), 400, 'INVALID_BODY');
  });
});

describe('sorgu parametreleri', () => {
  it('status: boş -> pending; geçerli değerler; geçersiz -> 400 INVALID_QUERY', () => {
    assert.equal(parseStatusFilter(undefined), 'pending');
    assert.equal(parseStatusFilter(''), 'pending');
    for (const value of ['pending', 'approved', 'rejected', 'cancelled', 'all']) {
      assert.equal(parseStatusFilter(value), value);
    }
    assert.equal(parseStatusFilter(' all '), 'all');
    for (const bad of ['PENDING', 'done', ['pending'], {}]) {
      rejects(() => parseStatusFilter(bad), 400, 'INVALID_QUERY');
    }
  });

  it('limit: varsayılan 30, 1..100 aralığına sıkıştırılır', () => {
    assert.equal(parseListLimit(undefined), 30);
    assert.equal(parseListLimit('abc'), 30);
    assert.equal(parseListLimit('0'), 1);
    assert.equal(parseListLimit('-4'), 1);
    assert.equal(parseListLimit('500'), 100);
    assert.equal(parseListLimit('12.9'), 12);
  });

  it('offset: yok -> 0; rakam dışı / negatif / aşırı büyük -> 400 INVALID_QUERY', () => {
    assert.equal(parseOffset(undefined), 0);
    assert.equal(parseOffset('0'), 0);
    assert.equal(parseOffset('60'), 60);
    for (const bad of ['-1', '1.5', 'abc', '1e3', '0x10', '99999999999', '1000001']) {
      rejects(() => parseOffset(bad), 400, 'INVALID_QUERY');
    }
  });

  it('q: kırpılır, boşluklar birleşir, 100 karakterle sınırlanır; metin değilse 400; LIKE joker karakterleri kaçışlanır', () => {
    assert.equal(parseSearch(undefined), null);
    assert.equal(parseSearch('   '), null);
    assert.equal(parseSearch('  gül   sitesi '), 'gül sitesi');
    assert.equal(parseSearch('x'.repeat(300)).length, 100);
    rejects(() => parseSearch(['a']), 400, 'INVALID_QUERY');
    assert.equal(likePattern('100%_!'), '%100!%!_!!%');
    assert.equal(likePattern('gül'), '%gül%');
  });
});

describe('revalidateStoredStructure (onayda saklanan yapı TEKRAR doğrulanır)', () => {
  const input = normalizeSetupSiteInput({
    name: 'Gül Sitesi',
    city: 'Ankara',
    district: 'Çankaya',
    address: 'Cadde 1',
    blocks: [
      { name: 'A Blok', apartmentCount: 12 },
      { name: 'B Blok', apartmentCount: 8 },
    ],
    doors: [{ name: 'Ana Kapı' }, { name: 'Yan Kapı' }],
  });
  const goodRow = () => ({
    site_name: input.siteName,
    city: input.city,
    district: input.district,
    address: input.address,
    management_type: 'apartment_site',
    blocks: JSON.parse(JSON.stringify(input.blocks)),
    doors: JSON.parse(JSON.stringify(input.doors)),
    block_count: input.totalBlockCount,
    apartment_count: input.totalApartmentCount,
    door_count: input.totalDoorCount,
  });

  it('geçerli satır: normalizeSetupSiteInput çıktısıyla birebir aynı sonuç', () => {
    const result = revalidateStoredStructure(goodRow());
    assert.deepEqual(result.input, input);
    assert.equal(result.managementType, 'apartment_site');
  });

  it('JSONB metin olarak gelse de (sahte / eski sürücü) çözülür', () => {
    const row = goodRow();
    row.blocks = JSON.stringify(row.blocks);
    row.doors = JSON.stringify(row.doors);
    assert.deepEqual(revalidateStoredStructure(row).input, input);
  });

  it('bozuk veri 409 / 500 DEĞİL 422 APPLICATION_DATA_INVALID (boş liste sessizce varsayılana DÖNMEZ)', () => {
    const mutations = {
      'blocks dizi değil': (row) => { row.blocks = { name: 'A' }; },
      'blocks boş': (row) => { row.blocks = []; },
      'doors boş': (row) => { row.doors = []; },
      'doors null': (row) => { row.doors = null; },
      'blocks çözülemeyen metin': (row) => { row.blocks = '{bozuk'; },
      'blok adı sayı': (row) => { row.blocks[0].name = 5; },
      'blok adı boş': (row) => { row.blocks[0].name = '  '; },
      'daire sayısı metin': (row) => { row.blocks[0].apartmentCount = '12'; },
      'daire sayısı ondalık': (row) => { row.blocks[0].apartmentCount = 2.5; },
      'daire sayısı 0': (row) => { row.blocks[0].apartmentCount = 0; },
      'daire sayısı üst sınır üstü': (row) => { row.blocks[0].apartmentCount = SITE_LIMITS.maxApartments + 1; },
      'blok öğesi nesne değil': (row) => { row.blocks[1] = 'B Blok'; },
      'kapı öğesi nesne değil': (row) => { row.doors[0] = 'Ana Kapı'; },
      'kapı adı boş': (row) => { row.doors[1].name = ''; },
      'blok sayısı üst sınır üstü': (row) => {
        row.blocks = Array.from({ length: SITE_LIMITS.maxBlocks + 1 }, (_, index) => ({ name: `B${index}`, apartmentCount: 1, sortOrder: index + 1 }));
        row.block_count = SITE_LIMITS.maxBlocks + 1;
        row.apartment_count = SITE_LIMITS.maxBlocks + 1;
      },
      'kapı sayısı üst sınır üstü': (row) => {
        row.doors = Array.from({ length: SITE_LIMITS.maxDoors + 1 }, (_, index) => ({ name: `K${index}`, doorIndex: index + 1 }));
        row.door_count = SITE_LIMITS.maxDoors + 1;
      },
      'toplam daire üst sınır üstü': (row) => {
        row.blocks = [
          { name: 'A', apartmentCount: SITE_LIMITS.maxApartments, sortOrder: 1 },
          { name: 'B', apartmentCount: 1, sortOrder: 2 },
        ];
        row.block_count = 2;
        row.apartment_count = SITE_LIMITS.maxApartments + 1;
      },
      'yinelenen blok adı': (row) => { row.blocks[1].name = 'a blok'; },
      'blok sayısı tutarsız': (row) => { row.block_count = 3; },
      'daire sayısı tutarsız': (row) => { row.apartment_count = 21; },
      'kapı sayısı tutarsız': (row) => { row.door_count = 5; },
      'site adı boş': (row) => { row.site_name = '  '; },
      'site adı çok uzun': (row) => { row.site_name = 'x'.repeat(121); },
      'normalizasyon adı değiştiriyor (uzun blok adı)': (row) => { row.blocks[0].name = 'x'.repeat(80); },
      'yönetim türü bilinmiyor': (row) => { row.management_type = 'otel'; },
    };
    for (const [label, mutate] of Object.entries(mutations)) {
      const row = goodRow();
      mutate(row);
      assert.throws(
        () => revalidateStoredStructure(row),
        (error) => isPlatformError(error) && error.statusCode === 422 && error.code === 'APPLICATION_DATA_INVALID' && /yeniden başvur/.test(error.message),
        label,
      );
    }
  });
});

describe('mapApplicationRow', () => {
  const row = {
    id: '41',
    applicant_user_code: 48213,
    status: 'approved',
    site_name: 'Gül Sitesi',
    city: 'Ankara',
    district: null,
    address: null,
    management_type: 'apartment_site',
    blocks: [{ name: 'A Blok', apartmentCount: 12, sortOrder: 1 }],
    doors: [{ name: 'Ana Kapı', doorIndex: 1 }],
    block_count: 1,
    apartment_count: 12,
    door_count: 1,
    device_uid: 'A0B1C2D3E4F5',
    note: 'Not',
    plan_code: null,
    payment_status: 'not_required',
    payment_reference: 'GIZLI-REF',
    decision_source: 'super_user',
    decided_by: 1,
    decided_at: '2026-10-16T08:00:00.000Z',
    decision_note: 'Tamam',
    site_code: '1000000007',
    created_at: new Date('2026-10-16T07:00:00.000Z'),
    applicant_name: 'Ayşe Başvuran',
    applicant_email: 'ayse@example.com',
    applicant_phone: '+905551112233',
    applicant_role: 'site_manager',
    decided_by_name: 'Root',
    device_available: true,
  };

  it('başvuran görünümü: sözleşmedeki alanlar, ve YALNIZ onlar (karar kaynağı, veren, başvuran iletişimi, ödeme referansı yok)', () => {
    assert.deepEqual(mapApplicationRow(row), {
      id: 41,
      status: 'approved',
      site_name: 'Gül Sitesi',
      city: 'Ankara',
      district: null,
      address: null,
      management_type: 'apartment_site',
      management_type_label: 'Apartman ve Site',
      block_count: 1,
      apartment_count: 12,
      door_count: 1,
      blocks: [{ name: 'A Blok', apartment_count: 12 }],
      doors: [{ name: 'Ana Kapı' }],
      device_uid: 'A0B1C2D3E4F5',
      note: 'Not',
      plan_code: null,
      payment_status: 'not_required',
      decision_note: 'Tamam',
      decided_at: '2026-10-16T08:00:00.000Z',
      site_code: 1000000007,
      created_at: '2026-10-16T07:00:00.000Z',
    });
  });

  it('süper görünümü: ek alanlar applicant, decision_source, decided_by_name, device_available; payment_reference / decided_by yine yok', () => {
    const view = mapApplicationRow(row, { forSuper: true });
    assert.deepEqual(view.applicant, {
      user_code: 48213,
      full_name: 'Ayşe Başvuran',
      email: 'ayse@example.com',
      phone: '+905551112233',
      role: 'site_manager',
    });
    assert.equal(view.decision_source, 'super_user');
    assert.equal(view.decided_by_name, 'Root');
    assert.equal(view.device_available, true);
    assert.equal('payment_reference' in view, false);
    assert.equal('decided_by' in view, false);
    assert.equal(JSON.stringify(view).includes('GIZLI-REF'), false);
  });

  it('başvuran hesabı silinmişse applicant null (satır kalır)', () => {
    const view = mapApplicationRow({ ...row, applicant_user_code: null, applicant_name: null }, { forSuper: true });
    assert.equal(view.applicant, null);
  });

  it('bozuk saklanan blok / kapı verisi okumayı ÇÖKERTMEZ (boş liste); bilinmeyen yönetim türü varsayılana döner', () => {
    const view = mapApplicationRow({ ...row, blocks: 'bozuk{', doors: null, management_type: 'bilinmeyen' });
    assert.deepEqual(view.blocks, []);
    assert.deepEqual(view.doors, []);
    assert.equal(view.management_type, 'apartment_site');
  });

  it('toIso: geçersiz / boş tarih null', () => {
    assert.equal(toIso(null), null);
    assert.equal(toIso('degil'), null);
    assert.equal(toIso(new Date('2026-01-02T03:04:05Z')), '2026-01-02T03:04:05.000Z');
  });
});

describe('mapApprovedSite / onboardingModeOf / sabitler', () => {
  it('onay yanıtındaki site: cihaz bağlandı mı + atanan cihaz', () => {
    const created = {
      site: { id: '900', name: 'Gül', city: 'A', district: null, address: null, approval_status: 'approved', management_type: 'apartment_site', management_type_label: 'Apartman ve Site', block_count: 2, apartment_count: 20, door_count: 2 },
      assignedDevice: { id: 77, device_uid: 'A0B1C2D3E4F5', hardware_type: 'esp32_wroom' },
    };
    const attached = mapApprovedSite(created, { deviceAttached: true });
    assert.equal(attached.site_code, 900);
    assert.equal(attached.device_attached, true);
    assert.deepEqual(attached.assigned_device, { device_uid: 'A0B1C2D3E4F5', hardware_type: 'esp32_wroom' });
    const bare = mapApprovedSite({ ...created, assignedDevice: null }, { deviceAttached: false });
    assert.equal(bare.device_attached, false);
    assert.equal(bare.assigned_device, null);
  });

  it('kip: yalnız "payment" payment; bozuk / eksik değer güvenli varsayılan approval', () => {
    assert.equal(onboardingModeOf({ mode: 'payment' }), 'payment');
    assert.equal(onboardingModeOf('{"mode":"payment"}'), 'payment');
    for (const value of [undefined, null, {}, { mode: 'bilinmeyen' }, 'bozuk', [], 5, { mode: 'approval' }]) {
      assert.equal(onboardingModeOf(value), 'approval');
    }
  });

  it('günlük sınır sözleşmedeki gibi 5', () => {
    assert.equal(APPLICATION_DAILY_LIMIT, 5);
  });
});
