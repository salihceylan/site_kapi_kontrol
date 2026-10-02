import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseSecurityPolicyBody,
  resolveSecurityPolicyUpdate,
} from '../src/utils/site_rules.js';

const baseSite = Object.freeze({
  feature_remote_open_enabled: true,
  feature_qr_enabled: true,
  feature_local_udp_enabled: true,
  feature_guest_pass_enabled: true,
  qr_entry_active: true,
  require_geofence: false,
  geofence_latitude: null,
  geofence_longitude: null,
  geofence_radius_meters: 75,
});

function run(body, { existing = baseSite, isSuperUser = false } = {}) {
  const parsed = parseSecurityPolicyBody(body);
  if (!parsed.ok) {
    return { stage: 'parse', ...parsed };
  }
  return { stage: 'resolve', ...resolveSecurityPolicyUpdate({ patch: parsed.patch, existing, isSuperUser }) };
}

test('bos govde: hicbir alan degismez (undefined != null)', () => {
  for (const isSuperUser of [true, false]) {
    const result = run({}, { isSuperUser });
    assert.equal(result.ok, true);
    assert.deepEqual(result.update, {});
  }
  // govde hic yoksa da ayni
  assert.deepEqual(run(undefined).update, {});
});

test('site yoneticisi: yalniz geofence/qr_entry_active gonderince 403 ALMAZ', () => {
  const result = run({
    qr_entry_active: false,
    require_geofence: true,
    geofence_latitude: 41.0082,
    geofence_longitude: 28.9784,
    geofence_radius_meters: 150,
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.update, {
    qrEntryActive: false,
    requireGeofence: true,
    geofenceLatitude: 41.0082,
    geofenceLongitude: 28.9784,
    geofenceRadiusMeters: 150,
  });
});

test('site yoneticisi: giris yontemi bayragini DEGISTIRMEK 403, ayni deger sessizce yok sayilir', () => {
  const denied = run({ feature_remote_open_enabled: false });
  assert.equal(denied.ok, false);
  assert.equal(denied.status, 403);

  const same = run({ feature_remote_open_enabled: true, feature_guest_pass_enabled: true });
  assert.equal(same.ok, true);
  assert.deepEqual(same.update, {});
});

test('super user: bayraklar uygulanir, en az bir giris yontemi kurali', () => {
  const ok = run({ feature_qr_enabled: false }, { isSuperUser: true });
  assert.equal(ok.ok, true);
  assert.equal(ok.update.featureQrEnabled, false);
  // QR kapaninca qr_entry_active de kapanir
  assert.equal(ok.update.qrEntryActive, false);

  const bothOff = run(
    { feature_qr_enabled: false, feature_remote_open_enabled: false },
    { isSuperUser: true },
  );
  assert.equal(bothOff.ok, false);
  assert.equal(bothOff.status, 400);

  // Mevcut durumda uzaktan acma kapaliysa QR'i de kapatmak reddedilir
  const existingRemoteOff = { ...baseSite, feature_remote_open_enabled: false };
  const denied = run({ feature_qr_enabled: false }, { isSuperUser: true, existing: existingRemoteOff });
  assert.equal(denied.ok, false);
  assert.equal(denied.status, 400);
});

test('super user kismi guncelleme qr_entry_active degerini BOZMAZ', () => {
  // QR acikken yalniz geofence guncellemesi: qr_entry_active hic yazilmaz
  const geofenceOnly = run(
    { require_geofence: true, geofence_latitude: 39.9, geofence_longitude: 32.8 },
    { isSuperUser: true },
  );
  assert.equal(geofenceOnly.ok, true);
  assert.equal('qrEntryActive' in geofenceOnly.update, false);

  // QR acikken qr_entry_active=false gonderilirse uygulanir
  const pause = run({ qr_entry_active: false }, { isSuperUser: true });
  assert.equal(pause.update.qrEntryActive, false);

  // QR ozelligi kapaliyken ilgisiz guncelleme, zaten false olan qr_entry_active'e dokunmaz
  const qrOff = { ...baseSite, feature_qr_enabled: false, qr_entry_active: false };
  const radiusOnly = run({ geofence_radius_meters: 100 }, { isSuperUser: true, existing: qrOff });
  assert.equal('qrEntryActive' in radiusOnly.update, false);

  // QR ozelligi kapaliyken qr_entry_active=true gonderilirse false'a zorlanir
  const forced = run({ qr_entry_active: true }, { isSuperUser: true, existing: qrOff });
  assert.equal(forced.update.qrEntryActive, false);
});

test('geofence: enlem/boylam/yaricap araliklari', () => {
  assert.equal(run({ geofence_latitude: 90.0001 }).stage, 'parse');
  assert.equal(run({ geofence_latitude: -90.5 }).stage, 'parse');
  assert.equal(run({ geofence_longitude: 180.1 }).stage, 'parse');
  assert.equal(run({ geofence_longitude: '-181' }).stage, 'parse');
  assert.equal(run({ geofence_latitude: 'abc' }).stage, 'parse');
  assert.equal(run({ geofence_latitude: '' }).stage, 'parse');
  assert.equal(run({ geofence_latitude: true }).stage, 'parse');
  assert.equal(run({ geofence_radius_meters: 9 }).stage, 'parse');
  assert.equal(run({ geofence_radius_meters: 2001 }).stage, 'parse');
  assert.equal(run({ geofence_radius_meters: 'abc' }).stage, 'parse');

  assert.equal(run({ geofence_radius_meters: 10 }).ok, true);
  assert.equal(run({ geofence_radius_meters: 2000 }).ok, true);
  assert.equal(run({ geofence_radius_meters: '250' }).update.geofenceRadiusMeters, 250);
  assert.equal(run({ geofence_radius_meters: 99.6 }).update.geofenceRadiusMeters, 100);
  // sinir degerleri
  assert.equal(run({ geofence_latitude: -90, geofence_longitude: 180 }).ok, true);
});

test('require_geofence=true ise gecerli koordinat zorunlu (400)', () => {
  // koordinat hic yok
  const missing = run({ require_geofence: true });
  assert.equal(missing.ok, false);
  assert.equal(missing.status, 400);

  // yalniz enlem var
  const onlyLat = run({ require_geofence: true, geofence_latitude: 41 });
  assert.equal(onlyLat.status, 400);

  // (0,0) ayarlanmamis sayilir
  const nullIsland = run({ require_geofence: true, geofence_latitude: 0, geofence_longitude: 0 });
  assert.equal(nullIsland.status, 400);

  // mevcut koordinat varsa yalniz bayragi acmak yeter
  const existing = { ...baseSite, geofence_latitude: 41.01, geofence_longitude: 28.97 };
  const okWithExisting = run({ require_geofence: true }, { existing });
  assert.equal(okWithExisting.ok, true);
  assert.equal(okWithExisting.update.requireGeofence, true);

  // geofence zaten aciksa koordinati null ile silmek reddedilir
  const enabled = { ...existing, require_geofence: true };
  const clearing = run({ geofence_latitude: null, geofence_longitude: null }, { existing: enabled });
  assert.equal(clearing.ok, false);
  assert.equal(clearing.status, 400);

  // geofence kapaliyken koordinati temizlemek serbest (null = temizle)
  const clearOk = run({ geofence_latitude: null, geofence_longitude: null }, { existing });
  assert.equal(clearOk.ok, true);
  assert.equal(clearOk.update.geofenceLatitude, null);
  assert.equal(clearOk.update.geofenceLongitude, null);

  // geofence'i kapatmak koordinat istemez
  const off = run({ require_geofence: false }, { existing: enabled });
  assert.equal(off.ok, true);
  assert.equal(off.update.requireGeofence, false);
});

test('yalniz yaricap degisikligi koordinat istemez (eski bozuk veriyi kilitlemez)', () => {
  const legacyBroken = { ...baseSite, require_geofence: true };
  const result = run({ geofence_radius_meters: 120 }, { existing: legacyBroken });
  assert.equal(result.ok, true);
  assert.equal(result.update.geofenceRadiusMeters, 120);
});

test('tip dogrulamasi: boolean alanlar', () => {
  assert.equal(run({ qr_entry_active: 'evet' }).stage, 'parse');
  assert.equal(run({ require_geofence: 5 }).stage, 'parse');
  assert.equal(run({ feature_qr_enabled: {} }, { isSuperUser: true }).stage, 'parse');
  // 'true'/'false' metinleri kabul
  assert.equal(run({ qr_entry_active: 'false' }).update.qrEntryActive, false);
  // null = degisiklik yok (eski istemciler null gonderebilir)
  assert.deepEqual(run({ qr_entry_active: null, require_geofence: null }).update, {});
});

test('qr_rotation_seconds: sayisal, [10,300] araligina kirpilir', () => {
  assert.equal(run({ qr_rotation_seconds: 5 }).update.qrRotationSeconds, 10);
  assert.equal(run({ qr_rotation_seconds: 9999 }).update.qrRotationSeconds, 300);
  assert.equal(run({ qr_rotation_seconds: '45' }).update.qrRotationSeconds, 45);
  assert.equal(run({ qr_rotation_seconds: 'abc' }).stage, 'parse');
});
