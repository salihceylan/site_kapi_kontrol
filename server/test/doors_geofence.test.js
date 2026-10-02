import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  GEOFENCE_DEFAULT_RADIUS_METERS,
  GEOFENCE_ERROR_CODES,
  buildGeofenceErrorBody,
  calculateHaversineDistanceMeters,
  extractClientLocation,
  isGeofenceError,
  parseLocationTimestampMs,
  validateGeofenceForDoorRequest,
} from '../src/services/geofence_service.js';

const NOW = Date.parse('2026-10-01T09:30:00.000Z');
const site = {
  site_code: 7,
  require_geofence: true,
  geofence_latitude: 41.0082,
  geofence_longitude: 28.9784,
  geofence_radius_meters: 100,
};
const authUser = { id: 5 };

function goodLocation(overrides = {}) {
  return {
    latitude: 41.0083,
    longitude: 28.9785,
    accuracy: 12,
    timestamp: new Date(NOW - 3000).toISOString(),
    is_mocked: false,
    ...overrides,
  };
}

function validate(clientLocation, siteOverrides = {}, extra = {}) {
  return validateGeofenceForDoorRequest({
    site: { ...site, ...siteOverrides },
    clientLocation,
    authUser,
    now: NOW,
    ...extra,
  });
}

function errorOf(fn) {
  try {
    fn();
  } catch (error) {
    return error;
  }
  return null;
}

