import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createAttemptTracker,
  decideRoleAfterManagerRemoval,
  evaluateManagerRemoval,
  isClientSafeError,
  isValidEmail,
  mapDoorServiceError,
  safeEqualStrings,
  sanitizeDisplayText,
} from '../src/utils/site_rules.js';

test('isValidEmail', () => {
  for (const ok of ['a@b.co', 'ali.veli+etiket@ornek.com.tr', "o'neil@ornek.org", 'x_y@sub.alan.example']) {
    assert.equal(isValidEmail(ok), true, ok);
  }
  const bad = [
    '', 'abc', '@ornek.com', 'a@', 'a@b', 'a@b.', 'a b@c.com', 'a@@b.com', 'a@b..com',
    'a@-b.com', 'a@b-.com', '<x@y.com>', 'x@y.com\nBcc: z@w.com', null, undefined, 123, {},
    `${'a'.repeat(65)}@ornek.com`, `a@${'b'.repeat(250)}.com`,
  ];
  for (const value of bad) {
    assert.equal(isValidEmail(value), false, String(value));
  }
});

test('sanitizeDisplayText: kontrol karakteri, bosluk ve uzunluk', () => {
  assert.equal(sanitizeDisplayText('  Ali \n\t Veli\u0000 ', 50), 'Ali Veli');
  assert.equal(sanitizeDisplayText(undefined, 10), '');
  assert.equal(sanitizeDisplayText(null, 10), '');
  assert.equal(sanitizeDisplayText('abcdefghij', 4), 'abcd');
  assert.equal(sanitizeDisplayText('a‮b​c', 10), 'a b c');
  assert.equal(Array.from(sanitizeDisplayText('😀😀😀', 2)).length, 2);
});

test('safeEqualStrings: sabit zamanli esitlik', () => {
  assert.equal(safeEqualStrings('123456', '123456'), true);
  assert.equal(safeEqualStrings('123456', '123457'), false);
  assert.equal(safeEqualStrings('123456', '12345'), false);
  assert.equal(safeEqualStrings('', ''), true);
  assert.equal(safeEqualStrings(null, undefined), true);
  assert.equal(safeEqualStrings(123456, '123456'), true);
});

test('createAttemptTracker: 5 hatada kilit, sure sonunda acilir, basari sifirlar', () => {
  let now = 1_000_000;
  const tracker = createAttemptTracker({
    maxFailures: 5,
    windowMs: 10 * 60 * 1000,
    lockMs: 15 * 60 * 1000,
    now: () => now,
  });
  const key = '12:3';

  assert.deepEqual(tracker.check(key), { locked: false, retryAfterSeconds: 0 });
  for (let i = 1; i <= 4; i += 1) {
    const state = tracker.recordFailure(key);
    assert.equal(state.failures, i);
    assert.equal(state.locked, false);
  }
  assert.equal(tracker.check(key).locked, false);
  const fifth = tracker.recordFailure(key);
  assert.equal(fifth.locked, true);

  const locked = tracker.check(key);
  assert.equal(locked.locked, true);
  assert.equal(locked.retryAfterSeconds, 15 * 60);

  // Baska anahtar etkilenmez
  assert.equal(tracker.check('12:4').locked, false);

  now += 14 * 60 * 1000;
  assert.equal(tracker.check(key).locked, true);
  assert.equal(tracker.check(key).retryAfterSeconds, 60);
  now += 61 * 1000;
  assert.equal(tracker.check(key).locked, false);

  // Kilit bittikten sonra sayac yeniden baslar
  assert.equal(tracker.recordFailure(key).failures, 1);
  tracker.reset(key);
  assert.equal(tracker.recordFailure(key).failures, 1);
});

test('createAttemptTracker: pencere disindaki hatalar birikmez; bellek siniri', () => {
  let now = 0;
  const tracker = createAttemptTracker({ maxFailures: 3, windowMs: 1000, lockMs: 5000, now: () => now, maxKeys: 5 });
  tracker.recordFailure('a');
  tracker.recordFailure('a');
  now += 1500; // pencere doldu
  assert.equal(tracker.recordFailure('a').failures, 1);

  for (let i = 0; i < 50; i += 1) {
    tracker.recordFailure(`k${i}`);
  }
  assert.ok(tracker.size() <= 6, `boyut sinirli kalmali (${tracker.size()})`);
});

test('evaluateManagerRemoval: son yonetici cikarilamaz', () => {
  const lastOne = evaluateManagerRemoval({
    managerCodes: [10],
    targetCode: 10,
    callerCode: 10,
    isSuperUser: false,
    targetIsOwner: true,
  });
  assert.equal(lastOne.ok, false);
  assert.equal(lastOne.statusCode, 400);

  // Super user bile son yoneticiyi cikaramaz
  const superLast = evaluateManagerRemoval({
    managerCodes: ['10'],
    targetCode: 10,
    callerCode: 1,
    isSuperUser: true,
    targetIsOwner: false,
  });
  assert.equal(superLast.ok, false);

  // Iki yoneticiden biri cikarilabilir
  const ok = evaluateManagerRemoval({
    managerCodes: [10, 11],
    targetCode: 11,
    callerCode: 10,
    isSuperUser: false,
    targetIsOwner: false,
  });
  assert.deepEqual(ok, { ok: true });

  // Ayni kisi iki tabloda (site_manager_sites + memberships) tek yonetici sayilir
  const duplicated = evaluateManagerRemoval({
    managerCodes: [10, 10],
    targetCode: 10,
    callerCode: 10,
    isSuperUser: false,
    targetIsOwner: false,
  });
  assert.equal(duplicated.ok, false);
});

