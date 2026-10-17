// Telefon bildirimi (Faz 3b-B): FCM hizmet hesabı yükleyici ve çalışma durumu.
//
// Sözleşme: docs/PLATFORM_BELGELER.md B1 / B6 (K6).
//  - Dosya (FCM_SERVICE_ACCOUNT_FILE) açılışta BİR KEZ okunur ve doğrulanır: type=service_account, project_id, client_email, private_key (PEM, RSA).
//  - Özel anahtar ve client_email YALNIZ bu modülün kapanımında tutulur: process.env'e, günlüğe, hata mesajına, /admin/push/status'a, audit'e ve
//    util.inspect / JSON.stringify / String() çıktısına GİRMEZ (toJSON / inspect / toString maskeli). Hata yalnız KOD taşır (JSON ayrıştırma
//    hatasının mesajı dosyadan parça içerebildiği için asla aktarılmaz).
//  - Okunamaz / bozuksa push `configured:false` olur; sunucu yine AÇILIR. PUSH_ENABLED kapalı olsa da dosya doğrulanır (açmadan önce
//    /admin/push/status ile `configured:true` görülebilsin).

import crypto from 'node:crypto';
import fs from 'node:fs';
import util from 'node:util';
import jwt from 'jsonwebtoken';
import { isPushEnabled, serviceAccountFile } from './push_config.js';

export const MAX_SERVICE_ACCOUNT_BYTES = 64 * 1024;
/** Google erişim jetonu için imzalanan JWT en çok 1 saat geçerlidir. */
export const ASSERTION_MAX_LIFETIME_SECONDS = 3600;
const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,61}[a-z0-9]$/;
const CLIENT_EMAIL_PATTERN = /^[A-Za-z0-9._%+-]{1,128}@[A-Za-z0-9.-]{1,253}$/;
const KEY_ID_PATTERN = /^[A-Za-z0-9]{8,64}$/;
const MASK = '[gizli]';

/** Hizmet hesabı kullanılamıyor: yalnız kod (ör. INVALID_JSON, INVALID_PRIVATE_KEY, FILE_ENOENT); içerik / yol yok. */
export class ServiceAccountError extends Error {
  constructor(code) {
    super(`FCM hizmet hesabi kullanilamiyor (${code}).`);
    this.name = 'ServiceAccountError';
    this.code = code;
  }
}

/**
 * Doğrulanmış hizmet hesabı nesnesi. Özel anahtar (KeyObject) ve client_email kapanımda; dışarıya yalnız project_id ve imzalama işlevi açılır.
 * @returns {Readonly<{ projectId: string, signAssertion: Function, toJSON: Function }>}
 */
export function createServiceAccount({ projectId, clientEmail, privateKey, keyId = null }) {
  const account = {
    projectId,
    /** RS256 imzalı JWT-bearer iddiası (iss = client_email, scope, aud, iat, exp <= 1 saat). */
    signAssertion({ audience, scope, nowSeconds, lifetimeSeconds = ASSERTION_MAX_LIFETIME_SECONDS }) {
      const iat = Math.floor(nowSeconds);
      const exp = iat + Math.min(Math.max(Number(lifetimeSeconds) || 0, 60), ASSERTION_MAX_LIFETIME_SECONDS);
      return jwt.sign({ iss: clientEmail, scope, aud: audience, iat, exp }, privateKey, {
        algorithm: 'RS256',
        ...(keyId ? { keyid: keyId } : {}),
      });
    },
    toJSON() {
      return { type: 'service_account', project_id: projectId, client_email: MASK, private_key: MASK };
    },
    toString() {
      return `[FcmServiceAccount ${projectId}]`;
    },
    [util.inspect.custom]() {
      return `FcmServiceAccount { project_id: '${projectId}', client_email: ${MASK}, private_key: ${MASK} }`;
    },
  };
  return Object.freeze(account);
}

