// Site Drive deposu (D1) ortak parçalar: yapılandırma, belirteç şifreleme, klasör ve dosya adı kuralları (karar T5). Saf: DB/ağ bağımsız.
// Sözleşme: docs/PLATFORM_DRIVE_DEPOLAMA.md "D1 uygulaması".

import crypto from 'node:crypto';
import { PlatformError } from './errors.js';

export const DRIVE_MODULE = 'drive_storage';
export const DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.file';
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
/**
 * Bağlantı kopukken site başına bekleme alanı sınırı. Alan dolunca YENİ yükleme reddedilir (503 DRIVE_QUEUE_FULL); bekleyen / kayıtlı hiçbir dosyaya dokunulmaz.
 * "Silmeyi biz yapmayız" (karar K6): bekleyen dosya SÜRE DOLDU DİYE SİLİNMEZ; Drive'a ulaşana kadar bekler.
 */
export const PENDING_MAX_BYTES = 100 * 1024 * 1024;
/** Bu süreyi aşan bekleyen dosya silinmez; yönetici durumunda "uzun süredir bekliyor" uyarısı çıkar (eski 7 gün SİLME kuralının yerine). */
export const PENDING_WARN_DAYS = 7;
/** Bekleme alanı doluluk uyarı eşikleri (yüzde): "dolmak üzere" ve "doldu". */
export const PENDING_NEAR_FULL_PERCENT = 80;
export const PENDING_FULL_PERCENT = 95;
export const OAUTH_STATE_MINUTES = 10;
/** Google Drive hesap kotası (about.get) uyarı eşiği (yüzde): bu oranda ve üstünde yöneticiye uyarı düşer; %100'de "doldu". */
export const QUOTA_WARN_PERCENT = 90;
export const QUOTA_FULL_PERCENT = 100;
/** Sağlık/kota denetimi sitenin Drive'ına en sık bu aralıkla gider (Google çağrısı az olsun). */
export const HEALTH_CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;

/** Yapılandırma .env'den: DRIVE_CLIENT_ID, DRIVE_CLIENT_SECRET, DRIVE_REDIRECT_URI, DRIVE_TOKEN_KEY (en az 32 karakter). */
export function driveConfig(env = process.env) {
  const text = (name) => String(env[name] ?? '').trim();
  const config = {
    clientId: text('DRIVE_CLIENT_ID'),
    clientSecret: text('DRIVE_CLIENT_SECRET'),
    redirectUri: text('DRIVE_REDIRECT_URI'),
    tokenKey: text('DRIVE_TOKEN_KEY'),
  };
  config.configured = Boolean(config.clientId && config.clientSecret && config.redirectUri && config.tokenKey.length >= 32);
  return config;
}

export function driveNotConfigured() {
  return new PlatformError(503, 'DRIVE_NOT_CONFIGURED', 'Google Drive bağlantısı Yakında…');
}

export function moduleDisabled() {
  return new PlatformError(403, 'MODULE_DISABLED', 'Dosya Deposu modülü bu sitede kapalı.', { module: DRIVE_MODULE });
}

// --- Yenileme belirteci şifreleme (AES-256-GCM; anahtar DRIVE_TOKEN_KEY'den sha256) ---

function keyOf(secret) {
  if (typeof secret !== 'string' || secret.length < 32) {
    throw new Error('DRIVE_TOKEN_KEY en az 32 karakter olmali');
  }
  return crypto.createHash('sha256').update(secret, 'utf8').digest();
}

export function encryptToken(plain, secret) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', keyOf(secret), iv);
  const body = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  return `v1:${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${body.toString('base64')}`;
}

export function decryptToken(stored, secret) {
  const parts = String(stored ?? '').split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') {
    throw new Error('sifreli belirtec biçimi geçersiz');
  }
  const decipher = crypto.createDecipheriv('aes-256-gcm', keyOf(secret), Buffer.from(parts[1], 'base64'));
  decipher.setAuthTag(Buffer.from(parts[2], 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(parts[3], 'base64')), decipher.final()]).toString('utf8');
}

export function hashState(state) {
  return crypto.createHash('sha256').update(String(state), 'utf8').digest('hex');
}

export function newOauthState() {
  const state = crypto.randomBytes(24).toString('base64url');
  return { state, hash: hashState(state) };
}

// --- Klasör ve dosya adı kuralları (karar T1-T5) ---

/** Dosya türü -> klasör ön eki (SrvEkim_26, suEkim_26, elektrikEkim_26, TeklifEkim_26, DekontEkim_26, GiderEkim_26, BelgeEkim_26). */
export const DRIVE_KINDS = Object.freeze({
  sozlesme: 'Srv',
  su: 'su',
  isi: 'isi',
  elektrik: 'elektrik',
  teklif: 'Teklif',
  dekont: 'Dekont',
  gider: 'Gider',
  belge: 'Belge',
});

