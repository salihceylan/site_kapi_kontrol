// Guvenlik (guv/claim-kapsam): cihaz sahiplenme (claim) ve degistirme (replace / kapiya atama) uclari site KAPSAMI olmadan
// calisiyordu: A sitesinin yoneticisi, B sitesinde takili sahipsiz bir cihazi sahiplenip MQTT parolasini / yerel kontrol anahtarini
// alabiliyor ya da sahibini ve kapisini sorarak cihazin varligini ogrenebiliyordu. Bu dosya (DB'siz, sıkı sahte istemci):
//   - SQL sozlesmesi: arama sorgusu ve atomik UPDATE kapsam kosulunu ve dogru parametreleri tasir;
//   - saldiri senaryolari: A yoneticisi B cihazini claim / replace / kapiya atama ile ele gecirEMEZ (404; varlik sizmaz, hicbir yazim yok);
//   - mesru akis: kendi sitesinde, envanter cihazinda, kendi cihazinda ve super kullanicida davranis AYNI.
// SQL'in GERCEK davranisi (kapsam kosulunun PostgreSQL'de dogru calistigi) scripts/qa_device_scope_pg.mjs ile gercek PG'de sinanir.
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pool } from '../src/db.js';
import { claimDevice } from '../src/services/membership_service.js';
import { membershipRouter } from '../src/routes/membership_routes.js';
import { managerRouter } from '../src/routes/manager_routes.js';
import {
  SQL_CLAIM_DEVICE_ATOMIC,
  sqlDeviceDeployedOutsideManagedSites,
  sqlDeviceVisibleToClaimant,
  sqlManagedSiteCodes,
} from '../src/services/membership_rules.js';
import { isDeviceInManagerScope } from '../src/services/site_service.js';
import { replaceDoorDevice, updateDoorDeviceAssignment } from '../src/services/door_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const NOT_REGISTERED = /şirket envanterinde kayıtlı değildir/;

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

// Oturum kullanicilari: id/user_code = 5 haneli oturum kimligi, db_id = users.id
const SITE_A = 101; // saldirganin yonettigi site
const SITE_B = 555; // magdurun sitesi
const attacker = { id: 48213, user_code: 48213, userCode: 48213, db_id: 7, userId: 7, role: 'site_manager' };
const superUser = { id: 10001, user_code: 10001, userCode: 10001, db_id: 1, userId: 1, role: 'super_user' };

// ---------------------------------------------------------------------------
// 1) Saf kapsam kurali
// ---------------------------------------------------------------------------
describe('isDeviceInManagerScope: cihaz kullanicinin kapsaminda mi?', () => {
  const managed = new Set([SITE_A]);
  const device = (extra = {}) => ({ site_code: null, assigned_door_site_code: null, owner_user_id: null, assigned_user_code: null, ...extra });

  it('super kullanici (null) her cihazi gorur; yetkisiz/bos girdi kapaliya duser', () => {
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B, assigned_door_site_code: SITE_B }), null, superUser), true);
    assert.equal(isDeviceInManagerScope(null, managed, attacker), false);
    assert.equal(isDeviceInManagerScope(undefined, null, superUser), true, 'super icin kapsam sinirsiz (cihaz bos olsa bile cagiran karar verir)');
    // Set olmayan yonetilen-site girdisi KAPALI duser: bagli cihaz kapsam disi sayilir
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_A }), [SITE_A], attacker), false);
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_A }), undefined, attacker), false);
  });

  it('hicbir yere bagli olmayan envanter cihazi kapsamdadir (sahiplik kurallari ayrica denetlenir)', () => {
    assert.equal(isDeviceInManagerScope(device(), managed, attacker), true);
    assert.equal(isDeviceInManagerScope(device({ owner_user_id: 999, assigned_user_code: 999 }), managed, attacker), true);
  });

  it('yonetilen siteye bagli cihaz kapsamdadir; yonetilmeyen siteye (site_code YA DA kapi) bagli cihaz DEGIL', () => {
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_A, assigned_door_site_code: SITE_A }), managed, attacker), true);
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B, assigned_door_site_code: SITE_B }), managed, attacker), false);
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B }), managed, attacker), false, 'yalniz devices.site_code');
    assert.equal(isDeviceInManagerScope(device({ assigned_door_site_code: SITE_B }), managed, attacker), false, 'yalniz kapi baglantisi');
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_A, assigned_door_site_code: SITE_B }), managed, attacker), false, 'tutarsiz: biri yonetilmeyen');
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_A }), new Set(), attacker), false, 'hicbir site yonetmeyen kullanici');
  });

  it('pg BIGINT degerleri string doner: "555" da yonetilmeyen siteyi yakalar, "101" yonetileni', () => {
    assert.equal(isDeviceInManagerScope(device({ site_code: String(SITE_B), assigned_door_site_code: String(SITE_B) }), managed, attacker), false);
    assert.equal(isDeviceInManagerScope(device({ site_code: String(SITE_A), assigned_door_site_code: String(SITE_A) }), managed, attacker), true);
  });

  it('cihazin KENDI sahibi (owner_user_id = users.id ya da assigned_user_code = user_code) kendi cihazini gorur; tesadufi esitlik sahip yapmaz', () => {
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B, assigned_door_site_code: SITE_B, owner_user_id: 7 }), managed, attacker), true);
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B, assigned_door_site_code: SITE_B, assigned_user_code: 48213 }), managed, attacker), true);
    // owner_user_id degeri tesaduf saldirganin user_code una esit: SAHIP DEGIL
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B, assigned_door_site_code: SITE_B, owner_user_id: 48213, assigned_user_code: 11111 }), managed, attacker), false);
    assert.equal(isDeviceInManagerScope(device({ site_code: SITE_B, owner_user_id: 999, assigned_user_code: 999 }), managed, attacker), false);
  });
});

