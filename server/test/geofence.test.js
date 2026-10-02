import test from 'node:test';
import assert from 'node:assert/strict';
import {
  calculateHaversineDistanceMeters,
  validateGeofenceForDoorRequest,
} from '../src/services/geofence_service.js';

test('Geofence Service Tests', async (t) => {
  await t.test('calculateHaversineDistanceMeters', async (t2) => {
    await t2.test('returns 0 for identical coordinates', () => {
      const d = calculateHaversineDistanceMeters(41.0082, 28.9784, 41.0082, 28.9784);
      assert.equal(d, 0);
    });

    await t2.test('calculates accurate distance between known points (Ankara Anıtkabir - Kızılay)', () => {
      // Anıtkabir: 39.9250, 32.8369
      // Kızılay: 39.9208, 32.8541
      const d = calculateHaversineDistanceMeters(39.9250, 32.8369, 39.9208, 32.8541);
      // Distance is ~1530 meters (+- 50 meters)
      assert.ok(d > 1450 && d < 1600, `Expected ~1530m, got ${d}`);
    });

    await t2.test('returns Infinity for invalid coordinates', () => {
      assert.equal(calculateHaversineDistanceMeters('invalid', 32, 39, 32), Infinity);
      assert.equal(calculateHaversineDistanceMeters(39, 32, NaN, 32), Infinity);
    });
  });

  await t.test('validateGeofenceForDoorRequest', async (t2) => {
    const defaultSite = {
      site_code: 101,
      require_geofence: true,
      geofence_latitude: 41.0082,
      geofence_longitude: 28.9784,
      geofence_radius_meters: 150,
    };

    const authUser = { id: 42, full_name: 'Ahmet Yilmaz', email: 'ahmet@example.com' };

    await t2.test('allows access if require_geofence is false', () => {
      const site = { ...defaultSite, require_geofence: false };
      const res = validateGeofenceForDoorRequest({ site, authUser });
      assert.equal(res.allowed, true);
      assert.equal(res.geofence_required, false);
    });

    await t2.test('allows access with warning if site coordinates are missing', () => {
      const site = { site_code: 101, require_geofence: true, geofence_latitude: null, geofence_longitude: null };
      const res = validateGeofenceForDoorRequest({ site, authUser });
      assert.equal(res.allowed, true);
      assert.equal(res.warning, 'SITE_COORDINATES_NOT_CONFIGURED');
    });

    await t2.test('throws 403 GEOFENCE_LOCATION_REQUIRED when location is missing', () => {
      assert.throws(
        () => validateGeofenceForDoorRequest({ site: defaultSite, authUser }),
        (err) => err.statusCode === 403 && err.code === 'GEOFENCE_LOCATION_REQUIRED'
      );
    });

    await t2.test('throws 403 GEOFENCE_MOCK_LOCATION when is_mocked is true (Aşama 6)', () => {
      assert.throws(
        () =>
          validateGeofenceForDoorRequest({
            site: defaultSite,
            authUser,
            clientLocation: {
              latitude: 41.0082,
              longitude: 28.9784,
              accuracy: 10,
              timestamp: Date.now(),
              is_mocked: true,
            },
          }),
        (err) => err.statusCode === 403 && err.code === 'GEOFENCE_MOCK_LOCATION'
      );
    });

    await t2.test('throws 403 GEOFENCE_LOCATION_STALE when location is older than 60s (C3)', () => {
      assert.throws(
        () =>
          validateGeofenceForDoorRequest({
            site: defaultSite,
            authUser,
            clientLocation: {
              latitude: 41.0082,
              longitude: 28.9784,
              accuracy: 10,
              timestamp: Date.now() - 90000, // 90s old (C3: >60s bayat)
            },
          }),
        (err) => err.statusCode === 403 && err.code === 'GEOFENCE_LOCATION_STALE'
      );
    });

    await t2.test('throws 403 GEOFENCE_LOCATION_INACCURATE when GPS accuracy is worse than 100m (C3)', () => {
      assert.throws(
        () =>
          validateGeofenceForDoorRequest({
            site: defaultSite,
            authUser,
            clientLocation: {
              latitude: 41.0082,
              longitude: 28.9784,
              accuracy: 250, // 250m accuracy is too blurry
              timestamp: Date.now(),
            },
          }),
        (err) => err.statusCode === 403 && err.code === 'GEOFENCE_LOCATION_INACCURATE'
      );
    });

    await t2.test('throws 403 GEOFENCE_OUT_OF_RANGE when outside allowed radius (Aşama 5)', () => {
      // 1 km away
      assert.throws(
        () =>
          validateGeofenceForDoorRequest({
            site: defaultSite,
            authUser,
            clientLocation: {
              latitude: 41.0180,
              longitude: 28.9784,
              accuracy: 10,
              timestamp: Date.now(),
            },
          }),
        (err) => err.statusCode === 403 && err.code === 'GEOFENCE_OUT_OF_RANGE' && err.distanceMeters > 150
      );
    });

    await t2.test('allows access when within allowed radius (Aşama 5)', () => {
      // ~20 meters away
      const res = validateGeofenceForDoorRequest({
        site: defaultSite,
        authUser,
        clientLocation: {
          latitude: 41.0083,
          longitude: 28.9785,
          accuracy: 8,
          timestamp: Date.now() - 2000, // 2s old
          is_mocked: false,
        },
      });

      assert.equal(res.allowed, true);
      assert.equal(res.geofence_required, true);
      assert.ok(res.distance_meters <= 150);
      assert.equal(res.allowed_radius_meters, 150);
    });
  });
});