describe('geofence C3 - alan dogrulamasi', () => {
  it('gecerli ISO8601 UTC konumla izin verir', () => {
    const res = validate(goodLocation());
    assert.equal(res.allowed, true);
    assert.equal(res.geofence_required, true);
    assert.ok(res.distance_meters <= 100);
    assert.equal(res.allowed_radius_meters, 100);
  });

  it('require_geofence=false iken konum gerekmez', () => {
    const res = validate(undefined, { require_geofence: false });
    assert.deepEqual(res, { allowed: true, geofence_required: false });
  });

  it('epoch ms timestamp (eski istemci) geriye donuk kabul edilir', () => {
    const res = validate(goodLocation({ timestamp: NOW - 2000 }));
    assert.equal(res.allowed, true);
  });

  it('konum hic yoksa GEOFENCE_LOCATION_REQUIRED + missing_fields', () => {
    const err = errorOf(() => validate(undefined));
    assert.equal(err.statusCode, 403);
    assert.equal(err.code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.deepEqual(err.missingFields, ['latitude', 'longitude', 'accuracy', 'timestamp']);
    const body = buildGeofenceErrorBody(err);
    assert.equal(body.code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.deepEqual(body.missing_fields, ['latitude', 'longitude', 'accuracy', 'timestamp']);
  });

  it('tek bir alan eksikse (accuracy / timestamp / latitude) REQUIRED', () => {
    for (const field of ['latitude', 'longitude', 'accuracy', 'timestamp']) {
      const loc = goodLocation();
      delete loc[field];
      const err = errorOf(() => validate(loc));
      assert.equal(err.code, 'GEOFENCE_LOCATION_REQUIRED', field);
      assert.deepEqual(err.missingFields, [field]);
    }
    // null ve bos metin de "yok" sayilir
    assert.equal(errorOf(() => validate(goodLocation({ latitude: null }))).code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.equal(errorOf(() => validate(goodLocation({ longitude: '' }))).code, 'GEOFENCE_LOCATION_REQUIRED');
  });

  it('NaN / sayi olmayan / aralik disi / (0,0) -> GEOFENCE_LOCATION_INVALID', () => {
    const invalids = [
      goodLocation({ latitude: NaN }),
      goodLocation({ longitude: 'abc' }),
      goodLocation({ latitude: Infinity }),
      goodLocation({ latitude: 91 }),
      goodLocation({ longitude: -181 }),
      goodLocation({ accuracy: -5 }),
      goodLocation({ accuracy: 'x' }),
      goodLocation({ timestamp: 'dun aksam' }),
      goodLocation({ timestamp: true }),
      goodLocation({ latitude: true }),
      goodLocation({ latitude: 0, longitude: 0 }),
    ];
    for (const loc of invalids) {
      const err = errorOf(() => validate(loc));
      assert.equal(err?.code, 'GEOFENCE_LOCATION_INVALID', JSON.stringify(loc));
      assert.equal(err.statusCode, 403);
    }
  });

  it('is_mocked=true -> GEOFENCE_MOCK_LOCATION (bool / "true" / 1)', () => {
    for (const mocked of [true, 'true', 1, 'TRUE']) {
      assert.equal(errorOf(() => validate(goodLocation({ is_mocked: mocked }))).code, 'GEOFENCE_MOCK_LOCATION');
    }
    // isMocked takma adi
    const loc = goodLocation();
    delete loc.is_mocked;
    loc.isMocked = true;
    assert.equal(errorOf(() => validate(loc)).code, 'GEOFENCE_MOCK_LOCATION');
    // false / eksik is_mocked sorun degil
    assert.equal(validate(goodLocation({ is_mocked: undefined })).allowed, true);
    assert.equal(validate(goodLocation({ is_mocked: 'false' })).allowed, true);
  });

  it('60 sn sinirindan bayat (veya gelecekteki) konum -> GEOFENCE_LOCATION_STALE', () => {
    assert.equal(
      errorOf(() => validate(goodLocation({ timestamp: new Date(NOW - 61000).toISOString() }))).code,
      'GEOFENCE_LOCATION_STALE',
    );
    assert.equal(
      errorOf(() => validate(goodLocation({ timestamp: new Date(NOW + 120000).toISOString() }))).code,
      'GEOFENCE_LOCATION_STALE',
    );
    // 59 sn hala kabul
    assert.equal(validate(goodLocation({ timestamp: new Date(NOW - 59000).toISOString() })).allowed, true);
  });

  it('accuracy > 100 m -> GEOFENCE_LOCATION_INACCURATE; tam 100 kabul', () => {
    assert.equal(errorOf(() => validate(goodLocation({ accuracy: 100.5 }))).code, 'GEOFENCE_LOCATION_INACCURATE');
    assert.equal(validate(goodLocation({ accuracy: 100 })).allowed, true);
  });

  it('yaricap disi -> GEOFENCE_OUT_OF_RANGE (+ mesafe/yaricap)', () => {
    const err = errorOf(() => validate(goodLocation({ latitude: 41.02 })));
    assert.equal(err.code, 'GEOFENCE_OUT_OF_RANGE');
    assert.ok(err.distanceMeters > 100);
    assert.equal(err.allowedRadiusMeters, 100);
    const body = buildGeofenceErrorBody(err);
    assert.equal(body.code, 'GEOFENCE_OUT_OF_RANGE');
    assert.equal(body.allowed_radius_meters, 100);
    assert.ok(body.distance_meters > 100);
    assert.ok(isGeofenceError(err));
  });

  it('varsayilan yaricap 100 m (site degeri yoksa/0 ise); site ozel degeri varsa o', () => {
    assert.equal(GEOFENCE_DEFAULT_RADIUS_METERS, 100);
    // ~130 m kuzey
    const far = goodLocation({ latitude: 41.0082 + 0.00117, longitude: 28.9784 });
    for (const radius of [null, undefined, 0, -5, 'abc']) {
      const err = errorOf(() => validate(far, { geofence_radius_meters: radius }));
      assert.equal(err.code, 'GEOFENCE_OUT_OF_RANGE', String(radius));
      assert.equal(err.allowedRadiusMeters, 100);
    }
    // site ozel yaricap 200 -> ayni konum kabul
    const res = validate(far, { geofence_radius_meters: 200 });
    assert.equal(res.allowed_radius_meters, 200);
  });

  it('site koordinati yoksa izin + uyari (eski yapilandirma); gecersizse GEOFENCE_SITE_MISCONFIGURED', () => {
    const res = validate(undefined, { geofence_latitude: null, geofence_longitude: null });
    assert.equal(res.allowed, true);
    assert.equal(res.warning, 'SITE_COORDINATES_NOT_CONFIGURED');
    assert.equal(
      errorOf(() => validate(goodLocation(), { geofence_latitude: 123 })).code,
      'GEOFENCE_SITE_MISCONFIGURED',
    );
  });

  it('forceRequire: site bayragi kapali olsa da (ekransiz cihaz) konum zorunlu', () => {
    const err = errorOf(() => validate(undefined, { require_geofence: false }, { forceRequire: true }));
    assert.equal(err.code, 'GEOFENCE_LOCATION_REQUIRED');
    assert.equal(validate(goodLocation(), { require_geofence: false }, { forceRequire: true }).allowed, true);
    // site koordinati yoksa zorlanamaz: izin + uyari
    const res = validate(undefined, { require_geofence: false, geofence_latitude: null }, { forceRequire: true });
    assert.equal(res.warning, 'SITE_COORDINATES_NOT_CONFIGURED');
  });

  it('tum hata kodlari GEOFENCE_ onekli ve 403', () => {
    for (const code of Object.values(GEOFENCE_ERROR_CODES)) {
      assert.ok(code.startsWith('GEOFENCE_'), code);
    }
  });
});

describe('geofence yardimcilari', () => {
  it('calculateHaversineDistanceMeters NaN-guvenli (null -> Infinity, 0 sanilmaz)', () => {
    assert.equal(calculateHaversineDistanceMeters(null, 28, 41, 28), Infinity);
    assert.equal(calculateHaversineDistanceMeters('', 28, 41, 28), Infinity);
    assert.equal(calculateHaversineDistanceMeters(41, 28, undefined, 28), Infinity);
    assert.equal(calculateHaversineDistanceMeters(95, 28, 41, 28), Infinity);
    assert.equal(calculateHaversineDistanceMeters(true, 28, 41, 28), Infinity);
    const d = calculateHaversineDistanceMeters(41.0082, 28.9784, 41.0092, 28.9784);
    assert.ok(d > 100 && d < 120, `~111 m beklenir, gelen ${d}`);
  });

  it('parseLocationTimestampMs ISO / epoch ms / epoch sn / gecersiz', () => {
    assert.equal(parseLocationTimestampMs('2026-10-01T09:30:00.000Z'), NOW);
    assert.equal(parseLocationTimestampMs('2026-10-01T12:30:00+03:00'), NOW);
    assert.equal(parseLocationTimestampMs('2026-10-01T09:30:00.000'), NOW); // saat dilimi yok => UTC
    assert.equal(parseLocationTimestampMs(NOW), NOW);
    assert.equal(parseLocationTimestampMs(String(NOW)), NOW);
    assert.equal(parseLocationTimestampMs(Math.floor(NOW / 1000)), Math.floor(NOW / 1000) * 1000);
    assert.equal(parseLocationTimestampMs(''), null);
    assert.equal(parseLocationTimestampMs('abc'), null);
    assert.equal(parseLocationTimestampMs(12), null);
    assert.equal(parseLocationTimestampMs(null), null);
    assert.equal(parseLocationTimestampMs(true), null);
  });

  it('extractClientLocation ust duzey alanlari ya da location nesnesini okur', () => {
    assert.equal(extractClientLocation(undefined), null);
    assert.equal(extractClientLocation({}), null);
    assert.equal(extractClientLocation({ qr_payload: 'x' }), null);
    assert.deepEqual(
      extractClientLocation({ latitude: 1, longitude: 2, accuracy: 3, timestamp: 't', is_mocked: true }),
      { latitude: 1, longitude: 2, accuracy: 3, timestamp: 't', is_mocked: true },
    );
    assert.deepEqual(
      extractClientLocation({ location: { latitude: 1, longitude: 2, accuracy: 3, timestamp: 't', isMocked: true } }),
      { latitude: 1, longitude: 2, accuracy: 3, timestamp: 't', is_mocked: true },
    );
    // ust duzey alan varsa o oncelikli
    assert.equal(
      extractClientLocation({ latitude: 10, location: { latitude: 99, longitude: 2 } }).latitude,
      10,
    );
  });
});
