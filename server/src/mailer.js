import nodemailer from 'nodemailer';

function requiredEnv(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) {
    throw new Error(`${name} env degiskeni eksik.`);
  }
  return value;
}

function createTransporter() {
  const host = requiredEnv('SMTP_HOST');
  const port = Number(process.env.SMTP_PORT || 587);
  const user = requiredEnv('SMTP_USER');
  const pass = requiredEnv('SMTP_PASSWORD');

  return nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    requireTLS: port !== 465,
    // Sınırlı zaman aşımları: nodemailer varsayılanları dakikalarca sürebilir; askıda kalan bir SMTP
    // bağlantısı kayıt isteğini (ve istemciyi) o kadar bekletmesin, hata hızlıca ve dürüstçe dönsün.
    // dnsTimeout: ad çözümleme varsayılanı 30 sn'dir; DNS takılırsa bağlantı zaman aşımı hiç başlamaz (daire PIN'i e-postası
    // yanıtı ayrıca ~8 sn ile sınırlar, bkz. apartment_service.sendIssuedApartmentPin).
    dnsTimeout: 5_000,
    connectionTimeout: 8_000,
    greetingTimeout: 8_000,
    socketTimeout: 20_000,
    auth: {
      user,
      pass,
    },
  });
}

// "14:32" biçimi (24 saat, Türkiye saati). Kullanıcı birden fazla kod e-postası aldığında hangisinin
// en son istenen olduğunu e-postadaki saatten ayırt edebilir.
export function formatIstanbulTime(date) {
  return new Intl.DateTimeFormat('tr-TR', {
    timeZone: 'Europe/Istanbul',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(date);
}

// Kullanici/yonetici kontrollu metinler HTML sablonlarina girmeden once kacirilir.
// (Kontrol karakterleri de temizlenir; "javascript:" gibi URL'ler ayri olarak safeHttpUrl ile suzulur.)
export function escapeHtml(value) {
  return String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
    .replaceAll('`', '&#96;');
}

// E-posta konu satiri: satir sonu/kontrol karakterleri (header injection) temizlenir.
export function singleLine(value, maxLength = 200) {
  return String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

// href icin: yalnizca http/https baglantilari kabul edilir; digerleri bos doner.
// Site adı zaten "... Sitesi" / "... Site" ile bitiyorsa tekrar "Sitesi" ekleme ("Yeşilvadi Sitesi Sitesi" olmasın).
export function withSitesi(siteName) {
  const name = String(siteName ?? '').trim();
  return /site(si)?$/i.test(name) ? name : `${name} Sitesi`;
}

export function safeHttpUrl(value) {
  const text = String(value ?? '').trim();
  try {
    const url = new URL(text);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : '';
  } catch (_) {
    return '';
  }
}

export async function sendIndividualVerificationEmail({
  to,
  fullName,
  code,
  ttlMinutes,
  requestedAt = new Date(),
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeFullName = escapeHtml(fullName);
  const safeCode = escapeHtml(code);
  // E-posta gecikmeli ulaşabilir ve her yeni istek öncekini geçersiz kılar: istek saati ve süre açıkça yazılır.
  const requestedTime = formatIstanbulTime(requestedAt);
  const validityNote =
    `Bu kod ${requestedTime} saatinde istendi` +
    `${Number.isFinite(ttlMinutes) ? ` ve ${ttlMinutes} dakika geçerlidir` : ''}. ` +
    'Birden fazla e-posta aldıysanız yalnızca en son istenen kod geçerlidir.';
  await transporter.sendMail({
    from,
    to,
    subject: 'Site ve Toplu Yaşam Yönetim Sistemi - E-posta doğrulama kodunuz',
    text: `Merhaba ${fullName}, Site ve Toplu Yaşam Yönetim Sistemi doğrulama kodunuz: ${code}. ${validityNote}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
        <div style="text-align: center; margin-bottom: 20px;">
          <h2 style="color: #111827; margin: 0;">Site ve Toplu Yaşam Yönetim Sistemi</h2>
          <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Hesap Doğrulama</p>
        </div>
        <p style="color: #374151; font-size: 16px;">Merhaba <strong>${safeFullName}</strong>,</p>
        <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">Hesabınızı aktif hale getirmek ve site/kapı işlemlerinize başlayabilmek için doğrulama kodunuz:</p>
        <div style="text-align: center; margin: 28px 0;">
          <span style="display: inline-block; padding: 14px 28px; font-size: 32px; font-weight: 700; letter-spacing: 10px; color: #1e40af; background-color: #eff6ff; border: 2px dashed #3b82f6; border-radius: 8px;">${safeCode}</span>
        </div>
        <p style="color: #6b7280; font-size: 13px; text-align: center;">Bu kodu uygulamadaki doğrulama ekranına giriniz.</p>
        <p style="color: #6b7280; font-size: 13px; text-align: center;">${escapeHtml(validityNote)}</p>
        <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
        <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu işlemi siz başlatmadıysanız bu e-postayı dikkate almayınız.</p>
      </div>
    `,
  });
}

export async function sendSiteManagerVerificationEmail({
  to,
  fullName,
  code,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeFullName = escapeHtml(fullName);
  const safeCode = escapeHtml(code);
  await transporter.sendMail({
    from,
    to,
    subject: 'Site ve Toplu Yaşam Yönetim Sistemi - E-posta dogrulama kodunuz',
    text: `Merhaba ${fullName}, Site ve Toplu Yaşam Yönetim Sistemi dogrulama kodunuz: ${code}`,
    html: `
      <div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#1f2937">
        <p>Merhaba <strong>${safeFullName}</strong>,</p>
        <p>Site ve Toplu Yaşam Yönetim Sistemi kaydinizi tamamlamak icin dogrulama kodunuz:</p>
        <p style="font-size:28px;font-weight:700;letter-spacing:8px">${safeCode}</p>
        <p>Bu kod 10 dakika boyunca gecerlidir.</p>
      </div>
    `,
  });
}

export async function sendApartmentCredentialsEmail({
  to,
  residentName,
  apartmentLabel,
  siteName,
  loginName,
  pinCode,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeResidentName = escapeHtml(residentName);
  const safeApartmentLabel = escapeHtml(apartmentLabel);
  const safeSiteName = escapeHtml(siteName);
  const safeLoginName = escapeHtml(loginName);
  const safePinCode = escapeHtml(pinCode);
  await transporter.sendMail({
    from,
    to,
    subject: 'Site ve Toplu Yaşam Yönetim Sistemi - Daire giris bilgileriniz',
    text: `Merhaba ${residentName}, ${siteName} icindeki ${apartmentLabel} icin giris bilgileriniz: kullanici adi ${loginName}, PIN ${pinCode}. PIN sistemde okunabilir bicimde saklanmaz ve yeniden gonderilemez; unutursaniz site yonetiminden yeni PIN isteyin.`,
    html: `
      <div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#1f2937">
        <p>Merhaba <strong>${safeResidentName}</strong>,</p>
        <p><strong>${safeSiteName}</strong> icindeki <strong>${safeApartmentLabel}</strong> icin giris bilgileriniz asagidadir:</p>
        <p><strong>Kullanici adi:</strong> ${safeLoginName}</p>
        <p><strong>PIN:</strong> ${safePinCode}</p>
        <p>Bu PIN sistemde okunabilir bicimde saklanmaz ve yeniden gonderilemez. Giris yaptiktan sonra sifrenizi profilinizden degistirebilirsiniz; unutursaniz site yonetiminden yeni PIN isteyin.</p>
      </div>
    `,
  });
}

export async function sendSuperUserSiteDeletionEmail({
  to,
  fullName,
  siteName,
  code,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeFullName = escapeHtml(fullName);
  const safeSiteName = escapeHtml(siteName);
  const safeCode = escapeHtml(code);
  await transporter.sendMail({
    from,
    to,
    subject: singleLine(`[DİKKAT] ${withSitesi(siteName)} Kalıcı Silme Doğrulama Kodu`),
    text: `Merhaba ${fullName}, '${siteName}' sitesi ve bağlı tüm daire/kapı/kullanıcı kayıtları silinecektir. Silme doğrulama kodunuz: ${code}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 2px solid #ef4444; border-radius: 12px; background-color: #ffffff;">
        <div style="text-align: center; margin-bottom: 20px;">
          <h2 style="color: #dc2626; margin: 0;">⚠️ SİTE KALICI SİLME İŞLEMİ</h2>
          <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Site ve Toplu Yaşam Yönetim Sistemi Güvenlik Doğrulaması</p>
        </div>
        <p style="color: #374151; font-size: 16px;">Merhaba <strong>${safeFullName}</strong>,</p>
        <p style="color: #b91c1c; font-size: 15px; line-height: 1.5; font-weight: bold;">
          DİKKAT: '<strong>${safeSiteName}</strong>' sitesi ve siteye bağlı tüm daire kullanıcıları, kapılar, cihazlar ve yetkiler KALICI OLARAK silinecektir. Bu işlem geri alınamaz!
        </p>
        <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
          Siteyi ve tüm verilerini silmekten eminseniz aşağıdaki 6 haneli doğrulama kodunu uygulamadaki ekrana giriniz:
        </p>
        <div style="text-align: center; margin: 28px 0;">
          <span style="display: inline-block; padding: 14px 28px; font-size: 32px; font-weight: 800; letter-spacing: 8px; color: #dc2626; background-color: #fef2f2; border: 2px dashed #ef4444; border-radius: 8px;">${safeCode}</span>
        </div>
        <p style="color: #6b7280; font-size: 13px; text-align: center;">Bu kod 10 dakika boyunca geçerlidir.</p>
        <hr style="border: none; border-top: 1px solid #fee2e2; margin: 24px 0;" />
        <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu işlemi siz talep etmediyseniz lütfen derhal şifrenizi değiştiriniz ve sistem yöneticisiyle iletişime geçiniz.</p>
      </div>
    `,
  });
}

export async function sendSiteManagerInvitationEmail({
  to,
  fullName,
  siteName,
  inviterName,
  isExistingUser,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeFullName = escapeHtml(fullName || 'Kullanıcı');
  const safeSiteName = escapeHtml(siteName);
  const safeInviterName = escapeHtml(inviterName || 'Site Yönetimi');

  const subject = singleLine(`Site ve Toplu Yaşam Yönetim Sistemi - ${withSitesi(siteName)} Yönetici Daveti`);
  const text = isExistingUser
    ? `Merhaba ${fullName || ''}, ${inviterName} sizi '${siteName}' sitesine Site Yöneticisi olarak ekledi. Site ve Toplu Yaşam Yönetim Sistemi uygulamasını açarak siteyi yönetmeye başlayabilirsiniz.`
    : `Merhaba ${fullName || ''}, ${inviterName} sizi '${siteName}' sitesine Site Yöneticisi olarak davet etti. Site ve Toplu Yaşam Yönetim Sistemi uygulamasını indirip bu e-posta adresiyle (${to}) kayıt olduğunuzda site yöneticiliği yetkiniz otomatik olarak tanımlanacaktır.`;

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">🏢 Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Site Yöneticisi Daveti</p>
      </div>
      <p style="color: #374151; font-size: 16px;">Merhaba <strong>${safeFullName}</strong>,</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
        <strong>${safeInviterName}</strong>, sizi '<strong>${safeSiteName}</strong>' sitesine <strong>Site Yöneticisi</strong> olarak ${isExistingUser ? 'ekledi' : 'davet etti'}.
      </p>
      ${isExistingUser
        ? `
        <div style="padding: 16px; background-color: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; margin: 20px 0;">
          <p style="color: #166534; margin: 0; font-size: 14.5px; font-weight: 600;">
            ✓ Hesabınız zaten mevcut olduğu için yöneticilik yetkiniz anında tanımlandı!
          </p>
          <p style="color: #15803d; margin: 6px 0 0 0; font-size: 13.5px;">
            Site ve Toplu Yaşam Yönetim Sistemi uygulamasını açarak siteyi, blokları, daireleri ve kapıları hemen yönetmeye başlayabilirsiniz.
          </p>
        </div>
        `
        : `
        <div style="padding: 16px; background-color: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; margin: 20px 0;">
          <p style="color: #1e40af; margin: 0; font-size: 14.5px; font-weight: 600;">
            📌 Nasıl Başlayabilirsiniz?
          </p>
          <p style="color: #1d4ed8; margin: 6px 0 0 0; font-size: 13.5px;">
            Site ve Toplu Yaşam Yönetim Sistemi uygulamasını açıp <strong>${escapeHtml(to)}</strong> e-posta adresiyle ücretsiz hesap oluşturup e-postanızı doğruladığınızda, '<strong>${safeSiteName}</strong>' sitesinin yöneticiliği otomatik olarak hesabınıza tanımlanacaktır.
          </p>
        </div>
        `
      }
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu daveti siz beklemiyorsanız bu e-postayı dikkate almayabilirsiniz.</p>
    </div>
  `;

  await transporter.sendMail({
    from,
    to,
    subject,
    text,
    html,
  });
}

export async function sendJoinRequestNotificationEmail({
  to,
  managerName,
  siteName,
  blockName,
  unitLabel,
  applicantName,
  applicantEmail,
  notes,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeManagerName = escapeHtml(managerName || 'Site Yöneticisi');
  const safeSiteName = escapeHtml(siteName);
  const blockPart = blockName ? `${blockName} ` : '';
  const safeApplicantName = escapeHtml(applicantName || 'Sakin');
  const safeApplicantEmail = escapeHtml(applicantEmail || '');
  const safeNotes = notes ? escapeHtml(notes) : null;

  // targetFlat HTML'e girer (kacirilmis), plainTargetFlat konu/duz metinde kullanilir (cift kacirma olmasin).
  const plainTargetFlat = `${blockPart}Daire ${unitLabel ?? ''}`.trim();
  const targetFlat = escapeHtml(plainTargetFlat);
  const subject = singleLine(`Site ve Toplu Yaşam Yönetim Sistemi - Yeni Daire Katılım Başvurusu (${siteName} - ${plainTargetFlat})`);
  const text = `Merhaba ${managerName || 'Site Yöneticisi'}, '${siteName}' sitesi ${plainTargetFlat} için yeni bir katılım başvurusu yapıldı. Başvuran: ${applicantName} (${applicantEmail}). Site ve Toplu Yaşam Yönetim Sistemi uygulamasından başvuruyu onaylayabilir veya reddedebilirsiniz.`;

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">🏢 Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Yeni Sakin Katılım Başvurusu</p>
      </div>
      <p style="color: #374151; font-size: 16px;">Merhaba <strong>${safeManagerName}</strong>,</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
        '<strong>${safeSiteName}</strong>' sitenizdeki <strong>${targetFlat}</strong> için yeni bir sakin katılım başvurusu oluşturuldu.
      </p>
      <div style="padding: 16px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin: 20px 0;">
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Başvuran Kişi:</strong> ${safeApplicantName}</p>
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>E-posta:</strong> ${safeApplicantEmail}</p>
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Hedef Daire:</strong> ${targetFlat}</p>
        ${safeNotes ? `<p style="color: #334155; margin: 0; font-size: 14px;"><strong>Başvuru Notu:</strong> <em>"${safeNotes}"</em></p>` : ''}
      </div>
      <div style="padding: 14px; background-color: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; margin: 20px 0;">
        <p style="color: #166534; margin: 0; font-size: 13.5px;">
          ✓ <strong>Ne Yapmalısınız?</strong><br/>
          Site ve Toplu Yaşam Yönetim Sistemi mobil uygulamasını açarak ilgili sitenizin <strong>Katılım Başvuruları</strong> veya <strong>Sakin Listesi</strong> ekranından başvuruyu inceleyip tek tıkla onaylayabilir veya reddedebilirsiniz.
        </p>
      </div>
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu bilgilendirme e-postası Site ve Toplu Yaşam Yönetim Sistemi tarafından otomatik olarak gönderilmiştir.</p>
    </div>
  `;

  await transporter.sendMail({
    from,
    to,
    subject,
    text,
    html,
  });
}

export async function sendPasswordResetEmail({
  to,
  fullName,
  resetUrl,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeFullName = escapeHtml(fullName || 'Kullanıcı');
  const safeResetUrl = escapeHtml(safeHttpUrl(resetUrl));

  const subject = 'Site ve Toplu Yaşam Yönetim Sistemi - Şifre Sıfırlama Bağlantısı';
  const text = `Merhaba ${fullName || 'Kullanıcı'}, hesabınız için şifre sıfırlama talebinde bulundunuz. Şifrenizi sıfırlamak için bağlantı: ${resetUrl} (Bu bağlantı 30 dakika boyunca geçerlidir.)`;

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e2e8f0; border-radius: 14px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 24px;">
        <h2 style="color: #0f172a; margin: 0; font-size: 22px;">🔐 Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #64748b; font-size: 14px; margin-top: 6px;">Şifre Sıfırlama Talebi</p>
      </div>
      <p style="color: #334155; font-size: 16px;">Merhaba <strong>${safeFullName}</strong>,</p>
      <p style="color: #475569; font-size: 15px; line-height: 1.6;">
        Site ve Toplu Yaşam Yönetim Sistemi hesabınız için bir şifre sıfırlama talebinde bulundunuz. Yeni bir şifre belirlemek için aşağıdaki butona tıklayınız:
      </p>
      <div style="text-align: center; margin: 32px 0;">
        <a href="${safeResetUrl}" style="display: inline-block; padding: 14px 32px; font-size: 16px; font-weight: bold; color: #ffffff; background: linear-gradient(135deg, #2563eb, #1d4ed8); text-decoration: none; border-radius: 10px; box-shadow: 0 4px 12px rgba(37, 99, 235, 0.35);">
          Şifremi Sıfırla
        </a>
      </div>
      <div style="padding: 14px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 20px;">
        <p style="color: #64748b; font-size: 12.5px; margin: 0 0 6px 0;">
          Buton çalışmıyorsa aşağıdaki bağlantıyı tarayıcınıza kopyalayabilirsiniz:
        </p>
        <p style="color: #2563eb; font-size: 12px; word-break: break-all; margin: 0;">
          <a href="${safeResetUrl}" style="color: #2563eb;">${safeResetUrl}</a>
        </p>
      </div>
      <p style="color: #94a3b8; font-size: 13px; line-height: 1.5;">
        ⏱️ Bu bağlantı <strong>30 dakika</strong> boyunca geçerlidir ve güvenlik amacıyla yalnızca bir kez kullanılabilir.
      </p>
      <hr style="border: none; border-top: 1px solid #f1f5f9; margin: 20px 0;" />
      <p style="color: #94a3b8; font-size: 12px; text-align: center; margin: 0;">
        Bu talebi siz yapmadıysanız lütfen bu e-postayı dikkate almayınız. Mevcut şifreniz güvenle korunmaktadır.
      </p>
    </div>
  `;

  await transporter.sendMail({
    from,
    to,
    subject,
    text,
    html,
  });
}

/**
 * Yeni modül talebi bildirimi (site yöneticisi -> sistem yöneticisi/süper kullanıcı).
 * Konu SABİTTİR (kullanıcı verisi içermez); site, modül, isteyen ve not gövdeye yazılır (HTML'de kaçırılır).
 */
export const MODULE_REQUEST_EMAIL_SUBJECT = 'Site ve Toplu Yaşam Yönetim Sistemi - Yeni Modül Talebi';

export async function sendModuleRequestNotificationEmail({
  to,
  fullName,
  siteName,
  moduleName,
  requesterName,
  note,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const safeFullName = escapeHtml(fullName || 'Sistem Yöneticisi');
  const safeSiteName = escapeHtml(siteName);
  const safeModuleName = escapeHtml(moduleName);
  const safeRequesterName = escapeHtml(requesterName || 'Site Yöneticisi');
  const noteText = String(note ?? '').trim();
  const safeNote = noteText ? escapeHtml(noteText) : null;

  const text =
    `Merhaba ${fullName || 'Sistem Yöneticisi'}, '${siteName}' sitesinin yöneticisi ${requesterName || 'Site Yöneticisi'} ` +
    `"${moduleName}" modülünü talep etti.${noteText ? ` Not: ${noteText}` : ''} ` +
    'Talebi uygulamadaki Modül Talepleri ekranından onaylayabilir veya reddedebilirsiniz.';

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">🧩 Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Yeni Modül Talebi</p>
      </div>
      <p style="color: #374151; font-size: 16px;">Merhaba <strong>${safeFullName}</strong>,</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
        '<strong>${safeSiteName}</strong>' sitesinin yöneticisi için yeni bir modül talebi oluşturuldu.
      </p>
      <div style="padding: 16px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin: 20px 0;">
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Site:</strong> ${safeSiteName}</p>
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Modül:</strong> ${safeModuleName}</p>
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>İsteyen:</strong> ${safeRequesterName}</p>
        ${safeNote ? `<p style="color: #334155; margin: 0; font-size: 14px;"><strong>Not:</strong> <em>"${safeNote}"</em></p>` : ''}
      </div>
      <p style="color: #4b5563; font-size: 14px; line-height: 1.5;">
        Talebi uygulamadaki <strong>Modül Talepleri</strong> ekranından onaylayabilir veya reddedebilirsiniz.
      </p>
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu bilgilendirme e-postası Site ve Toplu Yaşam Yönetim Sistemi tarafından otomatik olarak gönderilmiştir.</p>
    </div>
  `;

  await transporter.sendMail({
    from,
    to,
    subject: MODULE_REQUEST_EMAIL_SUBJECT,
    text,
    html,
  });
}

/**
 * Yeni site başvurusu bildirimi (bireysel kullanıcı -> sistem yöneticisi/süper kullanıcı). Konu SABİTTİR (kullanıcı verisi içermez: başlık
 * satır sonu enjeksiyonu olmaz); site adı, başvuran adı ve not gövdeye yazılır (HTML'de kaçırılır, düz metinde tek satıra indirilir).
 * Başvuranın e-posta adresi / telefonu e-postaya YAZILMAZ (süper kullanıcı bunları yalnız uygulamadaki başvuru ayrıntısında görür).
 */
export const SITE_APPLICATION_EMAIL_SUBJECT = 'Site ve Toplu Yaşam Yönetim Sistemi - Yeni Site Başvurusu';

export async function sendSiteApplicationNotificationEmail({
  to,
  fullName,
  siteName,
  applicantName,
  blockCount,
  apartmentCount,
  doorCount,
  note,
}) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const recipientName = singleLine(fullName, 120) || 'Sistem Yöneticisi';
  const site = singleLine(siteName, 200);
  const applicant = singleLine(applicantName, 120) || 'Bir kullanıcı';
  const noteText = String(note ?? '').trim();
  const sizeText = `${Number(blockCount) || 0} blok, ${Number(apartmentCount) || 0} daire, ${Number(doorCount) || 0} kapı`;

  const text =
    `Merhaba ${recipientName}, ${applicant} '${site}' adlı bir site kurmak için başvurdu (${sizeText}).` +
    `${noteText ? ` Not: ${noteText}` : ''} ` +
    'Başvuruyu uygulamadaki Site Başvuruları ekranından onaylayabilir veya reddedebilirsiniz.';

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Yeni Site Başvurusu</p>
      </div>
      <p style="color: #374151; font-size: 16px;">Merhaba <strong>${escapeHtml(recipientName)}</strong>,</p>
      <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
        Site yöneticisi olmak isteyen bir kullanıcı yeni bir site başvurusu yaptı.
      </p>
      <div style="padding: 16px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin: 20px 0;">
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Site:</strong> ${escapeHtml(site)}</p>
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Başvuran:</strong> ${escapeHtml(applicant)}</p>
        <p style="color: #334155; margin: 0 0 8px 0; font-size: 14px;"><strong>Boyut:</strong> ${escapeHtml(sizeText)}</p>
        ${noteText ? `<p style="color: #334155; margin: 0; font-size: 14px; white-space: pre-line;"><strong>Not:</strong> <em>"${escapeHtml(noteText)}"</em></p>` : ''}
      </div>
      <p style="color: #4b5563; font-size: 14px; line-height: 1.5;">
        Başvuruyu uygulamadaki <strong>Site Başvuruları</strong> ekranından onaylayabilir veya reddedebilirsiniz.
      </p>
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu bilgilendirme e-postası Site ve Toplu Yaşam Yönetim Sistemi tarafından otomatik olarak gönderilmiştir.</p>
    </div>
  `;

  await transporter.sendMail({
    from,
    to,
    subject: SITE_APPLICATION_EMAIL_SUBJECT,
    text,
    html,
  });
}

/**
 * Site başvurusu karar bildirimi (süper kullanıcı -> başvuran). Konu karara göre SABİTTİR (kullanıcı verisi içermez).
 * Onay: "site yöneticisi oldunuz, uygulamayı yenileyin"; red: gerekçe (varsa) ve yeniden başvurma bilgisi. Gerekçe HTML'de kaçırılır.
 */
export const SITE_APPLICATION_APPROVED_SUBJECT = 'Site ve Toplu Yaşam Yönetim Sistemi - Site Başvurunuz Onaylandı';
export const SITE_APPLICATION_REJECTED_SUBJECT = 'Site ve Toplu Yaşam Yönetim Sistemi - Site Başvurunuz Reddedildi';

export async function sendSiteApplicationDecisionEmail({ to, fullName, siteName, approved, reason }) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }

  const transporter = createTransporter();
  const recipientName = singleLine(fullName, 120) || 'Kullanıcı';
  const site = singleLine(siteName, 200);
  const isApproved = approved === true;
  const reasonText = isApproved ? '' : String(reason ?? '').trim();

  const text = isApproved
    ? `Merhaba ${recipientName}, '${site}' sitesi için yaptığınız başvuru onaylandı. Artık site yöneticisisiniz. ` +
      'Uygulamayı yenileyin (kapatıp yeniden açın) ve yönetici ekranlarını kullanmaya başlayın.'
    : `Merhaba ${recipientName}, '${site}' sitesi için yaptığınız başvuru reddedildi.` +
      `${reasonText ? ` Gerekçe: ${reasonText}` : ''} ` +
      'Bilgileri düzenleyerek uygulamadan yeniden başvurabilirsiniz.';

  const headline = isApproved ? 'Site Başvurunuz Onaylandı' : 'Site Başvurunuz Reddedildi';
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">${headline}</p>
      </div>
      <p style="color: #374151; font-size: 16px;">Merhaba <strong>${escapeHtml(recipientName)}</strong>,</p>
      ${
        isApproved
          ? `<p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
        '<strong>${escapeHtml(site)}</strong>' sitesi için yaptığınız başvuru <strong>onaylandı</strong>. Artık site yöneticisisiniz.
      </p>
      <p style="color: #4b5563; font-size: 14px; line-height: 1.5;">
        Uygulamayı yenileyin (kapatıp yeniden açın) ve yönetici ekranlarını kullanmaya başlayın.
      </p>`
          : `<p style="color: #4b5563; font-size: 15px; line-height: 1.5;">
        '<strong>${escapeHtml(site)}</strong>' sitesi için yaptığınız başvuru <strong>reddedildi</strong>.
      </p>
      ${reasonText ? `<div style="padding: 16px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin: 20px 0; white-space: pre-line; color: #334155; font-size: 14px;"><strong>Gerekçe:</strong> <em>"${escapeHtml(reasonText)}"</em></div>` : ''}
      <p style="color: #4b5563; font-size: 14px; line-height: 1.5;">
        Bilgileri düzenleyerek uygulamadan yeniden başvurabilirsiniz.
      </p>`
      }
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu bilgilendirme e-postası Site ve Toplu Yaşam Yönetim Sistemi tarafından otomatik olarak gönderilmiştir.</p>
    </div>
  `;

  await transporter.sendMail({
    from,
    to,
    subject: isApproved ? SITE_APPLICATION_APPROVED_SUBJECT : SITE_APPLICATION_REJECTED_SUBJECT,
    text,
    html,
  });
}

/**
 * SMTP yapılandırılmış mı (sunucu, kullanıcı, parola ve gönderen adresi dolu). Duyuru e-posta kuyruğu yapılandırma yokken satırları
 * dürüstçe 'failed' yapar (sessiz kayıp yok).
 */
export function isSmtpConfigured(env = process.env) {
  const filled = (name) => String(env[name] ?? '').trim() !== '';
  return filled('SMTP_HOST') && filled('SMTP_USER') && filled('SMTP_PASSWORD') && (filled('SMTP_FROM') || filled('SMTP_USER'));
}

/**
 * Kişiyi uygulamaya davet e-postası (058). `acceptUrl` tek kullanımlık belirteç içerir; günlüğe yazılmaz, yöneticiye dönmez.
 * Bağlantı 7 gün geçerlidir.
 */
export async function sendPersonInvitationEmail({ to, fullName, siteName, inviterName, acceptUrl }) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }
  const transporter = createTransporter();
  const safeUrl = escapeHtml(safeHttpUrl(acceptUrl));
  const safeSite = escapeHtml(siteName);
  const subject = singleLine(`Site ve Toplu Yaşam Yönetim Sistemi - ${withSitesi(siteName)} Uygulama Daveti`);
  const text = `Merhaba ${fullName || ''}, ${inviterName || 'Site yönetimi'} sizi '${siteName}' sitesinin uygulamasına davet etti. Hesabınızı oluşturmak için bağlantı: ${acceptUrl} (7 gün geçerli, bir kez kullanılabilir.) Daveti beklemiyorsanız bu e-postayı dikkate almayın.`;
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e2e8f0; border-radius: 14px; background-color: #ffffff;">
      <h2 style="color: #0f172a; margin: 0 0 12px 0;">Uygulamaya davet</h2>
      <p style="color: #334155; font-size: 16px;">Merhaba <strong>${escapeHtml(fullName || '')}</strong>,</p>
      <p style="color: #475569; font-size: 15px; line-height: 1.6;"><strong>${escapeHtml(inviterName || 'Site yönetimi')}</strong>, sizi '<strong>${safeSite}</strong>' sitesinin uygulamasına davet etti.</p>
      <p style="text-align: center; margin: 28px 0;"><a href="${safeUrl}" style="display: inline-block; padding: 14px 28px; font-weight: bold; color: #ffffff; background: #2563eb; text-decoration: none; border-radius: 10px;">Hesabımı oluştur</a></p>
      <p style="color: #94a3b8; font-size: 13px;">Bağlantı 7 gün geçerlidir ve yalnızca bir kez kullanılabilir. Daveti beklemiyorsanız bu e-postayı dikkate almayın.</p>
    </div>
  `;
  await transporter.sendMail({ from, to, subject, text, html });
}

// Tek, düz adres: virgül/noktalı virgül/boşluk/açılı ayraç yok (alıcı listesi enjeksiyonu: "a@x.com, b@y.com" gönderilmez).
const ANNOUNCEMENT_RECIPIENT_PATTERN = /^[^\s@,;<>"()]+@[^\s@,;<>"()]+\.[^\s@,;<>"()]+$/;

/**
 * Duyuru e-postasını (konu, düz metin, HTML, başlıklar) hazırlar; ağ kullanmaz. Konu `[Site Adı] Başlık` (acil: `ACİL: ` öneki); başlık,
 * site adı ve alıcı satır başı enjeksiyonuna (CRLF) karşı temizlenir; gövde düz yazıdır, HTML'de kaçırılır ve satır sonları korunur.
 * Geçersiz alıcı adresi { code: 'INVALID_RECIPIENT' } hatası verir.
 *
 * Altbilgi alıcı türüne göre doğrudur: hesabı olan alıcıya uygulamadaki Bildirim Tercihleri VE abonelikten çık bağlantısı (acil duyuru
 * tercihten bağımsızdır, bağlantı acil dahil her şeyi durdurur - metin bunu söyler); hesapsız alıcıya (uygulaması yok) abonelikten çık bağlantısı. `unsubscribeUrl` (http/https) verilirse RFC 8058 uyumlu `List-Unsubscribe` ve
 * `List-Unsubscribe-Post: List-Unsubscribe=One-Click` başlıkları HER alıcıya eklenir.
 */
export function buildAnnouncementEmail({ to, siteName, title, body, importance, hasAccount = true, unsubscribeUrl = null, attachmentCount = 0 }) {
  const recipient = String(to ?? '').trim();
  if (recipient.length > 254 || !ANNOUNCEMENT_RECIPIENT_PATTERN.test(recipient)) {
    const error = new Error('Gecersiz alici adresi.');
    error.code = 'INVALID_RECIPIENT';
    throw error;
  }
  const urgent = importance === 'urgent';
  const site = singleLine(siteName, 120) || 'Site';
  const titleText = singleLine(title, 200);
  const subject = singleLine(`${urgent ? 'ACİL: ' : ''}[${site}] ${titleText}`);
  const bodyText = String(body ?? '')
    .replace(/\r\n?/g, '\n')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '')
    .trim();
  // Belgeler (Faz 3b-A): E-postaya dosya EKLENMEZ (kişisel veri SMTP'ye çıkmasın); yalnız ek sayısı bildirilir.
  const attachments = Math.max(0, Math.floor(Number(attachmentCount) || 0));
  const attachmentNote = attachments > 0 ? `Bu duyurunun ${attachments} eki var; uygulamadan görüntüleyin.` : '';
  const link = safeHttpUrl(unsubscribeUrl);
  const sentBy = `Bu e-posta ${site} yönetimi tarafından gönderildi.`;
  let footerText = sentBy;
  let footerHtml = escapeHtml(sentBy);
  if (hasAccount !== false && link) {
    // Hesaplı alıcı: uygulamadaki tercih (acil duyuru hariç) VEYA bağlantı (acil dahil HER ŞEYİ durdurur) - ikisi de dürüstçe anlatılır
    const note = 'Acil duyurular uygulamadaki tercihten bağımsız gönderilir; bağlantıdan çıkış acil duyurular dahil tüm duyuru e-postalarını durdurur.';
    const prompt = "Bu e-postaları durdurmak için uygulamadaki Bildirim Tercihleri'ni kullanabilir veya şu bağlantıdan çıkabilirsiniz:";
    footerText = `${sentBy} ${note} ${prompt} ${link}`;
    footerHtml = `${escapeHtml(sentBy)} ${escapeHtml(note)} ${escapeHtml(prompt)} <a href="${escapeHtml(link)}" style="color: #6b7280;">Abonelikten çık</a>`;
  } else if (hasAccount !== false) {
    footerText = `${sentBy} Bildirim tercihlerinizi uygulamadan değiştirebilirsiniz.`;
    footerHtml = escapeHtml(footerText);
  } else if (link) {
    const prompt = 'Bu e-postaları almak istemiyorsanız şu bağlantıdan çıkabilirsiniz:';
    footerText = `${sentBy} ${prompt} ${link}`;
    footerHtml = `${escapeHtml(sentBy)} ${escapeHtml(prompt)} <a href="${escapeHtml(link)}" style="color: #6b7280;">Abonelikten çık</a>`;
  }
  const text = `${urgent ? 'ACİL DUYURU\n\n' : ''}${titleText}\n\n${bodyText}${attachmentNote ? `\n\n${attachmentNote}` : ''}\n\n--\n${footerText}`;
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      ${urgent ? '<p style="color: #b91c1c; font-size: 13px; font-weight: 700; letter-spacing: 1px; margin: 0 0 8px 0;">ACİL DUYURU</p>' : ''}
      <h2 style="color: #111827; margin: 0 0 16px 0; font-size: 20px;">${escapeHtml(titleText)}</h2>
      <div style="color: #374151; font-size: 15px; line-height: 1.6;">${escapeHtml(bodyText).replace(/\n/g, '<br />')}</div>
      ${attachmentNote ? `<p style="color: #374151; font-size: 14px; font-weight: 700; margin: 16px 0 0 0;">${escapeHtml(attachmentNote)}</p>` : ''}
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

/** Site yönetiminin duyurusunu bir sakine e-postayla gönderir (düz yazı; HTML kaçırılır). Kuyruk işçisi çağırır; SMTP'yi yavaş varsayar. */
export async function sendAnnouncementEmail({ to, siteName, title, body, importance, hasAccount, unsubscribeUrl, attachmentCount }) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }
  const message = buildAnnouncementEmail({ to, siteName, title, body, importance, hasAccount, unsubscribeUrl, attachmentCount });
  const transporter = createTransporter();
  await transporter.sendMail({ from, ...message });
}

/**
 * Hazırlanmış bir iletiyi ({ to, subject, text, html, headers? }) gönderir. İçeriği çağıran (örn. finans borç hatırlatma şablonu) üretir ve doğrular;
 * burada yalnız gönderen adresi + taşıyıcı bulunur. SMTP'yi yavaş varsayar (kuyruk işçisi çağırır).
 */
export async function sendPreparedEmail(message) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }
  const transporter = createTransporter();
  await transporter.sendMail({ from, ...message });
}

/**
 * Hesap silme bildirimi (kullanıcı -> ESKİ e-posta adresi). Konu SABİTTİR (kullanıcı verisi içermez); ad HTML'de kaçırılır, düz metinde tek satıra indirilir.
 * Silme işlemi bu gönderimden BAĞIMSIZDIR (gönderim hatası silmeyi geri almaz); çağıran hata ayrıntısını / adresi log'a yazmaz.
 */
export const ACCOUNT_DELETED_SUBJECT = 'Site ve Toplu Yaşam Yönetim Sistemi - Hesabınız Silindi';

export async function sendAccountDeletedEmail({ to, fullName, deletedAt = new Date() }) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }
  const transporter = createTransporter();
  const recipientName = singleLine(fullName, 120) || 'Kullanıcı';
  const when = new Intl.DateTimeFormat('tr-TR', { timeZone: 'Europe/Istanbul', dateStyle: 'long', timeStyle: 'short' }).format(deletedAt);
  const lines = [
    `Hesabınız ${when} tarihinde, sizin isteğinizle silindi.`,
    'Adınız, e-posta adresiniz, telefon numaranız ve parolanız sistemden kaldırıldı; site ve daire üyelikleriniz ile kapı erişim yetkileriniz sona erdi.',
    'Yasal saklama yükümlülükleri nedeniyle site yönetiminin tuttuğu bazı kayıtlar (ör. aidat ve ekstre kayıtları) kimliksizleştirilerek saklanabilir.',
    'Bu işlemi siz yapmadıysanız lütfen en kısa sürede destek ekibiyle iletişime geçin.',
    'İsterseniz aynı e-posta adresiyle daha sonra yeniden kayıt olabilirsiniz; eski verileriniz geri gelmez.',
  ];
  const text = `Merhaba ${recipientName},\n\n${lines.join('\n\n')}`;
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">Site ve Toplu Yaşam Yönetim Sistemi</h2>
        <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Hesabınız Silindi</p>
      </div>
      <p style="color: #374151; font-size: 16px;">Merhaba <strong>${escapeHtml(recipientName)}</strong>,</p>
      ${lines.map((line) => `<p style="color: #4b5563; font-size: 14px; line-height: 1.5;">${escapeHtml(line)}</p>`).join('\n      ')}
      <hr style="border: none; border-top: 1px solid #f3f4f6; margin: 24px 0;" />
      <p style="color: #9ca3af; font-size: 12px; text-align: center; margin: 0;">Bu bilgilendirme e-postası Site ve Toplu Yaşam Yönetim Sistemi tarafından otomatik olarak gönderilmiştir.</p>
    </div>
  `;
  await transporter.sendMail({ from, to, subject: ACCOUNT_DELETED_SUBJECT, text, html });
}

// Kargo geldi bildirimi (063): kisa, kargo firmasi/ad icermez.
export async function sendCargoArrivedEmail({ to, name, siteName, apartmentLabel }) {
  const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
  if (!from) {
    throw new Error('SMTP_FROM veya SMTP_USER env degiskeni eksik.');
  }
  const transporter = createTransporter();
  const subject = singleLine(`Kargo geldi - ${siteName} (${apartmentLabel})`);
  const text = `Merhaba ${name || ''}, ${siteName} sitesinde ${apartmentLabel} için bir kargo geldi. Teslim almak için görevliye uğrayabilirsiniz.`;
  const html = `<div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px;">
    <h2 style="color: #111827;">Kargo geldi</h2>
    <p style="color: #374151;">Merhaba <strong>${escapeHtml(name || '')}</strong>,</p>
    <p style="color: #4b5563;"><strong>${escapeHtml(siteName)}</strong> sitesinde <strong>${escapeHtml(apartmentLabel)}</strong> için bir kargo geldi. Teslim almak için görevliye uğrayabilirsiniz.</p>
  </div>`;
  await transporter.sendMail({ from, to, subject, text, html });
}
