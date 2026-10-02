import crypto from 'crypto';
import { isClientSafeError } from './site_rules.js';
import {
  generateNumericCode,
  normalizeEmail,
  normalizeOptionalBool,
  normalizePhone,
  validApprovalStatuses,
  validRoles,
} from './helpers.js';

// Site yapısı üst sınırları (admin uçları ve kullanıcı self-servis kurulumu aynı sabitleri kullanır).
export const SITE_LIMITS = Object.freeze({
  maxBlocks: 100,
  maxApartments: 5000,
  maxDoors: 100,
});

// PostgreSQL INTEGER (int4) üst sınırı: user_code gibi kolonlara taşma ile 500 döndürmemek için.
export const PG_INT4_MAX = 2147483647;

/**
 * Güvenli pozitif tamsayı kimliği ayrıştırıcı.
 * Number (isSafeInteger) veya yalnızca rakamlardan oluşan metin kabul eder; aksi halde null döner.
 * `max` ile kolon aralığı (örn. PG_INT4_MAX) sınırlanabilir.
 */
export function parsePositiveId(value, { max = Number.MAX_SAFE_INTEGER } = {}) {
  let num;
  if (typeof value === 'number') {
    num = value;
  } else if (typeof value === 'string') {
    const text = value.trim();
    if (!/^\d{1,16}$/.test(text)) {
      return null;
    }
    num = Number(text);
  } else {
    return null;
  }
  if (!Number.isSafeInteger(num) || num <= 0 || num > max) {
    return null;
  }
  return num;
}

/**
 * Pragmatik e-posta biçimi doğrulayıcı (RFC'nin tamamı değil; bariz hatalı girişleri eler).
 */
export function isValidEmail(raw) {
  const text = String(raw ?? '').trim();
  if (text.length < 5 || text.length > 254) {
    return false;
  }
  if (/\s/.test(text) || text.includes('..')) {
    return false;
  }
  const atIndex = text.indexOf('@');
  if (atIndex < 1 || atIndex !== text.lastIndexOf('@')) {
    return false;
  }
  const local = text.slice(0, atIndex);
  const domain = text.slice(atIndex + 1);
  if (local.length > 64 || local.startsWith('.') || local.endsWith('.')) {
    return false;
  }
  if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(domain)) {
    return false;
  }
  return !domain.split('.').some((label) => label.startsWith('-') || label.endsWith('-'));
}

