// S2: üyelik durum değişikliği (toggle), yetki kuralları, toplu yetki kapsamı ve token döndürme yardımcıları (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  MAX_BULK_USER_CODES,
  SQL_BULK_APARTMENT_USERS,
  SQL_BULK_BLOCK_USERS,
  assertPrimaryAdminCandidate,
  canDeleteApartmentMember,
  httpError,
  isLegacyResident,
  overrideRevokesAccess,
  resolveToggleTarget,
  sanitizeUserCodeList,
} from '../src/services/membership_rules.js';
import { normalizeDeviceIdList, rotateTokensForDevices, rotateTokensForSite } from '../src/services/local_token_service.js';
import { PG_INT4_MAX, isValidEmail, parsePositiveId } from '../src/utils/validators.js';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-members-tests-0123456789abcdef';

describe('members: toggle (aktif/pasif) sonuç kararı', () => {
  it('üyelik satırı güncellendiyse MEMBERSHIP', () => {
    assert.equal(resolveToggleTarget({ membershipRowCount: 1, legacyResidentMatches: false }), 'MEMBERSHIP');
    assert.equal(resolveToggleTarget({ membershipRowCount: 1, legacyResidentMatches: true }), 'MEMBERSHIP');
  });

  it('rowCount === 0 ve eski sakin değilse NOT_FOUND (404) — rastgele kullanıcı güncellenmez', () => {
    assert.equal(resolveToggleTarget({ membershipRowCount: 0, legacyResidentMatches: false }), 'NOT_FOUND');
  });

  it('rowCount === 0 ama eski tekil sakin eşleşiyorsa yalnızca legacy senkron', () => {
    assert.equal(resolveToggleTarget({ membershipRowCount: 0, legacyResidentMatches: true }), 'LEGACY_RESIDENT');
  });

  it('isLegacyResident yalnızca eşleşen kullanıcı kodunda true (null güvenli)', () => {
    assert.equal(isLegacyResident({ resident_user_code: 12345 }, 12345), true);
    assert.equal(isLegacyResident({ resident_user_code: '12345' }, 12345), true);
    assert.equal(isLegacyResident({ resident_user_code: 12346 }, 12345), false);
    assert.equal(isLegacyResident({ resident_user_code: null }, 0), false);
    assert.equal(isLegacyResident(undefined, 1), false);
  });

  it('toggleApartmentMemberStatus kaynağı global users.is_active alanını GÜNCELLEMEZ', async () => {
    const { toggleApartmentMemberStatus } = await import('../src/services/membership_service.js');
    const source = toggleApartmentMemberStatus.toString();
    assert.equal(/UPDATE\s+users/i.test(source), false);
    assert.match(source, /UPDATE apartment_memberships/);
    assert.match(source, /resolveToggleTarget/);
    // legacy senkron yalnızca eşleşme varsa yapılır
    assert.match(source, /if \(legacy\)/);
  });
});

describe('members: yetki kuralları', () => {
  it('kalıcı silme yalnızca süper kullanıcı / site yöneticisi içindir', () => {
    assert.equal(canDeleteApartmentMember({ isSuperUser: true, isSiteManager: true }), true);
    assert.equal(canDeleteApartmentMember({ isSuperUser: false, isSiteManager: true }), true);
    assert.equal(canDeleteApartmentMember({ isSuperUser: false, isSiteManager: false }), false);
  });

  it('aile reisi adayı pasif/çıkarılmış üye ise 409; hiç üye değilse 404', () => {
    assert.throws(() => assertPrimaryAdminCandidate(undefined), (err) => err.statusCode === 404);
    assert.throws(
      () => assertPrimaryAdminCandidate({ role: 'FAMILY_MEMBER', is_active: false }),
      (err) => err.statusCode === 409,
    );
    assert.doesNotThrow(() => assertPrimaryAdminCandidate({ role: 'FAMILY_MEMBER', is_active: true }));
  });

  it('setApartmentPrimaryAdmin güncellemesi pasif üyeyi yeniden aktifleştirmez', async () => {
    const { setApartmentPrimaryAdmin } = await import('../src/services/membership_service.js');
    const source = setApartmentPrimaryAdmin.toString();
    // eski kod "SET role = 'APARTMENT_ADMIN', is_active = TRUE" yapıyordu
    assert.equal(/role = 'APARTMENT_ADMIN', is_active = TRUE/.test(source), false);
    assert.match(source, /assertPrimaryAdminCandidate/);
  });

  it('changeApartmentMemberPassword: tanımsız `apt` hatası yok; başkasının şifresi değiştirilemez (DB\'siz 403)', async () => {
    const { changeApartmentMemberPassword } = await import('../src/services/membership_service.js');
    await assert.rejects(
      () =>
        changeApartmentMemberPassword({
          apartmentId: 5,
          targetUserCode: 20000,
          newPassword: 'yeni-sifre',
          currentPassword: 'eski',
          authUser: { userCode: 30000, id: 30000 },
        }),
      (err) => err.statusCode === 403,
    );
    // kendi hesabı ama mevcut şifre yok -> 400 (ReferenceError değil)
    await assert.rejects(
      () =>
        changeApartmentMemberPassword({
          apartmentId: 5,
          targetUserCode: 20000,
          newPassword: 'yeni-sifre',
          authUser: { userCode: 20000, id: 20000 },
        }),
      (err) => err.statusCode === 400,
    );
    // kısa şifre politikası (>=4) korunur
    await assert.rejects(
      () =>
        changeApartmentMemberPassword({
          apartmentId: 5,
          targetUserCode: 20000,
          newPassword: '123',
          currentPassword: 'eski',
          authUser: { userCode: 20000, id: 20000 },
        }),
      (err) => err.statusCode === 400,
    );
    // daire satırı artık fonksiyon içinde tanımlanıyor (eskiden tanımsız `apt` ReferenceError veriyordu)
    assert.match(changeApartmentMemberPassword.toString(), /const apt = aptRes\.rows\[0\]/);
  });

  it('httpError: expose=true ve statusCode taşır', () => {
    const err = httpError(404, 'yok');
    assert.equal(err.statusCode, 404);
    assert.equal(err.expose, true);
    assert.equal(err.message, 'yok');
  });
});