/** JSON metnini doğrular ve hizmet hesabı nesnesine çevirir; hata ServiceAccountError (yalnız kod). */
export function parseServiceAccount(text) {
  let data;
  try {
    data = JSON.parse(String(text ?? ''));
  } catch (_error) {
    throw new ServiceAccountError('INVALID_JSON');
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new ServiceAccountError('INVALID_JSON');
  }
  if (data.type !== 'service_account') {
    throw new ServiceAccountError('INVALID_TYPE');
  }
  const projectId = typeof data.project_id === 'string' ? data.project_id.trim() : '';
  if (!PROJECT_ID_PATTERN.test(projectId)) {
    throw new ServiceAccountError('INVALID_PROJECT_ID');
  }
  const clientEmail = typeof data.client_email === 'string' ? data.client_email.trim() : '';
  if (!CLIENT_EMAIL_PATTERN.test(clientEmail)) {
    throw new ServiceAccountError('INVALID_CLIENT_EMAIL');
  }
  const pem = data.private_key;
  if (typeof pem !== 'string' || !pem.includes('-----BEGIN PRIVATE KEY-----')) {
    throw new ServiceAccountError('INVALID_PRIVATE_KEY');
  }
  let privateKey;
  try {
    privateKey = crypto.createPrivateKey({ key: pem, format: 'pem' });
  } catch (_error) {
    throw new ServiceAccountError('INVALID_PRIVATE_KEY');
  }
  if (privateKey.asymmetricKeyType !== 'rsa') {
    throw new ServiceAccountError('INVALID_PRIVATE_KEY');
  }
  const keyId = typeof data.private_key_id === 'string' && KEY_ID_PATTERN.test(data.private_key_id) ? data.private_key_id : null;
  return createServiceAccount({ projectId, clientEmail, privateKey, keyId });
}

/**
 * Dosyayı okur ve doğrular. Okuma hatası yalnız sistem kodunu taşır (FILE_ENOENT, FILE_EACCES ...). Boyut ve tür OKUMADAN ÖNCE denetlenir (yanlış yola
 * verilmiş dev bir dosya / aygıt / dizin belleğe alınmaz): dosya değilse NOT_A_FILE, 64 KB üstü TOO_LARGE.
 */
export function loadServiceAccountFile(filePath, { readFileSync = fs.readFileSync, statSync = fs.statSync } = {}) {
  let text;
  try {
    const stat = statSync(filePath);
    if (typeof stat?.isFile === 'function' && !stat.isFile()) {
      throw new ServiceAccountError('NOT_A_FILE');
    }
    if (Number(stat?.size) > MAX_SERVICE_ACCOUNT_BYTES) {
      throw new ServiceAccountError('TOO_LARGE');
    }
    const buffer = readFileSync(filePath);
    if (buffer.length > MAX_SERVICE_ACCOUNT_BYTES) {
      throw new ServiceAccountError('TOO_LARGE');
    }
    text = buffer.toString('utf8');
  } catch (error) {
    if (error instanceof ServiceAccountError) {
      throw error;
    }
    const code = typeof error?.code === 'string' && /^[A-Z0-9_]{2,32}$/.test(error.code) ? error.code : 'UNREADABLE';
    throw new ServiceAccountError(`FILE_${code}`);
  }
  return parseServiceAccount(text);
}

// --- Çalışma durumu (süreç başına bir kez; testler / QA setPushRuntimeForTests ile değiştirir) -----------

let runtime = null;

/**
 * Ortamı okur ve hizmet hesabını yükler (açılışta bir kez; server.js startPushWorker çağırır). Hata fırlatmaz.
 * @returns {Readonly<{ enabled: boolean, configured: boolean, account: object | null, error: string | null }>}
 */
export function loadPushRuntime(env = process.env, { readFileSync = fs.readFileSync, statSync = fs.statSync } = {}) {
  const enabled = isPushEnabled(env);
  const file = serviceAccountFile(env);
  let account = null;
  let error = null;
  if (!file) {
    error = 'NOT_SET';
  } else {
    try {
      account = loadServiceAccountFile(file, { readFileSync, statSync });
    } catch (loadError) {
      error = loadError instanceof ServiceAccountError ? loadError.code : 'UNREADABLE';
    }
  }
  runtime = Object.freeze({ enabled, configured: account !== null, account, error });
  return runtime;
}

/** Güncel durum; henüz yüklenmediyse (testler, betikler) şimdi yükler. */
export function pushRuntime() {
  return runtime ?? loadPushRuntime();
}

/** Push gerçekten hazır mı (açık VE hizmet hesabı geçerli). push_available bu değerdir. */
export function isPushAvailable() {
  const state = pushRuntime();
  return state.enabled === true && state.configured === true;
}

/** Test / QA: durumu doğrudan ayarlar (null = bir sonraki erişimde ortamdan yeniden yükle). */
export function setPushRuntimeForTests(state) {
  runtime =
    state === null
      ? null
      : Object.freeze({ enabled: false, account: null, error: null, ...state, configured: state.configured ?? Boolean(state.account) });
  return runtime;
}
