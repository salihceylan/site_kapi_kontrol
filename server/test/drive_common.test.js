// Site Drive deposu (D1) saf kurallar: klasör ve dosya adı (karar T5), belirteç şifreleme, içerik türü doğrulama, yapılandırma.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanLabel,
  decryptToken,
  driveConfig,
  encryptToken,
  fileBaseName,
  folderNameFor,
  mimeMatchesContent,
  parseIsoDate,
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

  it('yapilandirma eksikse configured false', () => {
    assert.equal(driveConfig({}).configured, false);
    assert.equal(driveConfig({ DRIVE_CLIENT_ID: 'a', DRIVE_CLIENT_SECRET: 'b', DRIVE_REDIRECT_URI: 'https://x/cb', DRIVE_TOKEN_KEY: 'kisa' }).configured, false);
    assert.equal(driveConfig({ DRIVE_CLIENT_ID: 'a', DRIVE_CLIENT_SECRET: 'b', DRIVE_REDIRECT_URI: 'https://x/cb', DRIVE_TOKEN_KEY: KEY }).configured, true);
  });
});
