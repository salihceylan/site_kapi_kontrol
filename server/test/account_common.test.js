// Hesap silme / veri dışa aktarma ortak yardımcıları (DB'siz): kimliksiz değerler, hata kodları ve durumları, dosya adı, adres denetimi.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  BLOCKER_LAST_SITE_MANAGER,
  BLOCKER_SUPER_USER,
  DELETED_USER_NAME,
  EXPORT_MAX_BYTES,
  EXPORT_RATE_LIMIT,
  EXPORT_RATE_WINDOW_HOURS,
  accountBusy,
  accountDeleted,
  bodyOf,
  confirmRequired,
  currentPasswordInvalid,
  currentPasswordLocked,
  currentPasswordRequired,
  dateStamp,
  deleteBlocked,
  deletedEmailFor,
  exportFileName,
  exportRateLimited,
  isDeliverableEmail,
  isSubsetOf,
  lastSiteManagerBlocker,
  openDebtBlocker,
  numOrNull,
  plainObject,
  superUserBlocker,
  userCodeOf,
} from '../src/modules/account_common.js';
import { isPlatformError } from '../src/modules/errors.js';

describe('hesap silme: kimliksiz değerler', () => {
  it('silinmiş hesabın adı ve e-postası sabit biçimde; e-posta benzersiz (user_code) ve teslim edilemez (.invalid)', () => {
    assert.equal(DELETED_USER_NAME, 'Silinmiş Kullanıcı');
    assert.equal(deletedEmailFor(12345), 'deleted-12345@deleted.invalid');
    assert.notEqual(deletedEmailFor(12345), deletedEmailFor(12346));
    assert.equal(isDeliverableEmail(deletedEmailFor(12345)), false);
  });

  it('sınırlar sözleşmeyle uyumlu: 5 MB gövde, 24 saatte 3 dışa aktarma', () => {
    assert.equal(EXPORT_MAX_BYTES, 5 * 1024 * 1024);
    assert.equal(EXPORT_RATE_LIMIT, 3);
    assert.equal(EXPORT_RATE_WINDOW_HOURS, 24);
  });
});

describe('hesap silme: hata üreticileri (PlatformError, makine kodu + durum)', () => {
  it('kodlar ve HTTP durumları sözleşmedeki gibi', () => {
    const cases = [
      [confirmRequired(), 400, 'CONFIRM_REQUIRED'],
      [currentPasswordRequired(), 400, 'CURRENT_PASSWORD_REQUIRED'],
      [currentPasswordInvalid(), 400, 'CURRENT_PASSWORD_INVALID'], // 401/403 DEĞİL: istemci çıkış yapmasın
      [currentPasswordLocked(30), 429, 'CURRENT_PASSWORD_LOCKED'],
      [accountDeleted(), 401, 'ACCOUNT_DELETED'],
      [deleteBlocked([superUserBlocker()]), 409, 'ACCOUNT_DELETE_BLOCKED'],
      [accountBusy(), 409, 'ACCOUNT_DELETE_BUSY'],
      [exportRateLimited(120), 429, 'EXPORT_RATE_LIMITED'],
    ];
    for (const [error, status, code] of cases) {
      assert.ok(isPlatformError(error), code);
      assert.equal(error.statusCode, status, code);
      assert.equal(error.code, code);
      assert.ok(error.message.length > 5);
    }
  });

  it('429 hataları retry_after_seconds taşır (en az 1, yukarı yuvarlanır); engel hatası blockers taşır', () => {
    assert.equal(currentPasswordLocked(0).extra.retry_after_seconds, 1);
    assert.equal(currentPasswordLocked(29.2).extra.retry_after_seconds, 30);
    assert.equal(exportRateLimited(undefined).extra.retry_after_seconds, 1);
    assert.equal(exportRateLimited(3600).extra.retry_after_seconds, 3600);
    const blocked = deleteBlocked([superUserBlocker()]);
    assert.equal(blocked.extra.blockers.length, 1);
    assert.equal(blocked.extra.blockers[0].code, BLOCKER_SUPER_USER);
  });

  it('engel gövdeleri: kod + Türkçe mesaj; son yönetici engelinde site_id sayı', () => {
    const sup = superUserBlocker();
    assert.equal(sup.code, 'SUPER_USER');
    assert.ok(/Süper kullanıcı/.test(sup.message));
    assert.equal('site_id' in sup, false);
    const last = lastSiteManagerBlocker({ site_code: '1000000042', name: 'Gül Sitesi' });
    assert.equal(last.code, BLOCKER_LAST_SITE_MANAGER);
    assert.equal(last.site_id, 1000000042);
    assert.ok(last.message.includes('Gül Sitesi'));
    assert.ok(lastSiteManagerBlocker({ site_code: 1, name: null }).message.length > 10);
    assert.ok(lastSiteManagerBlocker({ site_code: 1, name: 'x'.repeat(500) }).message.length < 400, 'uzun site adı mesajı şişirmez');
    const debt = openDebtBlocker({ site_code: '1000000042', site_name: 'Gül Sitesi', apartment_id: '7', label: 'A Blok 3', balance_minor: 123450, account_party: 'tenant' });
    assert.equal(debt.code, 'OPEN_DEBT');
    assert.equal(debt.site_id, 1000000042);
    assert.equal(debt.apartment_id, 7);
    assert.equal(debt.amount_minor, 123450);
    assert.equal(debt.account_party, 'tenant');
    assert.match(debt.message, /A Blok 3 için ödenmemiş 1\.234,50 TL borcunuz var/);
  });
});

