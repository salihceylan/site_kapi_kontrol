#!/usr/bin/env node
// Cihaz KAPSAMI (claim / replace / kapiya atama) icin GERCEK PostgreSQL dogrulamasi: A sitesinin yoneticisi B sitesinin
// cihazini sahiplenemez / degistiremez / kapiya atayamaz (404; varligi, sahibi ve kapisi sizmaz); kendi sitesinde
// ve envanter cihazlarinda mesru akis bozulmaz. `npm test` ICINDE DEGILDIR; elle / CI'da bilincli olarak calistirilir.
//
//   cd server
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=kapi_qa DB_USER=postgres DB_PASSWORD=x \
//     QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_device_scope_pg.mjs
//
// ONCE `node scripts/migrate.js --apply --yes` ile bos bir yerel veritabani hazirlayin.
//
// GUVENLIK: betik tek kullanimlik YEREL veritabani icindir. DB_HOST yalnizca 127.0.0.1/localhost olabilir ve
// QA_CONFIRM_DISPOSABLE_DB=yes gerekir; aksi halde calismaz. Yalniz kendi QA satirlarini yazar ve siler
// (qa-claim-*@example.com kullanicilari, 10000004x site kodlari, QAC1* UID'li cihazlar). Ag/SMTP baglantisi kurulmaz.
import assert from 'node:assert/strict';

if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('REDDEDILDI: DB_HOST yalnizca 127.0.0.1 veya localhost olabilir (tek kullanimlik yerel veritabani).');
  process.exit(3);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('REDDEDILDI: veritabaninin tek kullanimlik oldugunu QA_CONFIRM_DISPOSABLE_DB=yes ile onaylayin.');
  process.exit(3);
}
process.env.JWT_SECRET ||= 'qa-integration-secret-0123456789abcdef-0123456789';
Object.assign(process.env, {
  SMTP_HOST: 'smtp.invalid',
  SMTP_USER: 'qa@example.invalid',
  SMTP_PASSWORD: 'qa',
  SMTP_FROM: 'AHBU QA <noreply@example.invalid>',
});

const { pool, ensureDbSchema } = await import('../src/db.js');
const { claimDevice } = await import('../src/services/membership_service.js');
const { SQL_CLAIM_DEVICE_ATOMIC } = await import('../src/services/membership_rules.js');
const { replaceDoorDevice, updateDoorDeviceAssignment } = await import('../src/services/door_service.js');
const { getManagedSiteCodes, isDeviceVisibleToManagedSites } = await import('../src/services/site_service.js');
const { findDeviceByUid } = await import('../src/services/device_service.js');

await ensureDbSchema(); // sunucu acilisindaki DDL (mqtt_site_id varsayilani vb.); idempotent

const q = (sql, params = []) => pool.query(sql, params);
const one = async (sql, params) => (await q(sql, params)).rows[0];
let step = 0;
const ok = (name) => console.log(`  OK ${String(++step).padStart(2, '0')}  ${name}`);

const SITE_A = 1000041001;
const SITE_B = 1000041002;
const UID = {
  free: 'QAC100000001', // envanter: hicbir yere bagli degil, sahipsiz
  bDoorFree: 'QAC100000002', // B'nin 1. kapisinda takili, SAHIPSIZ (sahibi hesabi silinmis) -> eski acik
  bDoorOwned: 'QAC100000003', // B'nin 2. kapisinda takili, sahibi B yoneticisi
  ownedOther: 'QAC100000004', // hicbir yere bagli degil, sahibi B yoneticisi
  aDoorFree: 'QAC100000005', // A'nin kapisinda takili, sahipsiz (A meşru olarak sahiplenebilir)
  assignedOther: 'QAC100000006', // hicbir yere bagli degil, sahipsiz ama B yoneticisine ATANMIS
  bSiteOnly: 'QAC100000007', // devices.site_code = B (kapi kaydi yok), sahipsiz
  aOwn: 'QAC100000008', // A yoneticisinin KENDI cihazi (sahibi A), hicbir yere bagli degil
  free2: 'QAC100000009', // ikinci envanter cihazi
  free3: 'QAC100000010',
  bSiteOnly2: 'QAC100000011', // devices.site_code = B (kapi kaydi yok), sahipsiz: B nin SITE_ADMIN UYESI sahiplenebilmeli
};

