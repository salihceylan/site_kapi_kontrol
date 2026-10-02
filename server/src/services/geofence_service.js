/**
 * AHBU Kapı Kontrol Sistemi - Geofence (Konum Doğrulama) Servisi
 * Aşama 5 & 6: Sunucu Tabanlı Mesafe Doğrulaması, Sahte Konum ve Güvenlik Katmanı
 *
 * SÖZLEŞME C3 (istemci -> sunucu; POST /app/doors/:id/open, POST /app/doors/scan-qr-open,
 * POST /app/doors/:id/qr-token):
 *
 *   İstek gövdesi alanları (üst düzey ya da `location` nesnesi içinde):
 *     latitude   : number  (-90..90, derece)
 *     longitude  : number  (-180..180, derece)
 *     accuracy   : number  (metre, >= 0)
 *     timestamp  : string  (ISO8601 UTC, örn. "2026-10-01T09:30:00.000Z"); geriye dönük uyum için
 *                  epoch milisaniye (sayı) da kabul edilir
 *     is_mocked  : boolean (isMocked takma adı da kabul edilir)
 *
 *   Site `require_geofence = true` ise: alanlardan biri yok/NaN/aralık dışı, konum 60 sn'den bayat,
 *   accuracy > 100 m ya da is_mocked = true ise HTTP 403 ve gövdede { error, code, ... } döner.
 *
 *   code değerleri:
 *     GEOFENCE_LOCATION_REQUIRED   -> konum alanlarından biri hiç gönderilmemiş (missing_fields listelenir)
 *     GEOFENCE_LOCATION_INVALID    -> alan var ama sayı/zaman değil, aralık dışı ya da (0,0)
 *     GEOFENCE_MOCK_LOCATION       -> is_mocked = true
 *     GEOFENCE_LOCATION_STALE      -> |şimdi - timestamp| > 60 sn
 *     GEOFENCE_LOCATION_INACCURATE -> accuracy > 100 m
 *     GEOFENCE_OUT_OF_RANGE        -> kapı alanı dışında (distance_meters, allowed_radius_meters döner)
 *     GEOFENCE_SITE_MISCONFIGURED  -> sitenin geofence merkezi geçersiz (yönetici düzeltmeli)
 *
 *   Varsayılan yarıçap: sitenin geofence_radius_meters değeri (> 0) varsa o, yoksa 100 m.
 *   Site koordinatı hiç tanımlı değilse (eski/yarım yapılandırma) geçişe izin verilir ve
 *   sonuçta warning = 'SITE_COORDINATES_NOT_CONFIGURED' döner (yönetici paneli bunu zorunlu kılar).
 */

export const GEOFENCE_DEFAULT_RADIUS_METERS = 100;
export const GEOFENCE_MAX_ACCURACY_METERS = 100;
export const GEOFENCE_MAX_AGE_MS = 60 * 1000;

export const GEOFENCE_ERROR_CODES = Object.freeze({
  LOCATION_REQUIRED: 'GEOFENCE_LOCATION_REQUIRED',
  LOCATION_INVALID: 'GEOFENCE_LOCATION_INVALID',
  MOCK_LOCATION: 'GEOFENCE_MOCK_LOCATION',
  LOCATION_STALE: 'GEOFENCE_LOCATION_STALE',
  LOCATION_INACCURATE: 'GEOFENCE_LOCATION_INACCURATE',
  OUT_OF_RANGE: 'GEOFENCE_OUT_OF_RANGE',
  SITE_MISCONFIGURED: 'GEOFENCE_SITE_MISCONFIGURED',
});

function isBlank(value) {
  return value === undefined || value === null || (typeof value === 'string' && value.trim() === '');
}

/** NaN-güvenli sayı: sayı ya da sayısal metin -> sonlu number, aksi halde null (boolean/boş/NaN -> null). */
function toFiniteNumber(value) {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === 'string') {
    const text = value.trim();
    if (!text) {
      return null;
    }
    const parsed = Number(text);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function toBoolean(value) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  if (typeof value === 'string') {
    return ['true', '1', 'yes'].includes(value.trim().toLowerCase());
  }
  return false;
}

