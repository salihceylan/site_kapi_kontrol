import crypto from 'crypto';

export const validRoles = new Set(['super_user', 'site_manager', 'apartment_owner']);
export const validApprovalStatuses = new Set(['pending', 'approved', 'rejected']);

export function auditLog(eventName, details) {
  // eslint-disable-next-line no-console
  console.log(JSON.stringify({
    at: new Date().toISOString(),
    event: eventName,
    ...details,
  }));
}

export function publicBaseUrl(req) {
  const configured = String(process.env.PUBLIC_BASE_URL || '').trim();
  if (configured) {
    return configured.replace(/\/+$/, '');
  }
  return `${req.protocol}://${req.get('host')}`;
}

export function safeFirmwareTarget(value) {
  const target = String(value || '').trim().toLowerCase();
  return /^[a-z0-9_-]{2,64}$/.test(target) ? target : null;
}

export function safeFirmwareFile(value) {
  const fileName = String(value || '').trim();
  return /^[a-zA-Z0-9_.-]+\.bin$/.test(fileName) ? fileName : null;
}

export function compareVersionParts(left, right) {
  const leftParts = String(left || '')
    .split(/[.-]/)
    .map((item) => Number.parseInt(item, 10));
  const rightParts = String(right || '')
    .split(/[.-]/)
    .map((item) => Number.parseInt(item, 10));
  const length = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < length; index += 1) {
    const leftValue = Number.isFinite(leftParts[index]) ? leftParts[index] : 0;
    const rightValue = Number.isFinite(rightParts[index]) ? rightParts[index] : 0;
    if (leftValue > rightValue) {
      return 1;
    }
    if (leftValue < rightValue) {
      return -1;
    }
  }
  return 0;
}

export function normalizeDeviceUid(raw) {
  return String(raw || '').trim().toUpperCase().replace(/[^0-9A-F]/g, '');
}

export function mqttUsernameForDevice(deviceUid) {
  return `device_${normalizeDeviceUid(deviceUid)}`;
}

export function generateMqttPassword() {
  return crypto.randomBytes(24).toString('base64url');
}

export function generateLocalControlToken() {
  return crypto.randomBytes(32).toString('base64url');
}

export function normalizePhone(raw) {
  const text = String(raw || '').trim();
  return text || null;
}

export function normalizeEmail(raw) {
  return String(raw || '').trim().toLowerCase();
}

export function normalizeOptionalEmail(raw) {
  if (raw === undefined) {
    return undefined;
  }
  const text = String(raw || '').trim().toLowerCase();
  return text || null;
}

export function normalizeOptionalText(raw) {
  if (raw === undefined) {
    return undefined;
  }
  const text = String(raw || '').trim();
  return text || null;
}

