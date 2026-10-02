/**
 * AHBU Kapı Kontrol Sistemi - Kapı Açma Politikası (saf, DB/MQTT bağımsız)
 *
 * Sözleşme C2: `assertDoorOpenAllowed({ door, channel, authUser })`
 *  - Senkron; ihlalde Error fırlatır: err.statusCode = 403, err.code = '<KOD>'.
 *  - `door`: site politika kolonlarını içeren satır (sites.feature_* / qr_entry_active ...).
 *    Kolon hiç yoksa (undefined/null) "açık" kabul edilir (geriye dönük uyum); yalnızca
 *    AÇIKÇA `false` olan bayrak engeller (009 migration varsayılanları TRUE).
 *  - `channel`:
 *      'remote' -> uygulamadan bulut üzerinden uzaktan açma   (feature_remote_open_enabled)
 *      'qr'     -> karekod ile açma (cihaz okuyucu / ekrandaki karekodu uygulamayla okutma)
 *                  (feature_qr_enabled VE qr_entry_active)
 *      'guest'  -> misafir geçiş linki                        (feature_guest_pass_enabled)
 *      'local'  -> yerel ağ (UDP/HTTP) ile açma               (feature_local_udp_enabled)
 *  - super_user istisnası: 'remote', 'qr' ve 'local' kanallarında korunur (mevcut davranış).
 *    'guest' kanalında istisna YOKTUR (herkese açık link; site bayrağı herkes için geçerli).
 *
 * Hata kodları:
 *   REMOTE_OPEN_DISABLED, QR_DISABLED, QR_ENTRY_INACTIVE, GUEST_DISABLED, LOCAL_DISABLED,
 *   DOOR_NOT_FOUND (door yok, 404), INVALID_DOOR_CHANNEL (programlama hatası, 500)
 *
 * Geofence burada DEĞİL (konum istekten gelir): bkz. geofence_service.js (C3).
 */

import crypto from 'node:crypto';
import net from 'node:net';

export const DOOR_CHANNELS = Object.freeze(['remote', 'qr', 'guest', 'local']);

function policyError(code, message, statusCode = 403) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function isSuperUser(authUser) {
  return authUser?.role === 'super_user';
}

/**
 * Politikayı değerlendirir; izinliyse null, değilse { code, message, statusCode } döner.
 */
export function evaluateDoorOpenPolicy({ door, channel, authUser } = {}) {
  if (!DOOR_CHANNELS.includes(channel)) {
    return {
      code: 'INVALID_DOOR_CHANNEL',
      message: 'Gecersiz kapi acma kanali.',
      statusCode: 500,
    };
  }
  if (!door || typeof door !== 'object') {
    return {
      code: 'DOOR_NOT_FOUND',
      message: 'Kapi bulunamadi.',
      statusCode: 404,
    };
  }

  const superUser = isSuperUser(authUser);

  switch (channel) {
    case 'remote':
      if (door.feature_remote_open_enabled === false && !superUser) {
        return {
          code: 'REMOTE_OPEN_DISABLED',
          message:
            'Bu sitede uygulama uzerinden uzaktan kapi acma yetkisi kapalidir. Lutfen kapi onundeki QR okuyucuyu kullanin.',
          statusCode: 403,
        };
      }
      return null;

    case 'qr':
      if (superUser) {
        return null;
      }
      if (door.feature_qr_enabled === false) {
        return {
          code: 'QR_DISABLED',
          message: 'Bu sitede karekod ile kapi acma yetkisi kapalidir.',
          statusCode: 403,
        };
      }
      if (door.qr_entry_active === false) {
        return {
          code: 'QR_ENTRY_INACTIVE',
          message: 'Bu sitede karekod ile giris yonetim tarafindan gecici olarak durdurulmustur.',
          statusCode: 403,
        };
      }
      return null;

    case 'guest':
      if (door.feature_guest_pass_enabled === false) {
        return {
          code: 'GUEST_DISABLED',
          message: 'Bu sitede misafir gecisleri yonetim tarafindan devre disi birakilmistir.',
          statusCode: 403,
        };
      }
      return null;

    case 'local':
      if (door.feature_local_udp_enabled === false && !superUser) {
        return {
          code: 'LOCAL_DISABLED',
          message: 'Bu sitede yerel ag uzerinden kapi acma yetkisi kapalidir.',
          statusCode: 403,
        };
      }
      return null;

    default:
      return null;
  }
}

