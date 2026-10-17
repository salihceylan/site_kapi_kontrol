// Telefon bildirimi (Faz 3b-B): FCM HTTP v1 istemcisi (firebase-admin YOK; K5).
//
// Sözleşme: docs/PLATFORM_BELGELER.md B1 / B5.
//  - Erişim jetonu: hizmet hesabıyla OAuth2 JWT-bearer (https://oauth2.googleapis.com/token). Bellekte önbellek (Google'ın verdiği ömür, en çok
//    1 saat); süresi 5 dk kala TEK-UÇUŞLA yenilenir (eşzamanlı gönderimler aynı isteği bekler).
//  - Gönderim: POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send, jeton başına bir çağrı. Her fetch 10 sn AbortSignal.timeout.
//  - Yanıt eşlemesi (classifyFcmError): 200 ok; UNREGISTERED ya da NOT_FOUND durumlu 404, 400 INVALID_ARGUMENT (alan message.token),
//    SENDER_ID_MISMATCH -> dead (cihaz satırı silinir; toplu silme koruması işçide); gövdesiz / kodsuz çıplak 404 -> invalid (yanlış URL / vekil
//    sunucu cihaz SİLDİRMEZ); THIRD_PARTY_AUTH_ERROR -> apns_auth (iOS devre kesici); 401 / 403 PERMISSION_DENIED -> auth (erişim jetonu BİR KEZ yenilenir ve
//    tek kez yeniden denenir); 429 / 5xx / ağ / zaman aşımı -> transient (Retry-After'a uyulur); diğer 4xx -> invalid.
//  - Yönlendirme izlenmez (redirect: 'error'): Bearer erişim jetonu / imzalı iddia başka bir adrese taşınamaz.
//  - GİZLİLİK: istek / yanıt gövdesi, erişim jetonu ve FCM kayıt jetonu hiçbir hataya / günlüğe girmez; yalnız HTTP kodu + kısa hata kodu.

import { sanitizeErrorCode } from './push_common.js';

export const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
export const TOKEN_REFRESH_MARGIN_MS = 5 * 60 * 1000;
export const ACCESS_TOKEN_MAX_LIFETIME_MS = 60 * 60 * 1000;
export const FETCH_TIMEOUT_MS = 10 * 1000;
/** Retry-After üst sınırı (sn). */
export const RETRY_AFTER_MAX_SECONDS = 3600;
const MAX_ERROR_BODY_BYTES = 64 * 1024;

/** Test / QA için değiştirilebilir uçlar ve saat (sahte oauth2 / FCM sunucusu). */
export const fcmHooks = {
  tokenUrl: 'https://oauth2.googleapis.com/token',
  apiBase: 'https://fcm.googleapis.com',
  fetch: (url, init) => globalThis.fetch(url, init),
  now: () => Date.now(),
  timeoutMs: FETCH_TIMEOUT_MS,
};

/** Erişim jetonu alınamadı. `code`: TOKEN_<http>[_<google kısa kodu>] | TOKEN_EMPTY | TIMEOUT | NETWORK. Gövde / jeton taşımaz. */
export class FcmAuthError extends Error {
  constructor(code, httpStatus = null) {
    super(`FCM erisim jetonu alinamadi (${code}).`);
    this.name = 'FcmAuthError';
    this.code = code;
    this.httpStatus = httpStatus;
  }
}

function networkCode(error) {
  return error?.name === 'TimeoutError' || error?.name === 'AbortError' ? 'TIMEOUT' : 'NETWORK';
}

/** Yanıt gövdesini en çok 64 KB okur ve JSON çözer (başarısızsa null). Gövde hiçbir yere yazılmaz. */
async function readJson(response) {
  try {
    const text = await response.text();
    if (text.length > MAX_ERROR_BODY_BYTES) {
      return null;
    }
    return JSON.parse(text);
  } catch (_error) {
    return null;
  }
}