async function cleanup() {
  await q(`DELETE FROM devices WHERE device_uid LIKE 'QAC1%'`);
  await q(`DELETE FROM sites WHERE site_code IN ($1, $2)`, [SITE_A, SITE_B]);
  await q(`DELETE FROM users WHERE email LIKE 'qa-claim-%@example.com'`);
}
await cleanup();

const user = (code, role) =>
  q(
    `INSERT INTO users (user_code, full_name, email, role, password_hash, login_name, is_active, email_verified, approval_status)
     VALUES ($1, $2, $3, $4, 'x', $5, TRUE, TRUE, 'approved')`,
    [code, `QA ${code}`, `qa-claim-${code}@example.com`, role, `qa_claim_${code}`],
  );
await user(41001, 'site_manager'); // A sitesinin yoneticisi (SALDIRGAN)
await user(41002, 'site_manager'); // B sitesinin yoneticisi (MAGDUR)
await user(41003, 'individual'); // hicbir sitenin yoneticisi degil
await user(41004, 'super_user');
await user(41005, 'site_manager'); // B sitesini YALNIZ site_memberships (SITE_ADMIN) uzerinden yoneten kullanici
const idOf = async (code) => Number((await one(`SELECT id FROM users WHERE user_code = $1`, [code])).id);
const idA = await idOf(41001);
const idB = await idOf(41002);
const authOf = (code, id, role = 'site_manager') => ({ id: code, user_code: code, userCode: code, db_id: id, userId: id, role });
const attacker = authOf(41001, idA);
const victim = authOf(41002, idB);
const superUser = authOf(41004, await idOf(41004), 'super_user');

for (const [site, name, manager] of [[SITE_A, 'QA Site A', 41001], [SITE_B, 'QA Site B', 41002]]) {
  await q(`INSERT INTO sites (site_code, name, approval_status) VALUES ($1, $2, 'approved')`, [site, name]);
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, manager]);
}
await q(`INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, 41005, 'SITE_ADMIN', TRUE)`, [SITE_B]);
const door = async (site, index, name) =>
  Number((await one(`INSERT INTO site_doors (site_code, door_name, door_index) VALUES ($1, $2, $3) RETURNING id`, [site, name, index])).id);
const doorA1 = await door(SITE_A, 1, 'A Ana Kapi');
const doorB1 = await door(SITE_B, 1, 'B Ana Kapi');
const doorB2 = await door(SITE_B, 2, 'B Arka Kapi');
const device = async (uid, { site = null, gate = null, owner = null, assigned = null, door = null } = {}) => {
  const id = Number(
    (await one(
      `INSERT INTO devices (device_uid, hardware_type, site_code, gate_name, owner_user_id, assigned_user_code, claimed_at, local_control_token, mqtt_username, mqtt_password)
       VALUES ($1, 'esp32_wroom', $2, $3, $4, $5, CASE WHEN $4::BIGINT IS NULL THEN NULL ELSE NOW() END, $6, $7, $8) RETURNING id`,
      [uid, site, gate, owner, assigned, `tok-${uid}`, `device_${uid}`, `pw-${uid}`],
    )).id,
  );
  if (door) await q(`UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`, [id, door]);
  return id;
};
const dev = {};
dev.free = await device(UID.free);
dev.bDoorFree = await device(UID.bDoorFree, { site: SITE_B, gate: 'B Ana Kapi', door: doorB1 });
dev.bDoorOwned = await device(UID.bDoorOwned, { site: SITE_B, gate: 'B Arka Kapi', owner: idB, assigned: 41002, door: doorB2 });
dev.ownedOther = await device(UID.ownedOther, { owner: idB, assigned: 41002 });
dev.aDoorFree = await device(UID.aDoorFree, { site: SITE_A, gate: 'A Ana Kapi' });
await q(`UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`, [dev.aDoorFree, doorA1]);
dev.assignedOther = await device(UID.assignedOther, { assigned: 41002 });
dev.bSiteOnly = await device(UID.bSiteOnly, { site: SITE_B });
dev.aOwn = await device(UID.aOwn, { owner: idA, assigned: 41001 });
dev.free2 = await device(UID.free2);
dev.free3 = await device(UID.free3);
dev.bSiteOnly2 = await device(UID.bSiteOnly2, { site: SITE_B });