export function validateCreateInput({
  fullName,
  email,
  password,
  role,
  phoneNumber,
  isActive,
}) {
  if (fullName.length < 3) {
    return 'full_name en az 3 karakter olmali.';
  }
  if (!email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (!validRoles.has(role)) {
    return 'Gecersiz rol.';
  }
  if (phoneNumber && !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  if (isActive === null) {
    return 'is_active alani true/false olmali.';
  }
  return null;
}

export function validateLoginName(loginName) {
  if (!loginName || loginName.length < 3) {
    return 'Kullanici adi en az 3 karakter olmali.';
  }
  if (!/^[a-z0-9._-]+$/i.test(loginName)) {
    return 'Kullanici adi yalnizca harf, rakam, nokta, alt tire ve tire icerebilir.';
  }
  return null;
}

export function validateUpdateInput({
  fullName,
  email,
  password,
  phoneNumber,
  isActive,
}) {
  if (fullName !== undefined && fullName !== null && fullName.length < 3) {
    return 'full_name en az 3 karakter olmali.';
  }
  if (email !== undefined && email !== null && !email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password !== undefined && password !== null && password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (
    phoneNumber !== undefined &&
    phoneNumber !== null &&
    !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)
  ) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  if (isActive === null) {
    return 'is_active alani true/false olmali.';
  }
  return null;
}

export function validateSiteInput({ name }) {
  if (name !== undefined && name !== null && name.length < 2) {
    return 'Site adi en az 2 karakter olmali.';
  }
  return null;
}

export function validateStructuredSiteInput({
  name,
  blockCount,
  apartmentCount,
  doorCount,
  blockApartmentCounts,
}) {
  if (!name || name.length < 2) {
    return 'Site adi en az 2 karakter olmali.';
  }
  if (!Number.isInteger(doorCount) || doorCount <= 0) {
    return 'Otomatik kapi sayisi pozitif tamsayi olmali.';
  }
  if (doorCount > SITE_LIMITS.maxDoors) {
    return 'Bu islem icin kapi sayisi fazla buyuk.';
  }

  if (blockApartmentCounts !== undefined) {
    if (!Array.isArray(blockApartmentCounts) || blockApartmentCounts.length === 0) {
      return 'En az bir blok tanimlanmali.';
    }
    if (blockApartmentCounts.length > SITE_LIMITS.maxBlocks) {
      return 'Bu islem icin blok sayisi fazla buyuk.';
    }
    const totalApartments = blockApartmentCounts.reduce((sum, count) => sum + count, 0);
    if (totalApartments > SITE_LIMITS.maxApartments) {
      return 'Bu islem icin daire sayisi fazla buyuk.';
    }
    if (blockApartmentCounts.some((count) => !Number.isInteger(count) || count < 0)) {
      return 'Her blok icin daire sayisi sifir veya pozitif tamsayi olmali.';
    }
    return null;
  }

  if (!Number.isInteger(blockCount) || blockCount <= 0) {
    return 'Blok sayisi pozitif tamsayi olmali.';
  }
  if (!Number.isInteger(apartmentCount) || apartmentCount < 0) {
    return 'Daire sayisi sifir veya pozitif tamsayi olmali.';
  }
  if (apartmentCount > SITE_LIMITS.maxApartments) {
    return 'Bu islem icin daire sayisi fazla buyuk.';
  }
  if (blockCount > SITE_LIMITS.maxBlocks) {
    return 'Bu islem icin blok sayisi fazla buyuk.';
  }
  return null;
}

export function parseSiteManagerCreationInput(raw) {
  if (raw === undefined || raw === null) {
    return null;
  }
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'Site yoneticisi bilgileri gecersiz.' };
  }

  const fullName = String(raw.full_name || '').trim();
  const email = normalizeEmail(raw.email);
  const password = String(raw.password || '').trim();
  const phoneNumber = normalizePhone(raw.phone_number);
  const isActive = normalizeOptionalBool(raw.is_active) ?? true;

  const validationError = validateCreateInput({
    fullName,
    email,
    password,
    role: 'site_manager',
    phoneNumber,
    isActive,
  });
  if (validationError) {
    return { error: validationError };
  }

  return {
    value: {
      fullName,
      email,
      password,
      phoneNumber,
      isActive,
    },
  };
}

