// Site başvurusu e-postaları (DB'siz, SMTP yok): sabit konu (başlık enjeksiyonu yok), HTML kaçışı, düz metin tek satır, adres gizliliği.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import {
  SITE_APPLICATION_APPROVED_SUBJECT,
  SITE_APPLICATION_EMAIL_SUBJECT,
  SITE_APPLICATION_REJECTED_SUBJECT,
  sendSiteApplicationDecisionEmail,
  sendSiteApplicationNotificationEmail,
} from '../src/mailer.js';

const XSS = '<img src=x onerror=alert(1)>';
const INJECT = 'Gül\r\nBcc: kurban@example.com\r\nSubject: x';

describe('site başvurusu e-postaları', () => {
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
    process.env.SMTP_FROM = 'Platform <noreply@example.invalid>';
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

  it('konular sabit ve ürün adını taşır (kullanıcı verisi içermez)', () => {
    assert.equal(SITE_APPLICATION_EMAIL_SUBJECT, 'Site ve Toplu Yaşam Yönetim Sistemi - Yeni Site Başvurusu');
    assert.equal(SITE_APPLICATION_APPROVED_SUBJECT, 'Site ve Toplu Yaşam Yönetim Sistemi - Site Başvurunuz Onaylandı');
    assert.equal(SITE_APPLICATION_REJECTED_SUBJECT, 'Site ve Toplu Yaşam Yönetim Sistemi - Site Başvurunuz Reddedildi');
    for (const subject of [SITE_APPLICATION_EMAIL_SUBJECT, SITE_APPLICATION_APPROVED_SUBJECT, SITE_APPLICATION_REJECTED_SUBJECT]) {
      assert.equal(/AHBU/.test(subject), false);
    }
  });

  it('bildirim: kullanıcı kontrollü alanlar HTML\'de kaçırılır; başlık satırları (CRLF) enjekte edilemez', async () => {
    await sendSiteApplicationNotificationEmail({
      to: 'root@example.com',
      fullName: XSS,
      siteName: `Site ${XSS}`,
      applicantName: INJECT,
      blockCount: 2,
      apartmentCount: 20,
      doorCount: 3,
      note: `not ${XSS}\r\nBcc: baska@example.com`,
    });
    assert.equal(sent.length, 1);
    const { subject, html, text, to, from } = sent[0];
    assert.equal(subject, SITE_APPLICATION_EMAIL_SUBJECT);
    assert.equal(/[\r\n]/.test(subject), false);
    assert.equal(to, 'root@example.com');
    assert.equal(from, 'Platform <noreply@example.invalid>');
    assert.equal(html.includes('<img'), false, 'ham HTML etiketi yok');
    assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'));
    // düz metin tek satır alanlarda satır sonu içermez (başvuran adı / site adı); not metni satır içerebilir ama konu / başlık değildir
    const firstLine = text.split('\n')[0];
    assert.ok(firstLine.includes('Gül Bcc: kurban@example.com Subject: x'), firstLine);
    assert.ok(text.includes('2 blok, 20 daire, 3 kapı'));
    assert.ok(text.includes('Site Başvuruları'));
    assert.ok(html.includes('2 blok, 20 daire, 3 kapı'));
  });

  it('bildirim: notsuz gönderimde not satırı yok; varsayılan adlar; başvuranın e-postası / telefonu e-postaya YAZILMAZ', async () => {
    await sendSiteApplicationNotificationEmail({ to: 'root@example.com', fullName: '', siteName: 'Gül Sitesi', applicantName: '', blockCount: 1, apartmentCount: 4, doorCount: 1, note: '  ' });
    const { html, text } = sent[0];
    assert.equal(/Not:/.test(html), false);
    assert.equal(/Not:/.test(text), false);
    assert.ok(text.includes('Sistem Yöneticisi'));
    assert.ok(text.includes('Bir kullanıcı'));
    assert.equal(/@/.test(html.replace('noreply', '')), false, 'e-posta adresi gövdede yok');
  });

  it('onay e-postası: "yönetici oldunuz, uygulamayı yenileyin"; konu onay konusudur', async () => {
    await sendSiteApplicationDecisionEmail({ to: 'ayse@example.com', fullName: 'Ayşe', siteName: `Gül ${XSS}`, approved: true, reason: 'bu kullanılmaz' });
    const { subject, text, html } = sent[0];
    assert.equal(subject, SITE_APPLICATION_APPROVED_SUBJECT);
    assert.match(text, /site yöneticisisiniz/);
    assert.match(text, /yenileyin/);
    assert.equal(text.includes('bu kullanılmaz'), false);
    assert.equal(html.includes('<img'), false);
    assert.ok(html.includes('&lt;img'));
  });

  it('ret e-postası: gerekçe (varsa) gösterilir ve HTML\'de kaçırılır; gerekçesizde Gerekçe satırı yok; yeniden başvuru bilgisi', async () => {
    await sendSiteApplicationDecisionEmail({ to: 'ayse@example.com', fullName: INJECT, siteName: 'Gül Sitesi', approved: false, reason: `Eksik belge ${XSS}` });
    const withReason = sent[0];
    assert.equal(withReason.subject, SITE_APPLICATION_REJECTED_SUBJECT);
    assert.equal(/[\r\n]/.test(withReason.subject), false);
    assert.match(withReason.text, /Gerekçe: Eksik belge/);
    assert.match(withReason.text, /yeniden başvurabilirsiniz/);
    assert.equal(withReason.html.includes('<img'), false);
    assert.ok(withReason.html.includes('Eksik belge &lt;img'));
    assert.ok(withReason.text.split('\n')[0].includes('Gül Bcc: kurban@example.com Subject: x'));

    await sendSiteApplicationDecisionEmail({ to: 'ayse@example.com', fullName: 'Ayşe', siteName: 'Gül Sitesi', approved: false, reason: null });
    assert.equal(/Gerekçe/.test(sent[1].text), false);
    assert.equal(/Gerekçe/.test(sent[1].html), false);
  });

  it('SMTP_FROM / SMTP_USER yoksa açık hata (çağıran fire-and-forget olarak yutar)', async () => {
    delete process.env.SMTP_FROM;
    delete process.env.SMTP_USER;
    await assert.rejects(() => sendSiteApplicationNotificationEmail({ to: 'a@example.com', siteName: 'S' }), /SMTP_FROM veya SMTP_USER/);
    await assert.rejects(() => sendSiteApplicationDecisionEmail({ to: 'a@example.com', siteName: 'S', approved: true }), /SMTP_FROM veya SMTP_USER/);
  });
});
