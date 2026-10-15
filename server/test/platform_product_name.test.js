// Urun adi (Faz 1.1): platformun adi "Site ve Toplu Yasam Yonetim Sistemi"; AHBU yalnizca Gecis Kontrol (kapi) modulunun adi.
// E-posta konu/baslik/imza/metinleri ve sifre sifirlama sayfalari yeni adi tasir; kapi modulu adlari DEGISMEZ.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import nodemailer from 'nodemailer';
import { pool } from '../src/db.js';
import {
  MODULE_REQUEST_EMAIL_SUBJECT,
  sendApartmentCredentialsEmail,
  sendIndividualVerificationEmail,
  sendJoinRequestNotificationEmail,
  sendModuleRequestNotificationEmail,
  sendPasswordResetEmail,
  sendSiteManagerInvitationEmail,
  sendSiteManagerVerificationEmail,
  sendSuperUserSiteDeletionEmail,
} from '../src/mailer.js';
import { authRouter } from '../src/routes/auth_routes.js';

const PRODUCT = 'Site ve Toplu Yaşam Yönetim Sistemi';
const here = path.dirname(fileURLToPath(import.meta.url));
const srcRoot = path.join(here, '..', 'src');
const read = (relative) => readFileSync(path.join(srcRoot, relative), 'utf8').replace(/\r\n/g, '\n');

// ---------------------------------------------------------------------------
// E-postalar
// ---------------------------------------------------------------------------

