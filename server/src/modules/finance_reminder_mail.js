// Borç hatırlatma e-postası içeriği (Faz 4b Ö6) — SAF (ağ yok). docs/PLATFORM_FINANS_4B.md "Ö6 İçerik kuralları" [AVUKAT DOĞRULASIN].
//
// Şablon SABİTTİR (iki ton: friendly "Nazik hatırlatma", standard "Resmî hatırlatma"); yönetici yalnız ≤ 300 karakter DÜZ METİN not ekleyebilir (HTML yok, kaçışlanır,
// satır başı enjeksiyonu temizlenir). Şablonda ASLA: tanıtım / kampanya / indirim, üçüncü taraf bağlantısı, tehdit / icra / dava / ihtar dili, borçlunun başkalarına
// ifşası. Konu satırı: "[{Site Adı}] Ödeme hatırlatması" — TUTAR, AD, DAİRE konuda YOK. Gövde adla hitap etmez ("Merhaba," / "Sayın site sakini,").
// Tutar satırı YALNIZ doğrulanmış gerçek hesap e-postasına (withAmount) yazılır; diğer adreslere tutarsız metin gider (yanlış adrese borç sızmasın).
// Altbilgi HER iletide: gönderen kimliği, "tanıtım iletisi değildir" ifadesi ve abonelikten çık bağlantısı (RFC 8058 List-Unsubscribe).

import { escapeHtml, safeHttpUrl, singleLine } from '../mailer.js';
import { formatMinor } from './finance_4b_common.js';

