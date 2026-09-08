import {
  normalizeEmail,
  normalizeOptionalBool,
  normalizePhone,
  validApprovalStatuses,
  validRoles,
} from './helpers.js';

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
  if (doorCount > 100) {
    return 'Bu islem icin kapi sayisi fazla buyuk.';
  }

  if (blockApartmentCounts !== undefined) {
    if (!Array.isArray(blockApartmentCounts) || blockApartmentCounts.length === 0) {
      return 'En az bir blok tanimlanmali.';
    }
    if (blockApartmentCounts.length > 100) {
      return 'Bu islem icin blok sayisi fazla buyuk.';
    }
    const totalApartments = blockApartmentCounts.reduce((sum, count) => sum + count, 0);
    if (totalApartments > 5000) {
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
  if (apartmentCount > 5000) {
    return 'Bu islem icin daire sayisi fazla buyuk.';
  }
  if (blockCount > 100) {
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
  if (!password || !/^\d{4}$/.test(password)) {
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
  if (gateName.length < 2) {
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

export function generateVerificationCode() {
  return String(Math.floor(1000 + Math.random() * 9000));
}

export function parseApprovalStatus(value) {
  return validApprovalStatuses.has(value) ? value : null;
}

export function parseRole(value) {
  return validRoles.has(value) ? value : null;
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
  return res.status(500).json({ error: genericErrorMessage });
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
  if (typeof error?.message === 'string' && error.message.trim().length > 0) {
    return res.status(400).json({ error: error.message });
  }
  return res.status(500).json({ error: genericErrorMessage });
}

export function handleDeviceMutationError(error, res, genericErrorMessage) {
  if (error?.code === '23505' && error?.constraint === 'devices_device_uid_key') {
    return res.status(409).json({ error: 'Bu cihazin unique id kayitli.' });
  }
  return res.status(500).json({ error: genericErrorMessage });
}
