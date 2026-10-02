// SX2 duzeltmeleri (DB'siz): cihaz sahipligi (users.id != user_code), kapi degistirme UID yolu,
// atanabilir cihaz listesi ve pasife alinmis uyeligin ek kapi izni (door_access_overrides).
import { describe, it, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  authUserCodeValue,
  authUserDbId,
  isDeviceAssignableToManagedSite,
  isDeviceOwnedByAuthUser,
  isDeviceVisibleToManagedSites,
} from '../src/services/site_service.js';
import {
  getAccessibleDoorForUser,
  listAccessibleDoorsForUser,
  listAssignableDevicesForUser,
  replaceDoorDevice,
} from '../src/services/door_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

// Oturumdaki kullanici: id/user_code = 5 haneli oturum kimligi, db_id = users.id (BIGSERIAL, farkli sayi)
const manager = { id: 48213, user_code: 48213, db_id: 7, userId: 7, role: 'site_manager' };
const superUser = { id: 10001, user_code: 10001, db_id: 1, userId: 1, role: 'super_user' };

describe('sahiplik yardimcilari: owner_user_id = users.id, assigned_user_code = user_code', () => {
  it('authUserDbId / authUserCodeValue', () => {
    assert.equal(authUserDbId(manager), 7);
    assert.equal(authUserDbId({ userId: '9' }), 9);
    assert.equal(authUserDbId({ id: 48213, user_code: 48213 }), null, 'db_id yoksa user_code users.id sayilmaz');
    assert.equal(authUserDbId({ db_id: 'x' }), null);
    assert.equal(authUserCodeValue(manager), 48213);
    assert.equal(authUserCodeValue({ userCode: 5 }), 5);
    assert.equal(authUserCodeValue({ id: 6 }), 6);
    assert.equal(authUserCodeValue({}), null);
  });

  it('isDeviceOwnedByAuthUser: users.id ile ve user_code ile eslesir; user_code ile owner_user_id KARISTIRILMAZ', () => {
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: 7, assigned_user_code: null }, manager), true);
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: null, assigned_user_code: 48213 }, manager), true);
    // baska kullanicinin users.id degeri tesaduf bu kullanicinin user_code'una esit: SAHIP DEGIL
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: 48213, assigned_user_code: 11111 }, manager), false);
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: 99, assigned_user_code: 7 }, manager), false);
    // db_id bilinmiyorsa yalniz assigned_user_code kullanilir
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: 48213, assigned_user_code: null }, { id: 48213, user_code: 48213 }), false);
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: 5, assigned_user_code: 48213 }, { id: 48213, user_code: 48213 }), true);
    assert.equal(isDeviceOwnedByAuthUser(null, manager), false);
    assert.equal(isDeviceOwnedByAuthUser({ owner_user_id: 7 }, null), false);
  });

  it('isDeviceAssignableToManagedSite / isDeviceVisibleToManagedSites gercek sahibi kabul eder, tesadufi esitligi reddeder', () => {
    const sites = new Set([101]);
    const mine = { site_code: null, assigned_door_site_code: null, owner_user_id: 7, assigned_user_code: null };
    const coincidence = { site_code: null, assigned_door_site_code: null, owner_user_id: 48213, assigned_user_code: 11111 };
    assert.equal(isDeviceAssignableToManagedSite(mine, sites, 101, manager), true);
    assert.equal(isDeviceVisibleToManagedSites(mine, sites, manager), true);
    assert.equal(isDeviceAssignableToManagedSite(coincidence, sites, 101, manager), false);
    assert.equal(isDeviceVisibleToManagedSites(coincidence, sites, manager), false);
  });
});

describe('listAssignableDevicesForUser: owner_user_id parametresi users.id (db_id)', () => {
  it('db_id $1, user_code $2; super user bayragi $4', async () => {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ text: String(text), params });
      return { rows: [], rowCount: 0 };
    };
    await listAssignableDevicesForUser({ siteCode: '101', authUser: manager });
    assert.deepEqual(calls[0].params, [7, 48213, 101, false]);
    await listAssignableDevicesForUser({ siteCode: 101, authUser: superUser });
    assert.deepEqual(calls[1].params, [1, 10001, 101, true]);
    // db_id bilinmiyorsa user_code owner_user_id yerine KULLANILMAZ (null)
    await listAssignableDevicesForUser({ siteCode: 101, authUser: { id: 48213, user_code: 48213, role: 'site_manager' } });
    assert.deepEqual(calls[2].params, [null, 48213, 101, false]);
  });
});

