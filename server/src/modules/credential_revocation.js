// Parolası YÖNETİMCE (yeniden) verilen hesabın eski parolayla edinilmiş JWT DIŞI erişiminin kapatılması.
//
// Neden ortak: apartment_service.resetApartmentPin (daire PIN'i) ve people_service (kişi hesabı / geçici parola) AYNI kuralı uygular. Parola özeti
// değişince açık oturumlar (JWT `pv`) ve güvenilir cihaz belirteçleri zaten geçersizleşir; ama misafir geçişleri, kapı karekod belirteçleri ve telefon
// bildirimi kayıtları parolaya bağlı değildir ve eski parolayı bilen biri tarafından edinilmiş olabilir. Bu işlev bunları AYNI işlemde kapatır.
//
// Çağıran: açık transaction'daki `client`. Giriş kilitlerinin açılması (clearAccountLocks) COMMIT'ten SONRA çağıranın işidir (bellek içi).
// Kilit sırası: users -> misafir geçişi / karekod / bildirim (resetApartmentPin ile aynı).

import { deletePushDataForUser } from './push_devices.js';

/**
 * @param {{ query: Function }} client açık transaction'daki bağlantı
 * @param {number|string} userCode hesabın user_code değeri
 * @returns {Promise<{ guest_passes: number, qr_tokens: number, push_devices: number, push_outbox: number }>} kapanan erişim SAYILARI
 */
export async function revokeCredentialAccess(client, userCode) {
  const guestPasses = await client.query(
    `UPDATE guest_passes SET is_active = FALSE WHERE created_by_user_code = $1 AND is_active = TRUE`,
    [userCode],
  );
  const qrTokens = await client.query(
    `UPDATE qr_access_tokens SET is_active = FALSE, revoked_at = NOW() WHERE user_code = $1 AND is_active = TRUE AND revoked_at IS NULL`,
    [userCode],
  );
  const push = await deletePushDataForUser(client, userCode);
  return {
    guest_passes: Number(guestPasses?.rowCount ?? 0),
    qr_tokens: Number(qrTokens?.rowCount ?? 0),
    push_devices: Number(push?.devices ?? 0),
    push_outbox: Number(push?.outbox ?? 0),
  };
}
