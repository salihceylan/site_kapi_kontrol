import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import {
  SCREEN_QR_GRACE_MS,
  applyScreenQrUpdate,
  checkScreenQrToken,
  clampScreenQrValiditySeconds,
  consumeScreenQrToken,
  normalizeScreenQrToken,
  releaseScreenQrToken,
} from '../src/services/door_access_policy.js';
import {
  applyStatusMessage,
  deviceScreenQrStore,
  getDeviceRuntimeStatus,
  normalizeDeviceTopicUid,
} from '../src/mqtt_bridge.js';

const T0 = 1_800_000_000_000;

describe('ekran karekodu tek kullanim mantigi (saf)', () => {
  it('yeni token kaydi: current/previous/expiresAt (gecerlilik + 12 sn tolerans)', () => {
    const first = applyScreenQrUpdate(null, 'abc123', 30, T0);
    assert.equal(first.currentToken, 'ABC123');
    assert.equal(first.previousToken, null);
    assert.equal(first.expiresAt, T0 + 30_000 + SCREEN_QR_GRACE_MS);
    const second = applyScreenQrUpdate(first, 'DEF456', 30, T0 + 30_000);
    assert.equal(second.currentToken, 'DEF456');
    assert.equal(second.previousToken, 'ABC123');
  });

  it('gecersiz token bicimi kaydi degistirmez', () => {
    const first = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    assert.equal(applyScreenQrUpdate(first, '', 30, T0 + 1), first);
    assert.equal(applyScreenQrUpdate(first, 'a b', 30, T0 + 1), first);
    assert.equal(applyScreenQrUpdate(null, '??', 30, T0), null);
  });

  it('ayni token tekrar gelirse kayit degismez (sure uzamaz, kullanildi isareti silinmez)', () => {
    const first = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    consumeScreenQrToken(first, 'ABC123', T0 + 1000);
    const again = applyScreenQrUpdate(first, 'abc123', 30, T0 + 20_000);
    assert.equal(again, first);
    assert.equal(again.expiresAt, T0 + 30_000 + SCREEN_QR_GRACE_MS);
    assert.equal(checkScreenQrToken(again, 'ABC123', T0 + 21_000).reason, 'ALREADY_USED');
  });

  it('gecerli token tuketilir; ikinci kullanim reddedilir (ALREADY_USED)', () => {
    const entry = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    const first = consumeScreenQrToken(entry, 'abc123', T0 + 5000);
    assert.equal(first.ok, true);
    assert.equal(first.which, 'current');
    const second = consumeScreenQrToken(entry, 'ABC123', T0 + 6000);
    assert.deepEqual(second, { ok: false, reason: 'ALREADY_USED' });
  });

  it('yan etkisiz kontrol tuketmez; release tokeni geri verir', () => {
    const entry = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    assert.equal(checkScreenQrToken(entry, 'ABC123', T0 + 1).ok, true);
    assert.equal(checkScreenQrToken(entry, 'ABC123', T0 + 2).ok, true); // hala tuketilmedi
    consumeScreenQrToken(entry, 'ABC123', T0 + 3);
    assert.equal(checkScreenQrToken(entry, 'ABC123', T0 + 4).reason, 'ALREADY_USED');
    releaseScreenQrToken(entry, 'ABC123');
    assert.equal(checkScreenQrToken(entry, 'ABC123', T0 + 5).ok, true);
  });

  it('yanlis / bos / kayitsiz durumlar', () => {
    const entry = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    assert.equal(checkScreenQrToken(entry, 'ZZZ999', T0).reason, 'MISMATCH');
    assert.equal(checkScreenQrToken(entry, '', T0).reason, 'INVALID');
    assert.equal(checkScreenQrToken(entry, 'a b', T0).reason, 'INVALID');
    assert.equal(checkScreenQrToken(undefined, 'ABC123', T0).reason, 'NO_ENTRY');
    assert.equal(checkScreenQrToken({}, 'ABC123', T0).reason, 'NO_ENTRY');
  });

  it('current token sure dolunca EXPIRED', () => {
    const entry = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    assert.equal(checkScreenQrToken(entry, 'ABC123', T0 + 30_000 + SCREEN_QR_GRACE_MS).ok, true);
    assert.equal(checkScreenQrToken(entry, 'ABC123', T0 + 30_000 + SCREEN_QR_GRACE_MS + 1).reason, 'EXPIRED');
  });

  it('onceki token yalnizca rotasyondan sonra 12 sn tolerans icinde gecerli', () => {
    const first = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    const second = applyScreenQrUpdate(first, 'DEF456', 30, T0 + 30_000);
    const within = checkScreenQrToken(second, 'ABC123', T0 + 30_000 + SCREEN_QR_GRACE_MS);
    assert.equal(within.ok, true);
    assert.equal(within.which, 'previous');
    assert.equal(checkScreenQrToken(second, 'ABC123', T0 + 30_000 + SCREEN_QR_GRACE_MS + 1).reason, 'EXPIRED');
  });

  it('kullanilmis token rotasyondan sonra onceki olarak bile TEKRAR kabul edilmez', () => {
    const first = applyScreenQrUpdate(null, 'ABC123', 30, T0);
    consumeScreenQrToken(first, 'ABC123', T0 + 10_000);
    const second = applyScreenQrUpdate(first, 'DEF456', 30, T0 + 30_000);
    assert.equal(checkScreenQrToken(second, 'ABC123', T0 + 31_000).reason, 'ALREADY_USED');
    assert.equal(checkScreenQrToken(second, 'DEF456', T0 + 31_000).ok, true);
  });

  it('kullanilmis tokenlar bellekte birikmez (rotasyonda budanir)', () => {
    let entry = applyScreenQrUpdate(null, 'AAA111', 30, T0);
    for (let i = 0; i < 20; i += 1) {
      consumeScreenQrToken(entry, entry.currentToken, T0 + i * 30_000 + 1);
      entry = applyScreenQrUpdate(entry, `TOK${String(i).padStart(3, '0')}`, 30, T0 + (i + 1) * 30_000);
    }
    assert.ok(entry.usedTokens.size <= 2, `usedTokens=${entry.usedTokens.size}`);
  });

  it('normalizeScreenQrToken / clampScreenQrValiditySeconds', () => {
    assert.equal(normalizeScreenQrToken(' ab12cd '), 'AB12CD');
    assert.equal(normalizeScreenQrToken('ab 12'), '');
    assert.equal(normalizeScreenQrToken('abc'), '');
    assert.equal(normalizeScreenQrToken(null), '');
    assert.equal(clampScreenQrValiditySeconds(undefined), 30);
    assert.equal(clampScreenQrValiditySeconds('abc'), 30);
    assert.equal(clampScreenQrValiditySeconds(-4), 30);
    assert.equal(clampScreenQrValiditySeconds(1), 5);
    assert.equal(clampScreenQrValiditySeconds(99999), 300);
    assert.equal(clampScreenQrValiditySeconds(45), 45);
  });
});

