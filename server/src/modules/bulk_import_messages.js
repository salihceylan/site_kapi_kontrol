// Toplu yükleme (Faz 2b) satır sorunu iletileri. Türkçe, alan etiketiyle, < 140 karakter, teknik ifade yok.
// Hücre değeri en çok 40 karakter yankılanır. İletiler önizleme yanıtında döner; ASLA `preview_hash`'e, çalıştırma kaydına ya da audit'e girmez.

export const MESSAGE_MAX_LENGTH = 139;

export const ERROR_CODES = Object.freeze([
  'REQUIRED',
  'TOO_LONG',
  'FORMULA_LIKE',
  'NAME_INVALID',
  'EMAIL_INVALID',
  'EMAIL_INTERNAL',
  'PHONE_INVALID',
  'DATE_INVALID',
  'DATE_RANGE',
  'NUMBER_INVALID',
  'NUMBER_RANGE',
  'FLOOR_INVALID',
  'LAND_SHARE_INVALID',
  'RELATION_INVALID',
  'RESPONSIBLE_INVALID',
  'NO_IDENTIFIER',
  'APARTMENT_REQUIRED',
  'BLOCK_NOT_FOUND',
  'BLOCK_AMBIGUOUS',
  'APARTMENT_NOT_FOUND',
  'DUPLICATE_IN_FILE',
  'CONFLICTING_ROWS',
  'RELATION_TAKEN',
  'PERSON_AMBIGUOUS',
  'PERSON_NOT_FOUND',
  'TOO_MANY_PLATES',
  'PLATE_REQUIRED',
]);

export const WARNING_CODES = Object.freeze([
  'PLATE_INVALID',
  'PLATE_EXISTS',
  'PLATE_DUP_IN_FILE',
  'ACCOUNT_NEW_APARTMENT',
  'RELATION_DIFFERS',
  'REACTIVATE_PERSON',
  'VALUE_KEPT',
  'FINANCE_RECORDS',
  'ROUNDED',
  'AREA_UNUSUAL',
  'NET_GT_GROSS',
  'FUTURE_DATE',
  'NO_VALUES',
]);

/** Hücre değerini iletiye koymak için: tek satır, en çok 40 karakter. */
export function echo(value) {
  const text = Array.from(String(value ?? '').replace(/\s+/g, ' ').trim());
  return text.length > 40 ? `${text.slice(0, 39).join('')}…` : text.join('');
}

function leadName(lead) {
  if (lead === '\t') return 'sekme';
  if (lead === '\r') return 'satır başı';
  return `«${lead}»`;
}

/**
 * İleti üretir. `ctx`: { label, value, max, lead, line, blocks, extra }.
 * Sonuç her zaman <= MESSAGE_MAX_LENGTH karakterdir (aşarsa kısaltılır).
 */