/**
 * İki coğrafi koordinat arasındaki mesafeyi Haversine formülüyle metre cinsinden hesaplar.
 * Geçersiz (NaN/boş/aralık dışı) girişte Infinity döner (asla "yakın" sanılmaz).
 * @returns {number} Mesafe (metre)
 */
export function calculateHaversineDistanceMeters(lat1, lon1, lat2, lon2) {
  const nLat1 = toFiniteNumber(lat1);
  const nLon1 = toFiniteNumber(lon1);
  const nLat2 = toFiniteNumber(lat2);
  const nLon2 = toFiniteNumber(lon2);

  if (nLat1 === null || nLon1 === null || nLat2 === null || nLon2 === null) {
    return Infinity;
  }
  if (Math.abs(nLat1) > 90 || Math.abs(nLat2) > 90 || Math.abs(nLon1) > 180 || Math.abs(nLon2) > 180) {
    return Infinity;
  }

  // Aynı nokta kontrolü
  if (nLat1 === nLat2 && nLon1 === nLon2) {
    return 0;
  }

  const R = 6371000; // Dünya yarıçapı (metre)
  const phi1 = (nLat1 * Math.PI) / 180;
  const phi2 = (nLat2 * Math.PI) / 180;
  const deltaPhi = ((nLat2 - nLat1) * Math.PI) / 180;
  const deltaLambda = ((nLon2 - nLon1) * Math.PI) / 180;

  const a =
    Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
  const clamped = Math.min(1, Math.max(0, a));
  const c = 2 * Math.atan2(Math.sqrt(clamped), Math.sqrt(1 - clamped));

  return R * c;
}

/**
 * timestamp -> epoch ms. ISO8601 metin (saat dilimi yoksa UTC varsayılır), epoch ms ya da epoch sn.
 * Geçersizse null.
 */