test('evaluateManagerRemoval: yonetici olmayan hedef 404, kurucu yalniz super user/kendisi', () => {
  const notManager = evaluateManagerRemoval({
    managerCodes: [10, 11],
    targetCode: 99,
    callerCode: 10,
    isSuperUser: false,
    targetIsOwner: false,
  });
  assert.equal(notManager.statusCode, 404);

  const ownerByAdmin = evaluateManagerRemoval({
    managerCodes: [10, 11],
    targetCode: 10,
    callerCode: 11,
    isSuperUser: false,
    targetIsOwner: true,
  });
  assert.equal(ownerByAdmin.ok, false);
  assert.equal(ownerByAdmin.statusCode, 403);

  const ownerBySuper = evaluateManagerRemoval({
    managerCodes: [10, 11],
    targetCode: 10,
    callerCode: 1,
    isSuperUser: true,
    targetIsOwner: true,
  });
  assert.equal(ownerBySuper.ok, true);

  const ownerSelf = evaluateManagerRemoval({
    managerCodes: [10, 11],
    targetCode: 10,
    callerCode: 10,
    isSuperUser: false,
    targetIsOwner: true,
  });
  assert.equal(ownerSelf.ok, true);
});

test('decideRoleAfterManagerRemoval: rol yalniz baska yonetilen site kalmadiysa geri alinir', () => {
  assert.equal(
    decideRoleAfterManagerRemoval({ currentRole: 'site_manager', hasOtherManagedSites: true, hasApartmentMembership: true }),
    null,
  );
  assert.equal(
    decideRoleAfterManagerRemoval({ currentRole: 'site_manager', hasOtherManagedSites: false, hasApartmentMembership: true }),
    'apartment_owner',
  );
  assert.equal(
    decideRoleAfterManagerRemoval({ currentRole: 'site_manager', hasOtherManagedSites: false, hasApartmentMembership: false }),
    'individual',
  );
  // site_manager olmayan roller degismez (super_user asla dusurulmez)
  for (const role of ['super_user', 'individual', 'apartment_owner', undefined]) {
    assert.equal(
      decideRoleAfterManagerRemoval({ currentRole: role, hasOtherManagedSites: false, hasApartmentMembership: false }),
      null,
      String(role),
    );
  }
});

test('isClientSafeError: is mantigi hatalari gecer, sistem/DB hatalari gecmez', () => {
  const business = new Error('Katılım talebi bulunamadı.');
  assert.equal(isClientSafeError(business), true);

  const withStatus = Object.assign(new Error('Yetkiniz yok.'), { statusCode: 403 });
  assert.equal(isClientSafeError(withStatus), true);

  const serverStatus = Object.assign(new Error('x'), { statusCode: 500 });
  assert.equal(isClientSafeError(serverStatus), false);

  const pgLike = Object.assign(new Error('duplicate key value violates unique constraint'), {
    code: '23505',
    severity: 'ERROR',
  });
  assert.equal(isClientSafeError(pgLike), false);

  assert.equal(isClientSafeError(new TypeError("Cannot read properties of undefined (reading 'x')")), false);
  assert.equal(isClientSafeError(new RangeError('boom')), false);
  assert.equal(isClientSafeError(Object.assign(new Error('connect ECONNREFUSED 127.0.0.1:5432'), { code: 'ECONNREFUSED' })), false);
  assert.equal(isClientSafeError(new Error('DOOR_NOT_FOUND')), false);
  assert.equal(isClientSafeError(new Error('')), false);
  assert.equal(isClientSafeError(null), false);
  assert.equal(isClientSafeError('metin'), false);
});

test('mapDoorServiceError: bilinen kodlar HTTP durumuna, bilinmeyenler null', () => {
  assert.deepEqual(mapDoorServiceError(new Error('DOOR_NOT_FOUND')), { status: 404, message: 'Kapi bulunamadi.' });
  assert.equal(mapDoorServiceError(new Error('DEVICE_NOT_FOUND')).status, 404);
  assert.equal(mapDoorServiceError(new Error('DEVICE_NOT_ASSIGNABLE')).status, 403);
  assert.equal(mapDoorServiceError(new Error('DEVICE_OWNED_BY_ANOTHER')).status, 409);
  assert.equal(mapDoorServiceError(new Error('MISSING_NEW_DEVICE')).status, 400);
  assert.deepEqual(mapDoorServiceError(new Error('Kapı adı boş olamaz.')), { status: 400, message: 'Kapı adı boş olamaz.' });
  assert.equal(mapDoorServiceError(new Error('Güncellenecek alan bulunamadı.')).status, 400);

  // Beklenmeyen sistem/DB hatasi: null (genel 500)
  assert.equal(mapDoorServiceError(new Error('relation "site_doors" does not exist')), null);
  assert.equal(mapDoorServiceError(Object.assign(new Error('x'), { code: '42P01' })), null);
  // Prototip anahtari gibi mesajlar haritadan sizmaz
  assert.equal(mapDoorServiceError(new Error('constructor')), null);
  assert.equal(mapDoorServiceError(new Error('__proto__')), null);
});