const MONTHS_TR = Object.freeze(['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık']);

/** İzin verilen içerik türü -> uzantı. */
export const DRIVE_MIME_EXTENSIONS = Object.freeze({
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'text/plain': 'txt',
});

/** "2026-10-20" -> { year, month (1-12), day }; geçersizse null. */
export function parseIsoDate(text) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text ?? ''));
  if (!match) return null;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 || probe.getUTCDate() !== day || year < 2000 || year > 2100) {
    return null;
  }
  return { year, month, day };
}

/** SrvEkim_26 gibi aylık klasör adı. */
export function folderNameFor(kind, date) {
  const prefix = DRIVE_KINDS[kind];
  if (!prefix || !date) throw new Error('gecersiz klasor girdisi');
  return `${prefix}${MONTHS_TR[date.month - 1]}_${String(date.year % 100).padStart(2, '0')}`;
}

/** Blok/daire etiketi: yalnız harf-rakam (Türkçe harfler ASCII'ye), büyük harf, en çok 8 karakter; boş ise ''. */
export function cleanLabel(raw) {
  const map = { ç: 'c', ğ: 'g', ı: 'i', ö: 'o', ş: 's', ü: 'u' };
  return String(raw ?? '')
    .trim()
    .toLocaleLowerCase('tr')
    .replace(/[çğıöşü]/g, (ch) => map[ch])
    .replace(/[^a-z0-9]/g, '')
    .toUpperCase()
    .slice(0, 8);
}

/**
 * Kaynak kayıt türü -> dosya adı ön eki (P1-11). Dosya `<ÖN EK>-<kayıt no>_<ad>` adıyla kaydedilir (örn. `IS-123_AB_D13_201026.pdf`) ve
 * `drive_files.source_type / source_id` aynı kayda bağlanır: belge hem adından hem kayıttan açılır. Kayıt no, kaydın kendi numarasıdır (doldurma yok).
 * Tür kimlikleri küçük harf + alt çizgidir (DB CHECK ile aynı kural); yeni tür eklemek için buraya satır eklemek yeter.
 */
export const DRIVE_SOURCE_TYPES = Object.freeze({
  work_item: 'IS', // iş takibi kaydı
  meter_reading: 'OKM', // sayaç okuması
  expense: 'GDR', // gider
  payment_notice: 'DKN', // dekont bildirimi
  contract: 'SZL', // sözleşme
  quote: 'TKL', // teklif
  document: 'BLG', // belge
  equipment: 'EKP', // ekipman
});

const SOURCE_ID_PATTERN = /^[1-9]\d{0,14}$/;

/**
 * { type, id } -> doğrulanmış { type, id: Number }. Kaynak verilmediyse (undefined / null) null döner.
 * Bilinmeyen tür ya da pozitif tam sayı olmayan numara 400 INVALID_SOURCE (kaynak bağı yalnız sunucu içi çağıranlardan ve sorgu süzgecinden gelir).
 */
export function parseDriveSource(raw) {
  if (raw === undefined || raw === null) return null;
  const type = String(raw.type ?? '');
  const idText = typeof raw.id === 'number' ? String(raw.id) : String(raw.id ?? '');
  if (!Object.hasOwn(DRIVE_SOURCE_TYPES, type) || !SOURCE_ID_PATTERN.test(idText)) {
    throw new PlatformError(400, 'INVALID_SOURCE', 'Kaynak kayıt geçersiz.');
  }
  return { type, id: Number(idText) };
}

/** "IS-123_" gibi dosya adı öneki; kaynak yoksa ''. */
export function sourcePrefix(source) {
  const parsed = parseDriveSource(source);
  return parsed ? `${DRIVE_SOURCE_TYPES[parsed.type]}-${parsed.id}_` : '';
}

/**
 * Dosya adının uzantısız gövdesi. Daire varsa AB_D13_201026 (A blok, daire 13, 20.10.2026: blok harfi + "B", "D" + daire no, gün-ay-yıl 2 hane);
 * daire yoksa tür ön ekiyle <Ön ek>_<ggaayy>. `source` ({ type, id }) verilirse başına kayıt kimliği gelir: IS-123_AB_D13_201026.
 * `serial` > 1 ise çakışmayı ayırmak için _2, _3 eklenir.
 */
