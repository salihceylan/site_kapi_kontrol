// Günlük (log) metni için kişisel veri / gizli değer temizleyici (docs/PLATFORM_SATISA_HAZIRLIK.md §0.9).
// SMTP / sürücü hata mesajları alıcı adresini, bazı kitaplıklar belirteçleri metne katabilir; günlüğe yazmadan önce
// bu yardımcıdan geçirilir. Amaç bilgi kaybı değil, kişisel verinin günlüğe düşmemesidir: kod/yapı korunur.

const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const BEARER = /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi;
const JWT_LIKE = /\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*/g;
// +90 5xx xxx xx xx, 05xx..., 10-13 haneli numara dizileri (telefon / kart / kimlik no gibi).
const PHONE_OR_LONG_DIGITS = /(?:\+?\d[\d ()-]{8,}\d)/g;

export function redactLogText(value, { maxLength = 300 } = {}) {
  return String(value ?? '')
    .replace(BEARER, 'Bearer <belirtec>')
    .replace(JWT_LIKE, '<belirtec>')
    .replace(EMAIL, '<e-posta>')
    .replace(PHONE_OR_LONG_DIGITS, (match) => (match.replace(/\D/g, '').length >= 10 ? '<numara>' : match))
    .slice(0, maxLength);
}

/** Hata nesnesinden günlüğe yazılabilir kısa özet: kod + temizlenmiş mesaj (yığın / ham nesne değil). */
export function describeErrorForLog(error) {
  const code = error?.code ?? error?.responseCode ?? error?.name ?? 'hata';
  const message = redactLogText(error?.message ?? '', { maxLength: 200 });
  return message ? `${code}: ${message}` : String(code);
}