const row = (uid) => one(`SELECT id, site_code, owner_user_id, assigned_user_code, gate_name FROM devices WHERE device_uid = $1`, [uid]);
const doorDevice = async (id) => (await one(`SELECT assigned_device_id FROM site_doors WHERE id = $1`, [id])).assigned_device_id;
const rejects = async (fn, check, label) => {
  try {
    await fn();
  } catch (error) {
    check(error);
    ok(label);
    return error;
  }
  return assert.fail(`${label}: hata beklenirdi`);
};
const status = (code) => (e) => assert.equal(e.statusCode, code, `HTTP ${code} beklenirdi, gelen ${e.statusCode} ${e.message}`);
const doorCode = (code, statusCode) => (e) => {
  assert.equal(e.message, code, `${code} beklenirdi, gelen ${e.message}`);
  assert.equal(e.statusCode ?? statusCode, statusCode);
};

console.log('--- 1) SALDIRI: A yoneticisi (41001) B sitesinin cihazini sahiplenmeye calisir ---');
const e404unknown = await rejects(() => claimDevice({ userCode: 41001, deviceInput: 'QAC1FFFFFFFF' }), status(404), 'olmayan UID -> 404');
const e404a = await rejects(() => claimDevice({ userCode: 41001, deviceInput: UID.bDoorFree }), status(404), 'B kapisindaki SAHIPSIZ cihaz -> 404');
assert.equal(e404a.message, e404unknown.message, 'mesaj "kayitli degil" ile birebir ayni: cihazin varligi sizmaz');
ok('404 mesaji olmayan UID ile birebir ayni (varlik sizmaz)');
await rejects(() => claimDevice({ userCode: 41001, deviceInput: UID.bDoorOwned }), status(404), 'B kapisindaki SAHIPLI cihaz -> 404 (409 DEGIL: sahibi sizmaz)');
await rejects(() => claimDevice({ userCode: 41001, deviceInput: `GD-WROOM-${UID.bSiteOnly}` }), status(404), 'devices.site_code=B (kapi kaydi yok) cihaz -> 404');
await rejects(() => claimDevice({ userCode: 41001, deviceInput: UID.bSiteOnly2 }), status(404), 'ikinci site_code=B cihaz -> 404 (sonra B nin uyesi sahiplenecek)');
for (const uid of [UID.bDoorFree, UID.bDoorOwned, UID.bSiteOnly]) {
  const r = await row(uid);
  assert.ok(r.owner_user_id === null || Number(r.owner_user_id) === idB, `${uid} sahibi degismedi`);
}
assert.equal((await row(UID.bDoorFree)).owner_user_id, null);
assert.equal((await row(UID.bDoorFree)).assigned_user_code, null);
assert.equal(Number(await doorDevice(doorB1)), dev.bDoorFree);
ok('B cihazlari ve kapi baglantilari DEGISMEDI');

console.log('--- 2) ZINCIRIN 2. HALKASI: saldirgan MQTT kimlik bilgisini goremez ---');
const managedA = await getManagedSiteCodes(attacker);
assert.deepEqual([...managedA], [SITE_A]);
for (const uid of [UID.bDoorFree, UID.bDoorOwned, UID.bSiteOnly]) {
  assert.equal(isDeviceVisibleToManagedSites(await findDeviceByUid(uid), managedA, attacker), false, `${uid} A yoneticisine gorunmez`);
}
ok('B cihazlari A yoneticisine gorunmez (mqtt-credentials / lookup 404)');

