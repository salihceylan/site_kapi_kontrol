// Sayac Okuma ve Faturalandirma: ortak sabitler, hatalar, girdi dogrulayicilari. Saf: DB/ag bagimsiz.
// Sozlesme: docs/PLATFORM_SAYAC.md. Hata govdesi { error, code, ...ek } (PlatformError). Para tamsayi kurus; okuma degeri en cok 3 ondalik (NUMERIC(14,3)).

import { PlatformError } from './errors.js';
import { parseIsoDate } from './finance_common.js';
import { parseMinor } from './finance_money.js';

export const METERING_MODULE = 'metering';
export const KINDS = Object.freeze(['water', 'electricity', 'heat', 'hot_water']);
export const METHODS = Object.freeze(['unit_price', 'invoice', 'heat']);
export const SOURCES = Object.freeze(['manual', 'file']);
export const KIND_LABELS = Object.freeze({ water: 'Su', electricity: 'Elektrik', heat: 'Isı', hot_water: 'Sıcak su' });

export const SERIAL_MAX = 40;
export const METERS_PER_SITE = 5000;
export const IMPORT_MAX_ROWS = 5000;
export const IMPORT_CODE_MAX = 80;
export const MAX_BODY_BYTES = 900_000;
/** Okuma degeri ust siniri (NUMERIC(14,3): 11 tam basamak). */
export const VALUE_MAX_MILLI = 99_999_999_999_999n;
export const KEY_PATTERN = /^[A-Za-z0-9._:-]{8,64}$/;

export const invalid = (message, field = null) => new PlatformError(400, 'INVALID_BODY', message, field ? { field } : undefined);
export const moduleDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Sayaç Okuma modülü kapalı.', { module: METERING_MODULE });
export const financeDisabled = () => new PlatformError(403, 'MODULE_DISABLED', 'Borçlandırma için Aidat ve Finans modülü açık olmalıdır.', { module: 'finance' });
export const meterNotFound = () => new PlatformError(404, 'METER_NOT_FOUND', 'Sayaç bulunamadı.');
export const apartmentNotFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
export const readingNotFound = () => new PlatformError(404, 'READING_NOT_FOUND', 'Okuma bulunamadı.');
export const billingNotFound = () => new PlatformError(404, 'BILLING_NOT_FOUND', 'Faturalandırma bulunamadı.');
export const serialTaken = () => new PlatformError(409, 'SERIAL_TAKEN', 'Bu seri numaralı sayaç bu türde zaten kayıtlı.');
export const meterLimit = () => new PlatformError(409, 'LIMIT_REACHED', `Bir sitede en fazla ${METERS_PER_SITE} sayaç kaydedilebilir.`, { limit: METERS_PER_SITE });
export const meterInactive = () => new PlatformError(409, 'METER_INACTIVE', 'Sayaç pasif; pasif sayaca okuma girilemez.');
export const readingExists = () => new PlatformError(409, 'READING_EXISTS', 'Bu sayaç için bu tarihte farklı bir okuma zaten var.');
export const readingOrder = (message) => new PlatformError(409, 'READING_OUT_OF_ORDER', message);
export const readingLocked = () => new PlatformError(409, 'READING_LOCKED', 'Bu okuma bir faturalandırma dönemine dahil olduğu için silinemez.');
export const noConsumption = () => new PlatformError(409, 'NO_CONSUMPTION', 'Seçilen aralıkta dağıtılacak tüketim yok (tüm farklar sıfır).');
export const incompleteReadings = (missing) =>
  new PlatformError(409, 'READINGS_INCOMPLETE', 'Bazı dairelerin okuması ya da alanı eksik. Eksikleri tamamlayın ya da atlayarak devam edin.', { missing_count: missing });
export const nothingToPost = () => new PlatformError(409, 'NOTHING_TO_POST', 'Borçlandırılacak daire yok.');
export const billingOverlap = () =>
  new PlatformError(409, 'BILLING_OVERLAP', 'Bu tür için seçilen tarih aralığı daha önce faturalandırılmış bir aralıkla çakışıyor.');
export const previewStale = (current) =>
  new PlatformError(409, 'PREVIEW_STALE', 'Önizleme güncel değil; okumalar değişmiş. Önizlemeyi yenileyin.', current);
export const idempotencyConflict = () =>
  new PlatformError(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı farklı bir istekle daha önce kullanılmış.');
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

export const objectOf = (body) => (body && typeof body === 'object' && !Array.isArray(body) ? body : {});

export function parseKind(value, { required = true } = {}) {
  if ((value === undefined || value === null || value === '') && !required) return null;
  if (!KINDS.includes(value)) throw invalid('Sayaç türü geçersiz (su, elektrik, ısı, sıcak su).', 'kind');
  return value;
}

export function parseSerial(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < 1 || text.length > SERIAL_MAX || /[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/.test(text)) {
    throw invalid(`Seri numarası 1-${SERIAL_MAX} karakter olmalıdır.`, 'serial_no');
  }
  return text;
}

export const parseDate = (value, label, field) => {
  try {
    return parseIsoDate(value, label);
  } catch (error) {
    throw invalid(error.message, field);
  }
};

/** Okuma degeri: sayi ya da metin (virgul/nokta), en cok 3 ondalik, >= 0. -> { milli: bigint, text: '123.450' } ya da null. */
export function parseReadingValue(raw) {
  let text;
  if (typeof raw === 'number') {
    if (!Number.isFinite(raw)) return null;
    text = String(raw);
    if (/e/i.test(text)) return null;
  } else if (typeof raw === 'string') {
    text = raw.trim().replace(',', '.');
  } else {
    return null;
  }
  const match = /^(\d{1,11})(?:\.(\d{1,3}))?$/.exec(text);
  if (!match) return null;
  const milli = BigInt(match[1]) * 1000n + BigInt((match[2] ?? '').padEnd(3, '0') || '0');
  if (milli > VALUE_MAX_MILLI) return null;
  return { milli, text: milliText(milli) };
}

export function milliText(milli) {
  const whole = milli / 1000n;
  const frac = String(milli % 1000n).padStart(3, '0');
  return `${whole}.${frac}`;
}

/** pg NUMERIC(…,3) metni ('123.450') -> milli bigint. */
export function milliOf(text) {
  const [whole, frac = ''] = String(text).split('.');
  return BigInt(whole) * 1000n + BigInt(frac.padEnd(3, '0').slice(0, 3) || '0');
}

export function parseMoney(value, field, label) {
  const parsed = parseMinor(value);
  if (parsed === null) throw invalid(`${label} kuruş cinsinden pozitif tamsayı olmalıdır.`, field);
  return parsed;
}

export function parseKey(value) {
  if (typeof value !== 'string' || !KEY_PATTERN.test(value)) throw invalid('İşlem anahtarı (idempotency_key) 8-64 karakter olmalıdır.', 'idempotency_key');
  return value;
}
