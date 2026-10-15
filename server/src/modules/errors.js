// Platform modül sistemi servis hataları. Rotalar `PlatformError`'ı { error, code } gövdesiyle yanıtlar;
// başka hatalar (DB vb.) istemciye SIZDIRILMAZ (genel mesaj + errorId).

export class PlatformError extends Error {
  /**
   * @param {number} statusCode HTTP durum kodu (4xx)
   * @param {string} code makine okunur kod (ör. MODULE_NOT_FOUND)
   * @param {string} message Türkçe kullanıcı mesajı
   */
  constructor(statusCode, code, message) {
    super(message);
    this.name = 'PlatformError';
    this.statusCode = statusCode;
    this.code = code;
    this.expose = true;
  }
}

export function isPlatformError(error) {
  return error instanceof PlatformError;
}