describe('hesap silme: küçük saf yardımcılar', () => {
  it('userCodeOf: user_code / userCode / id; geçersiz değerler null', () => {
    assert.equal(userCodeOf({ user_code: 12345 }), 12345);
    assert.equal(userCodeOf({ userCode: '12345' }), 12345);
    assert.equal(userCodeOf({ id: 12345 }), 12345);
    for (const bad of [null, undefined, {}, { id: 0 }, { id: -3 }, { id: 'abc' }, { id: 2147483648 }, { id: 1.5 }]) {
      assert.equal(userCodeOf(bad), null, JSON.stringify(bad));
    }
  });

  it('plainObject / bodyOf: yalnız düz nesne; dizi, null, metin boş nesne olur', () => {
    assert.deepEqual(plainObject({ a: 1 }), { a: 1 });
    for (const bad of [null, undefined, [], [1], 'x', 5]) {
      assert.deepEqual(plainObject(bad), {}, String(bad));
    }
    assert.deepEqual(bodyOf({ body: { confirm: true } }), { confirm: true });
    assert.deepEqual(bodyOf({}), {});
  });

  it('dateStamp / exportFileName: Europe/Istanbul takvimi, YYYYMMDD, sözleşmedeki ad biçimi', () => {
    // 2026-10-16 22:30 UTC = 2026-10-17 01:30 İstanbul (UTC+3)
    assert.equal(dateStamp(new Date('2026-10-16T22:30:00Z')), '20261017');
    assert.equal(dateStamp(new Date('2026-10-16T10:00:00Z')), '20261016');
    assert.equal(exportFileName(12345, new Date('2026-10-16T10:00:00Z')), 'kisisel-veri-12345-20261016.json');
    assert.match(exportFileName(10001), /^kisisel-veri-10001-\d{8}\.json$/);
  });

  it('isDeliverableEmail: dahili daire hesabı, silinmiş hesap, bozuk ve enjeksiyonlu adresler gönderilmez', () => {
    assert.equal(isDeliverableEmail('ada@example.com'), true);
    for (const bad of ['', null, undefined, 'daire11@ahbu.local', 'DAIRE@AHBU.LOCAL', 'deleted-1@deleted.invalid', 'a@b', 'a b@example.com', 'a@x.com, b@y.com', 'a@x.com\r\nBcc: z@y.com', `${'a'.repeat(250)}@example.com`]) {
      assert.equal(isDeliverableEmail(bad), false, String(bad));
    }
  });

  it('numOrNull / isSubsetOf', () => {
    assert.equal(numOrNull('42'), 42);
    assert.equal(numOrNull(null), null);
    assert.equal(numOrNull(undefined), null);
    assert.equal(numOrNull('x'), null);
    assert.equal(isSubsetOf([1, 2], [1, 2, 3]), true);
    assert.equal(isSubsetOf([], []), true);
    assert.equal(isSubsetOf([1, 4], [1, 2, 3]), false);
    assert.equal(isSubsetOf(['2'], [2]), true, 'pg BIGINT metni ile sayı eşleşir');
  });
});
