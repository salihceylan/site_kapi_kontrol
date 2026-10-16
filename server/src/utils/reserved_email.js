// Sistemin KENDİ ürettiği e-posta alan adları: kullanıcı kaydı / yönetici kullanıcı oluşturma / davet bunları KABUL ETMEZ.
//
//  - `deleted.invalid`: hesap silme (kimliksizleştirme) tombstone e-postası `deleted-<user_code>@deleted.invalid`. Alan adı kullanıcıya açık olsaydı biri
//    bu adresi önceden kaydedip bir hesabın silinmesini çökertebilir (users.email UNIQUE -> 23505) ya da tombstone adresine davet / sıfırlama yönlendirebilirdi.
//    `.invalid` (RFC 2606) zaten teslim edilemez; yine de kayıt aşamasında reddedilir.
// Bağımlılığı yoktur (validators.js ve site_rules.js ile hesap modülleri paylaşır; döngü olmasın).

export const DELETED_EMAIL_DOMAIN = 'deleted.invalid';

const RESERVED_DOMAINS = Object.freeze([DELETED_EMAIL_DOMAIN]);

/** E-posta ayrılmış (sistem) bir alan adındaysa ya da onun alt alan adındaysa true. Biçim doğrulaması YAPMAZ. */
export function isReservedEmail(value) {
  const text = String(value ?? '').trim().toLowerCase();
  const at = text.lastIndexOf('@');
  if (at < 0) {
    return false;
  }
  const domain = text.slice(at + 1);
  return RESERVED_DOMAINS.some((reserved) => domain === reserved || domain.endsWith(`.${reserved}`));
}
