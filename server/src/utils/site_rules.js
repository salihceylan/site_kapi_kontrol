// Site / yonetici akislarinin DB'siz (saf) kurallari.
// manager_routes.js ve site_service.js bu fonksiyonlari kullanir; ayri tutulmalarinin
// nedeni birim testlerin veritabani/MQTT'ye baglanmadan calisabilmesidir.

import crypto from 'crypto';

// ---------------------------------------------------------------------------
// Genel yardimcilar
// ---------------------------------------------------------------------------

// HTML5 "valid email" benzeri; alan adinda en az bir nokta zorunlu, toplam <= 254.
const EMAIL_PATTERN =
  /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;

export function isValidEmail(value) {
  if (typeof value !== 'string') {
    return false;
  }
  const text = value.trim();
  if (text.length < 6 || text.length > 254) {
    return false;
  }
  const localPart = text.slice(0, text.lastIndexOf('@'));
  if (localPart.length === 0 || localPart.length > 64) {
    return false;
  }
  return EMAIL_PATTERN.test(text);
}

// Kontrol karakterlerini (satir sonu, sekme, NUL, bidi vb. dahil) siler, bosluklari tek
// bosluga indirir, kirpar ve kod noktasi bazinda en fazla maxLength karaktere keser.
export function sanitizeDisplayText(value, maxLength) {
  const cleaned = String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001F\u007F-\u009F\u2028\u2029\u200B-\u200F\u202A-\u202E\u2066-\u2069]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const chars = Array.from(cleaned);
  return chars.length > maxLength ? chars.slice(0, maxLength).join('').trim() : cleaned;
}