export function fileBaseName({ kind, block, apartment, date, serial = 1, source = null }) {
  const stamp = `${String(date.day).padStart(2, '0')}${String(date.month).padStart(2, '0')}${String(date.year % 100).padStart(2, '0')}`;
  const blockLabel = cleanLabel(block);
  const aptLabel = cleanLabel(apartment);
  const head = aptLabel ? `${blockLabel ? `${blockLabel}B_` : ''}D${aptLabel}` : DRIVE_KINDS[kind];
  return `${sourcePrefix(source)}${head}_${stamp}${serial > 1 ? `_${serial}` : ''}`;
}

/**
 * Drive'ın yükleme yanıtı "teyit" sayılır mı? Dosya kimliği zorunlu; Drive boyut bildiriyorsa gönderilen boyutla aynı olmalı.
 * Sunucudaki geçici dosya YALNIZ teyitten SONRA silinir (K6): teyitsiz yanıtta dosya beklemede kalır ve yeniden denenir.
 */
export function driveConfirmed(sent, byteLength) {
  if (!sent || typeof sent.id !== 'string' || sent.id === '') return false;
  return !Number.isFinite(sent.size) || sent.size === byteLength;
}

/**
 * Drive'a ulaşan kopyanın doğrulaması (P2-2). Önce teyit (dosya kimliği + boyut), sonra Drive'ın bildirdiği SHA-256 bizim hesapladığımızla karşılaştırılır.
 * state: 'unconfirmed' (teyit yok) | 'mismatch' (SHA-256 uyuşmadı: Drive'daki kopya bozuk) | 'sha256' (tam doğrulandı) | 'size' (Drive sağlama toplamı bildirmedi; yalnız kimlik + boyut).
 * Yalnız 'sha256' ve 'size' başarıdır; sunucudaki geçici dosya bunlardan SONRA silinir (K6).
 */
export function verifyDriveCopy(sent, expectedSha256, byteLength) {
  if (!driveConfirmed(sent, byteLength)) return { state: 'unconfirmed' };
  const reported = typeof sent.sha256 === 'string' ? sent.sha256.trim().toLowerCase() : '';
  if (!reported) return { state: 'size' };
  return { state: reported === String(expectedSha256 ?? '').trim().toLowerCase() ? 'sha256' : 'mismatch' };
}

const DRIVE_ERROR_TEXT = Object.freeze({
  auth: 'Google Drive erişimi geçersiz; Drive yeniden bağlanmalı.',
  quota: 'Google Drive depolama alanı dolu; Google hesabında yer açılınca gönderilir.',
  rate_limit: 'Google istek sınırına takıldı; biraz sonra yeniden denenecek.',
  not_found: 'Drive klasörü bulunamadı; yeniden oluşturulup denenecek.',
  integrity: "Drive'a ulaşan kopyanın SHA-256 değeri uyuşmadı; dosya sunucuda bekliyor, yeniden denenecek.",
  unconfirmed: 'Drive yüklemeyi doğrulamadı; dosya sunucuda bekliyor, yeniden denenecek.',
  transient: "Google Drive'a ulaşılamadı; yeniden denenecek.",
});

/** Bekleme satırında yöneticiye gösterilecek Türkçe neden (DriveError.kind -> metin). Bilinmeyen tür "ulaşılamadı" sayılır. */
export function driveErrorText(kind) {
  return DRIVE_ERROR_TEXT[kind] ?? DRIVE_ERROR_TEXT.transient;
}

function formatBytes(bytes) {
  const n = Number(bytes);
  if (!Number.isFinite(n) || n < 0) return '-';
  const gb = n / 1024 ** 3;
  if (gb >= 1) return `${gb.toFixed(1).replace('.', ',')} GB`;
  return `${Math.max(1, Math.round(n / 1024 ** 2))} MB`;
}

/**
 * Hesap kotasının (about.get storageQuota) değerlendirmesi. checkedAt yoksa 'unknown'; limit yoksa (sınırsız hesap) 'ok' + unlimited.
 * state: 'unknown' | 'ok' | 'near_full' (>= %90) | 'full' (>= %100). BIGINT sütunlar metin gelebilir: Number'a çevrilir.
 */