export function parseLocationTimestampMs(value) {
  const numeric = toFiniteNumber(value);
  if (numeric !== null && (typeof value === 'number' || /^\s*-?\d+(\.\d+)?\s*$/.test(String(value)))) {
    if (numeric > 1e11) {
      return numeric; // epoch ms
    }
    if (numeric > 1e9) {
      return numeric * 1000; // epoch sn
    }
    return null;
  }
  if (typeof value !== 'string') {
    return null;
  }
  let text = value.trim();
  if (!text) {
    return null;
  }
  if (!/(?:Z|[+-]\d{2}(?::?\d{2})?)$/i.test(text)) {
    text = `${text}Z`; // saat dilimi belirtilmemiş: UTC kabul et (sunucu TZ'sine düşme)
  }
  const parsed = Date.parse(text);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * İstek gövdesinden konum alanlarını çıkarır: üst düzey alanlar veya `location` nesnesi.
 * Üst düzey alan yoksa `location` nesnesi kullanılır. Hiç alan yoksa null döner.
 */
export function extractClientLocation(body) {
  if (!body || typeof body !== 'object') {
    return null;
  }
  const nested = body.location && typeof body.location === 'object' ? body.location : null;
  const pick = (source) => ({
    latitude: source.latitude,
    longitude: source.longitude,
    accuracy: source.accuracy,
    timestamp: source.timestamp,
    is_mocked: source.is_mocked ?? source.isMocked,
  });

  const topLevel = pick(body);
  const hasTop = Object.values(topLevel).some((value) => value !== undefined);
  if (hasTop) {
    return topLevel;
  }
  if (nested) {
    const fromNested = pick(nested);
    if (Object.values(fromNested).some((value) => value !== undefined)) {
      return fromNested;
    }
  }
  return null;
}

function geofenceError(code, message, extra = {}) {
  const error = new Error(message);
  error.statusCode = 403;
  error.code = code;
  Object.assign(error, extra);
  return error;
}

/** Hata nesnesini istemci yanıt gövdesine çevirir (iç ayrıntı/stack sızdırmaz). */
export function buildGeofenceErrorBody(error) {
  const body = {
    error: error?.message || 'Konum dogrulamasi basarisiz.',
    code: error?.code || GEOFENCE_ERROR_CODES.LOCATION_REQUIRED,
  };
  if (error?.distanceMeters !== undefined) {
    body.distance_meters = error.distanceMeters;
  }
  if (error?.allowedRadiusMeters !== undefined) {
    body.allowed_radius_meters = error.allowedRadiusMeters;
  }
  if (Array.isArray(error?.missingFields)) {
    body.missing_fields = error.missingFields;
  }
  return body;
}

export function isGeofenceError(error) {
  return typeof error?.code === 'string' && error.code.startsWith('GEOFENCE_');
}

/**
 * Kapı talebi öncesinde sunucu tabanlı geofence ve güvenlik doğrulamalarını yapar.
 * @param {object} params
 * @param {object} params.site - Site (ya da kapı satırı) kaydı: require_geofence, geofence_latitude/longitude/radius_meters
 * @param {object} [params.clientLocation] - { latitude, longitude, accuracy, timestamp, is_mocked }
 * @param {object} params.authUser - İstekte bulunan kullanıcı (yalnızca loglama)
 * @param {string} [params.doorName] - Kapı adı (yalnızca loglama)
 * @param {number} [params.now] - Test için şimdiki zaman (ms)
 * @param {boolean} [params.forceRequire] - true ise site bayrağından bağımsız zorunlu kıl
 *        (ekransız/statik karekodlu cihazlar için)
 * @returns {object} { allowed: true, geofence_required, distance_meters?, allowed_radius_meters?, warning? }
 */
export function validateGeofenceForDoorRequest({
  site,
  clientLocation,
  authUser,
  doorName,
  now = Date.now(),
  forceRequire = false,
}) {
  // Sitede geofence zorunlu kılınmamışsa doğrudan izin ver (Geriye dönük uyumluluk)
  if (!forceRequire && site?.require_geofence !== true) {
    return { allowed: true, geofence_required: false };
  }

  const siteLat = toFiniteNumber(site?.geofence_latitude);
  const siteLon = toFiniteNumber(site?.geofence_longitude);

  // Sitede koordinat tanımlanmamışsa logla ve izin ver (Konfigürasyon tamamlanana kadar bloklamaz)
  if (siteLat === null || siteLon === null) {
    console.warn(`[Geofence] Sitede koordinat tanimli degil (Site: ${site?.site_code}). Gecise izin verildi.`);
    return { allowed: true, geofence_required: true, warning: 'SITE_COORDINATES_NOT_CONFIGURED' };
  }
  if (Math.abs(siteLat) > 90 || Math.abs(siteLon) > 180) {
    console.error(`[Geofence] Site koordinati gecersiz (Site: ${site?.site_code}).`);
    throw geofenceError(
      GEOFENCE_ERROR_CODES.SITE_MISCONFIGURED,
      'Sitenin konum (geofence) ayari gecersiz. Lutfen site yoneticisiyle iletisime geciniz.',
    );
  }

  // 1. İstemciden konum alanları gelmiş mi?
  const location = clientLocation && typeof clientLocation === 'object' ? clientLocation : {};
  const missingFields = ['latitude', 'longitude', 'accuracy', 'timestamp'].filter((field) => isBlank(location[field]));
  if (missingFields.length > 0) {
    throw geofenceError(
      GEOFENCE_ERROR_CODES.LOCATION_REQUIRED,
      'Bu kapi icin konum dogrulamasi zorunludur. Lutfen telefonunuzun GPS konum servisini ve uygulama izinlerini aciniz.',
      { missingFields },
    );
  }

  // 2. Alanlar sayısal/geçerli mi? (NaN-güvenli)
  const clientLat = toFiniteNumber(location.latitude);
  const clientLon = toFiniteNumber(location.longitude);
  const clientAccuracy = toFiniteNumber(location.accuracy);
  const clientTimestamp = parseLocationTimestampMs(location.timestamp);
  const invalid =
    clientLat === null ||
    clientLon === null ||
    clientAccuracy === null ||
    clientTimestamp === null ||
    Math.abs(clientLat) > 90 ||
    Math.abs(clientLon) > 180 ||
    clientAccuracy < 0 ||
    (clientLat === 0 && clientLon === 0);
  if (invalid) {
    throw geofenceError(
      GEOFENCE_ERROR_CODES.LOCATION_INVALID,
      'Konum bilgisi gecersiz. Lutfen GPS konumunuzun yenilenmesini bekleyip tekrar deneyiniz.',
    );
  }

  // 3. Aşama 6.3: Sahte Konum (Mock Location / Fake GPS) Koruması
  if (toBoolean(location.is_mocked ?? location.isMocked)) {
    console.warn(`[Geofence GUVENLIK IHLALI] Sahte konum tespit edildi. Kullanici: ${authUser?.id}`);
    throw geofenceError(
      GEOFENCE_ERROR_CODES.MOCK_LOCATION,
      'Sahte konum (Mock Location) kullanimi tespit edildi. Guvenlik nedeniyle islem yapilamaz.',
    );
  }

  // 4. Aşama 6.1: Konum zaman aşımı (en fazla 60 sn; gelecekteki zaman damgası da geçersiz)
  const ageMs = Math.abs(now - clientTimestamp);
  if (ageMs > GEOFENCE_MAX_AGE_MS) {
    console.warn(`[Geofence] Bayat konum tespit edildi (Yas: ${Math.round(ageMs / 1000)}s).`);
    throw geofenceError(
      GEOFENCE_ERROR_CODES.LOCATION_STALE,
      'Konum bilginiz guncel degil. Lutfen GPS sinyalinizin yenilenmesini bekleyiniz.',
    );
  }

  // 5. Aşama 6.2: Kabul edilebilir doğruluk (<= 100 m)
  if (clientAccuracy > GEOFENCE_MAX_ACCURACY_METERS) {
    console.warn(`[Geofence] Yetersiz GPS dogrulugu (~${Math.round(clientAccuracy)}m).`);
    throw geofenceError(
      GEOFENCE_ERROR_CODES.LOCATION_INACCURATE,
      `GPS dogrulugu yetersiz (~${Math.round(clientAccuracy)}m). Lutfen acik alana cikip tekrar deneyiniz.`,
    );
  }

  // 6. Aşama 5: Sunucu tabanlı Haversine mesafe hesaplama
  const distanceMeters = calculateHaversineDistanceMeters(siteLat, siteLon, clientLat, clientLon);
  const siteRadius = toFiniteNumber(site?.geofence_radius_meters);
  const allowedRadiusMeters = siteRadius !== null && siteRadius > 0 ? siteRadius : GEOFENCE_DEFAULT_RADIUS_METERS;

  if (!(distanceMeters <= allowedRadiusMeters)) {
    console.warn(
      `[Geofence RED] Kullanici kapi alaninda degil. Mesafe: ~${Math.round(distanceMeters)}m, Izin verilen: ${allowedRadiusMeters}m (Kapi: ${doorName || site?.site_code})`,
    );
    throw geofenceError(
      GEOFENCE_ERROR_CODES.OUT_OF_RANGE,
      `Kapi konumunda degilsiniz (Mesafe: ~${Math.round(distanceMeters)}m, Izin verilen sinir: ${allowedRadiusMeters}m). Lutfen kapiya yaklasiniz.`,
      {
        distanceMeters: Number.isFinite(distanceMeters) ? Math.round(distanceMeters) : null,
        allowedRadiusMeters,
      },
    );
  }

  return {
    allowed: true,
    geofence_required: true,
    distance_meters: Math.round(distanceMeters),
    allowed_radius_meters: allowedRadiusMeters,
  };
}
