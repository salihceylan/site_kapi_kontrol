// Hesap silme (kimliksizleştirme) ile ESZAMANLI akışların koruma ifadeleri (R2 F-3 / F-7; DB'siz, kaynak düzeyi).
// Gerçek PostgreSQL davranışı (bekleme, 40P01 = 0, tombstone'a bağlı satır kalmaması): scripts/qa_platform_pg.mjs "account" bölümü G.
//
// Kural: bir kullanıcıya YENİ bağlı satır (başvuru, yetki, izin, üyelik) yazan her akış, hedef hesabı AYNI işlemde `deleted_at IS NULL` ile okur ve
// `FOR KEY SHARE` ile kilitler (ya da tek ifadede CTE ile); silme commit ettiyse satır dönmez ve akış 404 ile durur, devam eden silme ise bu işlem bitene dek bekler.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = (relative) => readFileSync(path.join(here, '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

/** `export async function <name>(` ile başlayan gövdeyi (bir sonraki üst düzey `export` / `function`a kadar) döndürür. */
function bodyOf(text, name) {
  const start = text.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} bulunamadı`);
  const rest = text.slice(start + 1);
  const next = rest.search(/\n(?:export )?(?:async )?function |\nexport const |\n\/\*\*/);
  return norm(next < 0 ? text.slice(start) : text.slice(start, start + 1 + next));
}

const USER_LOCK = 'FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE';

describe('hesap silme ile eşzamanlı akışlar: hedef hesap kilidi + silinmemiş koşulu', () => {
  const membership = source('services/membership_service.js');

  it('createJoinRequest: önce daire (KEY SHARE), sonra kullanıcı (deleted_at IS NULL + KEY SHARE); silinmiş hesap 404', () => {
    const body = bodyOf(membership, 'createJoinRequest');
    const apartmentLock = body.indexOf('SELECT id FROM apartments WHERE id = $1 FOR KEY SHARE');
    const userLock = body.indexOf(USER_LOCK);
    assert.ok(apartmentLock > 0 && userLock > apartmentLock, 'kilit sırası: daire -> kullanıcı (hesap silme ile aynı yön)');
    assert.ok(body.indexOf("INSERT INTO join_requests") > userLock);
    assert.match(body, /userRes\.rowCount === 0\) \{ throw httpError\(404, 'Kullanıcı hesabı bulunamadı\.'\)/);
  });

  it('approveJoinRequest: talep + hesap TEK sorguda (jr FOR UPDATE, u FOR KEY SHARE), u.deleted_at IS NULL; silinmiş başvuran 404', () => {
    const body = bodyOf(membership, 'approveJoinRequest');
    assert.ok(body.includes('JOIN users u ON u.user_code = jr.user_code WHERE jr.id = $1 AND u.deleted_at IS NULL FOR UPDATE OF jr FOR KEY SHARE OF u'));
    assert.match(body, /reqRes\.rowCount === 0\) \{ throw httpError\(404, 'Katılım talebi bulunamadı\.'\)/);
  });

  it('setDoorAccessOverride: hedef hesap CTE\'de FOR KEY SHARE ile kilitlenir ve INSERT AYNI ifadede ondan beslenir; satır dönmezse 404 (ayrı "var mı" okuması YOK)', () => {
    const body = bodyOf(membership, 'setDoorAccessOverride');
    assert.ok(body.includes('WITH target AS ( SELECT user_code FROM users WHERE user_code = $3 AND deleted_at IS NULL FOR KEY SHARE ) INSERT INTO door_access_overrides'));
    assert.ok(body.includes('FROM target ON CONFLICT (door_id, user_code)'));
    assert.match(body, /result\.rowCount === 0\) \{ throw httpError\(404, 'Kullanıcı bulunamadı\.'\)/);
    assert.equal(/SELECT[^;]*FROM users WHERE user_code = \$\d/.test(body.replace(/WITH target AS[\s\S]*?FOR KEY SHARE/, '')), false, 'CTE dışında ayrı kullanıcı okuması yok');
  });

  it('assignStaffRole: hesap deleted_at IS NULL + FOR KEY SHARE ile okunur', () => {
    const body = bodyOf(source('modules/staff_role_service.js'), 'assignStaffRole');
    assert.ok(body.includes('FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE'));
    assert.match(body, /USER_NOT_FOUND/);
  });

  it('createSiteApplication: başvuran hesap AYNI işlemde deleted_at IS NULL + FOR KEY SHARE ile okunur; yoksa 404 USER_NOT_FOUND', () => {
    const body = bodyOf(source('modules/site_application_service.js'), 'createSiteApplication');
    assert.ok(body.includes('SELECT id, user_code, role, full_name FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE'));
    assert.match(body, /new PlatformError\(404, 'USER_NOT_FOUND'/);
  });

  it('inviteSiteManager (kayıtlı kullanıcı yolu): önce (site, hedef) üyelik satırı FOR UPDATE, sonra hesap KEY SHARE + deleted_at IS NULL; kayıp hesap 404; ilk okuma da silinmişi dışlar', () => {
    const body = bodyOf(source('services/site_service.js'), 'inviteSiteManager');
    assert.ok(body.includes('WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL LIMIT 1'));
    const membershipLock = body.indexOf('SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 FOR UPDATE');
    const userLock = body.indexOf('SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE');
    assert.ok(membershipLock > 0 && userLock > membershipLock, 'kilit sırası: üyelik satırı -> hesap (hesap silme ile aynı yön)');
    assert.ok(body.indexOf('INSERT INTO site_manager_sites') > userLock);
    assert.match(body, /lockedTarget\.rowCount === 0\) \{ const err = new Error\('Bu e-posta adresine ait hesap artık bulunmuyor\.'\); err\.statusCode = 404;/);
  });

  it('removeSiteManager (R2 F-7): hesap satırı FOR NO KEY UPDATE (FOR UPDATE değil) - katılım onayının KEY SHARE kilidiyle çakışıp 40P01 üretmez', () => {
    const body = bodyOf(source('services/site_service.js'), 'removeSiteManager');
    assert.ok(body.includes('SELECT role FROM users WHERE user_code = $1 FOR NO KEY UPDATE'));
    assert.equal(/SELECT role FROM users WHERE user_code = \$1 FOR UPDATE/.test(body), false);
    // yönetici satırları hesaptan ÖNCE kilitlenir (hesap silme ile aynı yön)
    assert.ok(body.indexOf('FROM site_manager_sites WHERE site_code = $1 FOR UPDATE') < body.indexOf('FOR NO KEY UPDATE'));
  });

  it('updateUserByCode ve PATCH /me: silinmiş hesaba yazmaz (WHERE ... AND deleted_at IS NULL)', () => {
    const body = bodyOf(source('services/user_service.js'), 'updateUserByCode');
    assert.match(body, /WHERE user_code = \$\$\{values\.length\} AND deleted_at IS NULL RETURNING/);
  });

  it('parola yolu: hesap silinmişse hash okunmaz (SELECT password_hash ... AND deleted_at IS NULL); parola sıfırlama UPDATE\'leri silinmişi dışlar', () => {
    assert.ok(norm(source('modules/account_password_guard.js')).includes('SELECT password_hash FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1'));
    const auth = norm(source('routes/auth_routes.js'));
    assert.ok((auth.match(/deleted_at IS NULL/g) ?? []).length >= 3, 'sıfırlama isteği, sıfırlama onayı ve profil yolu');
  });
});
