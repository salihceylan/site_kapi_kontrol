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
