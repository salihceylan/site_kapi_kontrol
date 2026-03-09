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
  await transporter.sendMail({
    from,
    to,
    subject: 'AHBU e-posta dogrulama kodunuz',
    text: `Merhaba ${fullName}, AHBU dogrulama kodunuz: ${code}`,
    html: `
      <div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#1f2937">
        <p>Merhaba <strong>${fullName}</strong>,</p>
        <p>AHBU kaydinizi tamamlamak icin 4 haneli dogrulama kodunuz:</p>
        <p style="font-size:28px;font-weight:700;letter-spacing:8px">${code}</p>
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
  await transporter.sendMail({
    from,
    to,
    subject: 'AHBU daire giris bilgileriniz',
    text: `Merhaba ${residentName}, ${siteName} icindeki ${apartmentLabel} icin giris bilgileriniz: kullanici adi ${loginName}, PIN ${pinCode}`,
    html: `
      <div style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#1f2937">
        <p>Merhaba <strong>${residentName}</strong>,</p>
        <p><strong>${siteName}</strong> icindeki <strong>${apartmentLabel}</strong> icin AHBU giris bilgileriniz asagidadir:</p>
        <p><strong>Kullanici adi:</strong> ${loginName}</p>
        <p><strong>PIN:</strong> ${pinCode}</p>
        <p>Giris yaptiktan sonra gerekirse site yoneticinizden yeni sifre talep edebilirsiniz.</p>
      </div>
    `,
  });
}