export function validateApartmentResidentInput({
  fullName,
  loginName,
  password,
  email,
  phoneNumber,
  isActive,
}) {
  if (!fullName || fullName.length < 3) {
    return 'Ad Soyad en az 3 karakter olmali.';
  }
  const loginError = validateLoginName(loginName);
  if (loginError) {
    return loginError;
  }
  // Sifre: bos birakilabilir (mevcut sakin duzenlemede "degistirme" sayilir); verilmisse 4 haneli sayisal olmali.
  // Yeni sakin olusturulurken sifre zorunlulugu apartment_service.provisionApartmentResident'ta uygulanir.
  if (password && !/^\d{4}$/.test(password)) {
    return 'Sifre 4 haneli sayisal olmali.';
  }
  if (email && !email.includes('@')) {
    return 'Gecerli e-posta girin.';
  }
  if (phoneNumber && !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  if (isActive === null) {
    return 'is_active alani true/false olmali.';
  }
  return null;
}

export function validateDoorAssignmentInput({ deviceUid }) {
  if (!deviceUid || deviceUid.length < 6) {
    return 'Cihaz unique id en az 6 karakter olmali.';
  }
  return null;
}

export function validateDeviceInput({
  deviceUid,
  assignedUserCode,
  siteCode,
}) {
  if (deviceUid.length < 6) {
    return 'Cihaz unique id en az 6 karakter olmali.';
  }
  if (Number.isNaN(assignedUserCode)) {
    return 'Kullanici ID sayisal olmali.';
  }
  if (Number.isNaN(siteCode)) {
    return 'Site ID sayisal olmali.';
  }
  return null;
}

export function validateDeviceAssignmentInput({
  siteCode,
  gateName,
}) {
  if (Number.isNaN(siteCode)) {
    return 'Site ID sayisal olmali.';
  }
  if (siteCode == null) {
    return 'Site ID zorunlu.';
  }
  // Kapi etiketi opsiyoneldir (istemci "Kapi Etiketi (opsiyonel)" der): bos kabul edilir, verilmisse en az 2 karakter.
  if (gateName && gateName.length < 2) {
    return 'Kapi adi en az 2 karakter olmali.';
  }
  return null;
}

export function validateSiteManagerRegistrationInput({
  fullName,
  email,
  password,
  phoneNumber,
}) {
  if (fullName.length < 3) {
    return 'Ad Soyad en az 3 karakter olmali.';
  }
  if (!email.includes('@')) {
    return 'Gecerli email girin.';
  }
  if (password.length < 6) {
    return 'Sifre en az 6 karakter olmali.';
  }
  if (!phoneNumber || !/^\+?[0-9()\-\s]{10,20}$/.test(phoneNumber)) {
    return 'Gecerli bir telefon numarasi girin.';
  }
  return null;
}

// E-posta doğrulama kodu: CSPRNG (crypto.randomInt) ile 6 haneli.
export function generateVerificationCode() {
  return generateNumericCode(6);
}

export function parseApprovalStatus(value) {
  return validApprovalStatuses.has(value) ? value : null;
}

export function parseRole(value) {
  return validRoles.has(value) ? value : null;
}

/**
 * Beklenmeyen (DB/sistem) hata yanıtı: ayrıntı istemciye SIZMAZ; genel mesaj + error_id döner,
 * ayrıntı (error_id ile) sunucu günlüğüne yazılır.
 */
function respondUnexpectedError(res, error, genericErrorMessage) {
  const errorId = crypto.randomBytes(4).toString('hex');
  // eslint-disable-next-line no-console
  console.error(`[mutation-error] error_id=${errorId}`, error?.code || error?.name || 'error', error?.message);
  return res.status(500).json({ error: genericErrorMessage, error_id: errorId });
}

export function handleUserMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'users_email_key') {
    return res.status(409).json({ error: 'Bu e-posta zaten kayitli.' });
  }
  if (error?.code === '23505' && error?.constraint === 'idx_users_login_name_unique') {
    return res.status(409).json({ error: 'Bu kullanici adi zaten kayitli.' });
  }
  if (error?.code === '23505') {
    return res
      .status(409)
      .json({ error: 'Kullanici kodu olusturulurken cakisma oldu, tekrar deneyin.' });
  }
  // Servisin bilerek firlattigi 4xx (statusCode'lu) is mantigi hatalari mesajiyla doner (500'e donusmez).
  const explicitStatus = Number(error?.statusCode);
  if (Number.isInteger(explicitStatus) && explicitStatus >= 400 && explicitStatus < 500 && isClientSafeError(error)) {
    return res.status(explicitStatus).json({ error: error.message });
  }
  return respondUnexpectedError(res, error, genericErrorMessage);
}

export function handleSiteMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'users_email_key') {
    return res.status(409).json({ error: 'Daire kullanicisi e-postasi uretilirken cakisma oldu.' });
  }
  if (error?.code === '23505' && error?.constraint === 'idx_users_login_name_unique') {
    return res.status(409).json({ error: 'Daire kullanicisi hesabi uretilirken kullanici adi cakismasi oldu.' });
  }
  if (error?.code === '23505') {
    return res.status(409).json({ error: 'Site kodu olusturulurken cakisma oldu.' });
  }
  if (error?.message === 'APARTMENT_LOGIN_GENERATION_FAILED') {
    return res.status(500).json({ error: 'Daire kullanicisi hesabi uretilemedi.' });
  }
  // Yalnızca iş mantığı hataları (kontrollü 4xx statusCode'lu veya kodsuz düz Error mesajları) istemciye
  // mesajıyla geçer; DB / sistem / TypeError gibi beklenmeyen hatalar genel mesaj + error_id ile döner.
  if (isClientSafeError(error)) {
    const explicit = Number(error.statusCode);
    const status = Number.isInteger(explicit) && explicit >= 400 && explicit < 500 ? explicit : 400;
    return res.status(status).json({ error: error.message });
  }
  return respondUnexpectedError(res, error, genericErrorMessage);
}

export function handleDeviceMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'devices_device_uid_key') {
    return res.status(409).json({ error: 'Bu cihazin unique id kayitli.' });
  }
  return respondUnexpectedError(res, error, genericErrorMessage);
}
