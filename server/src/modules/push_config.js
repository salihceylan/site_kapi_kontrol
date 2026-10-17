// Telefon bildirimi (Faz 3b-B) ortam ayarları ve açılış uyarıları (validateEnv bunları ekler).
//
// Sözleşme: docs/PLATFORM_BELGELER.md B4 / B6 ve "Ortam değişkenleri özeti (B)":
//   PUSH_ENABLED                (varsayılan 0) 1 iken outbox yazılır ve işçi gönderir; 0 iken HİÇ outbox satırı yazılmaz (cihaz kaydı yine çalışır).
//   FCM_SERVICE_ACCOUNT_FILE    hizmet hesabı JSON'unun YOLU (içeriği .env / PM2 ortamına KONMAZ); depo ve server/ DIŞINDA, 0600.
//   PUSH_MAX_PER_DAY_PER_USER   (varsayılan 8) kullanıcı başına İstanbul gününde en çok `normal` push.
//   PUSH_URGENT_MAX_PER_DAY_PER_SITE (varsayılan 3; e-postadaki ANNOUNCEMENT_URGENT_EMAIL_MAX_PER_DAY_PER_SITE ile aynı) site başına İstanbul gününde
//                               ACİL olarak kuyruğa giren en çok duyuru; fazlası `normal` yazılır (tercih / sessiz saat / kullanıcı sınırına tabi).
// Uyarılar dosya İÇERİĞİNİ okumaz ve yolu / içeriği yazdırmaz; yalnız durum (izin kipi, hata kodu) bildirir.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const DEFAULT_MAX_PER_DAY_PER_USER = 8;
export const DEFAULT_URGENT_MAX_PER_DAY_PER_SITE = 3;
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const ENABLED_VALUES = ['1', 'true', 'yes', 'on'];
const DISABLED_VALUES = ['', '0', 'false', 'no', 'off'];

const rawOf = (env, name) => String(env?.[name] ?? '').trim();

/** PUSH_ENABLED: yalnız açıkça 1/true/yes/on ise açık (geçersiz değer = kapalı + uyarı). */
export function isPushEnabled(env = process.env) {
  return ENABLED_VALUES.includes(rawOf(env, 'PUSH_ENABLED').toLowerCase());
}

const parseMaxPerDay = (raw) => {
  const value = /^\d{1,4}$/.test(raw) ? Number(raw) : NaN;
  return value >= 1 && value <= 1000 ? value : null;
};

/** PUSH_MAX_PER_DAY_PER_USER: 1-1000 tamsayı; tanımsız / geçersizse 8. */
export function pushMaxPerDay(env = process.env) {
  return parseMaxPerDay(rawOf(env, 'PUSH_MAX_PER_DAY_PER_USER')) ?? DEFAULT_MAX_PER_DAY_PER_USER;
}

/** PUSH_URGENT_MAX_PER_DAY_PER_SITE: 1-1000 tamsayı; tanımsız / geçersizse 3. */
export function pushUrgentMaxPerDayPerSite(env = process.env) {
  return parseMaxPerDay(rawOf(env, 'PUSH_URGENT_MAX_PER_DAY_PER_SITE')) ?? DEFAULT_URGENT_MAX_PER_DAY_PER_SITE;
}

/** FCM_SERVICE_ACCOUNT_FILE (kırpılmış) ya da null. */
export function serviceAccountFile(env = process.env) {
  const raw = rawOf(env, 'FCM_SERVICE_ACCOUNT_FILE');
  return raw === '' ? null : raw;
}

