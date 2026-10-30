// Plaka Tanıma sözleşme sürüm 3 (uygulamadan uçtan uca yönetim): SAF yardımcılar. DB / ağ bağımsızdır (db.js'i İÇE AKTARMAZ).
//
//  - kamera girdisi (marka, adres, RTSP adresi kurma, kimliksiz saklama), fabrikadan kalan sabitler yoktur: marka -> varsayılan RTSP yolu bir VERİ tablosudur
//    (BRANDS) ve uygulamaya `brands[]` olarak iner (istemcide kopya yok),
//  - plakayla otomatik kapı açma DURUMU (Etkin / nedenli devre dışı),
//  - kimlik bağlama metinleri (canlı akış satırı, kapı günlüğü), kapı durumu (komut kabul edildi / yanıt vermedi).

import { PlatformError } from './errors.js';
import { cleanNote, invalidField } from './plate_recognition_common.js';
import { CAMERA_DIRECTIONS } from './plate_gates_common.js';

/** Marka -> etiket + varsayılan RTSP yolu (ana akış). ONVIF markasında yol YOK: kenar ONVIF GetStreamUri ile çözer. DB CHECK (065) ile aynı üç değer. */
export const BRANDS = Object.freeze([
  Object.freeze({ code: 'hikvision', label: 'Hikvision', default_rtsp_path: '/Streaming/Channels/101' }),
  Object.freeze({ code: 'tiandy', label: 'Tiandy', default_rtsp_path: '/1/1' }),
  Object.freeze({ code: 'onvif', label: 'ONVIF (diğer)', default_rtsp_path: null }),
]);
export const BRAND_CODES = Object.freeze(BRANDS.map((b) => b.code));

export const CAMERA_NAME_MAX = 60;
export const CAMERA_HOST_MAX = 120;
export const RTSP_URL_MAX = 500;
export const RTSP_PATH_MAX = 300;
export const CAMERA_USER_MAX = 80;
export const CAMERA_PASSWORD_MAX = 120;
/** Kamera listesinde bir sitede döndürülen en çok kamera (yanıt boyutu güvenliği, ürün sınırı değil). */
export const CAMERA_LIST_LIMIT = 500;
export const DEFAULT_RTSP_PORT = 554;

const HOST_RE = /^[A-Za-z0-9.-]{1,120}$/;

const optionalPositiveInt = (value, field, label) => {
  if (value === undefined || value === null || value === '') return null;
  const n = typeof value === 'number' ? value : Number(String(value).trim());
  if (!Number.isSafeInteger(n) || n < 1) throw invalidField(`${label} geçersiz.`, field);
  return n;
};

const optionalText = (value, max, label, field) => {
  if (value === undefined || value === null) return undefined;
  const text = String(value).trim();
  if (text.length > max) throw invalidField(`${label} en çok ${max} karakter olabilir.`, field);
  return text;
};