describe('replaceDoorDevice - UID/QR yolunda owner_user_id users.id olarak yazilir/karsilastirilir', () => {
  const door = { id: 10, site_code: 101, door_name: 'Ana', assigned_device_id: null, site_name: 'S' };
  const isCode = (code, statusCode) => (err) => {
    assert.equal(err.code, code);
    assert.equal(err.statusCode, statusCode);
    return true;
  };

  // claimRowCount: sahipsiz cihazi sahiplenen UPDATE'in etkiledigi satir sayisi (0 = baskasi sahiplendi)
  function fakeClient({ device = null, claimRowCount = 1, usersRow = null } = {}) {
    const client = {
      sqls: [],
      params: [],
      log: [],
      released: false,
      async query(text, params) {
        const sql = norm(text);
        client.sqls.push(sql);
        client.params.push(params);
        client.log.push(sql.split(' ').slice(0, 3).join(' '));
        if (/FROM site_doors d JOIN sites s/.test(sql)) {
          return { rowCount: 1, rows: [door] };
        }
        if (/^SELECT id FROM users WHERE user_code = \$1/.test(sql)) {
          return usersRow ? { rowCount: 1, rows: [usersRow] } : { rowCount: 0, rows: [] };
        }
        if (/FROM devices LEFT JOIN site_doors assigned_door/.test(sql)) {
          return device ? { rowCount: 1, rows: [{ ...device }] } : { rowCount: 0, rows: [] };
        }
        if (/^UPDATE devices SET owner_user_id/.test(sql)) {
          return { rowCount: claimRowCount, rows: [] };
        }
        if (/^INSERT INTO devices/.test(sql)) {
          return { rowCount: 1, rows: [{ id: 555, device_uid: 'AABBCCDDEEFF' }] };
        }
        return { rowCount: 0, rows: [] };
      },
      release() {
        client.released = true;
      },
    };
    return client;
  }

  const managerOf101 = async (text) =>
    (/site_manager_sites/.test(text) ? { rows: [{ site_code: 101 }], rowCount: 1 } : { rows: [], rowCount: 0 });

  const claimUpdate = (client) => {
    const index = client.sqls.findIndex((sql) => /^UPDATE devices SET owner_user_id/.test(sql));
    return index < 0 ? null : { sql: client.sqls[index], params: client.params[index] };
  };

  it('sahipsiz envanter cihazi: owner_user_id = users.id (db_id), assigned_user_code = user_code; FK ihlali yok', async () => {
    const client = fakeClient({
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: null, assigned_user_code: null, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = managerOf101;
    pool.connect = async () => client;
    const result = await replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: manager });
    assert.equal(result.newDeviceUid, 'D4C771A172E0');
    const claim = claimUpdate(client);
    assert.ok(claim, 'sahiplenme UPDATE calismali');
    assert.deepEqual(claim.params, [7, 48213, 6], '[users.id, user_code, device id]; user_code owner_user_id e YAZILMAZ');
    assert.match(claim.sql, /WHERE id = \$3 AND owner_user_id IS NULL AND assigned_user_code IS NULL/);
    assert.ok(client.log.includes('COMMIT'));
    assert.equal(client.released, true);
  });

  it('yoneticinin KENDI sahiplendigi cihaz (owner_user_id = users.id) yanlis 409 vermez ve yeniden sahiplenilmez', async () => {
    const client = fakeClient({
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: 7, assigned_user_code: 48213, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = managerOf101;
    pool.connect = async () => client;
    const result = await replaceDoorDevice({ doorId: 10, newDeviceInput: 'GD-WROOM-D4C771A172E0', authUser: manager });
    assert.equal(result.newDeviceUid, 'D4C771A172E0');
    assert.equal(claimUpdate(client), null, 'zaten sahibi olan cihaza ikinci sahiplenme UPDATE i yok');
    assert.ok(client.log.includes('COMMIT'));
  });

  it('baskasinin cihazi 409 - owner_user_id degeri tesaduf bu kullanicinin user_code una esit olsa bile', async () => {
    const client = fakeClient({
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: 48213, assigned_user_code: 11111, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = managerOf101;
    pool.connect = async () => client;
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: manager }),
      isCode('DEVICE_OWNED_BY_ANOTHER', 409),
    );
    assert.ok(client.log.includes('ROLLBACK'));
    assert.equal(claimUpdate(client), null);
  });

  it('owner_user_id bos ama assigned_user_code baskasina ait cihaz ele gecirilemez (409, UPDATE yok)', async () => {
    const client = fakeClient({
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: null, assigned_user_code: 11111, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = managerOf101;
    pool.connect = async () => client;
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: manager }),
      isCode('DEVICE_OWNED_BY_ANOTHER', 409),
    );
    assert.equal(claimUpdate(client), null);
  });

  it('sahiplenme yarisi: UPDATE 0 satir doner (baska yonetici kapti) -> 409 ve ROLLBACK', async () => {
    const client = fakeClient({
      claimRowCount: 0,
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: null, assigned_user_code: null, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = managerOf101;
    pool.connect = async () => client;
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: manager }),
      isCode('DEVICE_OWNED_BY_ANOTHER', 409),
    );
    assert.ok(client.log.includes('ROLLBACK'));
  });

  it('super user sahipsiz cihazda users.id yazar (user_code degil); baskasinin cihazini da degistirebilir', async () => {
    const free = fakeClient({
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: null, assigned_user_code: null, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = async () => ({ rows: [], rowCount: 0 });
    pool.connect = async () => free;
    await replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: superUser });
    assert.deepEqual(claimUpdate(free).params, [1, 10001, 6]);

    const owned = fakeClient({
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: 99, assigned_user_code: 99999, is_defective: false, assigned_door_site_code: null },
    });
    pool.connect = async () => owned;
    const result = await replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: superUser });
    assert.equal(result.newDeviceUid, 'D4C771A172E0');
    assert.equal(claimUpdate(owned), null);
  });

  it('envanterde olmayan gecerli hex UID: INSERT owner_user_id = users.id', async () => {
    const client = fakeClient({ device: null });
    pool.query = managerOf101;
    pool.connect = async () => client;
    await replaceDoorDevice({ doorId: 10, newDeviceInput: 'GD-WROOM-AABBCCDDEEFF', authUser: manager });
    const index = client.sqls.findIndex((sql) => /^INSERT INTO devices/.test(sql));
    assert.ok(index >= 0, 'INSERT calismali');
    assert.deepEqual(client.params[index], ['AABBCCDDEEFF', 'esp32_wroom', 7, 48213]);
  });

  it('oturum nesnesinde db_id yoksa users.id, user_code uzerinden SELECT ile cozulur', async () => {
    const client = fakeClient({
      usersRow: { id: 7 },
      device: { id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: null, assigned_user_code: null, is_defective: false, assigned_door_site_code: null },
    });
    pool.query = managerOf101;
    pool.connect = async () => client;
    await replaceDoorDevice({
      doorId: 10,
      newDeviceInput: 'D4C771A172E0',
      authUser: { id: 48213, user_code: 48213, role: 'site_manager' },
    });
    const lookup = client.sqls.findIndex((sql) => /^SELECT id FROM users WHERE user_code = \$1/.test(sql));
    assert.ok(lookup >= 0);
    assert.deepEqual(client.params[lookup], [48213]);
    assert.deepEqual(claimUpdate(client).params, [7, 48213, 6]);
  });

  it('kaynakta authUser.id (user_code) ile owner_user_id yazma/karsilastirma kalibi kalmadi', async () => {
    const { readFileSync } = await import('node:fs');
    const source = readFileSync(new URL('../src/services/door_service.js', import.meta.url), 'utf8');
    assert.equal(/Number\(authUser\.id\)/.test(source), false);
    assert.equal(/authUser\?\.id \|\| authUser\?\.db_id/.test(source), false);
    const site = readFileSync(new URL('../src/services/site_service.js', import.meta.url), 'utf8');
    assert.equal(/authUser\.id \|\| authUser\.db_id/.test(site), false);
  });
});