console.log('--- 3) SQL KORUMASI TEK BASINA (JS on kontrolu atlansa bile atomik UPDATE kapsami uygular) ---');
for (const id of [dev.bDoorFree, dev.bSiteOnly]) {
  const res = await q(SQL_CLAIM_DEVICE_ATOMIC, [idA, 41001, id, false]);
  assert.equal(res.rowCount, 0, 'atomik UPDATE kapsam disi cihazda 0 satir');
}
ok('SQL_CLAIM_DEVICE_ATOMIC: kapsam disi cihaz 0 satir (A)');
assert.equal((await q(SQL_CLAIM_DEVICE_ATOMIC, [idA, 41001, dev.assignedOther, false])).rowCount, 0);
ok('SQL_CLAIM_DEVICE_ATOMIC: baskasina ATANMIS cihaz 0 satir');

console.log('--- 4) baskasina atanmis / baskasinin cihazi: mevcut 409 davranisi korunur ---');
await rejects(() => claimDevice({ userCode: 41001, deviceInput: UID.assignedOther }), status(409), 'sahipsiz ama B yoneticisine ATANMIS cihaz -> 409');
assert.equal(Number((await row(UID.assignedOther)).assigned_user_code), 41002);
ok('assigned_user_code uzerine YAZILMADI');
await rejects(() => claimDevice({ userCode: 41001, deviceInput: UID.ownedOther }), status(409), 'hicbir yere bagli olmayan, B nin cihazi -> 409 (eski davranis)');

console.log('--- 5) SALDIRI: replace / kapiya atama (A kapisi, B cihazi) ---');
const before = await row(UID.bDoorFree);
await rejects(() => replaceDoorDevice({ doorId: doorA1, newDeviceInput: UID.bDoorFree, authUser: attacker }), doorCode('DEVICE_NOT_FOUND', 404), 'replace (UID), B kapisindaki sahipsiz cihaz -> 404');
await rejects(() => replaceDoorDevice({ doorId: doorA1, newDeviceInput: UID.bDoorOwned, authUser: attacker }), doorCode('DEVICE_NOT_FOUND', 404), 'replace (UID), B kapisindaki sahipli cihaz -> 404 (409 DEGIL)');
await rejects(() => replaceDoorDevice({ doorId: doorA1, newDeviceId: dev.bDoorOwned, authUser: attacker }), doorCode('DEVICE_NOT_FOUND', 404), 'replace (id), B cihazi -> 404 (403/409 DEGIL)');
await rejects(() => replaceDoorDevice({ doorId: doorA1, newDeviceId: dev.bSiteOnly, authUser: attacker }), doorCode('DEVICE_NOT_FOUND', 404), 'replace (id), devices.site_code=B cihaz -> 404');
await rejects(() => updateDoorDeviceAssignment({ doorId: doorA1, deviceUid: UID.bDoorFree, authUser: attacker }), doorCode('DEVICE_NOT_FOUND', 404), 'kapiya atama (PATCH /manager/doors/:id/device), B cihazi -> 404');
await rejects(() => updateDoorDeviceAssignment({ doorId: doorA1, deviceUid: UID.bDoorOwned, authUser: attacker }), doorCode('DEVICE_NOT_FOUND', 404), 'kapiya atama, B nin sahipli cihazi -> 404');
const after = await row(UID.bDoorFree);
assert.deepEqual(after, before, 'B cihazi satiri degismedi');
assert.equal(Number(await doorDevice(doorB1)), dev.bDoorFree);
assert.equal(Number(await doorDevice(doorB2)), dev.bDoorOwned);
assert.equal(Number(await doorDevice(doorA1)), dev.aDoorFree, 'A kapisinin mevcut cihazi da bozulmadi (ROLLBACK)');
ok('hicbir saldirida B cihazi / kapisi / A kapisi DEGISMEDI');

