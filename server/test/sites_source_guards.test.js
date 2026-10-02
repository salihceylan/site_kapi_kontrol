// Kaynak metni uzerinden regresyon korumalari (DB/MQTT'ye baglanmaz, modulleri import etmez).
// Amac: guvenlik duzeltmelerinin (atomik SQL, transaction, ID dogrulama, hata sizintisi)
// sonradan sessizce geri alinmasini yakalamak.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const srcRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');
const read = (relative) => readFileSync(path.join(srcRoot, relative), 'utf8').replace(/\r\n/g, '\n');

function sliceFunction(source, startMarker) {
  const start = source.indexOf(startMarker);
  assert.ok(start >= 0, `${startMarker} bulunamadi`);
  const next = source.indexOf('\n/**', start + startMarker.length);
  return next === -1 ? source.slice(start) : source.slice(start, next);
}

test('manager_routes: ID dogrulamasi parseId ile, Number.isInteger(Number(..)) kalibi yok', () => {
  const source = read('routes/manager_routes.js');
  assert.equal(
    /Number\.isInteger\((siteCode|doorId|apartmentId|deviceId|userCode|invitationId|requestId)\)/.test(source),
    false,
  );
  assert.ok(source.includes("from '../utils/ids.js'"));
  assert.equal(/Number\(req\.params\./.test(source), false);
});

test('manager_routes: route govdelerinde dogrudan pool.query yok (yalniz 3 yardimci icinde, try icinde cagrilir)', () => {
  const source = read('routes/manager_routes.js');
  const count = (source.match(/pool\.query\(/g) || []).length;
  assert.equal(count, 3, 'pool.query yalnizca getDoorSiteCode/getApartmentSiteCode/blockBelongsToSite icinde olmali');
});

test('manager_routes: error.message istemciye sizmaz', () => {
  const source = read('routes/manager_routes.js');
  assert.equal(/error\.message\s*\|\|/.test(source), false);
  assert.equal(/\$\{error\.message\}/.test(source), false);
  // error.message yalnizca isClientSafeError ile suzulmus tek noktada (respondServiceError) doner
  const direct = source.match(/error:\s*error\.message/g) || [];
  assert.equal(direct.length, 1);
  assert.ok(source.indexOf('error: error.message') > source.indexOf('if (isClientSafeError(error))'));
});

test('manager_routes: yonetici davet ucu inviteLimiter ile korunur', () => {
  const source = read('routes/manager_routes.js');
  assert.match(
    source,
    /managerRouter\.post\('\/manager\/sites\/:siteCode\/managers\/invite',\s*authRequired,\s*requireSiteManager,\s*inviteLimiter,/,
  );
  assert.ok(source.includes("import { inviteLimiter } from '../middlewares/rate_limiters.js'"));
});

test('manager_routes: replace-device rotasi imzasi ve servis hata kodlari korunur', () => {
  const source = read('routes/manager_routes.js');
  assert.ok(source.includes("'/manager/doors/:id/replace-device'"));
  assert.ok(source.includes('replaceDoorDevice({'));
  assert.ok(source.includes('old_device_uid: result.oldDeviceUid'));
  assert.ok(source.includes('new_device_uid: result.newDeviceUid'));
  assert.ok(source.includes("req.body.device_input ?? req.body.deviceInput"));
  assert.ok(source.includes("req.body.device_id ?? req.body.deviceId"));
});

test('guest_passes_routes: hak tuketimi atomik SQL ile, pulse oncesi; basarisizsa iade', () => {
  const source = read('routes/guest_passes_routes.js');
  const claimAt = source.indexOf('pool.query(CLAIM_GUEST_PASS_SQL');
  const pulseAt = source.indexOf('await publishDoorPulse(');
  const releaseAt = source.indexOf('pool.query(RELEASE_GUEST_PASS_SQL');
  assert.ok(claimAt > 0 && pulseAt > claimAt, 'atomik tuketim pulse\'tan once olmali');
  assert.ok(releaseAt > pulseAt, 'pulse hatasinda hak iade edilmeli');
  // Eski check-then-update kalibi kalmadi
  assert.equal(source.includes('Number(pass.used_count) + 1'), false);
  assert.equal(/SET\s+used_count\s*=\s*\$1/.test(source), false);
});

test('guest_passes_routes: C2 politika (guest) ve olusturan kullanici kontrolu', () => {
  const source = read('routes/guest_passes_routes.js');
  assert.ok(source.includes("from '../services/door_access_policy.js'"));
  assert.match(source, /assertDoorOpenAllowed\(\{[\s\S]*?channel: 'guest'/);
  assert.ok(source.includes('getAccessibleDoorForUser({\n      authUser: creator'));
  assert.ok(source.includes('creator.is_active'));
  assert.ok(source.includes('creator.email_verified'));
  // politika, hak tuketiminden ONCE
  assert.ok(source.indexOf("channel: 'guest'") < source.indexOf('pool.query(CLAIM_GUEST_PASS_SQL'));
});

test('guest_passes_routes: hata govdelerinde error.message yok; HTML parcalari kacirilir', () => {
  const source = read('routes/guest_passes_routes.js');
  assert.equal(/\$\{error\.message\}/.test(source), false);
  assert.equal(/send\([^)]*error\.message/.test(source), false);
  assert.ok(source.includes('renderGuestPassPage({ pass: result.rows[0], nonce })'));
  assert.ok(source.includes('guestPageHeaders(nonce)'));
  // sayfa HTML'i route dosyasinda elle birlestirilmez
  assert.equal(source.includes('<!DOCTYPE'), false);
});

test('site_service: removeSiteManager transaction + FOR UPDATE ile', () => {
  const body = sliceFunction(read('services/site_service.js'), 'export async function removeSiteManager');
  assert.ok(body.includes("client.query('BEGIN')"));
  assert.ok(body.includes("client.query('COMMIT')"));
  assert.ok(body.includes("client.query('ROLLBACK')"));
  assert.ok((body.match(/FOR UPDATE/g) || []).length >= 2);
  assert.ok(body.includes('evaluateManagerRemoval('));
  assert.ok(body.includes('decideRoleAfterManagerRemoval('));
  assert.equal(body.includes("SET role = 'individual'"), false);
  // transaction disinda pool.query kullanilmaz
  assert.equal(/pool\.query\(/.test(body), false);
});

test('site_service: deleteSitePermanently tek transaction', () => {
  const body = sliceFunction(read('services/site_service.js'), 'export async function deleteSitePermanently');
  assert.ok(body.includes("client.query('BEGIN')"));
  assert.ok(body.includes("client.query('COMMIT')"));
  assert.ok(body.includes('DELETE FROM sites'));
  assert.equal(/pool\.query\(/.test(body), false);
});

test('site_service: silme kodu sabit zamanli karsilastirilir ve deneme siniri vardir', () => {
  const source = read('services/site_service.js');
  const body = sliceFunction(source, 'export async function confirmSiteDeletionWithEmailCode');
  assert.ok(body.includes('safeEqualStrings(site.deletion_email_code, cleanCode)'));
  assert.equal(/deletion_email_code\s*!==\s*cleanCode/.test(body), false);
  assert.ok(body.includes('deletionCodeAttempts.check('));
  assert.ok(body.includes('deletionCodeAttempts.recordFailure('));
  assert.ok(body.includes('statusCode = 429'));
});

test('site_service: inviteSiteManager e-posta dogrular ve yaniti kullanici varligina gore degismez', () => {
  const body = sliceFunction(read('services/site_service.js'), 'export async function inviteSiteManager');
  assert.ok(body.includes('isValidEmail(cleanEmail)'));
  assert.equal(body.includes('is_existing_user'), false);
  assert.equal((body.match(/return \{ ok: true, message: inviteMessage, email: cleanEmail \};/g) || []).length, 2);
});

test('site_service: join token uretimi site satiri kilidiyle serilestirilir', () => {
  const body = sliceFunction(read('services/site_service.js'), 'export async function getOrCreateSiteJoinToken');
  assert.ok(body.includes('FOR NO KEY UPDATE'));
  assert.ok(body.includes("client.query('BEGIN')"));
  assert.equal(/pool\.query\(/.test(body), false);
});
