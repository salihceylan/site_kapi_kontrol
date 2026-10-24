// Kişi yönetimi: Şifre sıfırlama ve toplu işlemler birim testleri (DB bağımsız / doğrulama kuralları)
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { executePeopleBulkAction, sendPersonPasswordReset } from '../src/modules/people_bulk_service.js';

describe('people_bulk_service input validation', () => {
  it('geçersiz siteCode veya personId durumunda 404 fırlatır', async () => {
    await assert.rejects(
      async () => sendPersonPasswordReset({ siteCode: 0, personId: 1, actor: { user_code: 1 } }),
      (err) => err.statusCode === 404 && err.code === 'SITE_NOT_FOUND',
    );
    await assert.rejects(
      async () => sendPersonPasswordReset({ siteCode: 123, personId: -1, actor: { user_code: 1 } }),
      (err) => err.statusCode === 404 && err.code === 'PERSON_NOT_FOUND',
    );
  });

  it('bulk-actions boş veya geçersiz person_ids durumunda 400 fırlatır', async () => {
    await assert.rejects(
      async () => executePeopleBulkAction({ siteCode: 123, action: 'send_invite', personIds: [], actor: { user_code: 1 } }),
      (err) => err.statusCode === 400 && err.code === 'INVALID_BODY',
    );
    await assert.rejects(
      async () => executePeopleBulkAction({ siteCode: 123, action: 'send_invite', personIds: 'bad', actor: { user_code: 1 } }),
      (err) => err.statusCode === 400 && err.code === 'INVALID_BODY',
    );
  });

  it('bulk-actions 100 kişiden fazla seçildiğinde 400 fırlatır', async () => {
    const tooMany = Array.from({ length: 101 }, (_, i) => i + 1);
    await assert.rejects(
      async () => executePeopleBulkAction({ siteCode: 123, action: 'send_invite', personIds: tooMany, actor: { user_code: 1 } }),
      (err) => err.statusCode === 400 && err.code === 'INVALID_BODY',
    );
  });
});