describe('members: kapı izni değişikliği ve toplu yetki kapsamı', () => {
  it('erişimi daraltan değişiklikler token döndürmeyi gerektirir', () => {
    assert.equal(overrideRevokesAccess(false), true);
    assert.equal(overrideRevokesAccess(null), true);
    assert.equal(overrideRevokesAccess(undefined), true);
    assert.equal(overrideRevokesAccess(true), false);
  });

  it('toplu yetki: daire/blok sorguları kapının sitesine (site_code = $2) bağlıdır', () => {
    const apt = SQL_BULK_APARTMENT_USERS.replace(/\s+/g, ' ');
    const blk = SQL_BULK_BLOCK_USERS.replace(/\s+/g, ' ');
    assert.match(apt, /a\.id = \$1 AND a\.site_code = \$2/);
    assert.match(blk, /a\.block_id = \$1 AND a\.site_code = \$2/);
  });

  it('sanitizeUserCodeList: tekilleştirir, int4 dışını/NaN\'ı eler, üst sınır uygular', () => {
    assert.deepEqual(sanitizeUserCodeList([10001, '10001', 10002, 'abc', -5, 0, 1.5, PG_INT4_MAX + 1, null]), [
      10001,
      10002,
    ]);
    assert.deepEqual(sanitizeUserCodeList('nope'), []);
    const many = Array.from({ length: MAX_BULK_USER_CODES + 50 }, (_, i) => i + 1);
    assert.equal(sanitizeUserCodeList(many).length, MAX_BULK_USER_CODES);
  });

  it('removeApartmentMember kapı istisnasını yalnızca üyelik kalmadıysa ve ilgili kullanıcı için siler', () => {
    const text = readFileSync(new URL('../src/services/membership_service.js', import.meta.url), 'utf8');
    // eski kalıp: sitedeki tüm kullanıcı istisnalarını koşulsuz silme
    assert.equal(/DELETE FROM door_access_overrides WHERE site_code = \$1 AND user_code = \$2`/.test(text), false);
    assert.match(text, /cleanupDoorOverridesIfNoMembership/);
  });
});

describe('members: yerel token döndürme yardımcıları (MQTT\'ye dokunmaz)', () => {
  it('normalizeDeviceIdList tekilleştirir ve geçersizleri eler', () => {
    assert.deepEqual(normalizeDeviceIdList([3, '3', 4, null, undefined, 'x', -1, 0, 5.5]), [3, 4]);
    assert.deepEqual(normalizeDeviceIdList(undefined), []);
  });

  it('boş liste / geçersiz site için hiçbir şey yapılmaz (device_service yüklenmez)', async () => {
    assert.equal(await rotateTokensForDevices({ deviceIds: [], reason: 't' }), 0);
    assert.equal(await rotateTokensForDevices({ deviceIds: [null, undefined], reason: 't' }), 0);
    assert.equal(await rotateTokensForSite({ siteCode: 'abc', reason: 't' }), 0);
    assert.equal(await rotateTokensForSite({ siteCode: -1, reason: 't' }), 0);
  });

  it('üyelik/izin kaldırma yolları token döndürmeyi çağırır', () => {
    const text = readFileSync(new URL('../src/services/membership_service.js', import.meta.url), 'utf8');
    for (const reason of [
      'apartment_member_removed',
      'apartment_member_deactivated',
      'apartment_member_deleted',
      'door_permission_reset',
      'door_permission_denied',
      'door_permission_bulk_revoked',
    ]) {
      assert.ok(text.includes(`reason: '${reason}'`), `${reason} yolu token döndürmüyor`);
    }
  });
});

describe('members: validators yardımcıları', () => {
  it('parsePositiveId güvenli tamsayıyı ayrıştırır', () => {
    assert.equal(parsePositiveId(5), 5);
    assert.equal(parsePositiveId('42'), 42);
    assert.equal(parsePositiveId(' 7 '), 7);
    for (const bad of [0, -1, 1.5, '1.5', '12abc', '1e3', '', null, undefined, NaN, Infinity, {}, [], true, 2 ** 53, '99999999999999999']) {
      assert.equal(parsePositiveId(bad), null, String(bad));
    }
  });

  it('parsePositiveId max (int4) sınırını uygular', () => {
    assert.equal(parsePositiveId(PG_INT4_MAX, { max: PG_INT4_MAX }), PG_INT4_MAX);
    assert.equal(parsePositiveId(PG_INT4_MAX + 1, { max: PG_INT4_MAX }), null);
    assert.equal(parsePositiveId('3000000000', { max: PG_INT4_MAX }), null);
  });

  it('isValidEmail bariz hatalı biçimleri reddeder', () => {
    for (const ok of ['a@b.co', 'ad.soyad+tag@ornek.com.tr', 'x_y@alt.alan.org']) {
      assert.equal(isValidEmail(ok), true, ok);
    }
    for (const bad of ['', 'a@b', '@b.co', 'a@@b.co', 'a b@c.co', 'a@b..co', '.a@b.co', 'a.@b.co', 'a@-b.co', 'a@b-.co', `${'x'.repeat(65)}@b.co`, null, undefined]) {
      assert.equal(isValidEmail(bad), false, String(bad));
    }
  });
});