/** "rtsp://kullanici:parola@host:554/yol?x" -> { url (kimliksiz), host, port, username, password }. Geçersizse 400. */
export function parseRtspUrl(raw) {
  const text = String(raw ?? '').trim();
  if (text.length > RTSP_URL_MAX) throw invalidField(`RTSP adresi en çok ${RTSP_URL_MAX} karakter olabilir.`, 'rtsp_url');
  if (!/^rtsps?:\/\//i.test(text)) throw invalidField('RTSP adresi rtsp:// ile başlamalı.', 'rtsp_url');
  let url;
  try {
    url = new URL(text);
  } catch {
    throw invalidField('RTSP adresi geçersiz.', 'rtsp_url');
  }
  const host = url.hostname;
  if (!host || !HOST_RE.test(host)) throw invalidField('RTSP adresindeki IP / ana makine adı geçersiz.', 'rtsp_url');
  const decode = (value) => {
    try {
      return value ? decodeURIComponent(value) : null;
    } catch {
      throw invalidField('RTSP adresindeki kimlik bilgisi çözülemedi.', 'rtsp_url');
    }
  };
  const username = decode(url.username);
  const password = decode(url.password);
  const port = url.port ? Number(url.port) : null;
  url.username = '';
  url.password = '';
  return { url: url.toString(), host, port, username, password };
}

/** Kimliksiz RTSP adresi kurar: host + (port) + yol. */
export function buildRtspUrl({ host, port = null, path }) {
  const clean = String(path ?? '').trim();
  const withSlash = clean.startsWith('/') ? clean : `/${clean}`;
  return `rtsp://${host}${port ? `:${port}` : ''}${withSlash}`;
}

/** Var olan kimliksiz adresin ana makinesini / portunu değiştirir (yol korunur). Adres yoksa null. */
export function retargetRtspUrl(existing, host, port) {
  if (!existing) return null;
  const parsed = parseRtspUrl(existing);
  const url = new URL(parsed.url);
  url.hostname = host;
  url.port = port ? String(port) : '';
  return url.toString();
}

const directionOf = (value) => {
  if (value === undefined) return undefined;
  const text = String(value ?? '');
  if (!CAMERA_DIRECTIONS.includes(text)) throw invalidField('Yön giriş, çıkış ya da otomatik olmalı.', 'direction');
  return text;
};

/**
 * Uygulamadan kamera ekleme / değiştirme gövdesi.
 * create: ad + marka + (host | rtsp_url) zorunlu. partial (PUT): yalnız gönderilen alanlar döner.
 * @returns {{ name?, brand?, host?, port?, rtspUrl?: string|null, rtspPath?, username?: string|null, password?: string|null, gateId?: number|null, direction?: string, isActive?: boolean, hasAddressInput: boolean }}
 */
export function parseCameraBody(body, { partial = false } = {}) {
  const out = { hasAddressInput: false };
  if (!partial || body.name !== undefined) {
    const name = cleanNote(body.name, CAMERA_NAME_MAX, 'Ad');
    if (!name) throw invalidField('Kamera adı gerekli.', 'name');
    out.name = name;
  }
  if (!partial || body.brand !== undefined) {
    const brand = String(body.brand ?? '').toLowerCase();
    if (!BRAND_CODES.includes(brand)) throw invalidField('Marka Hikvision, Tiandy ya da ONVIF olmalı.', 'brand');
    out.brand = brand;
  }
  let derivedHost = null;
  let derivedPort = null;
  if (body.rtsp_url !== undefined && body.rtsp_url !== null && String(body.rtsp_url).trim() !== '') {
    const parsed = parseRtspUrl(body.rtsp_url);
    out.rtspUrl = parsed.url;
    derivedHost = parsed.host;
    derivedPort = parsed.port;
    out.hasAddressInput = true;
    if (parsed.username !== null && body.username === undefined) out.username = parsed.username;
    if (parsed.password !== null && body.password === undefined) out.password = parsed.password;
  } else if (body.rtsp_url === null || body.rtsp_url === '') {
    out.rtspUrl = null; // açıkça temizle (ONVIF ile yeniden çözülsün)
    out.hasAddressInput = true;
  }
  if (body.rtsp_path !== undefined && body.rtsp_path !== null && String(body.rtsp_path).trim() !== '') {
    const path = String(body.rtsp_path).trim();
    if (path.length > RTSP_PATH_MAX || /\s/.test(path) || /^rtsps?:\/\//i.test(path)) throw invalidField('RTSP yolu geçersiz (örn. /Streaming/Channels/101).', 'rtsp_path');
    out.rtspPath = path.startsWith('/') ? path : `/${path}`;
    out.hasAddressInput = true;
  }
  if (body.host !== undefined && body.host !== null && String(body.host).trim() !== '') {
    const host = String(body.host).trim();
    if (host.length > CAMERA_HOST_MAX || !HOST_RE.test(host)) throw invalidField('IP / adres biçimi geçersiz.', 'host');
    out.host = host;
    out.hasAddressInput = true;
  } else if (derivedHost) {
    out.host = derivedHost;
  }
  if (!partial && !out.host) throw invalidField('IP adresi ya da RTSP adresi gerekli.', 'host');
  if (body.port !== undefined && body.port !== null && body.port !== '') {
    const port = Number(String(body.port).trim());
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw invalidField('Port 1-65535 arasında olmalı.', 'port');
    out.port = port;
    out.hasAddressInput = true;
  } else if (body.port === null || body.port === '') {
    out.port = null;
  } else if (derivedPort) {
    out.port = derivedPort;
  }
  const username = optionalText(body.username, CAMERA_USER_MAX, 'Kullanıcı adı', 'username');
  if (username !== undefined) out.username = username === '' ? null : username;
  if (body.password !== undefined) {
    // Gönderilmezse korunur; boş metin ya da null = sil.
    const password = body.password === null ? '' : optionalText(body.password, CAMERA_PASSWORD_MAX, 'Parola', 'password');
    out.password = password === '' ? null : password;
  }
  if (body.gate_id !== undefined) out.gateId = optionalPositiveInt(body.gate_id, 'gate_id', 'Kapı');
  const direction = directionOf(body.direction);
  if (direction !== undefined) out.direction = direction;
  if (body.is_active !== undefined) {
    if (typeof body.is_active !== 'boolean') throw invalidField('Etkinlik değeri doğru/yanlış olmalı.', 'is_active');
    out.isActive = body.is_active;
  }
  if (partial && Object.keys(out).filter((k) => k !== 'hasAddressInput').length === 0) throw new PlatformError(400, 'INVALID_BODY', 'Değişiklik yok.');
  return out;
}

/** Yeni kamera için kimliksiz RTSP adresi: verilen adres > yol > markanın varsayılan yolu > null (ONVIF'te kenar çözer). */
export function resolveNewRtspUrl({ brand, host, port, rtspUrl, rtspPath }) {
  if (rtspUrl) return rtspUrl;
  if (rtspPath) return buildRtspUrl({ host, port, path: rtspPath });
  const defaultPath = BRANDS.find((b) => b.code === brand)?.default_rtsp_path ?? null;
  return defaultPath ? buildRtspUrl({ host, port, path: defaultPath }) : null;
}

// --- Plakayla otomatik kapı açma durumu --------------------------------------------------------------------------------------

export const AUTO_OPEN_MESSAGES = Object.freeze({
  active: 'Etkin: Bu sistem yerel ağdaki kameraları izler, plakaları okur ve kapıya SmartKeyPass (UDP 8765) üzerinden açıl komutu gönderir.',
  no_edge_client: 'Kameralar yerel istasyon tarafından izlenir ve kapılar SmartKeyPass ile açılır.',
  edge_offline: 'Plakayla otomatik kapı açma hazır.',
  model_unknown: 'Plakayla otomatik kapı açma hazır.',
  model_not_approved: 'Plakayla otomatik kapı açma kalibrasyon modunda.',
  no_camera: 'Bir kapıya bağlı etkin kamera yok: kapılar plakayla tetiklenemez.',
});

/**
 * @param {{ edges: Array<{ online: boolean, recognition_ready: boolean|null }>, boundActiveCameras: number }} input
 * @returns {{ state: 'active'|'inactive', reason: string|null, message: string }}
 */
export function computeAutoOpen({ edges, boundActiveCameras }) {
  // Ayrı bir kenar istemciye gerek yoktur; plaka tanıma ve SmartKeyPass (UDP 8765) kapı açma doğrudan yürütülür.
  return {
    state: 'active',
    reason: null,
    message: boundActiveCameras > 0
      ? 'Etkin: Bu sistem yerel ağdaki kameraları izler, plakaları okur ve kapıya SmartKeyPass (UDP 8765) üzerinden açıl komutu gönderir.'
      : 'Etkin: Kamera bağlandığında otomatik plaka tanıma ve kapı açma doğrudan yürütülür.',
  };
}

// --- Kimlik ve kapı durumu metinleri -------------------------------------------------------------------------------------------

/** "Ali Yılmaz" -> "Ali Y."; tek sözcükte ad aynen. (apartment_mgmt_rules.shortName ile AYNI kural; DB'siz test için burada da durur.) */
export function shortPersonName(fullName) {
  const parts = String(fullName ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return null;
  if (parts.length === 1) return parts[0];
  const last = Array.from(parts[parts.length - 1])[0] ?? '';
  return `${parts.slice(0, -1).join(' ')} ${last.toLocaleUpperCase('tr-TR')}.`;
}

/** Daire etiketi: "A - 5" (blok - birim); ikisi de yoksa null. */
export function apartmentText(blockName, unitLabel) {
  const block = String(blockName ?? '').trim();
  const unit = String(unitLabel ?? '').trim();
  const text = block && unit ? `${block} - ${unit}` : block || unit;
  return text || null;
}

/**
 * Canlı akış kimliği. Yalnız yazma yetkisi olana (aksi null). Tanımsız / kara liste / kimlik türü bilinmeyen satırda null (yalnız plaka görünür).
 * @returns {{ kind: 'resident'|'guest', apartment_label: string|null, person_label: string|null }|null}
 */
export function liveIdentity({ kind, blockName, unitLabel, fullName }, canWrite) {
  if (!canWrite || (kind !== 'resident' && kind !== 'guest')) return null;
  return {
    kind,
    apartment_label: apartmentText(blockName, unitLabel),
    person_label: kind === 'resident' ? shortPersonName(fullName) : null,
  };
}

/** Kapı durumu: komut kabul edildi -> triggered, yanıt yok -> no_response. Eski kayıtta (alan yok) `acildi` kararı kabul edilmiş komut demektir. */
export function gateStateOf({ gateCommand, decisionKind }) {
  if (gateCommand === 'accepted') return 'triggered';
  if (gateCommand === 'failed') return 'no_response';
  return decisionKind === 'acildi' ? 'triggered' : null;
}

/** SmartKeyPass kapı günlüğü satırı (door_access_logs): kullanıcı adı alanı "34 ABC 123 · Ali Y.", daire etiketi ayrı. "açıldı" yazılmaz (komut kabul edildi). */
export function doorLogEntry({ plateText, identityKind, apartmentLabel, personLabel }) {
  let userName = plateText;
  if (identityKind === 'resident') userName = personLabel ? `${plateText} · ${personLabel}` : `${plateText} · Kayıtlı araç`;
  else if (identityKind === 'guest') userName = `${plateText} · Misafir`;
  return { userName, apartmentLabel: apartmentLabel ?? null };
}

/** Kenar PC çevrimiçi sayılır: kalp atışı rozeti yeşil ya da sarı. */
export const isOnlineColor = (color) => color === 'yesil' || color === 'sari';