/** Retry-After: saniye ya da HTTP tarihi -> saniye (0..3600) ya da null. */
export function parseRetryAfter(value, nowMs = Date.now()) {
  if (value === null || value === undefined || String(value).trim() === '') {
    return null;
  }
  const text = String(value).trim();
  let seconds = null;
  if (/^\d{1,7}$/.test(text)) {
    seconds = Number(text);
  } else {
    const at = Date.parse(text);
    if (Number.isFinite(at)) {
      seconds = Math.ceil((at - nowMs) / 1000);
    }
  }
  if (seconds === null || !Number.isFinite(seconds)) {
    return null;
  }
  return Math.min(Math.max(seconds, 0), RETRY_AFTER_MAX_SECONDS);
}

/**
 * FCM hata yanıtı -> { kind, code, httpStatus, retryAfterSeconds }. kind: dead | apns_auth | auth | transient | invalid.
 * `code` yalnız FCM hata kodu / durum metni (ör. UNREGISTERED, PERMISSION_DENIED) ya da HTTP_<kod>; yanıt metni taşınmaz.
 */
export function classifyFcmError(status, body, retryAfterSeconds = null) {
  const error = body && typeof body === 'object' && body.error && typeof body.error === 'object' ? body.error : {};
  const statusText = typeof error.status === 'string' ? error.status : '';
  const details = Array.isArray(error.details) ? error.details : [];
  const fcmCode = details.find((detail) => typeof detail?.errorCode === 'string')?.errorCode ?? '';
  const tokenField = details.some(
    (detail) => Array.isArray(detail?.fieldViolations) && detail.fieldViolations.some((violation) => violation?.field === 'message.token'),
  );
  const code = sanitizeErrorCode(fcmCode || statusText || `HTTP_${status}`);
  const result = (kind, overrideCode = code) => ({ kind, code: overrideCode, httpStatus: status, retryAfterSeconds });
  // Çıplak 404 (gövdesiz / kodsuz: yanlış URL, vekil sunucu) ölü jeton SAYILMAZ: cihaz silinmez, satır failed olur.
  if (fcmCode === 'UNREGISTERED' || (status === 404 && statusText === 'NOT_FOUND')) {
    return result('dead', fcmCode ? code : 'UNREGISTERED');
  }
  if (fcmCode === 'SENDER_ID_MISMATCH') {
    return result('dead');
  }
  if (status === 400 && (fcmCode === 'INVALID_ARGUMENT' || statusText === 'INVALID_ARGUMENT') && tokenField) {
    return result('dead', 'INVALID_TOKEN');
  }
  if (fcmCode === 'THIRD_PARTY_AUTH_ERROR') {
    return result('apns_auth', 'APNS_AUTH');
  }
  if (status === 401 || status === 403) {
    return result('auth');
  }
  if (status === 429 || status >= 500) {
    return result('transient');
  }
  return result('invalid');
}

/**
 * Hizmet hesabına bağlı FCM istemcisi. send(message) asla fırlatmaz: { kind: 'ok' | ..., code, httpStatus, retryAfterSeconds }.
 * @param {{ projectId: string, signAssertion: Function }} account
 */