export const REMINDER_TONES = Object.freeze(['friendly', 'standard']);
const RECIPIENT_PATTERN = /^[^\s@,;<>"()]+@[^\s@,;<>"()]+\.[^\s@,;<>"()]+$/;

/** 'YYYY-MM-DD' -> 'GG.AA.YYYY'. */
export const trDate = (iso) => `${iso.slice(8, 10)}.${iso.slice(5, 7)}.${iso.slice(0, 4)}`;

/**
 * Bağlantı / alan adı / e-posta benzeri içerik (üçüncü taraf bağlantısı ve kimlik avı riski): yönetici notunda REDDEDİLİR (R10 P2-16, R15 P2-3).
 * Kapalı TLD listesi YOK: metin NFKC ile normalleştirilir (tam genişlikli harf / nokta, ideografik nokta '。' -> '.'), sonra
 *   1) `şema://`, `www.`, `ad@alan` -> bağlantı;
 *   2) boşlukla ayrılmış her parçada (baştaki / sondaki noktalama atılır) `etiket(.etiket)*.tld` (Unicode harf / rakam / tire, tld >= 2 harf) alan adı sayılır, İSTİSNA:
 *      etiketler YALNIZ harf (rakam / tire yok) ve "tld" Başharfi büyük + küçük harf ("teşekkürler.Tr ekibi", "Lütfen.Ödeme") ise cümle sonu + boşluksuz yeni cümle sayılıp KABUL edilir;
 *      alan adından sonra yol / sorgu / port varsa her zaman bağlantıdır. Bilinen sezgisel boşluk: yol içermeyen "ornek.Com" biçimi cümle sonu sayılır (belgelenmiş).
 */
export function noteHasLink(note) {
  if (typeof note !== 'string') {
    return false;
  }
  const text = note.normalize('NFKC').replace(/[。．｡]/gu, '.');
  if (/[\p{L}][\p{L}\p{N}+.-]*:\/\//u.test(text) || /(?:^|[^\p{L}\p{N}])www\./iu.test(text) || /\S@\S/u.test(text)) {
    return true;
  }
  for (const raw of text.split(/\s+/u)) {
    const token = raw.replace(/^[("'“”‘’[<]+/u, '').replace(/[)"'“”‘’\]>.,;:!?]+$/u, '');
    const host = token.split(/[/?#]/u)[0].replace(/:\d{1,5}$/u, '');
    const match = /^((?:[\p{L}\p{N}-]+\.)+)(\p{L}{2,24})$/u.exec(host);
    if (!match) {
      continue;
    }
    const hasTail = token.length > host.length;
    const lettersOnly = /^[\p{L}.]+$/u.test(match[1]);
    const titleCase = /^\p{Lu}\p{Ll}+$/u.test(match[2]);
    if (!hasTail && lettersOnly && titleCase) {
      continue;
    }
    return true;
  }
  return false;
}

/** Yönetici notu: düz metin; kontrol karakterleri temizlenir, satır sonları tek boşluğa iner, en çok 300 karakter. */
export function cleanReminderNote(note) {
  if (note === null || note === undefined) {
    return null;
  }
  const text = singleLine(String(note).normalize('NFC'), 300).replace(/\s+/g, ' ').trim();
  return text === '' ? null : text;
}

/**
 * @param {{ to: string, siteName: string, tone: string, note?: string|null, apartments: Array<{ label: string, overdueMinor?: bigint|number|null, oldestDue?: string|null }>,
 *           withAmount: boolean, hasAccount: boolean, unsubscribeUrl?: string|null }} input
 * @returns {{ to: string, subject: string, text: string, html: string, headers?: object }}
 */
export function buildFinanceReminderEmail({ to, siteName, tone, note = null, apartments, withAmount, hasAccount, unsubscribeUrl = null }) {
  const recipient = String(to ?? '').trim();
  if (recipient.length > 254 || !RECIPIENT_PATTERN.test(recipient)) {
    const error = new Error('Gecersiz alici adresi.');
    error.code = 'INVALID_RECIPIENT';
    throw error;
  }
  const site = singleLine(siteName, 120) || 'Site';
  const subject = singleLine(`[${site}] Ödeme hatırlatması`);
  const labels = apartments.map((apt) => singleLine(apt.label, 120));
  const greeting = tone === 'standard' ? 'Sayın site sakini,' : 'Merhaba,';
  const subjectLine =
    labels.length === 1
      ? `${site} için ${labels[0]} dairesine ait vadesi geçmiş ödeme görünüyor.`
      : `${site} için ${labels.join(', ')} dairelerine ait vadesi geçmiş ödeme görünüyor.`;
  const amountLines = [];
  if (withAmount) {
    for (const [index, apt] of apartments.entries()) {
      const amount = apt.overdueMinor === null || apt.overdueMinor === undefined ? null : `${formatMinor(apt.overdueMinor)} ₺`;
      const due = apt.oldestDue ? ` (en eski vade: ${trDate(apt.oldestDue)})` : '';
      if (amount !== null) {
        amountLines.push(labels.length === 1 ? `Vadesi geçmiş tutar: ${amount}${due}.` : `${labels[index]}: ${amount}${due}`);
      }
    }
  }
  const amountText =
    withAmount && amountLines.length > 0
      ? amountLines.join('\n')
      : 'Güncel tutar için uygulamadaki "Borcum" bölümüne bakabilir veya site yönetimine başvurabilirsiniz.';
  const closing =
    'Ödemeyi yaptıysanız bu iletiyi dikkate almayın; kayıtlara yansıması birkaç gün sürebilir. Ayrıntıları uygulamadaki "Borcum" bölümünden görebilir ya da site yönetimiyle iletişime geçebilirsiniz.';
  // savunma derinliği: eski kayıtlarda bağlantı içeren not varsa ileti notsuz gider (ayrıştırıcı yeni notları zaten reddeder)
  const cleanedNote = cleanReminderNote(note);
  const noteText = noteHasLink(cleanedNote) ? null : cleanedNote;
  const link = safeHttpUrl(unsubscribeUrl);
  const sentBy = `Bu ileti ${site} site yönetimi tarafından gönderildi. Bu ileti bir tanıtım iletisi değildir; site yönetiminin aidat/avans kayıtlarına ilişkin bilgilendirmesidir.`;
  let footerText = sentBy;
  let footerHtml = escapeHtml(sentBy);
  if (link) {
    const prompt =
      hasAccount !== false
        ? "Bu e-postaları durdurmak için uygulamadaki Bildirim Tercihleri'ni kullanabilir veya şu bağlantıdan çıkabilirsiniz (site duyuru ve borç hatırlatma e-postaları durdurulur):"
        : 'Bu e-postaları almak istemiyorsanız şu bağlantıdan çıkabilirsiniz (site duyuru ve borç hatırlatma e-postaları durdurulur):';
    footerText = `${sentBy} ${prompt} ${link}`;
    footerHtml = `${escapeHtml(sentBy)} ${escapeHtml(prompt)} <a href="${escapeHtml(link)}" style="color: #6b7280;">Abonelikten çık</a>`;
  } else if (hasAccount !== false) {
    footerText = `${sentBy} Bildirim tercihlerinizi uygulamadan değiştirebilirsiniz.`;
    footerHtml = escapeHtml(footerText);
  }
  const text = [greeting, '', subjectLine, '', amountText, '', closing, ...(noteText ? ['', `Yönetim notu: ${noteText}`] : []), '', '--', footerText].join('\n');
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <p style="color: #374151; font-size: 15px; margin: 0 0 12px 0;">${escapeHtml(greeting)}</p>
      <p style="color: #374151; font-size: 15px; line-height: 1.6; margin: 0 0 12px 0;">${escapeHtml(subjectLine)}</p>
      <p style="color: #111827; font-size: 15px; line-height: 1.6; margin: 0 0 12px 0;">${escapeHtml(amountText).replace(/\n/g, '<br />')}</p>
      <p style="color: #374151; font-size: 15px; line-height: 1.6; margin: 0 0 12px 0;">${escapeHtml(closing)}</p>
      ${noteText ? `<p style="color: #374151; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0;">Yönetim notu: ${escapeHtml(noteText)}</p>` : ''}
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; margin: 0;">${footerHtml}</p>
    </div>
  `;
  const message = { to: recipient, subject, text, html };
  if (link) {
    message.headers = { 'List-Unsubscribe': `<${link}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' };
  }
  return message;
}