function isInside(child, parent, platform) {
  const fold = (value) => (platform === 'win32' ? value.toLowerCase() : value);
  const relative = path.relative(fold(parent), fold(child));
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

/**
 * Açılış uyarıları (sunucu yine AÇILIR; push yapılandırılamazsa `configured:false`). Yol depo içindeyse, POSIX'te dosya modu grup/diğerlerine
 * izin veriyorsa (mode & 0o077), bulunduğu dizin diğerlerine açık ya da grupça yazılabilirse (mode & 0o027) ya da dosya okunamıyorsa uyarır.
 * Dosya içeriği okunmaz.
 * @returns {string[]}
 */
export function pushEnvWarnings(env = process.env, { fsImpl = fs, repoRoot = REPO_ROOT, platform = process.platform, cwd = process.cwd() } = {}) {
  const warnings = [];
  const enabledRaw = rawOf(env, 'PUSH_ENABLED').toLowerCase();
  if (!ENABLED_VALUES.includes(enabledRaw) && !DISABLED_VALUES.includes(enabledRaw)) {
    warnings.push('PUSH_ENABLED gecersiz (1/0 beklenir); telefon bildirimi KAPALI kabul ediliyor.');
  }
  const maxRaw = rawOf(env, 'PUSH_MAX_PER_DAY_PER_USER');
  if (maxRaw !== '' && parseMaxPerDay(maxRaw) === null) {
    warnings.push(`PUSH_MAX_PER_DAY_PER_USER gecersiz (1-1000 tamsayi beklenir); varsayilan ${DEFAULT_MAX_PER_DAY_PER_USER} kullaniliyor.`);
  }
  const urgentRaw = rawOf(env, 'PUSH_URGENT_MAX_PER_DAY_PER_SITE');
  if (urgentRaw !== '' && parseMaxPerDay(urgentRaw) === null) {
    warnings.push(`PUSH_URGENT_MAX_PER_DAY_PER_SITE gecersiz (1-1000 tamsayi beklenir); varsayilan ${DEFAULT_URGENT_MAX_PER_DAY_PER_SITE} kullaniliyor.`);
  }
  const file = serviceAccountFile(env);
  if (!file) {
    if (isPushEnabled(env)) {
      warnings.push('PUSH_ENABLED=1 ama FCM_SERVICE_ACCOUNT_FILE tanimli degil: telefon bildirimi kullanilamaz (push_available:false).');
    }
    return warnings;
  }
  const resolved = path.resolve(cwd, file);
  if (isInside(resolved, repoRoot, platform)) {
    warnings.push(
      'GUVENLIK: FCM_SERVICE_ACCOUNT_FILE depo (ya da server/) dizini icinde. Hizmet hesabi dosyasi depo DISINDA tutulmali ' +
        '(oneri: /etc/kapi/fcm-service-account.json, sahibi API kullanicisi, 0600); dagitim yedeklerine ve git e girmemeli.',
    );
  }
  let stat;
  try {
    stat = fsImpl.statSync(resolved);
  } catch (error) {
    warnings.push(`FCM_SERVICE_ACCOUNT_FILE okunamiyor (${String(error?.code || 'HATA')}); telefon bildirimi yapilandirilmamis sayilir (configured:false).`);
    return warnings;
  }
  if (!stat.isFile()) {
    warnings.push('FCM_SERVICE_ACCOUNT_FILE bir dosya degil; telefon bildirimi yapilandirilmamis sayilir (configured:false).');
    return warnings;
  }
  if (platform !== 'win32' && (stat.mode & 0o077) !== 0) {
    warnings.push(
      `GUVENLIK: FCM_SERVICE_ACCOUNT_FILE izinleri cok acik (${(stat.mode & 0o777).toString(8)}); yalniz sahibi okuyabilmeli: chmod 600 (dizin 0700 / 0750).`,
    );
  }
  if (platform !== 'win32') {
    // Dizin: herkese açık (diğerleri okur / listeler / yazar) ya da grupça yazılabilir dizinde dosya değiştirilebilir / adı görülebilir.
    try {
      const dirStat = fsImpl.statSync(path.dirname(resolved));
      if ((dirStat.mode & 0o027) !== 0) {
        warnings.push(
          `GUVENLIK: FCM_SERVICE_ACCOUNT_FILE dizininin izinleri cok acik (${(dirStat.mode & 0o777).toString(8)}); oneri: 0700 ya da 0750 (diger kullanicilara kapali, grupca yazilamaz).`,
        );
      }
    } catch (_error) {
      // dizin okunamıyorsa dosya denetimi zaten yukarıda uyardı / geçti
    }
  }
  return warnings;
}
