// Google Drive REST istemcisi (D1): googleapis paketi YOK, yalnız fetch. `fetchImpl` testlerde değiştirilir.
// Yalnız drive.file kapsamı: uygulamanın kendi oluşturduğu klasör ve dosyalar. Belirteç ve dosya içeriği günlüğe YAZILMAZ.

import { DRIVE_SCOPE } from './drive_common.js';

const AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const REVOKE_URL = 'https://oauth2.googleapis.com/revoke';
const API = 'https://www.googleapis.com/drive/v3';
const UPLOAD = 'https://www.googleapis.com/upload/drive/v3/files';
const FOLDER_MIME = 'application/vnd.google-apps.folder';
const TIMEOUT_MS = 60_000;

/** Drive hatası: kind = 'auth' (izin kaldırıldı / belirteç geçersiz), 'not_found', 'quota', 'transient'. */
export class DriveError extends Error {
  constructor(kind, message, status = 0) {
    super(message);
    this.name = 'DriveError';
    this.kind = kind;
    this.status = status;
  }
}

function classify(status, bodyText) {
  if (status === 401 || /invalid_grant/.test(bodyText)) return 'auth';
  if (status === 404) return 'not_found';
  if (status === 403 && /storageQuotaExceeded|quotaExceeded|rateLimitExceeded|userRateLimitExceeded/.test(bodyText)) return 'quota';
  if (status === 403) return 'auth';
  return 'transient';
}

export function createDriveClient({ config, fetchImpl = globalThis.fetch } = {}) {
  async function call(url, init = {}) {
    let response;
    try {
      response = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
    } catch {
      throw new DriveError('transient', 'Google Drive eşleşmesine ulaşılamadı.');
    }
    return response;
  }

  async function json(url, init) {
    const response = await call(url, init);
    const text = await response.text();
    if (!response.ok) {
      throw new DriveError(classify(response.status, text), `Drive istegi basarisiz (${response.status})`, response.status);
    }
    return text ? JSON.parse(text) : {};
  }

  const form = (data) => ({
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(data).toString(),
  });
  const bearer = (token, extra = {}) => ({ Authorization: `Bearer ${token}`, ...extra });

  return {
    authUrl(state) {
      const params = new URLSearchParams({
        client_id: config.clientId,
        redirect_uri: config.redirectUri,
        response_type: 'code',
        scope: DRIVE_SCOPE,
        access_type: 'offline',
        prompt: 'consent',
        include_granted_scopes: 'false',
        state,
      });
      return `${AUTH_URL}?${params.toString()}`;
    },
    /** code -> { refreshToken, accessToken, expiresIn } */
    async exchangeCode(code) {
      const body = await json(
        TOKEN_URL,
        form({ code, client_id: config.clientId, client_secret: config.clientSecret, redirect_uri: config.redirectUri, grant_type: 'authorization_code' }),
      );
      return { refreshToken: body.refresh_token ?? null, accessToken: body.access_token, expiresIn: Number(body.expires_in) || 3000, scope: String(body.scope ?? '') };
    },
    async refreshAccess(refreshToken) {
      const body = await json(
        TOKEN_URL,
        form({ refresh_token: refreshToken, client_id: config.clientId, client_secret: config.clientSecret, grant_type: 'refresh_token' }),
      );
      return { accessToken: body.access_token, expiresIn: Number(body.expires_in) || 3000 };
    },
    async revoke(token) {
      await call(REVOKE_URL, form({ token })).catch(() => {});
    },
    async accountEmail(accessToken) {
      const body = await json(`${API}/about?fields=user(emailAddress)`, { headers: bearer(accessToken) });
      return body?.user?.emailAddress ?? null;
    },
    /** Üst klasörde (yoksa kök) ada göre klasör bulur, yoksa oluşturur. */
    async ensureFolder(accessToken, name, parentId) {
      const escaped = name.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      const parentClause = parentId ? ` and '${parentId}' in parents` : " and 'root' in parents";
      const q = `name = '${escaped}' and mimeType = '${FOLDER_MIME}' and trashed = false${parentClause}`;
      const found = await json(`${API}/files?${new URLSearchParams({ q, fields: 'files(id)', pageSize: '1', spaces: 'drive' })}`, { headers: bearer(accessToken) });
      if (found.files?.[0]?.id) return found.files[0].id;
      const created = await json(`${API}/files?fields=id`, {
        method: 'POST',
        headers: bearer(accessToken, { 'Content-Type': 'application/json' }),
        body: JSON.stringify({ name, mimeType: FOLDER_MIME, ...(parentId ? { parents: [parentId] } : {}) }),
      });
      return created.id;
    },
    /** Tek istekte (multipart) yükler; { id, size } döner. */
    async uploadFile(accessToken, { name, mimeType, parentId, data }) {
      const boundary = `kapi${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`;
      const meta = JSON.stringify({ name, parents: [parentId] });
      const head = Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`);
      const tail = Buffer.from(`\r\n--${boundary}--`);
      const body = await json(`${UPLOAD}?uploadType=multipart&fields=id,size`, {
        method: 'POST',
        headers: bearer(accessToken, { 'Content-Type': `multipart/related; boundary=${boundary}` }),
        body: Buffer.concat([head, data, tail]),
      });
      return { id: body.id, size: Number(body.size) };
    },
    /** Dosya içeriği: { body (web ReadableStream), contentLength } ; yoksa DriveError('not_found'). */
    async downloadFile(accessToken, fileId) {
      const response = await call(`${API}/files/${encodeURIComponent(fileId)}?alt=media`, { headers: bearer(accessToken) });
      if (!response.ok) {
        throw new DriveError(classify(response.status, await response.text().catch(() => '')), `Drive indirme basarisiz (${response.status})`, response.status);
      }
      return { body: response.body, contentLength: Number(response.headers.get('content-length')) || null };
    },
  };
}
