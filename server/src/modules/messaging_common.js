// Site basina SMS + WhatsApp baglantisi (117) ortak parcalar: anahtar, sifreleme, dogrulama, surucu kayitlari. Saf: DB bagimsiz.
// Sir (usercode/password/access_token) YALNIZ sifreli saklanir, yanita ve gunluge ASLA yazilmaz; telefon numarasi hic islenmez.
// Yeni SMS saglayicisi eklemek: docs/MESAJ_SURUCU_REHBERI.md.

import { decryptToken, encryptToken } from './drive_common.js';
import { PlatformError } from './errors.js';
import { createNetgsmAdapter } from './sms_provider.js';

export const CHANNEL_SMS = 'sms';
export const CHANNEL_WHATSAPP = 'whatsapp';
const FETCH_TIMEOUT_MS = 10_000;

/** .env MESSAGING_SECRET_KEY (en az 32 karakter). Yoksa 503: sir kaydedilmez, kayitli sir cozulmez. */
export function messagingKey(env = process.env) {
  const key = String(env?.MESSAGING_SECRET_KEY ?? '').trim();
  if (key.length < 32) {
    throw new PlatformError(503, 'MESSAGING_NOT_CONFIGURED', 'Mesaj bağlantısı bu sunucuda henüz yapılandırılmamış (şifreleme anahtarı yok).');
  }
  return key;
}

export const sealSecrets = (object, env) => encryptToken(JSON.stringify(object), messagingKey(env));
export const openSecrets = (stored, env) => JSON.parse(decryptToken(stored, messagingKey(env)));

/** Sir olmayan, yanita girebilecek maskeli gorunum: ilk iki karakter + yildiz. */
export const maskText = (value) => `${String(value ?? '').slice(0, 2)}***`;

const NETGSM_BALANCE_ERRORS = Object.freeze({
  '30': 'Kullanıcı kodu veya şifre hatalı (ya da API erişimi kapalı).',
  '40': 'Mesaj başlığı tanımsız.',
  '70': 'Hatalı sorgu.',
  '100': 'NetGSM sistem hatası.',
});

/**
 * NetGSM bakiye / kimlik SORGUSU. GERCEK SMS GONDERMEZ (ucret riski yok). Yanit "00 <bakiye>" ise kimlik dogru.
 * Donus: { ok, code, message, balance? } — balance yalniz sayi ise.
 */
export async function checkNetgsm({ usercode, password }, fetchImpl = fetch) {
  const params = new URLSearchParams({ usercode, password, tip: '2' });
  const response = await fetchImpl(`https://api.netgsm.com.tr/balance/list/get?${params.toString()}`, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  const parts = (await response.text()).trim().split(/\s+/);
  const code = parts[0] || 'EMPTY';
  if (response.ok && code === '00') {
    const balance = Number(String(parts[1] ?? '').replace(',', '.'));
    return { ok: true, code, message: 'Kimlik doğrulandı.', ...(Number.isFinite(balance) ? { balance } : {}) };
  }
  return { ok: false, code, message: NETGSM_BALANCE_ERRORS[code] ?? 'Sağlayıcı kimliği doğrulayamadı.' };
}

const text = (value) => String(value ?? '').trim();
const invalid = (message) => new PlatformError(400, 'INVALID_MESSAGING_FIELD', message);

/** SMS surucu kaydi: yeni saglayici = buraya bir girdi (alan listesi, dogrulama, baglayici, sinama). */
export const SMS_DRIVERS = Object.freeze({
  netgsm: {
    id: 'netgsm',
    label: 'NetGSM',
    secretFields: ['usercode', 'password'],
    configFields: ['header'],
    validate(input) {
      const header = text(input.header);
      if (!/^[\p{L}\p{N} .-]{1,20}$/u.test(header)) throw invalid('Mesaj başlığı 1-20 karakter olmalı (harf, rakam, boşluk, nokta, tire).');
      const usercode = text(input.usercode);
      const password = text(input.password);
      if (!usercode || !password) throw invalid('Kullanıcı kodu ve şifre zorunlu.');
      if (usercode.length > 64 || password.length > 128) throw invalid('Kullanıcı kodu veya şifre çok uzun.');
      return { config: { header }, secrets: { usercode, password } };
    },
    createAdapter: ({ config, secrets }, fetchImpl) => createNetgsmAdapter({ usercode: secrets.usercode, password: secrets.password, header: config.header, fetchImpl }),
    check: ({ secrets }, fetchImpl) => checkNetgsm(secrets, fetchImpl),
  },
});

/**
 * WhatsApp surucu ISKELETI (Meta WhatsApp Cloud API). Bu surumde yalniz alan dogrulamasi: gercek baglanti / gonderim YOK ve sahte sonuc uretilmez.
 * Meta hesabi baglaninca `active: true` + gercek sinama eklenir (docs/MESAJ_SURUCU_REHBERI.md).
 */
export const WHATSAPP_DRIVER = Object.freeze({
  id: 'meta_cloud',
  label: 'Meta WhatsApp Cloud API',
  active: false,
  note: 'WhatsApp sürücüsü bu sürümde doğrulama modunda; Meta hesabı bağlanınca etkinleşir.',
  validate(input) {
    const phoneNumberId = text(input.phone_number_id);
    const businessName = text(input.business_name);
    const accessToken = text(input.access_token);
    if (!/^\d{5,20}$/.test(phoneNumberId)) throw invalid('Telefon numarası kimliği (phone_number_id) 5-20 haneli sayı olmalı.');
    if (businessName.length < 1 || businessName.length > 100) throw invalid('İşletme adı 1-100 karakter olmalı.');
    return { config: { phone_number_id: phoneNumberId, business_name: businessName }, secrets: { access_token: accessToken } };
  },
  validateToken(token) {
    if (text(token).length < 20 || text(token).length > 1024 || /\s/.test(text(token))) throw invalid('Erişim belirteci (access_token) 20-1024 karakter olmalı, boşluk içermemeli.');
  },
});
