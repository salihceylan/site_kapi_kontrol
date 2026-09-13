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
    auth: {
      user,
      pass,
    },
  });
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export async function sendIndividualVerificationEmail({
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
    subject: 'AHBU e-posta doğrulama kodunuz',
    text: `Merhaba ${fullName}, AHBU doğrulama kodunuz: ${code}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
        <div style="text-align: center; margin-bottom: 20px;">
          <h2 style="color: #111827; margin: 0;">AHBU Kapı Kontrol</h2>
          <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Hesap Doğrulama</p>
        </div>
        <p style="color: #374151; font-size: 16px;">Merhaba <strong>${safeFullName}</strong>,</p>
        <p style="color: #4b5563; font-size: 15px; line-height: 1.5;">AHBU hesabınızı aktif hale getirmek ve site/kapı işlemlerinize başlayabilmek için 4 haneli doğrulama kodunuz:</p>
        <div style="text-align: center; margin: 28px 0;">
          <span style="display: inline-block; padding: 14px 28px; font-size: 32px; font-weight: 700; letter-spacing: 10px; color: #1e40af; background-color: #eff6ff; border: 2px dashed #3b82f6; border-radius: 8px;">${safeCode}</span>
        </div>
        <p style="color: #6b7280; font-size: 13px; text-align: center;">Bu kodu uygulamadaki doğrulama ekranına giriniz.</p>
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
    subject: 'AHBU e-posta dogrulama kodunuz',
    text: `Merhaba ${fullName}, AHBU dogrulama kodunuz: ${code}`,
    html: `
      <div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#1f2937">
        <p>Merhaba <strong>${safeFullName}</strong>,</p>
        <p>AHBU kaydinizi tamamlamak icin 4 haneli dogrulama kodunuz:</p>
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
    subject: 'AHBU daire giris bilgileriniz',
    text: `Merhaba ${residentName}, ${siteName} icindeki ${apartmentLabel} icin giris bilgileriniz: kullanici adi ${loginName}, PIN ${pinCode}`,
    html: `
      <div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#1f2937">
        <p>Merhaba <strong>${safeResidentName}</strong>,</p>
        <p><strong>${safeSiteName}</strong> icindeki <strong>${safeApartmentLabel}</strong> icin AHBU giris bilgileriniz asagidadir:</p>
        <p><strong>Kullanici adi:</strong> ${safeLoginName}</p>
        <p><strong>PIN:</strong> ${safePinCode}</p>
        <p>Giris yaptiktan sonra gerekirse site yoneticinizden yeni sifre talep edebilirsiniz.</p>
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
    subject: `[DİKKAT] ${siteName} Sitesi Kalıcı Silme Doğrulama Kodu`,
    text: `Merhaba ${fullName}, '${siteName}' sitesi ve bağlı tüm daire/kapı/kullanıcı kayıtları silinecektir. Silme doğrulama kodunuz: ${code}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 2px solid #ef4444; border-radius: 12px; background-color: #ffffff;">
        <div style="text-align: center; margin-bottom: 20px;">
          <h2 style="color: #dc2626; margin: 0;">⚠️ SİTE KALICI SİLME İŞLEMİ</h2>
          <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">AHBU Güvenlik Doğrulaması</p>
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

  const subject = `AHBU - ${siteName} Sitesi Yönetici Daveti`;
  const text = isExistingUser
    ? `Merhaba ${fullName || ''}, ${inviterName} sizi '${siteName}' sitesine Site Yöneticisi olarak ekledi. AHBU Kapı Kontrol uygulamasını açarak siteyi yönetmeye başlayabilirsiniz.`
    : `Merhaba ${fullName || ''}, ${inviterName} sizi '${siteName}' sitesine Site Yöneticisi olarak davet etti. AHBU Kapı Kontrol uygulamasını indirip bu e-posta adresiyle (${to}) kayıt olduğunuzda site yöneticiliği yetkiniz otomatik olarak tanımlanacaktır.`;

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
      <div style="text-align: center; margin-bottom: 20px;">
        <h2 style="color: #111827; margin: 0;">🏢 AHBU Kapı Kontrol</h2>
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
            AHBU Kapı Kontrol uygulamasını açarak siteyi, blokları, daireleri ve kapıları hemen yönetmeye başlayabilirsiniz.
          </p>
        </div>
        `
        : `
        <div style="padding: 16px; background-color: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; margin: 20px 0;">
          <p style="color: #1e40af; margin: 0; font-size: 14.5px; font-weight: 600;">
            📌 Nasıl Başlayabilirsiniz?
          </p>
          <p style="color: #1d4ed8; margin: 6px 0 0 0; font-size: 13.5px;">
            AHBU Kapı Kontrol uygulamasını açıp <strong>${escapeHtml(to)}</strong> e-posta adresiyle ücretsiz hesap oluşturup e-postanızı doğruladığınızda, '<strong>${safeSiteName}</strong>' sitesinin yöneticiliği otomatik olarak hesabınıza tanımlanacaktır.
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