console.log('--- 6) MESRU AKIS bozulmaz ---');
let res = await claimDevice({ userCode: 41001, deviceInput: UID.free });
assert.equal(res.ok, true);
assert.equal(Number((await row(UID.free)).owner_user_id), idA);
ok('A, envanterdeki serbest cihazi sahiplenir');
res = await claimDevice({ userCode: 41001, deviceInput: UID.free });
assert.equal(res.already_owned, true);
ok('tekrar okutma idempotent (already_owned)');
res = await claimDevice({ userCode: 41001, deviceInput: UID.aDoorFree });
assert.equal(res.ok, true);
assert.equal(Number((await row(UID.aDoorFree)).owner_user_id), idA);
ok('A, KENDI sitesinin kapisinda takili sahipsiz cihazi sahiplenir');
res = await claimDevice({ userCode: 41002, deviceInput: UID.bDoorFree });
assert.equal(res.ok, true);
assert.equal(Number((await row(UID.bDoorFree)).owner_user_id), idB);
ok('B, KENDI sitesinin sahipsiz cihazini sahiplenir');
res = await claimDevice({ userCode: 41002, deviceInput: UID.assignedOther });
assert.equal(res.ok, true);
assert.equal(Number((await row(UID.assignedOther)).owner_user_id), idB);
ok('kendisine ATANMIS (assigned_user_code) cihazi sahiplenir');
res = await claimDevice({ userCode: 41005, deviceInput: UID.bSiteOnly2 });
assert.equal(res.ok, true);
assert.equal(Number((await row(UID.bSiteOnly2)).owner_user_id), await idOf(41005));
ok('B sitesini YALNIZ site_memberships (SITE_ADMIN) ile yoneten kullanici B nin cihazini sahiplenir (UNION in 2. kolu)');
res = await claimDevice({ userCode: 41004, deviceInput: UID.bSiteOnly });
assert.equal(res.ok, true);
ok('super kullanici kapsam disi (B) cihazi sahiplenebilir (mevcut davranis)');
await rejects(() => claimDevice({ userCode: 41003, deviceInput: UID.free2 }), (e) => assert.equal(e.code, 'DEVICE_ADD_FORBIDDEN'), 'yonetici olmayan kullanici cihaz EKLEYEMEZ (403, degismedi)');

res = await replaceDoorDevice({ doorId: doorA1, newDeviceId: dev.aOwn, authUser: attacker });
assert.equal(res.newDeviceUid, UID.aOwn);
assert.equal(Number(await doorDevice(doorA1)), dev.aOwn);
ok('replace (id): A kendi cihazini kendi kapisina takar');
res = await replaceDoorDevice({ doorId: doorA1, newDeviceInput: `GD-WROOM-${UID.free2}`, authUser: attacker });
assert.equal(res.newDeviceUid, UID.free2);
assert.equal(Number((await row(UID.free2)).owner_user_id), idA);
ok('replace (UID/QR): A envanterdeki serbest cihazi sahiplenip kendi kapisina takar (mevcut davranis)');
res = await replaceDoorDevice({ doorId: doorA1, newDeviceInput: UID.aDoorFree, authUser: attacker });
assert.equal(res.newDeviceUid, UID.aDoorFree);
ok('replace (UID): A kendi sitesinde onceden takili cihazi geri takar');
res = await updateDoorDeviceAssignment({ doorId: doorA1, deviceUid: UID.aOwn, authUser: attacker });
assert.equal(res.assigned_device_uid, UID.aOwn);
ok('kapiya atama: A kendi cihazini kendi kapisina atar');
res = await replaceDoorDevice({ doorId: doorB1, newDeviceId: dev.bDoorFree, authUser: victim });
assert.equal(res.newDeviceUid, UID.bDoorFree);
ok('B kendi kapisinda kendi cihazini degistirir');
res = await replaceDoorDevice({ doorId: doorB1, newDeviceId: dev.bDoorOwned, authUser: superUser });
assert.equal(res.newDeviceUid, UID.bDoorOwned);
ok('super kullanici herhangi bir sitenin kapisini degistirebilir (kapsam sinirsiz)');

await cleanup();
console.log(`\nTAMAM: ${step} dogrulama gecti (gercek PostgreSQL).`);
await pool.end();
