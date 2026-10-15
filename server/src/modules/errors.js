// Platform modül sistemi servis hataları. Rotalar `PlatformError`'ı { error, code } gövdesiyle yanıtlar;
// başka hatalar (DB vb.) istemciye SIZDIRILMAZ (genel mesaj + errorId).

export class PlatformError extends Error {
  /**
   * @param {number} statusCode HTTP durum kodu (4xx)
   * @param {string} code makine okunur kod (ör. MODULE_NOT_FOUND)
   * @param {string} message Türkçe kullanıcı mesajı
   * @param {Record<string, unknown>} [extra] yanıt gövdesine eklenen ek alanlar (ör. PERSON_EXISTS -> person_id)
   */
  constructor(statusCode, code, message, extra = null) {
    super(message);
    this.name = 'PlatformError';
    this.statusCode = statusCode;
    this.code = code;
    this.expose = true;
    this.extra = extra && typeof extra === 'object' ? extra : null;
  }
}

export function isPlatformError(error) {
  return error instanceof PlatformError;
}
