/**
 * Yerel kontrol token'ı döndürme (yetki kaldırma sonrası).
 *
 * Bir kullanıcının daire üyeliği / kapı izni kaldırıldığında, daha önce uygulama önbelleğine
 * aldığı cihaz `local_control_token` değeri ile yerel (UDP/HTTP) açma yapabilmesi engellenmelidir.
 * Bunun için ilgili cihazların token'ı döndürülür ve MQTT `local_control_config` komutuyla cihaza iletilir
 * (device_service.rotateLocalControlTokensForDeviceIds mevcut mekanizmasını kullanır).
 *
 * device_service -> mqtt_bridge zincirini yalnızca gerektiğinde yüklemek için (ve birim testlerin
 * MQTT'ye dokunmaması için) device_service tembel (dynamic import) yüklenir.
 */

/**
 * Cihaz kimliği listesini tekilleştirip güvenli pozitif tamsayılara indirger.
 */
export function normalizeDeviceIdList(deviceIds) {
  if (!Array.isArray(deviceIds)) {
    return [];
  }
  const out = new Set();
  for (const item of deviceIds) {
    const num = Number(item);
    if (Number.isSafeInteger(num) && num > 0) {
      out.add(num);
    }
  }
  return [...out];
}

async function loadDeviceService() {
  return import('./device_service.js');
}

/**
 * Verilen cihaz kimliklerinin token'ını döndürür. Asla fırlatmaz (ana işlem zaten tamamlanmıştır);
 * başarısızlık sunucu günlüğüne yazılır. Döndürülen cihaz sayısını verir.
 */
export async function rotateTokensForDevices({ deviceIds, reason }) {
  const ids = normalizeDeviceIdList(deviceIds);
  if (ids.length === 0) {
    return 0;
  }
  try {
    const { rotateLocalControlTokensForDeviceIds } = await loadDeviceService();
    const rotated = await rotateLocalControlTokensForDeviceIds(ids, reason);
    return Array.isArray(rotated) ? rotated.length : 0;
  } catch (error) {
    console.error('[LocalToken] Token döndürme başarısız:', reason, error?.code || error?.name || 'error');
    return 0;
  }
}

/**
 * Sitedeki tüm cihazların token'ını döndürür (daireden çıkarma / üyelik pasifleştirme sonrası:
 * kullanıcı sitedeki birden fazla kapıya erişebiliyor olabilir).
 */
export async function rotateTokensForSite({ siteCode, reason }) {
  const code = Number(siteCode);
  if (!Number.isSafeInteger(code) || code <= 0) {
    return 0;
  }
  try {
    const { deviceIdsForSite, rotateLocalControlTokensForDeviceIds } = await loadDeviceService();
    const deviceIds = normalizeDeviceIdList(await deviceIdsForSite(code));
    if (deviceIds.length === 0) {
      return 0;
    }
    const rotated = await rotateLocalControlTokensForDeviceIds(deviceIds, reason);
    return Array.isArray(rotated) ? rotated.length : 0;
  } catch (error) {
    console.error('[LocalToken] Site token döndürme başarısız:', reason, error?.code || error?.name || 'error');
    return 0;
  }
}
