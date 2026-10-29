// Site Drive deposu (D1) saf kurallar: klasör ve dosya adı (karar T5), belirteç şifreleme, içerik türü doğrulama, yapılandırma.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  DRIVE_SOURCE_TYPES,
  PENDING_MAX_BYTES,
  PENDING_WARN_DAYS,
  cleanLabel,
  decryptToken,
  driveConfig,
  driveConfirmed,
  encryptToken,
  fileBaseName,
  folderNameFor,
  mimeMatchesContent,
  parseDriveSource,
  parseIsoDate,
  queueWarnings,
  sourcePrefix,
} from '../src/modules/drive_common.js';

const KEY = 'k'.repeat(40);

describe('drive_common adlandirma (T5)', () => {
  it('klasor adlari kararla ayni', () => {
    const d = parseIsoDate('2026-10-20');
    assert.equal(folderNameFor('sozlesme', d), 'SrvEkim_26');
    assert.equal(folderNameFor('su', d), 'suEkim_26');
    assert.equal(folderNameFor('elektrik', d), 'elektrikEkim_26');
    assert.equal(folderNameFor('teklif', d), 'TeklifEkim_26');
    assert.equal(folderNameFor('dekont', d), 'DekontEkim_26');
    assert.equal(folderNameFor('gider', d), 'GiderEkim_26');
    assert.equal(folderNameFor('belge', d), 'BelgeEkim_26');
    assert.equal(folderNameFor('gider', parseIsoDate('2027-02-03')), 'GiderŞubat_27');
  });

  it('dosya adi AB_D13_201026 ve cakisma eki', () => {
    const date = parseIsoDate('2026-10-20');
    assert.equal(fileBaseName({ kind: 'su', block: 'A', apartment: '13', date }), 'AB_D13_201026');
    assert.equal(fileBaseName({ kind: 'su', block: 'A', apartment: '13', date, serial: 2 }), 'AB_D13_201026_2');
    assert.equal(fileBaseName({ kind: 'su', apartment: '5', date }), 'D5_201026');
    assert.equal(fileBaseName({ kind: 'gider', date }), 'Gider_201026');
  });

  it('ad onek kurali (P1-11): <ON EK>-<kayit no>_<mevcut ad>; kaynak yoksa ad degismez', () => {
    const date = parseIsoDate('2026-10-20');
    assert.equal(fileBaseName({ kind: 'su', block: 'A', apartment: '13', date, source: { type: 'work_item', id: 123 } }), 'IS-123_AB_D13_201026');
    assert.equal(fileBaseName({ kind: 'su', block: 'A', apartment: '13', date, serial: 2, source: { type: 'work_item', id: 123 } }), 'IS-123_AB_D13_201026_2');
    assert.equal(fileBaseName({ kind: 'gider', date, source: { type: 'expense', id: '18' } }), 'GDR-18_Gider_201026');
    assert.equal(fileBaseName({ kind: 'su', block: 'A', apartment: '13', date, source: null }), 'AB_D13_201026');
    assert.equal(sourcePrefix({ type: 'meter_reading', id: 77 }), 'OKM-77_');
    assert.equal(sourcePrefix(undefined), '');
  });

  it('kaynak turleri: oneki ayri, kucuk-harf kimlik (DB CHECK ile uyumlu), ad guvenli karakterlerden olusur', () => {
    const prefixes = Object.values(DRIVE_SOURCE_TYPES);
    assert.equal(new Set(prefixes).size, prefixes.length, 'oneker benzersiz');
    for (const [type, prefix] of Object.entries(DRIVE_SOURCE_TYPES)) {
      assert.match(type, /^[a-z][a-z_]{0,31}$/, type);
      assert.match(prefix, /^[A-Z]{2,4}$/, prefix);
    }
    assert.equal(DRIVE_SOURCE_TYPES.work_item, 'IS');
  });

  it('kaynak dogrulama: bilinmeyen tur, sifir / negatif / ondalik / metin / bilimsel no 400 INVALID_SOURCE; ham deger yazilmaz', () => {
    assert.deepEqual(parseDriveSource({ type: 'work_item', id: '45' }), { type: 'work_item', id: 45 });
    assert.equal(parseDriveSource(undefined), null);
    assert.equal(parseDriveSource(null), null);
    for (const bad of [
      { type: 'bilinmeyen', id: 1 },
      { type: 'work_item', id: 0 },
      { type: 'work_item', id: -1 },
      { type: 'work_item', id: 1.5 },
      { type: 'work_item', id: '1e3' },
      { type: 'work_item', id: '007' },
      { type: 'work_item', id: '1 OR 1=1' },
      { type: 'work_item', id: 10 ** 16 },
      { type: '__proto__', id: 1 },
      { type: 'constructor', id: 1 },
      { id: 1 },
      {},
    ]) {
      assert.throws(() => parseDriveSource(bad), (e) => e.code === 'INVALID_SOURCE' && e.statusCode === 400, JSON.stringify(bad));
    }
  });

  it('etiket temizleme ve tarih dogrulama', () => {
    assert.equal(cleanLabel(' ç-1/ş '), 'C1S');
    assert.equal(cleanLabel('../../x'), 'X');
    assert.equal(parseIsoDate('2026-02-30'), null);
    assert.equal(parseIsoDate('20-10-2026'), null);
  });
});

