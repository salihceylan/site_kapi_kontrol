import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { sendJoinRequestNotificationEmail, sendPasswordResetEmail } from '../src/mailer.js';

describe('Mailer Tests', () => {
  it('sendJoinRequestNotificationEmail is a defined function', () => {
    assert.equal(typeof sendJoinRequestNotificationEmail, 'function');
  });

  it('sendPasswordResetEmail is a defined function', () => {
    assert.equal(typeof sendPasswordResetEmail, 'function');
  });

  it('rejects when SMTP environment variables are missing', async () => {
    const originalHost = process.env.SMTP_HOST;
    const originalFrom = process.env.SMTP_FROM;
    try {
      delete process.env.SMTP_FROM;
      delete process.env.SMTP_USER;
      await assert.rejects(
        () =>
          sendJoinRequestNotificationEmail({
            to: 'manager@example.com',
            managerName: 'Ali Yönetici',
            siteName: 'Güneş Sitesi',
            blockName: 'A Blok',
            unitLabel: '5',
            applicantName: 'Ahmet Yılmaz',
            applicantEmail: 'ahmet@example.com',
            notes: 'Yeni taşındım',
          }),
        /env degiskeni eksik/i,
      );
    } finally {
      if (originalHost) process.env.SMTP_HOST = originalHost;
      if (originalFrom) process.env.SMTP_FROM = originalFrom;
    }
  });
});