export function quotaInfo({ limitBytes = null, usedBytes = null, checkedAt = null } = {}) {
  const used = usedBytes === null || usedBytes === undefined ? null : Number(usedBytes);
  if (!checkedAt || used === null || !Number.isFinite(used)) {
    return { state: 'unknown', limit_bytes: null, used_bytes: null, percent: null, unlimited: false, checked_at: null, label: 'Kota henüz denetlenmedi.' };
  }
  const limit = limitBytes === null || limitBytes === undefined ? null : Number(limitBytes);
  if (!limit || !Number.isFinite(limit) || limit <= 0) {
    return { state: 'ok', limit_bytes: null, used_bytes: used, percent: null, unlimited: true, checked_at: checkedAt, label: `Kullanılan: ${formatBytes(used)} (sınırsız kota).` };
  }
  const percent = Math.floor((used * 100) / limit);
  const state = percent >= QUOTA_FULL_PERCENT ? 'full' : percent >= QUOTA_WARN_PERCENT ? 'near_full' : 'ok';
  return { state, limit_bytes: limit, used_bytes: used, percent, unlimited: false, checked_at: checkedAt, label: `Google Drive kotası: %${percent} dolu (${formatBytes(used)} / ${formatBytes(limit)}).` };
}

/**
 * Kota uyarıları (K6: hiçbiri dosya silmez). `quota`: quotaInfo çıktısı. `quotaBlockedCount`: son denemesi "Google depolama alanı dolu" ile dönen bekleyen dosya sayısı.
 * "Google kotası dolu" ile "sunucu bekleme alanı dolu" (queueWarnings, DRIVE_QUEUE_*) AYRI kodlardır: yönerge farklıdır (Google hesabında yer aç ↔ bağlantıyı düzelt / bekleyenleri gönder).
 */
export function quotaWarnings(quota, { quotaBlockedCount = 0 } = {}) {
  const out = [];
  const percent = quota?.percent;
  if (quota?.state === 'full' || quotaBlockedCount > 0) {
    out.push({
      code: 'DRIVE_QUOTA_FULL',
      message: `Google Drive depolama alanı doldu${Number.isFinite(percent) ? ` (%${Math.min(percent, 100)})` : ''}. Yeni dosyalar Drive'a gönderilemez, sunucuda bekler; hiçbir dosya silinmez. Google hesabında yer açın ya da depolamayı artırın.`,
    });
  } else if (quota?.state === 'near_full') {
    out.push({
      code: 'DRIVE_QUOTA_NEAR_FULL',
      message: `Google Drive depolama alanı %${percent} dolu (${formatBytes(quota.used_bytes)} / ${formatBytes(quota.limit_bytes)}). Dolarsa yeni dosyalar Drive'a gönderilemez, sunucuda bekler; hiçbir dosya silinmez. Yer açın ya da depolamayı artırın.`,
    });
  }
  return out;
}

/** Drive'a ulaşan kopyası doğrulanamayan (SHA-256 uyuşmayan) bekleyen dosyalar için uyarı. Dosya silinmez; sunucudaki asıl kopya yeniden gönderilir. */
export function integrityWarnings(count) {
  const n = Number(count) || 0;
  if (n <= 0) return [];
  return [
    {
      code: 'DRIVE_INTEGRITY_FAILED',
      message: `${n} dosyanın Drive'a ulaşan kopyası doğrulanamadı (SHA-256 uyuşmadı). Dosya silinmedi; sunucudaki asıl kopya yeniden gönderilecek.`,
    },
  ];
}

/**
 * Yönetici ekranı için Drive sağlık özeti (P2-17): bağlantı durumu, erişim belirteci, son başarılı aktarım, bekleyen kuyruk, kota.
 * Saf: DB/ağ bağımsız. `conn` site_drive_connections satırı (ya da null); `queue` { pendingCount, overdueCount, oldestPendingAt, integrityFailedCount, quotaBlockedCount, maxAttempts, lastError }.
 * state: 'not_configured' | 'disconnected' | 'error' | 'warning' | 'ok'.
 */
