import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'crypto';
import { sendPasswordResetEmail } from '../src/mailer.js';
import { normalizeEmail } from '../src/utils/helpers.js';

describe('Password Reset Logic Tests', () => {
  it('generates 32-byte hex token and corresponding sha256 hash', () => {
    const token = crypto.randomBytes(32).toString('hex');
    assert.equal(token.length, 64);

    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    assert.equal(tokenHash.length, 64);
    assert.notEqual(token, tokenHash);
  });

  it('verifies expiration timestamp is set in the future (30 min)', () => {
    const expiresAt = new Date(Date.now() + 30 * 60 * 1000);
    const now = new Date();
    assert.ok(expiresAt > now);
    const diffMinutes = Math.round((expiresAt.getTime() - now.getTime()) / (60 * 1000));
    assert.equal(diffMinutes, 30);
  });

  it('normalizes email correctly for password reset lookups', () => {
    assert.equal(normalizeEmail('  Ahmet.Yilmaz@Example.COM  '), 'ahmet.yilmaz@example.com');
    assert.equal(normalizeEmail(''), '');
  });

  it('rejects sendPasswordResetEmail when SMTP environment variables are missing', async () => {
    const originalFrom = process.env.SMTP_FROM;
    const originalUser = process.env.SMTP_USER;
    try {
      delete process.env.SMTP_FROM;
      delete process.env.SMTP_USER;
      await assert.rejects(
        () =>
          sendPasswordResetEmail({
            to: 'test@example.com',
            fullName: 'Test User',
            resetUrl: 'https://api.gudeteknoloji.com.tr/auth/reset-password?token=123',
          }),
        /env degiskeni eksik/i,
      );
    } finally {
      if (originalFrom) process.env.SMTP_FROM = originalFrom;
      if (originalUser) process.env.SMTP_USER = originalUser;
    }
  });
});