export function createFcmClient(account, hooks = fcmHooks) {
  let cached = null; // { token, expiresAtMs }
  let inflight = null;

  async function requestAccessToken() {
    const nowMs = hooks.now();
    const assertion = account.signAssertion({ audience: hooks.tokenUrl, scope: FCM_SCOPE, nowSeconds: Math.floor(nowMs / 1000) });
    let response;
    try {
      response = await hooks.fetch(hooks.tokenUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
        signal: AbortSignal.timeout(hooks.timeoutMs),
        redirect: 'error',
      });
    } catch (error) {
      throw new FcmAuthError(networkCode(error));
    }
    const body = await readJson(response);
    if (!response.ok) {
      // Yalnız HTTP kodu + Google'ın kısa `error` kodu (ör. invalid_grant); açıklama / gövde YOK.
      const googleCode = typeof body?.error === 'string' && /^[a-z_]{1,40}$/.test(body.error) ? `_${body.error.toUpperCase()}` : '';
      throw new FcmAuthError(`TOKEN_${response.status}${googleCode}`, response.status);
    }
    const token = typeof body?.access_token === 'string' ? body.access_token : '';
    if (token === '') {
      throw new FcmAuthError('TOKEN_EMPTY', response.status);
    }
    const expiresIn = Number(body?.expires_in);
    const lifetimeMs = Number.isFinite(expiresIn) && expiresIn > 0 ? Math.min(expiresIn * 1000, ACCESS_TOKEN_MAX_LIFETIME_MS) : ACCESS_TOKEN_MAX_LIFETIME_MS;
    cached = { token, expiresAtMs: nowMs + lifetimeMs };
    return token;
  }

  function refresh() {
    if (!inflight) {
      inflight = requestAccessToken().finally(() => {
        inflight = null;
      });
    }
    return inflight;
  }

  /** Önbellekteki jeton (süresine 5 dk'dan fazla varsa) ya da tek-uçuş yenileme. */
  function getAccessToken() {
    if (cached && cached.expiresAtMs - hooks.now() > TOKEN_REFRESH_MARGIN_MS) {
      return Promise.resolve(cached.token);
    }
    return refresh();
  }

  /** FCM jetonu reddetti (401 / 403): önbellek bu jetonsa düşürülür ve TEK-UÇUŞ yenilenir (başka gönderim zaten yenilediyse o kullanılır). */
  function refreshAfterReject(rejectedToken) {
    if (cached && cached.token !== rejectedToken && cached.expiresAtMs - hooks.now() > TOKEN_REFRESH_MARGIN_MS) {
      return Promise.resolve(cached.token);
    }
    if (cached?.token === rejectedToken) {
      cached = null;
    }
    return refresh();
  }

  async function post(message, token) {
    let response;
    try {
      response = await hooks.fetch(`${hooks.apiBase}/v1/projects/${encodeURIComponent(account.projectId)}/messages:send`, {
        method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json; charset=utf-8' },
        body: JSON.stringify({ message }),
        signal: AbortSignal.timeout(hooks.timeoutMs),
        redirect: 'error',
      });
    } catch (error) {
      return { kind: 'transient', code: networkCode(error), httpStatus: null, retryAfterSeconds: null };
    }
    if (response.ok) {
      await response.text().catch(() => '');
      return { kind: 'ok', code: null, httpStatus: response.status, retryAfterSeconds: null };
    }
    const body = await readJson(response);
    return classifyFcmError(response.status, body, parseRetryAfter(response.headers?.get?.('retry-after'), hooks.now()));
  }

  const authFailure = (error) => ({
    kind: 'auth',
    code: sanitizeErrorCode(error?.code ?? 'TOKEN_FAILED'),
    httpStatus: error?.httpStatus ?? null,
    retryAfterSeconds: null,
  });

  /** Tek jetona tek mesaj. Asla fırlatmaz. */
  async function send(message) {
    let token;
    try {
      token = await getAccessToken();
    } catch (error) {
      return authFailure(error);
    }
    const first = await post(message, token);
    if (first.kind !== 'auth') {
      return first;
    }
    // 401 / 403: erişim jetonu bir kez yenilenir ve tek kez yeniden denenir; sürerse çağıran (işçi) devre kesiciye sayar.
    try {
      token = await refreshAfterReject(token);
    } catch (error) {
      return authFailure(error);
    }
    return post(message, token);
  }

  return Object.freeze({ send, getAccessToken });
}

const clients = new WeakMap();

/** Hizmet hesabı başına tek istemci (erişim jetonu önbelleği paylaşılır). */
export function fcmClientFor(account) {
  if (!account) {
    return null;
  }
  let client = clients.get(account);
  if (!client) {
    client = createFcmClient(account);
    clients.set(account, client);
  }
  return client;
}