describe('drive_common sifreleme ve icerik', () => {
  it('belirtec gidis donus, yanlis anahtar ve bozulma reddedilir', () => {
    const enc = encryptToken('1//refresh', KEY);
    assert.ok(!enc.includes('refresh'));
    assert.equal(decryptToken(enc, KEY), '1//refresh');
    assert.notEqual(enc, encryptToken('1//refresh', KEY), 'her seferinde farkli iv');
    assert.throws(() => decryptToken(enc, 'z'.repeat(40)));
    const parts = enc.split(':');
    parts[3] = Buffer.from('tampered-data').toString('base64');
    assert.throws(() => decryptToken(parts.join(':'), KEY));
    assert.throws(() => encryptToken('a', 'kisa'));
  });

  it('icerik turu basliktan dogrulanir', () => {
    assert.equal(mimeMatchesContent('application/pdf', Buffer.from('%PDF-1.7 x')), true);
    assert.equal(mimeMatchesContent('application/pdf', Buffer.from('MZ....')), false);
    assert.equal(mimeMatchesContent('image/jpeg', Buffer.from([0xff, 0xd8, 0xff, 0xe0])), true);
    assert.equal(mimeMatchesContent('image/png', Buffer.from([0xff, 0xd8, 0xff, 0xe0])), false);
    assert.equal(mimeMatchesContent('text/plain', Buffer.from('merhaba')), true);
    assert.equal(mimeMatchesContent('text/plain', Buffer.from([0, 1, 2])), false);
    assert.equal(mimeMatchesContent('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', Buffer.from([0x50, 0x4b, 0x03, 0x04])), true);
  });

  it('Drive teyidi: dosya kimligi sart, boyut bildirildiyse ayni olmali (K6: gecici dosya yalniz teyitten sonra silinir)', () => {
    assert.equal(driveConfirmed({ id: 'abc', size: 15 }, 15), true);
    assert.equal(driveConfirmed({ id: 'abc', size: Number.NaN }, 15), true, 'boyut bildirilmediyse kimlik yeterli');
    assert.equal(driveConfirmed({ id: 'abc', size: 16 }, 15), false);
    assert.equal(driveConfirmed({ size: 15 }, 15), false);
    assert.equal(driveConfirmed({ id: '', size: 15 }, 15), false);
    assert.equal(driveConfirmed({ id: 42, size: 15 }, 15), false);
    assert.equal(driveConfirmed(null, 15), false);
    assert.equal(driveConfirmed(undefined, 15), false);
  });

  it('bekleme alani uyarilari: yok / bekliyor / uzun suredir / dolmak uzere / doldu; hicbiri silme demez', () => {
    assert.deepEqual(queueWarnings({}), []);
    assert.deepEqual(queueWarnings({ pendingCount: 0, pendingBytes: 0, overdueCount: 0 }), []);
    assert.deepEqual(queueWarnings({ pendingCount: 2, pendingBytes: 1000 }).map((w) => w.code), ['DRIVE_FILES_WAITING']);
    assert.deepEqual(queueWarnings({ pendingCount: 2, pendingBytes: 1000, overdueCount: 1 }).map((w) => w.code), ['DRIVE_FILES_OVERDUE']);
    assert.deepEqual(queueWarnings({ pendingCount: 1, pendingBytes: PENDING_MAX_BYTES * 0.8 }).map((w) => w.code), ['DRIVE_QUEUE_NEARLY_FULL', 'DRIVE_FILES_WAITING']);
    assert.deepEqual(queueWarnings({ pendingCount: 1, pendingBytes: PENDING_MAX_BYTES * 0.95 }).map((w) => w.code), ['DRIVE_QUEUE_FULL', 'DRIVE_FILES_WAITING']);
    assert.deepEqual(queueWarnings({ pendingCount: 3, pendingBytes: PENDING_MAX_BYTES, overdueCount: 3 }).map((w) => w.code), ['DRIVE_QUEUE_FULL', 'DRIVE_FILES_OVERDUE']);
    const all = [
      ...queueWarnings({ pendingCount: 3, pendingBytes: PENDING_MAX_BYTES, overdueCount: 3 }),
      ...queueWarnings({ pendingCount: 1, pendingBytes: PENDING_MAX_BYTES * 0.8 }),
    ];
    for (const warning of all) {
      assert.match(warning.message, /silin/i, warning.code);
      assert.doesNotMatch(warning.message, /siliniyor|silinecek|silinir/, warning.code);
    }
    assert.match(queueWarnings({ pendingCount: 3, overdueCount: 3 })[0].message, new RegExp(`${PENDING_WARN_DAYS} günden uzun`));
  });

  it('yapilandirma eksikse configured false', () => {
    assert.equal(driveConfig({}).configured, false);
    assert.equal(driveConfig({ DRIVE_CLIENT_ID: 'a', DRIVE_CLIENT_SECRET: 'b', DRIVE_REDIRECT_URI: 'https://x/cb', DRIVE_TOKEN_KEY: 'kisa' }).configured, false);
    assert.equal(driveConfig({ DRIVE_CLIENT_ID: 'a', DRIVE_CLIENT_SECRET: 'b', DRIVE_REDIRECT_URI: 'https://x/cb', DRIVE_TOKEN_KEY: KEY }).configured, true);
  });
});