// ---------------------------------------------------------------------------
// 2) SQL sozlesmesi
// ---------------------------------------------------------------------------
describe('SQL sozlesmesi: kapsam kosulu arama sorgusunda ve atomik UPDATE te bulunur', () => {
  const balanced = (sql) => (sql.match(/\(/g) || []).length === (sql.match(/\)/g) || []).length;

  it('sqlManagedSiteCodes: getManagedSiteCodes ile AYNI kume (site_manager_sites UNION aktif SITE_OWNER/SITE_ADMIN)', () => {
    const sql = norm(sqlManagedSiteCodes('$9'));
    assert.match(sql, /FROM site_manager_sites scope_sms WHERE scope_sms\.manager_user_code = \$9/);
    assert.match(sql, /UNION SELECT scope_sm\.site_code FROM site_memberships scope_sm WHERE scope_sm\.user_code = \$9 AND scope_sm\.role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND scope_sm\.is_active = TRUE/);
  });

  it('sqlDeviceDeployedOutsideManagedSites: devices.site_code VE kapi baglantisi (site_doors) okunur; bagli olmayan icin FALSE', () => {
    const sql = norm(sqlDeviceDeployedOutsideManagedSites('d', '$2'));
    assert.match(sql, /d\.site_code IS NOT NULL AND NOT EXISTS \(SELECT 1 FROM \(SELECT scope_sms\.site_code/);
    assert.match(sql, /EXISTS \( SELECT 1 FROM site_doors scope_door WHERE scope_door\.assigned_device_id = d\.id AND NOT EXISTS \(SELECT 1 FROM \(SELECT scope_sms\.site_code/);
    assert.doesNotMatch(sql, /\bNOT IN\b/, 'NOT IN kullanilmaz: yonetilen-site kumesinde NULL cikarsa kapsam ACILIRDI; NOT EXISTS kapali kalir');
    assert.ok(balanced(sql));
  });

  it('sqlDeviceVisibleToClaimant: super VEYA kendi cihazi VEYA yonetilmeyen siteye bagli degil', () => {
    const sql = norm(sqlDeviceVisibleToClaimant('found', { userCodeParam: '$3', userIdParam: '$4', superParam: '$5' }));
    assert.match(sql, /^\( \$5::BOOLEAN = TRUE OR found\.owner_user_id = \$4 OR NOT \(/);
    assert.match(sql, /scope_sms\.manager_user_code = \$3/);
    assert.ok(balanced(sql));
  });

  it('SQL_CLAIM_DEVICE_ATOMIC: mevcut kosullar korunur + kapsam + atama kosulu; super ($4) hepsini atlar', () => {
    const sql = norm(SQL_CLAIM_DEVICE_ATOMIC);
    assert.match(sql, /WHERE id = \$3 AND owner_user_id IS NULL AND COALESCE\(is_defective, FALSE\) = FALSE AND \( \$4::BOOLEAN = TRUE OR \(/);
    assert.match(sql, /\(assigned_user_code IS NULL OR assigned_user_code = \$2\)/, 'baska kullaniciya atanmis cihazin uzerine yazilmaz');
    assert.match(sql, /AND NOT \( \(devices\.site_code IS NOT NULL AND NOT EXISTS \(SELECT 1 FROM \(SELECT scope_sms\.site_code/);
    assert.match(sql, /scope_door\.assigned_device_id = devices\.id AND NOT EXISTS \(SELECT 1 FROM \(SELECT scope_sms\.site_code/);
    assert.doesNotMatch(sql, /\bNOT IN\b/);
    assert.match(sql, /RETURNING id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at, is_defective/);
    assert.ok(balanced(sql));
    // yer tutucular $1..$4 disinda parametre yok
    assert.deepEqual([...new Set(sql.match(/\$\d+/g))].sort(), ['$1', '$2', '$3', '$4']);
  });
});

// ---------------------------------------------------------------------------
// 3) POST /membership/claim-device
// ---------------------------------------------------------------------------
function installClaimDb({ role = 'site_manager', lookupRows = [], updateRows = [], recheckRows = [] } = {}) {
  const log = [];
  const client = {
    released: false,
    release() {
      client.released = true;
    },
    query: async (text, params = []) => {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
      if (/^SELECT id, user_code, full_name, email, email_verified, role FROM users/.test(sql)) {
        return ok([{ id: 7, user_code: 48213, full_name: 'Ayse', email: 'a@example.com', email_verified: true, role }]);
      }
      if (/^SELECT s\.site_code FROM sites s WHERE s\.approval_status = 'approved'/.test(sql)) return ok([{ site_code: SITE_A }]);
      if (/^SELECT found\.id, found\.device_uid/.test(sql)) return ok(lookupRows);
      if (/^UPDATE devices SET owner_user_id/.test(sql)) return ok(updateRows);
      if (/^SELECT owner_user_id, is_defective FROM devices/.test(sql)) return ok(recheckRows);
      throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    },
  };
  pool.connect = async () => client;
  return { log, client };
}

const inventoryRow = (extra = {}) => ({
  id: 77,
  device_uid: 'D4C771A172E0',
  hardware_type: 'esp32_wroom',
  gate_name: null,
  site_code: null,
  owner_user_id: null,
  assigned_user_code: null,
  claimed_at: null,
  is_defective: false,
  defective_reason: null,
  ...extra,
});
// SQL_CLAIM_DEVICE_ATOMIC RETURNING satiri: assigned_user_code / defective_reason YOKTUR (gercek UPDATE nin bicimi).
const returningRow = (extra = {}) => {
  const row = inventoryRow(extra);
  delete row.assigned_user_code;
  delete row.defective_reason;
  return row;
};
const lookupOf = (log) => log.find((entry) => /^SELECT found\.id/.test(entry.sql));
const updateOf = (log) => log.find((entry) => /^UPDATE devices SET owner_user_id/.test(entry.sql));
const rolledBack = (log) => log.some((entry) => entry.sql === 'ROLLBACK');

describe('claimDevice: arama sorgusu kapsami SQL de uygular; kapsam disi cihaz "kayitli degil" (404)', () => {
  it('arama sorgusu: kapsam kosulu + parametreler [uid, ham, user_code, users.id, super mi]', async () => {
    const { log } = installClaimDb({ lookupRows: [inventoryRow()], updateRows: [returningRow({ owner_user_id: 7 })] });
    await claimDevice({ userCode: 48213, deviceInput: 'GD-WROOM-D4C771A172E0' });
    const lookup = lookupOf(log);
    assert.ok(lookup, 'arama sorgusu calisti');
    assert.deepEqual(lookup.params, ['D4C771A172E0', 'GD-WROOM-D4C771A172E0', 48213, 7, false]);
    assert.match(lookup.sql, /FROM devices WHERE UPPER\(device_uid\) = \$1 OR UPPER\(device_uid\) = \$2 OR UPPER\(REPLACE\(REPLACE\(device_uid, ':', ''\), '-', ''\)\) = \$1 \) found WHERE \( \$5::BOOLEAN = TRUE OR found\.owner_user_id = \$4 OR NOT \(/);
    assert.match(lookup.sql, /scope_door\.assigned_device_id = found\.id/);
    assert.match(lookup.sql, /scope_sms\.manager_user_code = \$3/);
  });

  it('SALDIRI: B sitesinin cihazi (DB kapsam disi oldugu icin satir dondurmez) -> 404, UPDATE yok, ROLLBACK, mesaj olmayan cihazla AYNI', async () => {
    const attack = installClaimDb({ lookupRows: [] });
    const first = await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }).catch((e) => e);
    assert.equal(first.statusCode, 404);
    assert.match(first.message, NOT_REGISTERED);
    assert.equal(updateOf(attack.log), undefined, 'sahiplenme UPDATE i calismadi');
    assert.equal(rolledBack(attack.log), true);
    assert.equal(attack.client.released, true);
    const unknown = installClaimDb({ lookupRows: [] });
    const second = await claimDevice({ userCode: 48213, deviceInput: 'FFFFFFFFFFFF' }).catch((e) => e);
    assert.equal(second.statusCode, first.statusCode);
    assert.equal(second.message, first.message, 'olmayan cihazla birebir ayni yanit: varlik sizmaz');
    assert.equal(updateOf(unknown.log), undefined);
  });

  it('super kullanici: kapsam sinirsiz (super=true gecer), UPDATE super=true ile calisir', async () => {
    const { log } = installClaimDb({ role: 'super_user', lookupRows: [inventoryRow({ site_code: SITE_B })], updateRows: [returningRow({ site_code: SITE_B, owner_user_id: 7 })] });
    const result = await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' });
    assert.equal(result.ok, true);
    assert.equal(lookupOf(log).params[4], true);
    assert.deepEqual(updateOf(log).params, [7, 48213, 77, true]);
  });

  it('mesru akis: envanter / kendi sitesindeki sahipsiz cihaz sahiplenilir; UPDATE parametreleri [users.id, user_code, cihaz id, super=false]', async () => {
    const { log, client } = installClaimDb({
      lookupRows: [inventoryRow({ site_code: SITE_A })],
      updateRows: [returningRow({ site_code: SITE_A, owner_user_id: 7, claimed_at: new Date() })],
    });
    const result = await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' });
    assert.equal(result.ok, true);
    assert.equal(result.device.owner_user_id, 7);
    assert.deepEqual(updateOf(log).params, [7, 48213, 77, false]);
    assert.ok(log.some((entry) => entry.sql === 'COMMIT'));
    assert.equal(client.released, true);
  });

  it('istemciye dönen cihaz nesnesi assigned_user_code TASIMAZ (yanit bicimi degismedi)', async () => {
    installClaimDb({
      lookupRows: [inventoryRow({ owner_user_id: 7, assigned_user_code: 48213 })],
    });
    const already = await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' });
    assert.equal(already.already_owned, true);
    assert.equal('assigned_user_code' in already.device, false);
    installClaimDb({ lookupRows: [inventoryRow({ assigned_user_code: 48213 })], updateRows: [returningRow({ owner_user_id: 7 })] });
    const claimed = await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' });
    assert.equal(claimed.ok, true);
    assert.equal('assigned_user_code' in claimed.device, false);
  });

  it('sahipsiz ama BASKASINA ATANMIS (assigned_user_code) cihaz: 409, UPDATE yok (uzerine yazilmaz); kendisine atanmis cihaz sahiplenilir', async () => {
    const other = installClaimDb({ lookupRows: [inventoryRow({ assigned_user_code: 11111 })] });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }), (e) => e.statusCode === 409);
    assert.equal(updateOf(other.log), undefined);
    assert.equal(rolledBack(other.log), true);

    const mine = installClaimDb({ lookupRows: [inventoryRow({ assigned_user_code: 48213 })], updateRows: [returningRow({ owner_user_id: 7 })] });
    assert.equal((await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' })).ok, true);
    assert.ok(updateOf(mine.log));

    // super kullanici atanmis cihazi da devralabilir (mevcut davranis)
    const sup = installClaimDb({ role: 'super_user', lookupRows: [inventoryRow({ assigned_user_code: 11111 })], updateRows: [returningRow({ owner_user_id: 7 })] });
    assert.equal((await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' })).ok, true);
    assert.ok(updateOf(sup.log));
  });

  it('mevcut 409 / 400 davranisi korunur: sahipli cihaz 409, arizali cihaz 400 (kapsamdaki cihazlarda)', async () => {
    installClaimDb({ lookupRows: [inventoryRow({ owner_user_id: 99 })] });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }), (e) => e.statusCode === 409);
    installClaimDb({ lookupRows: [inventoryRow({ is_defective: true, defective_reason: 'kırık' })] });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }), (e) => e.statusCode === 400 && /arızalı/.test(e.message));
  });

  it('YARIS: arama gordu ama UPDATE 0 satir (cihaz bu arada B sitesine baglandi) ve kapsamli yeniden kontrol satir dondurmez -> 404 (409 DEGIL)', async () => {
    const { log } = installClaimDb({ lookupRows: [inventoryRow()], updateRows: [], recheckRows: [] });
    const error = await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }).catch((e) => e);
    assert.equal(error.statusCode, 404);
    assert.match(error.message, NOT_REGISTERED);
    assert.equal(rolledBack(log), true);
    const recheck = log.find((entry) => /^SELECT owner_user_id, is_defective FROM devices/.test(entry.sql));
    assert.deepEqual(recheck.params, [77, 48213, 7, false], 'yeniden kontrol de AYNI kapsam kosuluyla ve ayni kimliklerle');
    assert.match(recheck.sql, /WHERE id = \$1 AND \( \$4::BOOLEAN = TRUE OR devices\.owner_user_id = \$3 OR NOT \(/);
  });

  it('YARIS: 0 satir, yeniden kontrolde cihaz GORUNUR ve baskasinin -> 409; kendi cihazi ise already_owned; arizali -> 400', async () => {
    installClaimDb({ lookupRows: [inventoryRow()], updateRows: [], recheckRows: [{ owner_user_id: 99, is_defective: false }] });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }), (e) => e.statusCode === 409);
    installClaimDb({ lookupRows: [inventoryRow()], updateRows: [], recheckRows: [{ owner_user_id: 7, is_defective: false }] });
    assert.equal((await claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' })).already_owned, true);
    installClaimDb({ lookupRows: [inventoryRow()], updateRows: [], recheckRows: [{ owner_user_id: null, is_defective: true }] });
    await assert.rejects(() => claimDevice({ userCode: 48213, deviceInput: 'D4C771A172E0' }), (e) => e.statusCode === 400);
  });

  it('kaynak: kapsam yardimcisi kullanilir ve atomik UPDATE e super bayragi (4. parametre) gecer', () => {
    const source = readFileSync(new URL('../src/services/membership_service.js', import.meta.url), 'utf8');
    assert.match(source, /sqlDeviceVisibleToClaimant\('found'/);
    assert.match(source, /sqlDeviceVisibleToClaimant\('devices'/);
    assert.match(source, /client\.query\(SQL_CLAIM_DEVICE_ATOMIC, \[user\.id, user\.user_code, deviceRow\.id, isSuper\]\)/);
  });
});

// ---------------------------------------------------------------------------
// 4) Rota duzeyi: POST /membership/claim-device, replace-device, kapiya atama
// ---------------------------------------------------------------------------
function routeHandler(router, method, routePath) {
  const layer = router.stack.find((item) => item.route && item.route.path === routePath && item.route.methods[method]);
  assert.ok(layer, `${method.toUpperCase()} ${routePath} rotasi bulunamadi`);
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

async function callRoute(router, method, routePath, { params = {}, body = {}, authUser }) {
  const handler = routeHandler(router, method, routePath);
  const res = {
    statusCode: 200,
    body: undefined,
    headers: {},
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    send() {
      return this;
    },
  };
  const silenced = { error: console.error, warn: console.warn, log: console.log };
  console.error = () => {};
  console.warn = () => {};
  console.log = () => {};
  try {
    await handler({ params, body, query: {}, headers: {}, ip: '127.0.0.1', authUser }, res);
  } finally {
    Object.assign(console, silenced);
  }
  return res;
}

describe('rota duzeyi: A yoneticisi B nin cihazini claim edemez (404 + "kayitli degil")', () => {
  it('POST /membership/claim-device -> 404 ve olmayan cihazla ayni govde', async () => {
    installClaimDb({ lookupRows: [] });
    const attack = await callRoute(membershipRouter, 'post', '/membership/claim-device', { body: { deviceInput: 'GD-WROOM-D4C771A172E0' }, authUser: attacker });
    installClaimDb({ lookupRows: [] });
    const unknown = await callRoute(membershipRouter, 'post', '/membership/claim-device', { body: { deviceInput: 'GD-WROOM-FFFFFFFFFFFF' }, authUser: attacker });
    assert.equal(attack.statusCode, 404);
    assert.match(attack.body.error, NOT_REGISTERED);
    assert.deepEqual(attack.body, unknown.body);
  });

  it('POST /membership/claim-device mesru: kendi/envanter cihazi 200', async () => {
    installClaimDb({ lookupRows: [inventoryRow()], updateRows: [returningRow({ owner_user_id: 7 })] });
    const res = await callRoute(membershipRouter, 'post', '/membership/claim-device', { body: { deviceInput: 'D4C771A172E0' }, authUser: attacker });
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.ok, true);
  });
});

// Kapi/cihaz sahte DB'si: pool.query (yetki sorgulari) + pool.connect (islem istemcisi). Sıkı: tanimsiz SQL hata verir.
function installDoorDb({ device = null, door = { id: 10, site_code: SITE_A, door_name: 'A Ana Kapi', assigned_device_id: 5, site_name: 'A' }, managed = [SITE_A], claimRowCount = 1 } = {}) {
  const sqls = [];
  const client = {
    sqls,
    released: false,
    release() {
      client.released = true;
    },
    query: async (text) => {
      const sql = norm(text);
      sqls.push(sql);
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
      if (/FROM site_doors d JOIN sites s/.test(sql)) return ok(door ? [door] : []);
      if (/^SELECT id, site_code, door_name, assigned_device_id FROM site_doors/.test(sql)) return ok(door ? [door] : []);
      if (/FROM devices LEFT JOIN site_doors assigned_door/.test(sql) || /FROM devices LEFT JOIN site_doors door ON door\.assigned_device_id = devices\.id/.test(sql)) {
        return ok(device ? [{ ...device }] : []);
      }
      if (/^SELECT device_uid FROM devices WHERE id = \$1/.test(sql)) return ok([{ device_uid: 'ESKICIHAZ001' }]);
      if (/^UPDATE devices SET owner_user_id/.test(sql)) return { rows: [], rowCount: claimRowCount };
      if (/^INSERT INTO devices/.test(sql)) return ok([{ id: 555, device_uid: 'AABBCCDDEEFF' }]);
      if (/^(UPDATE|INSERT INTO) (devices|site_doors|site_modules)/.test(sql)) return { rows: [], rowCount: 1 };
      if (/^SELECT d\.id, d\.site_code, sites\.name AS site_name/.test(sql)) return ok([{ id: 10, site_code: SITE_A }]);
      throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    },
  };
  pool.connect = async () => client;
  pool.query = async (text, params = []) => {
    const sql = norm(text);
    if (/^SELECT site_code FROM site_doors WHERE id = \$1/.test(sql)) return ok(door ? [{ site_code: door.site_code }] : []);
    // hasSiteManagementAccess: site_manager_sites, sonra site_memberships
    if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2/.test(sql)) {
      return ok(managed.includes(Number(params[0])) ? [{ one: 1 }] : []);
    }
    if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2/.test(sql)) return ok([]);
    // getManagedSiteCodes
    if (/^SELECT site_code FROM site_manager_sites WHERE manager_user_code = \$1 UNION/.test(sql)) return ok(managed.map((site_code) => ({ site_code })));
    if (/^SELECT approval_status FROM sites WHERE site_code = \$1/.test(sql)) return ok([{ approval_status: 'approved' }]);
    throw new Error(`SAHTE VERITABANI (pool): tanimsiz SQL: ${sql}`);
  };
  return client;
}

const writes = (client) => client.sqls.filter((sql) => /^(UPDATE|INSERT INTO|DELETE FROM)\b/.test(sql));
const bDevice = (extra = {}) => ({
  id: 6,
  device_uid: 'D4C771A172E0',
  site_code: SITE_B,
  owner_user_id: null,
  assigned_user_code: null,
  is_defective: false,
  assigned_door_site_code: SITE_B,
  ...extra,
});
const isNotFound = (error) => {
  assert.equal(error.message, 'DEVICE_NOT_FOUND');
  assert.equal(error.code, 'DEVICE_NOT_FOUND');
  assert.equal(error.statusCode, 404);
  return true;
};

describe('replaceDoorDevice: A yoneticisi B nin cihazini kendi kapisina takamaz (404; sahiplik ve atanmislik sizmaz)', () => {
  const attacks = [
    ['id ile, sahipsiz B cihazi', { newDeviceId: 6 }, bDevice()],
    ['id ile, B yoneticisinin sahip oldugu cihaz (eskiden 409)', { newDeviceId: 6 }, bDevice({ owner_user_id: 999, assigned_user_code: 999 })],
    ['UID ile, sahipsiz B cihazi (eskiden: sahiplen + 403)', { newDeviceInput: 'D4C771A172E0' }, bDevice()],
    ['UID/QR ile, B yoneticisinin cihazi (eskiden 409)', { newDeviceInput: 'GD-WROOM-D4C771A172E0' }, bDevice({ owner_user_id: 999, assigned_user_code: 999 })],
    ['yalniz devices.site_code=B (kapi kaydi yok)', { newDeviceInput: 'D4C771A172E0' }, bDevice({ assigned_door_site_code: null })],
    ['yalniz B kapisina takili (devices.site_code bos)', { newDeviceId: 6 }, bDevice({ site_code: null })],
  ];
  for (const [name, input, device] of attacks) {
    it(`SALDIRI ${name}: DEVICE_NOT_FOUND / 404, HICBIR yazim yok, ROLLBACK`, async () => {
      const client = installDoorDb({ device });
      await assert.rejects(() => replaceDoorDevice({ doorId: 10, ...input, authUser: attacker }), isNotFound);
      assert.deepEqual(writes(client), [], 'ne sahiplenme UPDATE i ne kapi/cihaz yazimi ne INSERT');
      assert.ok(client.sqls.includes('ROLLBACK'));
      assert.equal(client.sqls.includes('COMMIT'), false);
      assert.equal(client.released, true);
    });
  }

  it('kendi sahip oldugu cihaz yonetilmeyen sitede: mevcut 403 DEVICE_NOT_ASSIGNABLE korunur (varligini zaten biliyor)', async () => {
    const client = installDoorDb({ device: bDevice({ owner_user_id: 7, assigned_user_code: 48213 }) });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 6, authUser: attacker }),
      (e) => e.code === 'DEVICE_NOT_ASSIGNABLE' && e.statusCode === 403,
    );
    assert.equal(writes(client).length, 0);
  });

  it('MESRU: kendi sitesine bagli sahipsiz cihaz / envanter cihazi / kendi cihazi takilir (davranis ayni)', async () => {
    const own = installDoorDb({ device: bDevice({ site_code: SITE_A, assigned_door_site_code: SITE_A }) });
    const own1 = await replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: attacker });
    assert.equal(own1.newDeviceUid, 'D4C771A172E0');
    assert.ok(own.sqls.includes('COMMIT'));
    assert.ok(own.sqls.some((sql) => /^UPDATE devices SET owner_user_id/.test(sql)), 'sahipsiz cihaz sahiplenildi');

    const inventory = installDoorDb({ device: bDevice({ site_code: null, assigned_door_site_code: null }) });
    const inv = await replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: attacker });
    assert.equal(inv.newDeviceUid, 'D4C771A172E0');
    assert.ok(inventory.sqls.includes('COMMIT'));

    const mine = installDoorDb({ device: bDevice({ site_code: null, assigned_door_site_code: null, owner_user_id: 7, assigned_user_code: 48213 }) });
    const mineResult = await replaceDoorDevice({ doorId: 10, newDeviceId: 6, authUser: attacker });
    assert.equal(mineResult.newDeviceUid, 'D4C771A172E0');
    assert.ok(mine.sqls.includes('COMMIT'));
    assert.equal(mine.sqls.some((sql) => /^UPDATE devices SET owner_user_id/.test(sql)), false);
  });

  it('super kullanici her sitenin cihazini takabilir (kapsam sinirsiz)', async () => {
    const client = installDoorDb({ device: bDevice({ owner_user_id: 999, assigned_user_code: 999 }) });
    const result = await replaceDoorDevice({ doorId: 10, newDeviceId: 6, authUser: superUser });
    assert.equal(result.newDeviceUid, 'D4C771A172E0');
    assert.ok(client.sqls.includes('COMMIT'));
  });

  it('kaynak sirasi: kapsam kapisi, sahiplenme UPDATE inden ONCE calisir', () => {
    const source = readFileSync(new URL('../src/services/door_service.js', import.meta.url), 'utf8');
    const scope = source.indexOf('await assertDeviceInScope(existingDev);');
    const claim = source.indexOf('SET owner_user_id = $1, assigned_user_code = $2, claimed_at = NOW()');
    assert.ok(scope > 0 && claim > 0, 'her iki ifade de bulunmali');
    assert.ok(scope < claim, 'kapsam kontrolu sahiplenmeden once');
    assert.match(source, /await assertDeviceInScope\(devRes\.rows\[0\]\);\r?\n\s+await assertDeviceAssignable\(devRes\.rows\[0\]\);/);
  });
});

describe('updateDoorDeviceAssignment (PATCH /manager/doors/:id/device, kapi olustururken cihaz): B cihazi kapsam disi -> 404', () => {
  it('SALDIRI: A kapisina B cihazi atanamaz (sahipsiz ve sahipli): DEVICE_NOT_FOUND, yazim yok, ROLLBACK', async () => {
    for (const device of [bDevice(), bDevice({ owner_user_id: 999, assigned_user_code: 999 })]) {
      const client = installDoorDb({ device });
      await assert.rejects(
        () => updateDoorDeviceAssignment({ doorId: 10, deviceUid: 'D4C771A172E0', authUser: attacker }),
        (e) => e.message === 'DEVICE_NOT_FOUND',
      );
      assert.deepEqual(writes(client), []);
      assert.ok(client.sqls.includes('ROLLBACK'));
    }
  });

  it('MESRU: kendi cihazi / kendi sitesindeki cihaz atanir; super her cihazi atar', async () => {
    const mine = installDoorDb({ device: bDevice({ site_code: null, assigned_door_site_code: null, owner_user_id: 7, assigned_user_code: 48213 }) });
    await updateDoorDeviceAssignment({ doorId: 10, deviceUid: 'D4C771A172E0', authUser: attacker });
    assert.ok(mine.sqls.includes('COMMIT'));
    assert.ok(mine.sqls.some((sql) => /^UPDATE site_doors SET assigned_device_id = \$1 WHERE id = \$2/.test(sql)));

    const sup = installDoorDb({ device: bDevice({ owner_user_id: 999, assigned_user_code: 999 }) });
    await updateDoorDeviceAssignment({ doorId: 10, deviceUid: 'D4C771A172E0', authUser: superUser });
    assert.ok(sup.sqls.includes('COMMIT'));
  });
});

describe('rota duzeyi: replace-device ve kapiya atama -> 404 JSON', () => {
  it('POST /manager/doors/:id/replace-device: B cihazi -> 404 "Secilen yeni cihaz bulunamadi."', async () => {
    const client = installDoorDb({ device: bDevice({ owner_user_id: 999, assigned_user_code: 999 }) });
    const res = await callRoute(managerRouter, 'post', '/manager/doors/:id/replace-device', {
      params: { id: '10' },
      body: { device_input: 'GD-WROOM-D4C771A172E0' },
      authUser: attacker,
    });
    assert.equal(res.statusCode, 404);
    assert.equal(res.body.error, 'Secilen yeni cihaz bulunamadi.');
    assert.deepEqual(writes(client), []);
  });

  it('PATCH /manager/doors/:id/device: B cihazi -> 404 (403 DEGIL)', async () => {
    const client = installDoorDb({ device: bDevice() });
    const res = await callRoute(managerRouter, 'patch', '/manager/doors/:id/device', {
      params: { id: '10' },
      body: { device_uid: 'D4C771A172E0' },
      authUser: attacker,
    });
    assert.equal(res.statusCode, 404);
    assert.deepEqual(writes(client), []);
  });

  it('kapi baska sitenin ise (B nin kapisi) rota 403 verir ve servise HIC girmez', async () => {
    const client = installDoorDb({ device: bDevice(), door: { id: 20, site_code: SITE_B, door_name: 'B Ana Kapi', assigned_device_id: 6, site_name: 'B' } });
    const res = await callRoute(managerRouter, 'post', '/manager/doors/:id/replace-device', {
      params: { id: '20' },
      body: { device_input: 'D4C771A172E0' },
      authUser: attacker,
    });
    assert.equal(res.statusCode, 403);
    assert.deepEqual(client.sqls, [], 'islem istemcisi hic kullanilmadi');
  });
});