describe('urun adi: e-posta konu / baslik / metinleri', () => {
  const sent = [];
  const saved = {};
  const originalCreateTransport = nodemailer.createTransport;

  beforeEach(() => {
    sent.length = 0;
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) {
      saved[name] = process.env[name];
    }
    process.env.SMTP_HOST = 'smtp.invalid';
    process.env.SMTP_USER = 'user@example.invalid';
    process.env.SMTP_PASSWORD = 'test-only';
    process.env.SMTP_FROM = 'Sistem <noreply@example.invalid>';
    delete process.env.SMTP_PORT;
    nodemailer.createTransport = () => ({
      sendMail: async (message) => {
        sent.push(message);
      },
    });
  });

  afterEach(() => {
    nodemailer.createTransport = originalCreateTransport;
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  const noAhbu = (message) => {
    for (const field of ['subject', 'text', 'html']) {
      assert.equal(/AHBU/i.test(String(message[field] ?? '')), false, `${field} AHBU iceriyor: ${message[field]}`);
    }
  };

  it('e-posta dogrulama kodu (bireysel): konu, metin ve baslik yeni ad; "AHBU hesabiniz" -> "Hesabiniz"', async () => {
    await sendIndividualVerificationEmail({ to: 'a@example.com', fullName: 'Ali', code: '123456', ttlMinutes: 30 });
    const [message] = sent;
    assert.equal(message.subject, `${PRODUCT} - E-posta doğrulama kodunuz`);
    assert.match(message.text, new RegExp(`^Merhaba Ali, ${PRODUCT} doğrulama kodunuz: 123456\\.`));
    assert.match(message.html, new RegExp(`<h2 style="color: #111827; margin: 0;">${PRODUCT}</h2>`));
    assert.match(message.html, />Hesabınızı aktif hale getirmek/);
    noAhbu(message);
  });

  it('e-posta dogrulama kodu (site yoneticisi)', async () => {
    await sendSiteManagerVerificationEmail({ to: 'a@example.com', fullName: 'Ali', code: '654321' });
    const [message] = sent;
    assert.equal(message.subject, `${PRODUCT} - E-posta dogrulama kodunuz`);
    assert.match(message.text, new RegExp(`${PRODUCT} dogrulama kodunuz: 654321`));
    assert.match(message.html, new RegExp(`<p>${PRODUCT} kaydinizi tamamlamak icin dogrulama kodunuz:</p>`));
    noAhbu(message);
  });

  it('daire giris bilgileri', async () => {
    await sendApartmentCredentialsEmail({
      to: 'a@example.com',
      residentName: 'Ali',
      apartmentLabel: 'A Blok Daire 5',
      siteName: 'Gül Sitesi',
      loginName: 'ali.5',
      pinCode: '1234',
    });
    const [message] = sent;
    assert.equal(message.subject, `${PRODUCT} - Daire giris bilgileriniz`);
    assert.match(message.html, /icin giris bilgileriniz asagidadir/);
    noAhbu(message);
  });

  it('site kalici silme dogrulama kodu', async () => {
    await sendSuperUserSiteDeletionEmail({ to: 's@example.com', fullName: 'Süper', siteName: 'Gül Sitesi', code: '111222' });
    const [message] = sent;
    assert.match(message.html, new RegExp(`${PRODUCT} Güvenlik Doğrulaması`));
    assert.match(message.subject, /Kalıcı Silme Doğrulama Kodu/);
    noAhbu(message);
  });

  it('yonetici daveti (mevcut ve yeni kullanici): konu "<ad> - ... Yonetici Daveti", metinde "<ad> uygulamasini"', async () => {
    await sendSiteManagerInvitationEmail({ to: 'a@example.com', fullName: 'Ali', siteName: 'Gül', inviterName: 'Veli', isExistingUser: true });
    await sendSiteManagerInvitationEmail({ to: 'b@example.com', fullName: 'Ayşe', siteName: 'Gül', inviterName: 'Veli', isExistingUser: false });
    assert.equal(sent.length, 2);
    for (const message of sent) {
      assert.equal(message.subject, `${PRODUCT} - Gül Sitesi Yönetici Daveti`);
      assert.match(message.text, new RegExp(`${PRODUCT} uygulamasını`));
      assert.match(message.html, new RegExp(`🏢 ${PRODUCT}</h2>`));
      assert.match(message.html, new RegExp(`${PRODUCT} uygulamasını`));
      noAhbu(message);
    }
  });

  it('daire katilim basvurusu bildirimi: konu, metin, mobil uygulama ve imza', async () => {
    await sendJoinRequestNotificationEmail({
      to: 'm@example.com',
      managerName: 'Müdür',
      siteName: 'Gül Sitesi',
      blockName: 'A Blok',
      unitLabel: '5',
      applicantName: 'Ali',
      applicantEmail: 'ali@example.com',
      notes: 'merhaba',
    });
    const [message] = sent;
    assert.equal(message.subject, `${PRODUCT} - Yeni Daire Katılım Başvurusu (Gül Sitesi - A Blok Daire 5)`);
    assert.match(message.text, new RegExp(`${PRODUCT} uygulamasından başvuruyu onaylayabilir`));
    assert.match(message.html, new RegExp(`${PRODUCT} mobil uygulamasını`));
    assert.match(message.html, new RegExp(`e-postası ${PRODUCT} tarafından otomatik`));
    noAhbu(message);
  });

  it('sifre sifirlama e-postasi', async () => {
    await sendPasswordResetEmail({ to: 'a@example.com', fullName: 'Ali', resetUrl: 'https://api.example.com/auth/reset-password?token=abc' });
    const [message] = sent;
    assert.equal(message.subject, `${PRODUCT} - Şifre Sıfırlama Bağlantısı`);
    assert.match(message.text, /^Merhaba Ali, hesabınız için şifre sıfırlama talebinde bulundunuz\./);
    assert.match(message.html, new RegExp(`🔐 ${PRODUCT}</h2>`));
    assert.match(message.html, new RegExp(`${PRODUCT} hesabınız için bir şifre sıfırlama talebinde`));
    noAhbu(message);
  });

  it('yeni modul talebi bildirimi: SABIT konu, site/modul/isteyen/not metinde; HTML kacirilir; konu kullanici verisi icermez', async () => {
    const xss = '<img src=x onerror=alert(1)>';
    await sendModuleRequestNotificationEmail({
      to: 'root@example.com',
      fullName: 'Süper Kullanıcı',
      siteName: `Gül ${xss}`,
      moduleName: 'Geçiş Kontrol (AHBU)',
      requesterName: `Ayşe ${xss}`,
      note: `Lütfen açın ${xss}`,
    });
    const [message] = sent;
    assert.equal(message.to, 'root@example.com');
    assert.equal(message.subject, 'Site ve Toplu Yaşam Yönetim Sistemi - Yeni Modül Talebi');
    assert.equal(message.subject, MODULE_REQUEST_EMAIL_SUBJECT);
    assert.equal(message.subject.includes('Gül'), false);
    assert.match(message.text, /^Merhaba Süper Kullanıcı, 'Gül <img/);
    assert.match(message.text, /Not: Lütfen açın/);
    assert.match(message.text, /Modül Talepleri ekranından onaylayabilir veya reddedebilirsiniz\.$/);
    assert.match(message.html, new RegExp(`🧩 ${PRODUCT}</h2>`));
    assert.match(message.html, /<strong>Modül:<\/strong> Geçiş Kontrol \(AHBU\)/);
    assert.equal(message.html.includes('<img'), false, 'HTML kacirilmali');
    assert.match(message.html, /&lt;img src=x onerror=alert\(1\)&gt;/);
    assert.match(message.html, new RegExp(`${PRODUCT} tarafından otomatik olarak gönderilmiştir`));
  });

  it('modul talebi: not yoksa Not satiri yoktur; bos alici adi varsayilana duser', async () => {
    await sendModuleRequestNotificationEmail({ to: 'root@example.com', siteName: 'Gül Sitesi', moduleName: 'Aidat ve Finans', requesterName: '', note: '   ' });
    const [message] = sent;
    assert.equal(message.text.includes('Not:'), false);
    assert.equal(message.html.includes('<strong>Not:</strong>'), false);
    assert.match(message.text, /^Merhaba Sistem Yöneticisi, 'Gül Sitesi' sitesinin yöneticisi Site Yöneticisi "Aidat ve Finans" modülünü talep etti\./);
  });

  it('modul talebi: SMTP ayari yoksa acik hata (cagiran fire-and-forget yakalar)', async () => {
    delete process.env.SMTP_FROM;
    delete process.env.SMTP_USER;
    await assert.rejects(
      () => sendModuleRequestNotificationEmail({ to: 'a@example.com', siteName: 'S', moduleName: 'M' }),
      /env degiskeni eksik/,
    );
  });
});

// ---------------------------------------------------------------------------
// Sifre sifirlama sayfalari
// ---------------------------------------------------------------------------

describe('urun adi: sifre sifirlama sayfalari', () => {
  let server;
  let baseUrl;
  const token = 'a'.repeat(64);

  before(async () => {
    for (const layer of authRouter.stack) {
      if (layer.route?.path === '/auth/reset-password' && layer.route.methods.get) {
        layer.route.stack[0].handle = (_req, _res, next) => next(); // hiz sinirlayici
      }
    }
    const app = express();
    app.use(authRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    delete pool.query;
  });

  beforeEach(() => {
    mock.method(console, 'error', () => {});
    pool.query = async () => ({
      rowCount: 1,
      rows: [{ user_code: 1, full_name: 'Ali', email: 'a@example.com', password_reset_expires_at: new Date(Date.now() + 600000) }],
    });
  });

  afterEach(() => {
    mock.restoreAll();
    delete pool.query;
  });

  it('hata sayfasi: baslik "Sifre Sifirlama Hatasi | <urun adi>"; AHBU yok', async () => {
    const res = await fetch(`${baseUrl}/auth/reset-password`);
    assert.equal(res.status, 400);
    const html = await res.text();
    assert.match(html, new RegExp(`<title>Şifre Sıfırlama Hatası \\| ${PRODUCT}</title>`));
    assert.equal(/AHBU/i.test(html), false);
  });

  it('yeni sifre formu: baslik "Yeni Sifre Belirleme | <urun adi>"; basari metni uygulamayi urun adiyla anar; AHBU yok', async () => {
    const res = await fetch(`${baseUrl}/auth/reset-password?token=${token}`);
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.match(html, new RegExp(`<title>Yeni Şifre Belirleme \\| ${PRODUCT}</title>`));
    assert.match(html, new RegExp(`yeni şifrenizle ${PRODUCT} uygulamasına giriş yapabilirsiniz`));
    assert.equal(/AHBU/i.test(html), false);
  });
});

// ---------------------------------------------------------------------------
// Kaynak korumasi: AHBU yalnizca kapi modulunde kalir
// ---------------------------------------------------------------------------

describe('urun adi: AHBU yalnizca kapi (Gecis Kontrol) modulunde kalir', () => {
  const ALLOWED_FILES = new Set([
    'modules/catalog.js', // "Gecis Kontrol (AHBU)" modul adi
    'routes/door_log_routes.js', // X-AHBU-Device-UID basligi (cihaz)
    'services/door_access_policy.js', // AHBU:DOOR: karekod bicimi (kapi) ve dosya aciklamasi
    'services/geofence_service.js', // kapi geofence aciklamasi
  ]);

  function listJs(dir) {
    const out = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) out.push(...listJs(full));
      else if (/\.js$/.test(entry.name)) out.push(full);
    }
    return out;
  }

  it('src altinda "AHBU" gecen dosyalar yalnizca kapi modulu dosyalaridir (mailer.js ve auth_routes.js temiz)', () => {
    const offenders = [];
    for (const file of listJs(srcRoot)) {
      const relative = path.relative(srcRoot, file).split(path.sep).join('/');
      if (/AHBU/.test(readFileSync(file, 'utf8')) && !ALLOWED_FILES.has(relative)) {
        offenders.push(relative);
      }
    }
    assert.deepEqual(offenders, []);
    assert.equal(/AHBU/.test(read('mailer.js')), false);
    assert.equal(/AHBU/.test(read('routes/auth_routes.js')), false);
  });

  it('kalanlar degismedi: katalog adi, cihaz basligi, karekod bicimi', () => {
    assert.match(read('modules/catalog.js'), /name: 'Geçiş Kontrol \(AHBU\)'/);
    assert.match(read('routes/door_log_routes.js'), /X-AHBU-Device-UID/);
    assert.match(read('services/door_access_policy.js'), /AHBU:DOOR:/);
  });
});