describe('listAccessibleDoorsForUser - pasife alinmis uyeligin ek kapi izni (override) CALISMAZ', () => {
  async function captureSql(authUser) {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ sql: norm(String(text).replace(/--[^\n]*/g, ' ')), params });
      return { rows: [], rowCount: 0 };
    };
    await listAccessibleDoorsForUser(authUser);
    return calls[0];
  }

  it('override kolu uyelik durumuna baglidir: sitede uyelik kayitliysa en az biri AKTIF olmali', async () => {
    const { sql, params } = await captureSql({ id: 48213, user_code: 48213, role: 'apartment_owner' });
    assert.deepEqual(params, [48213, null]);
    // 2. kol: ek izin VAR ve (hic uyelik/sakinlik yok VEYA aktif uyelik VEYA aktif sakin gostergesi var)
    assert.match(
      sql,
      /OR \( EXISTS \( SELECT 1 FROM door_access_overrides dao WHERE dao\.door_id = d\.id AND dao\.user_code = \$1 AND dao\.is_allowed = TRUE \) AND \( NOT \( EXISTS \( SELECT 1 FROM apartment_memberships am_any INNER JOIN apartments a_any ON a_any\.id = am_any\.apartment_id WHERE a_any\.site_code = d\.site_code AND am_any\.user_code = \$1 \) OR EXISTS \( SELECT 1 FROM apartments a_any_res WHERE a_any_res\.site_code = d\.site_code AND a_any_res\.resident_user_code = \$1 \) \) OR EXISTS \( SELECT 1 FROM apartment_memberships am_on INNER JOIN apartments a_on ON a_on\.id = am_on\.apartment_id WHERE a_on\.site_code = d\.site_code AND a_on\.is_active = TRUE AND am_on\.user_code = \$1 AND am_on\.is_active = TRUE \) OR EXISTS \( SELECT 1 FROM apartments a_on_res WHERE a_on_res\.site_code = d\.site_code AND a_on_res\.is_active = TRUE AND a_on_res\.resident_user_code = \$1 \) \) \)/,
    );
    // parantezler dengeli (yeni blok SQL'i bozmaz)
    assert.equal((sql.match(/\(/g) || []).length, (sql.match(/\)/g) || []).length);
  });

  it('yonetici/site sahibi kolu (1) ve reddetme (is_allowed = FALSE) kolu degismedi', async () => {
    const { sql } = await captureSql({ id: 1, user_code: 1, role: 'apartment_owner' });
    assert.match(sql, /sms\.site_code = d\.site_code AND sms\.manager_user_code = \$1/);
    assert.match(sql, /sm\.role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND sm\.is_active = TRUE/);
    assert.match(sql, /NOT EXISTS \( SELECT 1 FROM door_access_overrides dao_neg WHERE dao_neg\.door_id = d\.id AND dao_neg\.user_code = \$1 AND dao_neg\.is_allowed = FALSE \)/);
  });

  it('getAccessibleDoorForUser (acma/QR/misafir yollarinin ortak noktasi) ayni sorguyu kullanir', async () => {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ sql: norm(text), params });
      return { rows: [], rowCount: 0 };
    };
    await getAccessibleDoorForUser({ authUser: { id: 48213, role: 'apartment_owner' }, doorId: 5 });
    assert.match(calls[0].sql, /am_any/);
    assert.match(calls[0].sql, /a_on_res/);
    assert.deepEqual(calls[0].params, [48213, 5]);
  });

  it('super user sorgusu uyelik kosulu icermez (her kapi)', async () => {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ sql: norm(text), params });
      return { rows: [], rowCount: 0 };
    };
    await listAccessibleDoorsForUser({ id: 1, role: 'super_user' });
    assert.doesNotMatch(calls[0].sql, /am_any/);
  });
});