/**
 * C2: İzin yoksa Error fırlatır (statusCode, code ile); izinliyse undefined döner.
 */
export function assertDoorOpenAllowed({ door, channel, authUser } = {}) {
  const violation = evaluateDoorOpenPolicy({ door, channel, authUser });
  if (violation) {
    throw policyError(violation.code, violation.message, violation.statusCode);
  }
}

/** Fırlatmayan sürüm (UI/yanıt şekillendirme için). */
export function isDoorChannelAllowed({ door, channel, authUser } = {}) {
  return evaluateDoorOpenPolicy({ door, channel, authUser }) === null;
}

// ---------------------------------------------------------------------------
// İstek doğrulama yardımcıları
// ---------------------------------------------------------------------------

/** Pozitif güvenli tamsayı (yalnızca rakam); aksi halde null. */
export function parsePositiveDoorId(value) {
  const text = String(value ?? '').trim();
  if (!/^[0-9]{1,15}$/.test(text)) {
    return null;
  }
  const parsed = Number(text);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

/** Yerel IP bilgisi: yalnızca geçerli IP literali, aksi halde null (log enjeksiyonu/uzun metin engeli). */
export function normalizeLocalIp(value) {
  const text = String(value ?? '').trim();
  if (!text || text.length > 45) {
    return null;
  }
  return net.isIP(text) ? text : null;
}

/**
 * Uygulamanın okuttuğu karekod yükünü çözer.
 * Biçimler: "AHBU:DOOR:<uid>:<token>", "AHBU:DOOR:<uid>", "<uid>:<token>", "<uid>"
 * @returns {{uid: string, token: string} | null}
 */
export function parseScanQrPayload(raw) {
  if (typeof raw !== 'string') {
    return null;
  }
  let text = raw.trim();
  if (!text || text.length > 128) {
    return null;
  }
  if (/^AHBU:DOOR:/i.test(text)) {
    text = text.slice('AHBU:DOOR:'.length).trim();
  }
  const parts = text.split(':');
  const uid = String(parts[0] || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  if (!uid) {
    return null;
  }
  const token = parts.length > 1 ? String(parts[1] || '').trim().toUpperCase() : '';
  return { uid, token };
}

// ---------------------------------------------------------------------------
// Cihaz donanımı: ekranlı (WROOM) / ekransız (C3)
// ---------------------------------------------------------------------------

export function resolveHardwareTarget(row) {
  return String(
    row?.assigned_device_hardware_target ||
      row?.assigned_device_hardware_type ||
      row?.hardware_target ||
      row?.hardware_type ||
      '',
  ).toLowerCase();
}

/**
 * Cihazın dinamik karekod ekranı var mı? C3 -> yok. Bilinmeyen donanım "ekranlı" kabul edilir
 * (fail-closed: statik UID ile açmaya düşmez).
 */
export function doorDeviceHasScreen(row) {
  return !resolveHardwareTarget(row).includes('c3');
}

// ---------------------------------------------------------------------------
// Ekran karekodu (dinamik token) saklama mantığı - saf fonksiyonlar
// mqtt_bridge.js içindeki deviceScreenQrStore (Map<uid, entry>) üzerinde çalışır.
// entry: { currentToken, previousToken, updatedAt, expiresAt, usedTokens:Set }
// ---------------------------------------------------------------------------

export const SCREEN_QR_GRACE_MS = 12000;
export const SCREEN_QR_DEFAULT_VALID_SECONDS = 30;

export function normalizeScreenQrToken(raw) {
  const text = String(raw ?? '').trim().toUpperCase();
  return /^[0-9A-Z]{4,32}$/.test(text) ? text : '';
}

export function clampScreenQrValiditySeconds(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return SCREEN_QR_DEFAULT_VALID_SECONDS;
  }
  return Math.min(Math.max(Math.round(parsed), 5), 300);
}

function safeEqual(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  if (left.length !== right.length) {
    return false;
  }
  return crypto.timingSafeEqual(left, right);
}

/**
 * Cihazdan gelen yeni ekran tokenını uygular. Aynı token tekrar gelirse (yinelenen yayın)
 * kayıt DEĞİŞMEZ; geçerlilik süresi uzatılmaz ve "kullanıldı" işareti sıfırlanmaz.
 */
export function applyScreenQrUpdate(prev, token, validSeconds, now = Date.now()) {
  const normalized = normalizeScreenQrToken(token);
  if (!normalized) {
    return prev ?? null;
  }
  if (prev && prev.currentToken === normalized) {
    return prev;
  }
  const used = new Set();
  if (prev?.usedTokens) {
    for (const candidate of prev.usedTokens) {
      if (candidate === prev.currentToken || candidate === normalized) {
        used.add(candidate);
      }
    }
  }
  const seconds = clampScreenQrValiditySeconds(validSeconds);
  return {
    currentToken: normalized,
    previousToken: prev?.currentToken || null,
    updatedAt: now,
    expiresAt: now + seconds * 1000 + SCREEN_QR_GRACE_MS,
    usedTokens: used,
  };
}

/**
 * Yan etkisiz doğrulama.
 * @returns {{ok: true, which: 'current'|'previous', token: string} |
 *           {ok: false, reason: 'NO_ENTRY'|'INVALID'|'MISMATCH'|'EXPIRED'|'ALREADY_USED'}}
 */
export function checkScreenQrToken(entry, token, now = Date.now()) {
  if (!entry || !entry.currentToken) {
    return { ok: false, reason: 'NO_ENTRY' };
  }
  const normalized = normalizeScreenQrToken(token);
  if (!normalized) {
    return { ok: false, reason: 'INVALID' };
  }

  const isCurrent = safeEqual(normalized, entry.currentToken);
  const isPrevious = entry.previousToken ? safeEqual(normalized, entry.previousToken) : false;
  if (!isCurrent && !isPrevious) {
    return { ok: false, reason: 'MISMATCH' };
  }

  if (isCurrent) {
    if (now > entry.expiresAt) {
      return { ok: false, reason: 'EXPIRED' };
    }
  } else if (now > entry.updatedAt + SCREEN_QR_GRACE_MS) {
    return { ok: false, reason: 'EXPIRED' };
  }

  if (entry.usedTokens && entry.usedTokens.has(normalized)) {
    return { ok: false, reason: 'ALREADY_USED' };
  }
  return { ok: true, which: isCurrent ? 'current' : 'previous', token: normalized };
}

/** Doğrular ve tokenı TEK KULLANIMLIK olarak tüketir (senkron => yarış yok). */
export function consumeScreenQrToken(entry, token, now = Date.now()) {
  const result = checkScreenQrToken(entry, token, now);
  if (!result.ok) {
    return result;
  }
  if (!entry.usedTokens) {
    entry.usedTokens = new Set();
  }
  entry.usedTokens.add(result.token);
  return result;
}

/** Tüketilmiş tokenı geri verir (kapı komutu gönderilemediğinde). */
export function releaseScreenQrToken(entry, token) {
  const normalized = normalizeScreenQrToken(token);
  if (entry?.usedTokens && normalized) {
    entry.usedTokens.delete(normalized);
  }
}