export function issueMessage(code, ctx = {}) {
  const label = ctx.label ?? 'Alan';
  const value = echo(ctx.value);
  let text;
  switch (code) {
    case 'REQUIRED':
      text = `${label} zorunludur.`;
      break;
    case 'TOO_LONG':
      text = `${label} çok uzun (en çok ${ctx.max ?? 600} karakter).`;
      break;
    case 'FORMULA_LIKE':
      text = `${label} formül gibi görünüyor (${leadName(ctx.lead ?? '=')} ile başlıyor). İşareti kaldırın.`;
      break;
    case 'NAME_INVALID':
      text = `${label} 2 ile 100 karakter arasında olmalıdır.`;
      break;
    case 'EMAIL_INVALID':
      text = `E-posta biçimi geçersiz: «${value}».`;
      break;
    case 'EMAIL_INTERNAL':
      text = 'Bu e-posta adresi (@ahbu.local) kişi kaydı için kullanılamaz.';
      break;
    case 'PHONE_INVALID':
      text = `Telefon geçersiz: «${value}». 10 haneli numara girin.`;
      break;
    case 'DATE_INVALID':
      text = `${label} geçersiz: «${value}». GG.AA.YYYY biçimini kullanın.`;
      break;
    case 'DATE_RANGE':
      text = `${label} 1900 ile bugünden en çok 1 yıl sonrası arasında olmalıdır.`;
      break;
    case 'NUMBER_INVALID':
      text = `${label} sayı değil: «${value}».`;
      break;
    case 'NUMBER_RANGE':
      text = `${label} 0’dan büyük ve en çok 999.999,99 olmalıdır.`;
      break;
    case 'FLOOR_INVALID':
      text = `Kat geçersiz: «${value}». -20 ile 500 arası bir sayı ya da «Zemin» yazın.`;
      break;
    case 'LAND_SHARE_INVALID':
      text = 'Arsa payı geçersiz: pay ve payda birlikte dolu olmalı, payda 0’dan büyük, pay payda’dan büyük olmamalı.';
      break;
    case 'RELATION_INVALID':
      text = `İlişki anlaşılamadı: «${value}». Malik, Kiracı, Aile ya da Sakin yazın.`;
      break;
    case 'RESPONSIBLE_INVALID':
      text = `Borç Sorumlusu anlaşılamadı: «${value}». Malik, Kiracı ya da İkisi yazın.`;
      break;
    case 'NO_IDENTIFIER':
      text = 'Kişiyi tanımak için e-posta, daire ya da telefon gerekir.';
      break;
    case 'APARTMENT_REQUIRED':
      text = 'Blok ve Daire No birlikte doldurulmalıdır.';
      break;
    case 'BLOCK_NOT_FOUND': {
      const names = (ctx.blocks ?? []).slice(0, 6).join(', ');
      text = `Blok bulunamadı: «${value}».${names ? ` Sitedeki bloklar: ${names}.` : ''}`;
      break;
    }
    case 'BLOCK_AMBIGUOUS':
      text = `Blok birden çok bloğa uyuyor: «${value}». Blok adını tam yazın.`;
      break;
    case 'APARTMENT_NOT_FOUND':
      text = `Daire bulunamadı: «${value}». Daire sayısını Site Yapısı’ndan artırın.`;
      break;
    case 'DUPLICATE_IN_FILE':
      text = ctx.severity === 'warning'
        ? `Aynı kişi ve daire dosyada satır ${ctx.line} ile aynı; birleştirildi.`
        : `Bu daire dosyada daha önce (satır ${ctx.line}) geçti.`;
      break;
    case 'CONFLICTING_ROWS':
      text = `Aynı kişi ve daire için satır ${ctx.line} ile çelişen ilişki var. Farklı kişiyseniz e-posta ya da telefon ekleyin.`;
      break;
    case 'RELATION_TAKEN':
      text = 'Bu dairede bu ilişki için başka bir kişi var. Eş ya da hissedar için «Aile» yazın.';
      break;
    case 'PERSON_AMBIGUOUS':
      text = 'Birden çok kişi eşleşti. E-posta ya da telefon ekleyerek ayırın.';
      break;
    case 'PERSON_NOT_FOUND':
      text = 'Kişi bulunamadı. Kayıtlı bir e-posta ya da dairede kayıtlı bir sakin gerekir.';
      break;
    case 'TOO_MANY_PLATES':
      text = 'Bir hücrede en çok 5 plaka olabilir.';
      break;
    case 'PLATE_REQUIRED':
      text = 'Plaka zorunludur.';
      break;
    case 'PLATE_INVALID':
      text = `Plaka atlandı (biçim geçersiz): «${value}».`;
      break;
    case 'PLATE_EXISTS':
      text = `Plaka atlandı: «${value}» sitede başka bir kişide kayıtlı.`;
      break;
    case 'PLATE_DUP_IN_FILE':
      text = `Plaka atlandı: «${value}» dosyada başka bir kişide de var.`;
      break;
    case 'ACCOUNT_NEW_APARTMENT':
      text = 'Hesaplı kişiye yeni daire eklenmedi. Kişi kartından elle ekleyin.';
      break;
    case 'RELATION_DIFFERS':
      text = 'İlişki değişmedi: kayıtlı ilişki dosyadakinden farklı.';
      break;
    case 'REACTIVATE_PERSON':
      text = 'Pasif kişi yeniden etkinleştirilecek.';
      break;
    case 'VALUE_KEPT':
      text = `${label} korundu: dolu alanın üzerine yazılmadı.`;
      break;
    case 'FINANCE_RECORDS':
      text = 'Bu dairenin mali kaydı var; yeni değerler yalnız sonraki borçlandırmayı etkiler.';
      break;
    case 'ROUNDED':
      text = `${label} 2 ondalığa yuvarlandı.`;
      break;
    case 'AREA_UNUSUAL':
      text = `${label} olağandışı görünüyor (${value} m²). Kontrol edin.`;
      break;
    case 'NET_GT_GROSS':
      text = 'Net m², brüt m²’den büyük. Kontrol edin.';
      break;
    case 'FUTURE_DATE':
      text = `${label} gelecekte: ${value}.`;
      break;
    case 'NO_VALUES':
      text = 'Satırda yüklenecek bir değer yok.';
      break;
    default:
      text = 'Satır işlenemedi.';
  }
  const chars = Array.from(text);
  return chars.length > MESSAGE_MAX_LENGTH ? `${chars.slice(0, MESSAGE_MAX_LENGTH - 1).join('')}…` : text;
}

export function severityOf(code) {
  return WARNING_CODES.includes(code) ? 'warning' : 'error';
}