describe('UID normalizasyonu (ekran QR kayit anahtari)', () => {
  it('normalizeDeviceTopicUid: hex, kucuk harf, ayraclar, MAC bicimi', () => {
    assert.equal(normalizeDeviceTopicUid('d4c771a172e0'), 'D4C771A172E0');
    assert.equal(normalizeDeviceTopicUid(' D4C771A172E0 '), 'D4C771A172E0');
    assert.equal(normalizeDeviceTopicUid('D4-C7-71-A1-72-E0'), 'D4C771A172E0');
    // MAC (iki noktali) -> cihazin efuse UID'si bayt ters
    assert.equal(normalizeDeviceTopicUid('E0:72:A1:71:C7:D4'), 'D4C771A172E0');
    assert.equal(normalizeDeviceTopicUid(''), '');
    assert.equal(normalizeDeviceTopicUid(null), '');
  });

  it('DB cihaz UID biçimi ile topic UID aynı anahtara iner (kayit-sorgu uyusmazligi yok)', () => {
    const dbUid = 'D4C771A172E0';
    const topicUid = 'd4c771a172e0';
    assert.equal(normalizeDeviceTopicUid(dbUid), normalizeDeviceTopicUid(topicUid));
  });
});

describe('mqtt_bridge screen_qr isleyicisi (C7)', () => {
  it('retained screen_qr YOK SAYILIR; normal mesaj kaydedilir; token LOGLANMAZ', () => {
    const uid = 'A1B2C3D4E5F6';
    deviceScreenQrStore.delete(uid);
    const logSpy = mock.method(console, 'log', () => {});
    const warnSpy = mock.method(console, 'warn', () => {});
    try {
      const payload = JSON.stringify({ token: 'SECR3T', valid_seconds: 30, device_uid: uid });

      applyStatusMessage(`device/${uid}/screen_qr`, payload, { retain: true });
      assert.equal(deviceScreenQrStore.has(uid), false, 'retained mesaj kaydedilmemeli');

      applyStatusMessage(`device/${uid}/screen_qr`, payload, { retain: false });
      assert.equal(deviceScreenQrStore.get(uid)?.currentToken, 'SECR3T');

      // Hicbir log cagrisi token degerini icermemeli
      const allLogs = [...logSpy.mock.calls, ...warnSpy.mock.calls].map((call) => call.arguments.join(' ')).join('\n');
      assert.equal(allLogs.includes('SECR3T'), false, 'ekran tokeni loglanmamali');
    } finally {
      logSpy.mock.restore();
      warnSpy.mock.restore();
      deviceScreenQrStore.delete(uid);
    }
  });

  it('retained mesaj durum haritasini da guncellemez (qr_verify retained de yok sayilir)', () => {
    const uid = 'AABBCCDDEEFF';
    applyStatusMessage(`device/${uid}/qr_verify`, JSON.stringify({ token: 'QR:abc', request_id: 5 }), { retain: true });
    assert.equal(getDeviceRuntimeStatus(uid).last_payload_at, null);
  });

  it('ayni token tekrar yayinlansa kullanildi isareti silinmez', () => {
    const uid = 'A1B2C3D4E5F7';
    deviceScreenQrStore.delete(uid);
    const payload = JSON.stringify({ token: 'TOK777', valid_seconds: 30 });
    applyStatusMessage(`device/${uid}/screen_qr`, payload, { retain: false });
    const entry = deviceScreenQrStore.get(uid);
    assert.equal(consumeScreenQrToken(entry, 'TOK777').ok, true);
    applyStatusMessage(`device/${uid}/screen_qr`, payload, { retain: false });
    assert.equal(consumeScreenQrToken(deviceScreenQrStore.get(uid), 'TOK777').reason, 'ALREADY_USED');
    deviceScreenQrStore.delete(uid);
  });
});