// Sabit zamanli metin karsilastirmasi (uzunluk farkinda erken doner; uzunluk gizli degildir).
export function safeEqualStrings(left, right) {
  const a = Buffer.from(String(left ?? ''), 'utf8');
  const b = Buffer.from(String(right ?? ''), 'utf8');
  if (a.length !== b.length) {
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

// Istemciye guvenle gosterilebilecek (is mantigi) hata mi? DB/sistem hatalari ve ic hata
// kodlari (DOOR_NOT_FOUND gibi) istemciye oldugu gibi gitmez.
export function isClientSafeError(error) {
  if (!error || typeof error.message !== 'string' || error.message.trim() === '') {
    return false;
  }
  const status = Number(error.statusCode);
  if (Number.isInteger(status) && status >= 500) {
    return false;
  }
  if (Number.isInteger(status) && status >= 400 && status < 500) {
    return true;
  }
  // TypeError, pg DatabaseError, Node SystemError vb. alt siniflar elenir.
  if (Object.getPrototypeOf(error) !== Error.prototype) {
    return false;
  }
  if (error.code || error.severity || error.routine || error.errno) {
    return false;
  }
  if (/^[A-Z0-9_]+$/.test(error.message.trim())) {
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Deneme sayaci (brute-force korumasi)
// ---------------------------------------------------------------------------

/**
 * Bellek ici, anahtar bazli ardisik hata sayaci.
 * - maxFailures hataya ulasinca anahtar lockMs boyunca kilitlenir.
 * - windowMs icinde yeni hata gelmezse sayac sifirlanir.
 */
export function createAttemptTracker({
  maxFailures = 5,
  windowMs = 10 * 60 * 1000,
  lockMs = 15 * 60 * 1000,
  now = () => Date.now(),
  maxKeys = 2000,
} = {}) {
  const entries = new Map();

  function prune(current) {
    if (entries.size <= maxKeys) {
      return;
    }
    for (const [key, entry] of entries) {
      const lockExpired = !entry.lockedUntil || entry.lockedUntil <= current;
      const windowExpired = entry.firstFailureAt + windowMs <= current;
      if (lockExpired && windowExpired) {
        entries.delete(key);
      }
    }
    // Hala doluysa en eskileri at (bellek siniri).
    while (entries.size > maxKeys) {
      const oldestKey = entries.keys().next().value;
      entries.delete(oldestKey);
    }
  }

  return {
    /** @returns {{ locked: boolean, retryAfterSeconds: number }} */
    check(key) {
      const current = now();
      const entry = entries.get(key);
      if (entry?.lockedUntil && entry.lockedUntil > current) {
        return {
          locked: true,
          retryAfterSeconds: Math.max(1, Math.ceil((entry.lockedUntil - current) / 1000)),
        };
      }
      return { locked: false, retryAfterSeconds: 0 };
    },
    /** @returns {{ failures: number, locked: boolean }} */
    recordFailure(key) {
      const current = now();
      prune(current);
      let entry = entries.get(key);
      if (!entry || (entry.lockedUntil && entry.lockedUntil <= current) || entry.firstFailureAt + windowMs <= current) {
        entry = { failures: 0, firstFailureAt: current, lockedUntil: 0 };
      }
      entry.failures += 1;
      if (entry.failures >= maxFailures) {
        entry.lockedUntil = current + lockMs;
      }
      entries.set(key, entry);
      return { failures: entry.failures, locked: entry.lockedUntil > current };
    },
    reset(key) {
      entries.delete(key);
    },
    size() {
      return entries.size;
    },
  };
}

// ---------------------------------------------------------------------------
// Site yoneticisi cikarma kurallari
// ---------------------------------------------------------------------------

/**
 * @param {{ managerCodes: Array<number|string>, targetCode: number, callerCode: number,
 *           isSuperUser: boolean, targetIsOwner: boolean }} input
 * managerCodes: sitenin tum yoneticileri (site_manager_sites UNION aktif SITE_OWNER/SITE_ADMIN).
 */
export function evaluateManagerRemoval({
  managerCodes,
  targetCode,
  callerCode,
  isSuperUser,
  targetIsOwner,
}) {
  const codes = new Set((managerCodes || []).map((item) => Number(item)));
  if (!codes.has(Number(targetCode))) {
    return {
      ok: false,
      statusCode: 404,
      message: 'Kullanıcı bu sitenin yöneticisi değil.',
    };
  }

  const remaining = [...codes].filter((code) => code !== Number(targetCode));
  if (remaining.length === 0) {
    return {
      ok: false,
      statusCode: 400,
      message: 'Sitenin en az 1 aktif yöneticisi bulunmalıdır. Son yönetici çıkarılamaz.',
    };
  }

  if (targetIsOwner && !isSuperUser && Number(callerCode) !== Number(targetCode)) {
    return {
      ok: false,
      statusCode: 403,
      message: 'Sitenin kurucu yöneticisi (Site Sahibi) yalnızca Süper Kullanıcı tarafından çıkarılabilir.',
    };
  }

  return { ok: true };
}

/**
 * Yoneticilik kalkinca global rol ne olmali? null => degistirme.
 * Rol yalnizca baska yonetilen site kalmadiysa geri alinir; onceki rol tahmini:
 * dairede aktif uyeligi varsa apartment_owner, yoksa individual.
 */
export function decideRoleAfterManagerRemoval({
  currentRole,
  hasOtherManagedSites,
  hasApartmentMembership,
}) {
  if (currentRole !== 'site_manager') {
    return null;
  }
  if (hasOtherManagedSites) {
    return null;
  }
  return hasApartmentMembership ? 'apartment_owner' : 'individual';
}

// ---------------------------------------------------------------------------
// Guvenlik politikasi (PATCH /manager/sites/:id/security-policy)
// ---------------------------------------------------------------------------

const INVALID = Symbol('invalid');

export const GEOFENCE_RADIUS_MIN = 10;
export const GEOFENCE_RADIUS_MAX = 2000;
export const QR_ROTATION_MIN = 10;
export const QR_ROTATION_MAX = 300;

const FEATURE_FIELDS = [
  { body: 'feature_remote_open_enabled', patch: 'featureRemoteOpenEnabled', column: 'feature_remote_open_enabled' },
  { body: 'feature_qr_enabled', patch: 'featureQrEnabled', column: 'feature_qr_enabled' },
  { body: 'feature_local_udp_enabled', patch: 'featureLocalUdpEnabled', column: 'feature_local_udp_enabled' },
  { body: 'feature_guest_pass_enabled', patch: 'featureGuestPassEnabled', column: 'feature_guest_pass_enabled' },
];

// undefined/null -> undefined (degisiklik yok); true/false/'true'/'false' -> bool; digeri INVALID
function readBool(raw) {
  if (raw === undefined || raw === null) {
    return undefined;
  }
  if (typeof raw === 'boolean') {
    return raw;
  }
  if (raw === 'true') {
    return true;
  }
  if (raw === 'false') {
    return false;
  }
  return INVALID;
}

function readFiniteNumber(raw) {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : INVALID;
  }
  if (typeof raw === 'string') {
    const text = raw.trim();
    if (text === '') {
      return INVALID;
    }
    const value = Number(text);
    return Number.isFinite(value) ? value : INVALID;
  }
  return INVALID;
}

// undefined -> undefined (degisiklik yok); null -> null (temizle); sayi -> aralik kontrollu
function readCoordinate(raw, min, max) {
  if (raw === undefined) {
    return undefined;
  }
  if (raw === null) {
    return null;
  }
  const value = readFiniteNumber(raw);
  if (value === INVALID || value < min || value > max) {
    return INVALID;
  }
  return value;
}

function isValidCoordinatePair(latitude, longitude) {
  if (typeof latitude !== 'number' || typeof longitude !== 'number') {
    return false;
  }
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return false;
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return false;
  }
  // (0,0) "ayarlanmamis" varsayilani gibi davranir; gercek bir site merkezi olamaz.
  return !(latitude === 0 && longitude === 0);
}

/**
 * Gövdeyi tip/aralik acisindan dogrular. undefined => alan gonderilmedi (degistirme),
 * null (yalniz enlem/boylam) => temizle.
 * @returns {{ ok: true, patch: object } | { ok: false, error: string }}
 */
export function parseSecurityPolicyBody(body) {
  const source = body && typeof body === 'object' ? body : {};
  const patch = {};

  for (const field of FEATURE_FIELDS) {
    const value = readBool(source[field.body]);
    if (value === INVALID) {
      return { ok: false, error: `${field.body} alani true/false olmalidir.` };
    }
    patch[field.patch] = value;
  }

  const qrEntryActive = readBool(source.qr_entry_active);
  if (qrEntryActive === INVALID) {
    return { ok: false, error: 'qr_entry_active alani true/false olmalidir.' };
  }
  patch.qrEntryActive = qrEntryActive;

  const requireGeofence = readBool(source.require_geofence);
  if (requireGeofence === INVALID) {
    return { ok: false, error: 'require_geofence alani true/false olmalidir.' };
  }
  patch.requireGeofence = requireGeofence;

  const latitude = readCoordinate(source.geofence_latitude, -90, 90);
  if (latitude === INVALID) {
    return { ok: false, error: 'Enlem -90 ile 90 arasinda olmalidir.' };
  }
  patch.geofenceLatitude = latitude;

  const longitude = readCoordinate(source.geofence_longitude, -180, 180);
  if (longitude === INVALID) {
    return { ok: false, error: 'Boylam -180 ile 180 arasinda olmalidir.' };
  }
  patch.geofenceLongitude = longitude;

  if (source.geofence_radius_meters === undefined || source.geofence_radius_meters === null) {
    patch.geofenceRadiusMeters = undefined;
  } else {
    const radius = readFiniteNumber(source.geofence_radius_meters);
    if (radius === INVALID || Math.round(radius) < GEOFENCE_RADIUS_MIN || Math.round(radius) > GEOFENCE_RADIUS_MAX) {
      return {
        ok: false,
        error: `Konum yaricapi ${GEOFENCE_RADIUS_MIN} ile ${GEOFENCE_RADIUS_MAX} metre arasinda olmalidir.`,
      };
    }
    patch.geofenceRadiusMeters = Math.round(radius);
  }

  if (source.qr_rotation_seconds === undefined || source.qr_rotation_seconds === null) {
    patch.qrRotationSeconds = undefined;
  } else {
    const seconds = readFiniteNumber(source.qr_rotation_seconds);
    if (seconds === INVALID) {
      return { ok: false, error: 'qr_rotation_seconds sayisal olmalidir.' };
    }
    patch.qrRotationSeconds = Math.max(QR_ROTATION_MIN, Math.min(QR_ROTATION_MAX, Math.round(seconds)));
  }

  return { ok: true, patch };
}

function existingFlag(value) {
  // Kolon varsayilanlari TRUE; eski satirlarda alan hic gelmeyebilir.
  return value === undefined || value === null ? true : Boolean(value);
}

function numberOrNull(value) {
  if (value === undefined || value === null || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Dogrulanmis patch + mevcut site satiri + yetkiden updateSiteByCode girdisini uretir.
 * @returns {{ ok: true, update: object } | { ok: false, status: number, error: string }}
 */
export function resolveSecurityPolicyUpdate({ patch, existing, isSuperUser }) {
  const update = {};

  // 1) Giris yontemi bayraklari yalnizca super user degistirebilir.
  for (const field of FEATURE_FIELDS) {
    const requested = patch[field.patch];
    if (requested === undefined) {
      continue;
    }
    if (!isSuperUser) {
      if (requested !== existingFlag(existing?.[field.column])) {
        return {
          ok: false,
          status: 403,
          error: 'Giris yontemi yetkilendirmesi (Uygulama/QR) yalnizca super user tarafindan yapilabilir.',
        };
      }
      continue; // degeri ayni; sessizce yok say
    }
    update[field.patch] = requested;
  }

  const effective = (field) => (
    isSuperUser && patch[field.patch] !== undefined
      ? patch[field.patch]
      : existingFlag(existing?.[field.column])
  );
  const effRemote = effective(FEATURE_FIELDS[0]);
  const effQr = effective(FEATURE_FIELDS[1]);

  // 2) En az bir giris yontemi acik kalmali (yalnizca bu bayraklara dokunuluyorsa kontrol).
  const touchesAccessMode = isSuperUser
    && (patch.featureRemoteOpenEnabled !== undefined || patch.featureQrEnabled !== undefined);
  if (touchesAccessMode && !effRemote && !effQr) {
    return {
      ok: false,
      status: 400,
      error: 'En az bir giris yontemi (Mobil Uygulama veya QR Kod) acik olmalidir.',
    };
  }

  // 3) QR girisi: QR ozelligi kapaliysa aktif olamaz; kismi guncellemede mevcut deger bozulmaz.
  if (!effQr) {
    if (patch.qrEntryActive !== undefined || existing?.qr_entry_active !== false) {
      update.qrEntryActive = false;
    }
  } else if (patch.qrEntryActive !== undefined) {
    update.qrEntryActive = patch.qrEntryActive;
  }

  // 4) Konum dogrulamasi
  if (patch.requireGeofence !== undefined) {
    update.requireGeofence = patch.requireGeofence;
  }
  if (patch.geofenceLatitude !== undefined) {
    update.geofenceLatitude = patch.geofenceLatitude;
  }
  if (patch.geofenceLongitude !== undefined) {
    update.geofenceLongitude = patch.geofenceLongitude;
  }
  if (patch.geofenceRadiusMeters !== undefined) {
    update.geofenceRadiusMeters = patch.geofenceRadiusMeters;
  }
  if (patch.qrRotationSeconds !== undefined) {
    update.qrRotationSeconds = patch.qrRotationSeconds;
  }

  const touchesGeofence = patch.requireGeofence !== undefined
    || patch.geofenceLatitude !== undefined
    || patch.geofenceLongitude !== undefined;
  if (touchesGeofence) {
    const effRequire = patch.requireGeofence !== undefined
      ? patch.requireGeofence
      : Boolean(existing?.require_geofence);
    const effLatitude = patch.geofenceLatitude !== undefined
      ? patch.geofenceLatitude
      : numberOrNull(existing?.geofence_latitude);
    const effLongitude = patch.geofenceLongitude !== undefined
      ? patch.geofenceLongitude
      : numberOrNull(existing?.geofence_longitude);
    if (effRequire && !isValidCoordinatePair(effLatitude, effLongitude)) {
      return {
        ok: false,
        status: 400,
        error: 'Konum dogrulamasi acikken gecerli bir enlem ve boylam (site merkezi) zorunludur.',
      };
    }
  }

  return { ok: true, update };
}

// ---------------------------------------------------------------------------
// Kapi servisi hatalari -> HTTP
// ---------------------------------------------------------------------------

const DOOR_ERROR_MAP = {
  DOOR_NOT_FOUND: { status: 404, message: 'Kapi bulunamadi.' },
  DEVICE_NOT_FOUND: { status: 404, message: 'Cihaz sirket hesabinda kayitli degil.' },
  DEVICE_NOT_ASSIGNABLE: { status: 403, message: 'Bu cihaz yonettiginiz siteye atanamaz.' },
  DEVICE_OWNED_BY_ANOTHER: {
    status: 409,
    message: 'Bu cihaz baska bir kullanici hesabi tarafindan sahiplenilmis.',
  },
  DEVICE_DEFECTIVE: { status: 409, message: 'Bu cihaz arizali olarak isaretlenmis.' },
  MISSING_NEW_DEVICE: {
    status: 400,
    message: 'Lutfen yeni cihazin QR kodunu, seri numarasini veya cihaz ID\'sini belirtin.',
  },
};

// door_service'in kullaniciya gosterilmek icin firlattigi (kod olmayan) dogrulama mesajlari.
const DOOR_VALIDATION_MESSAGES = new Set([
  'Kapı adı zorunludur.',
  'Kapı adı boş olamaz.',
  'Güncellenecek alan bulunamadı.',
]);

/** @returns {{ status: number, message: string } | null} null => beklenmeyen (generic 500) */
export function mapDoorServiceError(error) {
  const message = typeof error?.message === 'string' ? error.message : '';
  if (Object.prototype.hasOwnProperty.call(DOOR_ERROR_MAP, message)) {
    return DOOR_ERROR_MAP[message];
  }
  if (DOOR_VALIDATION_MESSAGES.has(message)) {
    return { status: 400, message };
  }
  if (isClientSafeError(error) && Number.isInteger(Number(error.statusCode))) {
    return { status: Number(error.statusCode), message };
  }
  return null;
}