export function buildDriveHealth({ configured = true, conn = null, now = new Date(), lastTransferAt = null, queue = {}, quota = quotaInfo() } = {}) {
  const status = conn?.status ?? 'disconnected';
  const expiresAt = conn?.token_expires_at ?? null;
  let tokenState = 'none';
  let tokenLabel = 'Drive bağlı değil.';
  if (status === 'connected') {
    const live = expiresAt && new Date(expiresAt).getTime() > now.getTime();
    tokenState = live ? 'valid' : 'refreshable';
    tokenLabel = live ? 'Erişim belirteci geçerli.' : 'Erişim belirteci gerektiğinde otomatik yenilenir.';
  } else if (status === 'error') {
    tokenState = 'invalid';
    tokenLabel = 'Google erişimi geçersiz; Drive yeniden bağlanmalı.';
  }
  const q = {
    pending_count: Number(queue.pendingCount) || 0,
    overdue_count: Number(queue.overdueCount) || 0,
    oldest_pending_at: queue.oldestPendingAt ?? null,
    integrity_failed_count: Number(queue.integrityFailedCount) || 0,
    quota_blocked_count: Number(queue.quotaBlockedCount) || 0,
    max_attempts: Number(queue.maxAttempts) || 0,
    last_error: queue.lastError ?? null,
  };
  let state;
  let message;
  if (!configured) {
    state = 'not_configured';
    message = 'Google Drive bağlantısı henüz yapılandırılmadı.';
  } else if (status === 'disconnected') {
    state = 'disconnected';
    message = 'Drive bağlı değil.';
  } else if (status === 'error') {
    state = 'error';
    message = 'Drive bağlantısı koptu; yeniden bağlayın. Bekleyen dosyalar silinmez.';
  } else if (quota.state === 'full' || quota.state === 'near_full' || q.quota_blocked_count > 0 || q.integrity_failed_count > 0 || q.overdue_count > 0) {
    state = 'warning';
    message = 'Drive bağlı; ilgilenmeniz gereken uyarılar var.';
  } else {
    state = 'ok';
    message = q.pending_count > 0 ? `Drive bağlı; ${q.pending_count} dosya gönderilmeyi bekliyor.` : 'Drive bağlantısı sağlıklı.';
  }
  return {
    state,
    message,
    connection: { status, account_email: conn?.account_email ?? null, connected_at: conn?.connected_at ?? null, last_error: conn?.last_error ?? null },
    token: { state: tokenState, label: tokenLabel, expires_at: status === 'connected' ? expiresAt : null, checked_at: conn?.health_checked_at ?? null },
    last_transfer_at: lastTransferAt,
    queue: q,
    quota,
  };
}

/**
 * Bekleme alanı durumundan yöneticiye gösterilecek uyarılar: [{ code, message }]. Hiçbir uyarı dosya silmez; hepsi "bekliyor" bilgisidir.
 * `overdueCount`: PENDING_WARN_DAYS'i aşmış bekleyen dosya sayısı.
 */
export function queueWarnings({ pendingCount = 0, pendingBytes = 0, overdueCount = 0 } = {}) {
  const out = [];
  const percent = Math.floor((Number(pendingBytes) * 100) / PENDING_MAX_BYTES);
  if (percent >= PENDING_FULL_PERCENT) {
    out.push({
      code: 'DRIVE_QUEUE_FULL',
      message: `Bekleme alanı doldu (%${Math.min(percent, 100)}). Drive'a gönderilemeyen dosyalar silinmez; alan boşalana kadar yeni dosya kabul edilmez. Drive bağlantısını yenileyip bekleyenleri gönderin.`,
    });
  } else if (percent >= PENDING_NEAR_FULL_PERCENT) {
    out.push({
      code: 'DRIVE_QUEUE_NEARLY_FULL',
      message: `Bekleme alanı %${percent} doldu. Dolarsa yeni dosya kabul edilmez; mevcut dosyalar silinmez.`,
    });
  }
  if (overdueCount > 0) {
    out.push({
      code: 'DRIVE_FILES_OVERDUE',
      message: `${overdueCount} dosya ${PENDING_WARN_DAYS} günden uzun süredir Drive'a gönderilemedi. Dosyalar silinmedi; Drive bağlantısı düzelince gönderilir.`,
    });
  } else if (pendingCount > 0) {
    out.push({
      code: 'DRIVE_FILES_WAITING',
      message: `${pendingCount} dosya Drive'a gönderilmeyi bekliyor. Silinmez; bağlantı sağlanınca gönderilir.`,
    });
  }
  return out;
}

/** Sunucu tarafında ilk baytlardan tür tahmini (istemcinin bildirdiği türe güvenilmez). */
export function sniffMime(b) {
  if (b.length >= 5 && b.subarray(0, 5).toString('latin1') === '%PDF-') return 'application/pdf';
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (b.length >= 12 && b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
  if (b.length >= 4 && b.subarray(0, 4).equals(Buffer.from([0xd0, 0xcf, 0x11, 0xe0]))) return 'application/ole';
  if (b.length >= 4 && b.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]))) return 'application/zip';
  return null;
}

/** İstemci türü ile içerik başlığı uyuşuyor mu? (docx/xlsx = zip, doc/xls = ole, txt = başlıksız ve NUL baytsız). */
export function mimeMatchesContent(mime, buffer) {
  const sniffed = sniffMime(buffer);
  if (mime === 'text/plain') return sniffed === null && !buffer.includes(0);
  if (mime === 'application/msword' || mime === 'application/vnd.ms-excel') return sniffed === 'application/ole';
  if (mime.endsWith('wordprocessingml.document') || mime.endsWith('spreadsheetml.sheet')) return sniffed === 'application/zip';
  return sniffed === mime;
}