export function normalizeOptionalBool(raw) {
  if (raw === undefined) {
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
  return null;
}

export function normalizeOptionalInteger(raw) {
  if (raw === undefined) {
    return undefined;
  }
  if (raw === null) {
    return null;
  }

  const text = String(raw).trim();
  if (!text) {
    return null;
  }

  const value = Number(text);
  if (!Number.isInteger(value) || value <= 0) {
    return Number.NaN;
  }
  return value;
}

export function normalizeBlockApartmentCounts(raw) {
  if (raw === undefined) {
    return undefined;
  }
  if (!Array.isArray(raw)) {
    return null;
  }

  const counts = [];
  for (const item of raw) {
    const value = normalizeOptionalInteger(item);
    if (value === undefined || value === null || Number.isNaN(value)) {
      if (Number(item) === 0 || String(item).trim() === '0') {
        counts.push(0);
        continue;
      }
      return null;
    }
    counts.push(value);
  }
  return counts;
}

export function mapUserRow(row) {
  return {
    id: row.id,
    full_name: row.full_name,
    email: row.email,
    login_name: row.login_name,
    role: row.role,
    is_active: row.is_active,
    email_verified: row.email_verified,
    approval_status: row.approval_status,
    phone_number: row.phone_number,
    created_at: row.created_at,
  };
}

export function mapSiteRow(row) {
  return {
    id: Number(row.id),
    name: row.name,
    address: row.address,
    city: row.city,
    district: row.district,
    block_count: Number(row.block_count ?? 1),
    apartment_count: Number(row.apartment_count ?? 0),
    door_count: Number(row.door_count ?? 1),
    approval_status: validApprovalStatuses.has(row.approval_status)
      ? row.approval_status
      : 'approved',
    approved_at: row.approved_at ?? null,
    mqtt_site_id: Number(row.mqtt_site_id ?? 0),
    manager_user_code:
      row.manager_user_code === null || row.manager_user_code === undefined
        ? null
        : Number(row.manager_user_code),
    manager_name: row.manager_name ?? null,
    block_apartment_counts: Array.isArray(row.block_apartment_counts)
      ? row.block_apartment_counts.map(Number)
      : [],
    created_at: row.created_at,
  };
}

export function mapDeviceRow(row) {
  return {
    id: Number(row.id),
    device_uid: row.device_uid,
    assigned_user_code: row.assigned_user_code,
    gate_name: row.gate_name,
    assigned_door_id:
      row.assigned_door_id === null || row.assigned_door_id === undefined
        ? null
        : Number(row.assigned_door_id),
    site_code:
      row.site_code === null || row.site_code === undefined
        ? null
        : Number(row.site_code),
    site_name: row.site_name ?? null,
    assigned_door_name: row.assigned_door_name ?? null,
    site_approval_status: validApprovalStatuses.has(row.site_approval_status)
      ? row.site_approval_status
      : 'approved',
    mqtt_username: row.mqtt_username ?? null,
    mqtt_configured: Boolean(row.mqtt_username && row.mqtt_password),
    mqtt_connected: row.mqtt_connected === null || row.mqtt_connected === undefined
      ? null
      : Boolean(row.mqtt_connected),
    firmware_version: row.firmware_version ?? null,
    ota_status: row.ota_status ?? null,
    ota_last_version: row.ota_last_version ?? null,
    wifi_rssi:
      row.wifi_rssi === null || row.wifi_rssi === undefined
        ? null
        : Number(row.wifi_rssi),
    wifi_signal_percent:
      row.wifi_signal_percent === null || row.wifi_signal_percent === undefined
        ? null
        : Number(row.wifi_signal_percent),
    last_seen_at: row.last_seen_at ?? null,
    last_event: row.last_event ?? null,
    created_at: row.created_at,
  };
}

export function mapDeviceMqttCredentialsRow(row) {
  return {
    device_uid: row.device_uid,
    mqtt_host: String(process.env.MQTT_HOST || 'mqtt.gudeteknoloji.com.tr'),
    mqtt_port: Number(process.env.MQTT_PORT || 8883),
    mqtt_username: row.mqtt_username,
    mqtt_password: row.mqtt_password,
    local_control_token: row.local_control_token,
  };
}

export function mapLocalDoorControl({ token, status }) {
  return {
    token: token ?? null,
    ip: status.local_ip ?? null,
    port: status.local_control_port ?? 8765,
    available: status.local_control_available === true,
  };
}

export function mapBlockRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    block_name: row.block_name,
    sort_order: Number(row.sort_order),
    created_at: row.created_at,
  };
}

export function mapApartmentRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    block_id: Number(row.block_id),
    block_name: row.block_name,
    unit_label: row.unit_label,
    sort_order: Number(row.sort_order),
    is_active: row.is_active,
    resident_user_code:
      row.resident_user_code === null || row.resident_user_code === undefined
        ? null
        : Number(row.resident_user_code),
    resident_full_name: row.resident_full_name ?? null,
    resident_login_name: row.resident_login_name ?? null,
    resident_email: row.resident_email ?? null,
    resident_pin_code: row.resident_pin_code ?? null,
    resident_phone_number: row.resident_phone_number ?? null,
    resident_is_active:
      row.resident_is_active === null || row.resident_is_active === undefined
        ? null
        : Boolean(row.resident_is_active),
    created_at: row.created_at,
  };
}

export function mapDoorRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name ?? null,
    door_name: row.door_name,
    door_index: Number(row.door_index),
    is_active: row.is_active,
    assigned_device_id:
      row.assigned_device_id === null || row.assigned_device_id === undefined
        ? null
        : Number(row.assigned_device_id),
    assigned_device_uid: row.assigned_device_uid ?? null,
    mqtt_site_id:
      row.mqtt_site_id === null || row.mqtt_site_id === undefined
        ? null
        : Number(row.mqtt_site_id),
    created_at: row.created_at,
  };
}

export function mapDoorAccessLogRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name || null,
    door_id: row.door_id != null ? Number(row.door_id) : null,
    door_name: row.door_name || '',
    user_code: row.user_code != null ? Number(row.user_code) : null,
    user_name: row.user_name || '',
    user_role: row.user_role || null,
    apartment_label: row.apartment_label || null,
    trigger_type: row.trigger_type || 'cloud_app',
    opened_at: row.opened_at ? new Date(row.opened_at).toISOString() : null,
    ip_address: row.ip_address || null,
    created_at: row.created_at ? new Date(row.created_at).toISOString() : null,
  };
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

export function buildBlockApartmentCounts({
  blockCount,
  apartmentCount,
  blockApartmentCounts,
}) {
  if (blockApartmentCounts && blockApartmentCounts.length > 0) {
    return blockApartmentCounts;
  }
  const count = Math.max(1, blockCount || 1);
  const perBlock = Math.floor((apartmentCount || 0) / count);
  const remainder = (apartmentCount || 0) % count;
  const result = [];
  for (let i = 0; i < count; i++) {
    result.push(perBlock + (i < remainder ? 1 : 0));
  }
  return result;
}

