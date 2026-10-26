// Kullanıcı hesabı işlemlerinin denetim kaydı (audit_log): süper kullanıcının hesap oluşturma / güncelleme / rol değişimi / parola belirleme /
// aktiflik değişimi / kalıcı silme ve abonelik (site yöneticisi) talebi kararı. admin_routes bu yardımcıları, kullanıcı satırını değiştiren AYNI
// transaction'ın bağlantısıyla çağırır (recordAudit `inTransaction: true`: değişiklik ve kayıt birlikte işlenir / geri alınır).
//
// Ayrıntıda (details) YALNIZ kimlik, rol kodu, durum ve alan ADLARI bulunur: ad, e-posta, telefon, parola (özeti dahil) yazılmaz.
// Hesap bir siteye bağlı olmadığından siteCode yoktur (null); hedef her zaman `user` + kullanıcı kodudur.
import { recordAudit } from './audit_service.js';

export const USER_AUDIT_ACTIONS = Object.freeze([
  'user.created',
  'user.updated',
  'user.role_changed',
  'user.password_set',
  'user.activated',
  'user.deactivated',
  'user.deleted',
  'user.subscription_approved',
  'user.subscription_rejected',
]);

// PATCH gövdesindeki alan adları (undefined = gönderilmedi). Yalnız ALAN ADI kaydedilir, değer değil.
const UPDATE_FIELD_NAMES = Object.freeze([
  ['fullName', 'full_name'],
  ['phoneNumber', 'phone_number'],
  ['password', 'password'],
  ['isActive', 'is_active'],
  ['role', 'role'],
  ['emailVerified', 'email_verified'],
]);

function write(db, actor, action, userCode, details) {
  return recordAudit(
    db,
    { actor, action, siteCode: null, targetType: 'user', targetId: String(userCode), details },
    { inTransaction: true },
  );
}

/**
 * Değişiklikten ÖNCE hesabın rol / aktiflik durumu (eski rol ve gerçek aktiflik değişimi için). Satır `FOR NO KEY UPDATE` ile kilitlenir:
 * okuma ile yazma arasında başka bir istek rolü değiştirip yanlış "eski rol" kaydetmesin (anahtar sütun değişmediğinden FK denetimleriyle çakışmaz).
 * Hesap yok / silinmişse null.
 * @param {{ query: Function }} db açık transaction'daki bağlantı
 */
export async function readUserStateForAudit(db, userCode) {
  const result = await db.query(
    'SELECT role, is_active FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR NO KEY UPDATE',
    [userCode],
  );
  return result.rows?.[0] ?? null;
}

/** POST /admin/users: hesap oluşturuldu (ilk parola yönetimce belirlendiği için geçicidir). */
export function auditUserCreated(db, actor, user, { temporaryPassword = true } = {}) {
  return write(db, actor, 'user.created', user.id, {
    role: user.role ?? null,
    is_active: user.is_active === true,
    temporary_password: temporaryPassword === true,
  });
}

/**
 * PATCH /admin/users/:id: tek `user.updated` (değişen alan adları) + gereken ayrı olaylar:
 * rol gerçekten değiştiyse `user.role_changed` (eski / yeni rol kodu), parola gönderildiyse `user.password_set` (parola YOK),
 * aktiflik gerçekten değiştiyse `user.activated` / `user.deactivated`.
 * `before`: readUserStateForAudit çıktısı (okunamadıysa null: değişim varsayılır). `changes`: PATCH'in kullandığı alan nesnesi.
 */
export async function auditUserUpdated(db, actor, { before, user, changes }) {
  const fields = UPDATE_FIELD_NAMES.filter(([key]) => changes?.[key] !== undefined).map(([, name]) => name);
  await write(db, actor, 'user.updated', user.id, { fields });
  if (changes?.role !== undefined && (!before || before.role !== user.role)) {
    await write(db, actor, 'user.role_changed', user.id, { old_role: before?.role ?? null, new_role: user.role ?? null });
  }
  if (changes?.password !== undefined) {
    await write(db, actor, 'user.password_set', user.id, { temporary: true });
  }
  if (changes?.isActive !== undefined) {
    await auditUserActiveChange(db, actor, { before, user });
  }
}

/** Aktiflik gerçekten değiştiyse `user.activated` / `user.deactivated` (değişmediyse yazmaz). */
export async function auditUserActiveChange(db, actor, { before, user }) {
  const isActive = user.is_active === true;
  if (before && (before.is_active === true) === isActive) {
    return false;
  }
  return write(db, actor, isActive ? 'user.activated' : 'user.deactivated', user.id, {
    old_is_active: before ? before.is_active === true : null,
    new_is_active: isActive,
  });
}

/** DELETE /admin/users/:id: hesap kalıcı silindi (silinen rolü ve etkilediği site sayısı; kimlik bilgisi yazılmaz). */
export function auditUserDeleted(db, actor, { userCode, role, affectedSiteCount }) {
  return write(db, actor, 'user.deleted', userCode, {
    role: role ?? null,
    affected_site_count: Number.isInteger(affectedSiteCount) ? affectedSiteCount : 0,
  });
}

/** PATCH /admin/subscription-requests/:id: site yöneticisi abonelik talebi onaylandı / reddedildi. */
export function auditSubscriptionDecision(db, actor, user, { approved }) {
  return write(db, actor, approved ? 'user.subscription_approved' : 'user.subscription_rejected', user.id, {
    role: user.role ?? null,
  });
}
